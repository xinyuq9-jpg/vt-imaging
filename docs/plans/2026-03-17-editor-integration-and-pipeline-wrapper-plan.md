# Editor Integration & Pipeline Wrapper Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace inline UI code in Morpho1/3/4/5 with `morpho.Editor` calls, create a `Morpho_run.m` pipeline wrapper, and clean up legacy UI files.

**Architecture:** The existing `morpho.Editor` (handle class) already supports all needed features: D/E/R modes, configurable overlay colors, context frame switching, opacity control, frame navigation, line drawing, and undo. Each interactive stage gets its inline ginput loop replaced with an Editor constructor + `run()` call. A thin `Morpho_run.m` wrapper calls stages sequentially via MATLAB's `run()`.

**Tech Stack:** MATLAB R2025a, Image Processing Toolbox, `+morpho` package

**Design doc:** `docs/plans/2026-03-17-editor-integration-and-pipeline-wrapper-design.md`

---

### Task 1: Integrate Editor into Morpho1_masking.m

**Files:**
- Modify: `Morpho1_masking.m:23-24` (remove addpath)
- Modify: `Morpho1_masking.m:158-245` (replace inline UI with Editor)

**Step 1: Remove addpath**

In `Morpho1_masking.m`, delete line 24:
```matlab
addpath("bonus_scripts");
```

**Step 2: Replace inline mask editing loop**

Replace lines 158-245 (the entire `else` block for manual mask editing, from `disp(" ")` through `close(hMaskFig)`) with:

```matlab
    else

        disp(" ")
        disp("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
        disp("Draw masks over pixels likely to contain vocal tract.")
        disp("Use D=Draw, E=Erase, S=Settings, Q=Quit/done.")
        disp("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
        disp(" ")

        context_frame_data = morpho.video.read_single(input_filename, context_frame);

        editor = morpho.Editor(vt_mask_dilate, ...
            background=context_frame_data, ...
            overlay_color="red", ...
            modes="DE", ...
            brush_size=cfg.masking.brush_size, ...
            draw_mode=cfg.masking.draw_mode, ...
            overlay_opacity=cfg.masking.mask_opacity, ...
            show_opacity_control=true, ...
            show_context_frame=true, ...
            frame_source=input_filename, ...
            frame_indices=1:no_frames, ...
            current_frame=context_frame);
        vt_mask_cleaned = editor.run();
        vt_mask_cleaned = bwmorph(vt_mask_cleaned, 'close');

    end
```

**Step 3: Update manual_threshold_chooser call**

Line 351 calls `manual_threshold_chooser(sample_frames)` which relied on `addpath("bonus_scripts")`. Change to:

```matlab
manual_threshold = bonus_scripts.manual_threshold_chooser(sample_frames);
```

OR move `manual_threshold_chooser.m` into `+morpho/masking.m` as a static method. The simpler option: keep the addpath but move it to just before the call site rather than at the top. Actually, the cleanest fix is to use the full path:

```matlab
run(fullfile("bonus_scripts", "manual_threshold_chooser"));
```

No — `manual_threshold_chooser` is a function, not a script. The simplest fix: keep `addpath("bonus_scripts")` only if `manual_threshold_chooser` is still needed. Since it IS still called on line 351, keep the addpath.

**Revised Step 1**: Keep `addpath("bonus_scripts")` in Morpho1_masking.m (manual_threshold_chooser still needs it). Remove it only from Morpho4_outliner.m.

**Step 4: Verify**

Open MATLAB, run `Morpho1_masking` on a test file. Confirm:
- Editor figure opens with red overlay on context frame
- D/E drawing works
- S opens settings with context frame + opacity controls
- Q exits and returns cleaned mask
- Output files are saved correctly

**Step 5: Commit**

```
git add Morpho1_masking.m
git commit -m "refactor(Morpho1): replace inline mask editor with morpho.Editor"
```

---

### Task 2: Integrate Editor into Morpho3_QA.m

**Files:**
- Modify: `Morpho3_QA.m:137-191` (replace inline QA editing with Editor)

