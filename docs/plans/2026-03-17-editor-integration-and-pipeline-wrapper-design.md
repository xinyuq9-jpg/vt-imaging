# Editor Integration & Pipeline Wrapper Design

**Date:** 2026-03-17
**Status:** Validated

## Goals

1. Replace inline UI code in Morpho1/3/4/5 with `morpho.Editor` calls
2. Create `Morpho_run.m` pipeline wrapper to run stages 0-5 with optional stage selection
3. Delete legacy `Morpho*_UI.m` files from `bonus_scripts/`

## Editor Integration

### Morpho1 (masking) — `Morpho1_masking.m:158-243`

Replace ~80 lines of inline ginput mask editing loop with:

```matlab
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
```

### Morpho3 (QA) — `Morpho3_QA.m:137-191`

Replace ~50 lines of inline ginput QA editing loop with:

```matlab
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
```

### Morpho4 (outliner) — `Morpho4_outliner.m:641-711`

Replace the manual-check inline editing block with:

```matlab
editor = morpho.Editor(vt_mask, ...
    background=this_frame, ...
    overlay_color="green", ...
    modes="DE", ...
    brush_size=0);
vt_mask = editor.run();
```

The `do_edit` retry loop and `take_note` prompt stay. Trace is recomputed from edited mask.

### Morpho5 (finaliser) — `Morpho5_finaliser.m:154-233`

Replace the inner ginput editing loop (runs when user picks 'f' to fix) with:

```matlab
editor = morpho.Editor(trace_holder_edited(f).outline, ...
    background=this_frame, ...
    overlay_color="green", ...
    modes="DE", ...
    brush_size=cfg.finaliser.brush_size, ...
    draw_mode=cfg.finaliser.draw_mode, ...
    allow_line_draw=true);
trace_holder_edited(f).outline = editor.run();
```

The outer `while f <= no_frames` loop with text `input('f/n/b/r')` stays unchanged.

## Pipeline Wrapper — `Morpho_run.m`

New file at project root:

```matlab
function Morpho_run(opts)
    arguments
        opts.stages (1,:) double = 0:5
    end

    stage_scripts = { ...
        0, @() run("Morpho0_register"); ...
        1, @() run("Morpho1_masking"); ...
        2, @() run("Morpho2_subsetter"); ...
        3, @() run("Morpho3_QA"); ...
        4, @() run("Morpho4_outliner"); ...
        5, @() run("Morpho5_finaliser"); ...
    };

    for i = 1:size(stage_scripts, 1)
        stage_num = stage_scripts{i, 1};
        if ismember(stage_num, opts.stages)
            fprintf('\n=== Stage %d ===\n', stage_num);
            stage_scripts{i, 2}();
        end
    end

    fprintf('\n=== Pipeline complete ===\n');
end
```

Usage:
- `Morpho_run()` — runs stages 0-5
- `Morpho_run(stages=3:5)` — runs stages 3-5
- `Morpho_run(stages=[1 3])` — runs stages 1 and 3

Design decisions:
- Uses MATLAB's `run()` — each stage script creates its own `cfg`, no variable collision
- No try/catch wrapping — errors propagate so stale data doesn't feed the next stage
- No shared config passing — each stage is still standalone

## Cleanup

### Delete legacy UI files (4 files)

- `bonus_scripts/Morpho1_UI.m`
- `bonus_scripts/Morpho3_UI.m`
- `bonus_scripts/Morpho4_UI.m`
- `bonus_scripts/Morpho5_UI.m`

### Fix `morpho.ui` to `morpho.display` references

- `Morpho5_finaliser.m:45` — `morpho.ui.mode_to_ink` -> `morpho.display.mode_to_ink`
- `Morpho5_finaliser.m:120,134` — `morpho.ui.show_pair` -> `morpho.display.show_pair`

### Remove `addpath("bonus_scripts")`

- `Morpho1_masking.m:24`
- `Morpho4_outliner.m:21`

`manual_threshold_chooser` (called from Morpho1) needs its call site updated since it currently relies on the addpath.

## Net Effect

- ~210 lines of duplicated inline UI code removed
- ~45 lines of Editor calls added
- 1 new ~25-line wrapper file
- 4 legacy UI files deleted