**Step 1: Replace inline QA editing loop**

Replace lines 137-191 (the `else` block from `disp("ERASE/REDRAW pixels")` through the mask save section) with:

```matlab
    else

        disp("ERASE/REDRAW pixels using Editor. R=Redraw, E=Erase, S=Settings, Q=Quit.")

        vt_ever_og = vt_ever;

        editor = morpho.Editor(vt_ever, ...
            original=vt_ever_og, ...
            background=anatomy_med, ...
            overlay_color="pink", ...
            modes="RE", ...
            brush_size=cfg.qa.brush_size, ...
            draw_mode=cfg.qa.draw_mode);
        vt_ever = editor.run();
        vt_ever = vt_ever > 0;

        vt_ever_cleaned = vt_ever;

        % Save QA masks only when manually created/edited
        if cfg.qa.save_shared_QA_mask_for_group == 1
            save(shared_QA_mask_path, 'vt_ever_cleaned');
            save(perfile_QA_mask_path, 'vt_ever_cleaned');

            disp("Saved shared QA mask: " + string(shared_QA_mask_path));
            disp("Saved per-file QA mask: " + string(perfile_QA_mask_path));
        end
    end
```

**Step 2: Verify**

Open MATLAB, run `Morpho3_QA` on a test file. Confirm:
- Editor opens with pink overlay on median anatomy
- R mode restores original pixel values (from vt_ever_og)
- E mode erases
- Output QA mask saved correctly

**Step 3: Commit**

```
git add Morpho3_QA.m
git commit -m "refactor(Morpho3): replace inline QA editor with morpho.Editor"
```

---

### Task 3: Integrate Editor into Morpho4_outliner.m

**Files:**
- Modify: `Morpho4_outliner.m:21` (remove addpath)
- Modify: `Morpho4_outliner.m:641-711` (replace inline manual-check editor with Editor)

**Step 1: Remove addpath**

Delete line 21:
```matlab
addpath("bonus_scripts");
```

Morpho4 no longer calls any bonus_scripts functions directly (a_star is called via `morpho.tracing.a_star_bridge`).

**Step 2: Replace manual-check editing block**

Replace lines 648-698 (the inner `while do_edit` loop's editing section). The current structure is:

```
if manual_check
    if pixel_count < suspicion_threshold
        do_edit = 'y';
        while do_edit == 'y' || do_edit == 'Y'
            % --- INLINE EDITING (replace this) ---
            % ... ginput loop, imshowpair, expand_brush, toggle pixels ...
            % --- END INLINE EDITING ---
            % redo trace
            % ask do_edit again
            % ask take_note
        end
    end
end
```

Replace the editing section inside the while loop (lines 650-698) with:

```matlab
        do_edit='y';
              while do_edit == 'y' || do_edit =='Y'

                  disp("ADD/REMOVE pixels to build contiguous outline. D=Draw, E=Erase, Q=Done.")

                  vt_mask = vt_output(:,:,f) > 0;

                  editor = morpho.Editor(vt_mask, ...
                      background=this_frame, ...
                      overlay_color="green", ...
                      modes="DE", ...
                      brush_size=0);
                  vt_mask = editor.run();

                  %%%redo trace
                  [top_edited, ~] = morpho.tracing.find_endpoints(vt_mask);
                  [tx_edited, ty_edited, trace_mat_edited] = morpho.tracing.trace_boundary(vt_mask, top_edited);
                  vt_trace_edited = [ty_edited, tx_edited];

                  % Show result for evaluation
                  scaling_factor_local = max(max(this_frame))*1.5;
                  imshowpair(this_frame/scaling_factor_local+vt_mask, trace_mat_edited)

                  do_edit=input('would you like a redo? (y/n)', 's');
                  if isempty(do_edit); do_edit = 'y'; end
              end %end do_edit while
              trace_mat = trace_mat_edited;
              vt_trace_result = vt_trace_edited;

              %%%take notes in case a frame is unfixably bad
              take_note=input('Note this frame down as a failure to revisit? (y/n)', 's');
              if isempty(take_note); take_note = 'y'; end
              if take_note == 'y' || take_note == 'Y'
                  note=strcat(input_rootname, "_Frame_",int2str(f));
                  fid = fopen(fullfile(output_trace_dir, "failed_traces.txt"), 'a+');
                    fprintf(fid, '%s \n', note);
                  fclose(fid);
              end
```

**Step 3: Verify**

Run `Morpho4_outliner` with `manual_check=true` and a file that triggers the suspicion threshold. Confirm Editor opens with green overlay, editing works, trace is recomputed after.

**Step 4: Commit**

```
git add Morpho4_outliner.m
git commit -m "refactor(Morpho4): replace inline manual-check editor with morpho.Editor"
```

---

### Task 4: Integrate Editor into Morpho5_finaliser.m

**Files:**
- Modify: `Morpho5_finaliser.m:45` (fix morpho.ui ref)
- Modify: `Morpho5_finaliser.m:120,134,167,258` (fix morpho.ui.show_pair refs)
- Modify: `Morpho5_finaliser.m:154-233` (replace inline editing with Editor)

**Step 1: Fix all morpho.ui references to morpho.display**

Replace all `morpho.ui.` with `morpho.display.` throughout the file:

- Line 45: `morpho.ui.mode_to_ink` → `morpho.display.mode_to_ink`
- Line 120: `morpho.ui.show_pair` → `morpho.display.show_pair`
- Line 134: `morpho.ui.show_pair` → `morpho.display.show_pair`
- Line 167: `morpho.ui.show_pair` → `morpho.display.show_pair`
- Line 182: `morpho.ui.settings_dialog` → removed (replaced by Editor)
- Line 188: `morpho.ui.expand_brush` → removed (replaced by Editor)
- Line 258: `morpho.ui.show_pair` → `morpho.display.show_pair`

**Step 2: Replace inline editing procedure**

Replace lines 153-234 (the `else` block containing the editing procedure) with:

```matlab
        else
            %%%%%%%%%%%%%%%%%%%%%%%%%
            %%% editing procedure %%%
            %%%%%%%%%%%%%%%%%%%%%%%%%

            editor = morpho.Editor(trace_holder_edited(f).outline, ...
                background=this_frame, ...
                overlay_color="green", ...
                modes="DE", ...
                brush_size=cfg.finaliser.brush_size, ...
                draw_mode=cfg.finaliser.draw_mode, ...
                allow_line_draw=true);
            trace_holder_edited(f).outline = editor.run();

            %%%%%%%%%%%%%%%%%%
            %%% redo trace %%%
            %%%%%%%%%%%%%%%%%%
            [top, bottom] = morpho.tracing.find_endpoints(trace_holder_edited(f).outline);
            [tx, ty, trace_mat_edited] = morpho.tracing.trace_boundary(trace_holder_edited(f).outline, top);
            trace_holder_edited(f).trace_y = ty;
            trace_holder_edited(f).trace_x = tx;
            trace_holder_edited(f).endpoints_top = [top(1), top(2)];
            trace_holder_edited(f).endpoints_bottom = [bottom(1), bottom(2)];
            trace_holder_edited(f).outline = trace_mat_edited;

        end %else edit procedure for current frame terminates here
```

**Step 3: Verify**

Run `Morpho5_finaliser` on a test file. Confirm:
- Frame display with `show_pair` works (using morpho.display)
- Choosing 'f' opens Editor with green overlay and line drawing
- Two-click line drawing works (D mode)
- Erasing works (E mode)
- Trace is recomputed after editing
- n/b/r navigation in outer loop still works

**Step 4: Commit**

```
git add Morpho5_finaliser.m
git commit -m "refactor(Morpho5): replace inline editor with morpho.Editor, fix ui->display refs"
```

---

### Task 5: Create Morpho_run.m pipeline wrapper

**Files:**
- Create: `Morpho_run.m`

**Step 1: Write the wrapper**

Create `Morpho_run.m` at project root:

```matlab
function Morpho_run(opts)
%MORPHO_RUN Run the VT-imaging pipeline (stages 0-5).
%   Morpho_run()              — run all stages
%   Morpho_run(stages=3:5)    — run stages 3 to 5
%   Morpho_run(stages=[1 3])  — run stages 1 and 3
    arguments
        opts.stages (1,:) double = 0:5
    end

    stage_names = ["register", "masking", "subsetter", "QA", "outliner", "finaliser"];
    stage_scripts = [ ...
        "Morpho0_register", ...
        "Morpho1_masking", ...
        "Morpho2_subsetter", ...
        "Morpho3_QA", ...
        "Morpho4_outliner", ...
        "Morpho5_finaliser"];

    for stage_num = opts.stages
        idx = stage_num + 1;  % 0-based stage -> 1-based index
        if idx < 1 || idx > numel(stage_scripts)
            warning("Skipping unknown stage %d", stage_num);
            continue;
        end

        fprintf('\n========================================\n');
        fprintf('=== Stage %d: %s ===\n', stage_num, stage_names(idx));
        fprintf('========================================\n\n');

        run(stage_scripts(idx));
    end

    fprintf('\n=== Pipeline complete ===\n');
end
```

**Step 2: Verify**

In MATLAB:
```matlab
% Quick smoke test — run just the non-interactive stage
Morpho_run(stages=2)
```

**Step 3: Commit**

```
git add Morpho_run.m
git commit -m "feat: add Morpho_run pipeline wrapper with stage selection"
```

---

### Task 6: Delete legacy UI files and morpho.ui

**Files:**
- Delete: `bonus_scripts/Morpho1_UI.m`
- Delete: `bonus_scripts/Morpho3_UI.m`
- Delete: `bonus_scripts/Morpho4_UI.m`
- Delete: `bonus_scripts/Morpho5_UI.m`
- Delete: `+morpho/ui.m`

**Step 1: Verify no remaining references to deleted files**

Search for any imports or calls to the files being deleted:
- `Morpho1_UI` — should only appear in bonus_scripts/ and old plan docs
- `Morpho3_UI` — same
- `Morpho4_UI` — same
- `Morpho5_UI` — same
- `morpho.ui.` — should have zero hits in .m files after Tasks 1-4 (plan docs are fine)

**Step 2: Delete the files**

```bash
rm bonus_scripts/Morpho1_UI.m
rm bonus_scripts/Morpho3_UI.m
rm bonus_scripts/Morpho4_UI.m
rm bonus_scripts/Morpho5_UI.m
rm +morpho/ui.m
```

**Step 3: Verify**

In MATLAB, confirm no errors:
```matlab
cfg = morpho.Config();  % package still loads
editor = morpho.Editor(ones(10));  % Editor still works
morpho.display.mode_to_ink('D');  % display functions work
```

**Step 4: Commit**

```
git add -A bonus_scripts/Morpho1_UI.m bonus_scripts/Morpho3_UI.m bonus_scripts/Morpho4_UI.m bonus_scripts/Morpho5_UI.m +morpho/ui.m
git commit -m "cleanup: delete legacy Morpho*_UI.m files and redundant +morpho/ui.m"
```

---

### Task 7: Final integration verification

**Step 1: Run full pipeline on a small test dataset**

```matlab
Morpho_run()
```

Walk through each stage, confirming:
- Stage 0: Registration runs (interactive ginput for reference — unchanged)
- Stage 1: Editor opens for masking (red overlay, D/E/S/Q)
- Stage 2: Subsetter runs (non-interactive — unchanged)
- Stage 3: Editor opens for QA (pink overlay, R/E/S/Q)
- Stage 4: Outliner runs, Editor opens if suspicion triggered (green overlay)
- Stage 5: Finaliser shows frames, Editor opens on 'f' (green overlay, line draw)

**Step 2: Run selective stages**

```matlab
Morpho_run(stages=3:5)
Morpho_run(stages=[0 2])
```

**Step 3: Final commit if any fixes needed**

```
git add -A
git commit -m "fix: address integration issues from full pipeline test"
```
