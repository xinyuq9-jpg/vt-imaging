# VT-Imaging Code Reorganization Design

**Date:** 2026-03-16
**Status:** Approved

## Problem

Shared logic (file discovery, lock files, directory setup, UI dialogs, display, path conventions, parameters) is copy-pasted across all Morpho scripts. Making a single change often requires editing 4-6 files. Additionally, full video loading into RAM causes performance issues on long videos (3+ min, up to 10k frames).

## Solution: Config Object + Shared Utilities + Chunked Processing

Keep each `Morpho0`–`Morpho5` script as a standalone entry point, but extract all shared logic into a `+morpho/` MATLAB package. Replace full-video RAM loading with chunked/streaming frame processing.

## File Structure

```
vt-imaging/
├── Morpho0_register.m              # entry points (simplified)
├── Morpho1_masking.m
├── Morpho2_subsetter.m
├── Morpho3_QA.m
├── Morpho4_outliner.m
├── Morpho5_finaliser.m
├── select_input_files.m
│
├── +morpho/
│   ├── Config.m                    # paths, per-stage params, defaults
│   ├── io.m                        # lock files, discover_files, ADB grouping,
│   │                               #   append_to_mat, read_csv, write_csv
│   ├── video.m                     # read_frames (with index support),
│   │                               #   streaming_stats, process_chunks,
│   │                               #   frame_count, grayscale conversion
│   ├── ui.m                        # settings_dialog (replaces 4 UI functions),
│   │                               #   show_pair, brush_edit_loop, expand_brush
│   ├── masking.m                   # variance threshold, tissue threshold,
│   │                               #   morphological cleanup, lip clip
│   ├── registration.m              # rigid registration logic from Morpho0
│   └── tracing.m                   # boundary tracing, A* bridging, skeleton,
│                                   #   spline methods, logical matrix indexing
│
├── bonus_scripts/                  # untouched
```

## Component Details

### 1. Config Class (`+morpho/Config.m`)

Central configuration holding all paths and per-stage parameters.

```matlab
classdef Config
    properties
        projectDir  string      % root working directory (defaults to pwd)
        remoteBase  string      % remote ADB source folder
        remoteLogDir string     % remote log folder

        % Per-stage parameter structs
        register    struct
        masking     struct
        subsetter   struct
        qa          struct
        outliner    struct
        finaliser   struct
    end

    methods
        function obj = Config(overrides)
            arguments
                overrides.projectDir string = pwd
            end
            obj.projectDir = overrides.projectDir;
            obj.register  = obj.defaultRegister();
            obj.masking   = obj.defaultMasking();
            obj.subsetter = obj.defaultSubsetter();
            obj.qa        = obj.defaultQA();
            obj.outliner  = obj.defaultOutliner();
            obj.finaliser = obj.defaultFinaliser();
        end

        function p = dir(obj, name)
            % Single source of truth for all output paths
            map = dictionary( ...
                "avi_raw",        "avi_raw", ...
                "avi_reg",        "avi_reg", ...
                "reg_transforms", "avi_reg/reg_trasforms", ...
                "morph_avi",      "morph/avi", ...
                "morph_mat",      "morph/mat", ...
                "mat_sub",        "morph/mat_sub", ...
                "log_sub",        "morph/mat_sub/log_sub", ...
                "mat_qa",         "morph/mat_QA", ...
                "qa_masks",       "morph/mat_QA_masks", ...
                "masks",          "morph/masks", ...
                "vt_trace",       "morph/vt_trace", ...
                "vt_trace_mat",   "morph/vt_trace_mat", ...
                "vt_trace_avi",   "morph/vt_trace_avi", ...
                "vt_skeleton",    "morph/vt_skeleton", ...
                "vt_endpoints",   "morph/vt_endpoints" ...
            );
            p = fullfile(obj.projectDir, map(name));
        end

        function ensure(obj, name)
            d = obj.dir(name);
            if ~isfolder(d), mkdir(d); end
        end
    end

    methods (Access = private)
        function s = defaultMasking(~)
            s = struct( ...
                'automatic_var_threshold', true, ...
                'var_threshold', 0.5, ...
                'mask_thickening', true, ...
                'final_erode', true, ...
                'automatic_tissue_threshold', true, ...
                'manual_tissue_threshold', NaN, ...
                'lip_clip', true, ...
                'context_frame', 'auto', ...
                'mask_opacity', 0.5, ...
                'brush_size', 10, ...
                'draw_mode', 'D' ...
            );
        end

        function s = defaultQA(~)
            s = struct( ...
                'use_saved_qa_mask', true, ...
                'skip_manual_if_shared', false, ...
                'save_shared_mask', true, ...
                'brush_size', 50, ...
                'draw_mode', 'E' ...
            );
        end

        function s = defaultOutliner(~)
            s = struct( ...
                'draw_connector', "a_star", ...
                'a_star_weight', 999, ...
                'polynomial_degree', 2, ...
                'lambda', 0.5, ...
                'vt_skel_thresh', 0.75, ...
                'manual_check', false, ...
                'suspicion_threshold', 0.5, ...
                'scaling_factor', 5 ...
            );
        end

        function s = defaultFinaliser(~)
            s = struct( ...
                'scaling_factor', 5, ...
                'brush_size', 5, ...
                'draw_mode', 'E' ...
            );
        end

        function s = defaultRegister(~)
            s = struct();
        end

        function s = defaultSubsetter(~)
            s = struct();
        end
    end
end
```

### 2. I/O Utilities (`+morpho/io.m`)

Static methods for file operations shared across stages.

```matlab
classdef io
    methods (Static)
        function tf = is_locked(filepath)
            tf = isfile(filepath + ".lock");
        end

        function lock(filepath)
            fid = fopen(filepath + ".lock", 'w');
            fprintf(fid, '%s', datetime("now"));
            fclose(fid);
        end

        function unlock(filepath)
            f = filepath + ".lock";
            if isfile(f), delete(f); end
        end

        function [files, adb_groups] = discover_files(inputDir, pattern)
            % Find files matching pattern, group by ADB prefix.
            % Returns file list + dictionary mapping ADB name -> file indices.
            % Replaces the repeated dir() + grouping logic in every script.
        end

        function T = read_csv(filepath)
            T = readtable(filepath);
        end

        function write_csv(filepath, T)
            writetable(T, filepath);
        end

        function append_to_mat(filepath, data, indices)
            % Append chunk results to a -v7.3 matfile for incremental saving.
            % Creates file on first call, appends on subsequent calls.
        end
    end
end
```

### 3. Video Utilities (`+morpho/video.m`)

Frame I/O with chunked processing — eliminates full-video RAM loading.

```matlab
classdef video
    methods (Static)
        function frames = read_frames(videoPath, frameIndices)
            % Read specific frames, return as single-precision grayscale.
            % Replaces the repeated: read(v) -> squeeze -> cast -> channel select
            arguments
                videoPath string
                frameIndices = []  % empty = all frames
            end
        end

        function n = frame_count(videoPath)
            v = VideoReader(videoPath);
            n = max(1, floor(v.Duration * v.FrameRate + 1e-6));
            if isprop(v, 'NumFrames')
                n = min(n, v.NumFrames);
            end
        end

        function frame = read_single(videoPath, frameIdx)
            % Read one frame as single-precision grayscale.
            % For interactive display (QA, finaliser) without loading full video.
        end

        function process_chunks(videoPath, processFn, opts)
            % Chunked frame processing — never holds more than chunkSize frames in RAM.
            %
            % processFn signature: result = processFn(chunk, frameIndices)
            %   chunk: H x W x chunkSize single array
            %   frameIndices: 1 x chunkSize vector of original frame numbers
            %   result: H x W x chunkSize output (e.g. binary masks)
            %
            arguments
                videoPath string
                processFn function_handle
                opts.chunkSize = 500
                opts.frameIndices = []
                opts.outputFile string = ""
            end
        end

        function [running_mean, running_var] = streaming_stats(videoPath, opts)
            % Welford's online algorithm — single pass, O(H x W) memory.
            % Returns mean and variance images across all frames.
            % Replaces loading full video just to compute variance (Morpho1)
            % or mean VT frequency map (Morpho3, Morpho4).
            arguments
                videoPath string
                opts.frameIndices = []
                opts.skipFirstN = 0   % skip noisy initial frames
            end
        end

        function write_avi(filepath, frames, framerate)
            v = VideoWriter(filepath, 'Motion JPEG AVI');
            v.FrameRate = framerate;
            open(v);
            writeVideo(v, frames);
            close(v);
        end
    end
end
```

### 4. UI Utilities (`+morpho/ui.m`)

Replaces Morpho1_UI, Morpho3_UI, Morpho4_UI, Morpho5_UI with one parameterized implementation.

```matlab
classdef ui
    methods (Static)
        function [draw_mode, brush_size, ink, varargout] = settings_dialog(draw_mode, brush_size, mask_size, opts)
            % Unified settings dialog replacing all 4 stage-specific UIs.
            %
            % opts.show_context_frame  (bool) — show context frame field (Morpho1)
            % opts.show_opacity        (bool) — show opacity field (Morpho1)
            % opts.no_frames           (int)  — max context frame value
            % opts.mask_opacity        (double) — current opacity
            % opts.context_frame       (int)  — current context frame
            % opts.modes              (string) — allowed modes e.g. "DE" or "RE"
            %
            % Validates draw_mode (D/E/R), clamps brush_size to [0, mask/4],
            % sets ink value from mode. Fixes Morpho5_UI typo (dis -> disp).
            arguments
                draw_mode
                brush_size
                mask_size
                opts.show_context_frame = false
                opts.show_opacity = false
                opts.no_frames = 1
                opts.mask_opacity = 0.5
                opts.context_frame = 1
                opts.modes = "DE"
            end
        end

        function show_pair(frame, overlay, opts)
            % Standardized frame+overlay display with consistent window positioning.
            arguments
                frame
                overlay
                opts.scaling_factor = 1
                opts.position = [0.5, 0, 0.5, 1]
            end
            imshowpair(frame / opts.scaling_factor, overlay);
            set(gcf, 'Units', 'Normalized', 'OuterPosition', opts.position);
        end

        function mask = brush_edit_loop(frame, mask, opts)
            % Shared ginput -> brush -> apply ink -> redisplay loop.
            % Used by Morpho1, 3, 4, 5 with stage-specific options.
            arguments
                frame
                mask
                opts.brush_size = 5
                opts.draw_mode = 'D'
                opts.scaling_factor = 1
                opts.exit_value = 999
                opts.mask_size = []
                opts.modes = "DE"
            end
        end

        function [x_brush, y_brush] = expand_brush(x, y, brush_size, mask_size)
            % Clamp brush coordinates to image bounds.
            x_brush = max(1, round(x)-brush_size) : min(mask_size(2), round(x)+brush_size);
            y_brush = max(1, round(y)-brush_size) : min(mask_size(1), round(y)+brush_size);
        end
    end
end
```

### 5. Masking Utilities (`+morpho/masking.m`)

Threshold detection and morphological operations from Morpho1.

```matlab
classdef masking
    methods (Static)
        function threshold = auto_variance_threshold(frame_var)
            % KSD-based optimal variance threshold detection.
            % Extracted from Morpho1's automatic threshold logic.
        end

        function threshold = auto_tissue_threshold(frame, mask)
            % KSD-based tissue/air intensity threshold.
            % Per-frame bimodal distribution splitting.
        end

        function mask = morphological_cleanup(mask, opts)
            % Shared bwmorph pipeline: thicken, bridge, close, erode.
            arguments
                mask
                opts.thicken = true
                opts.bridge = true
                opts.close_size = 3
                opts.erode = true
            end
        end

        function mask = clip_lip(mask)
            % Remove anterior lip region from mask.
        end

        function tissue_mask = classify_tissue(frame, vt_mask, threshold)
            % Apply tissue threshold + morphological cleanup to single frame.
            % Used as processFn callback with video.process_chunks.
        end
    end
end
```

### 6. Registration (`+morpho/registration.m`)

```matlab
classdef registration
    methods (Static)
        function tform = register_frame(frame, reference, mask)
            % Rigid registration (translation + rotation) of one frame.
            % Uses imregconfig('monomodal') + imregtform.
        end

        function registered = apply_transform(frame, tform, ref)
            % Apply transform with imwarp.
        end
    end
end
```

### 7. Tracing (`+morpho/tracing.m`)

```matlab
classdef tracing
    methods (Static)
        function skeleton = compute_skeleton(vt_mean, threshold)
            % Compute mean VT skeleton via thinning.
        end

        function bridge = connect_compartments(vt_frame, method, opts)
            % Bridge disconnected VT compartments.
            % method: "a_star", "mean_spline", "upper_spline", "polynomial"
        end

        function [trace_x, trace_y] = trace_boundary(vt_frame, start_point)
            % bwtraceboundary wrapper with clockwise tracing.
        end

        function tf = pixel_in_mask(pixel, mask_logical)
            % Replaces ismember(pixel, linear_index_list) with
            % direct logical matrix indexing — O(1) instead of O(n).
        end
    end
end
```

## Performance: Chunked Processing

### Problem
Full video loading (`frames = read(v)`) puts entire video in RAM. For 10k frames at 256x256 single: ~2.5 GB per array. Multiple arrays (frames + vt_output + trace_outline) can exceed available memory.

### Solution

| Stage | Current | After |
|-------|---------|-------|
| Morpho0 | Already streams frame-by-frame | No change |
| Morpho1 | `read(v)` loads all frames; `zeros(size(frames))` duplicates | `streaming_stats` for variance; `process_chunks` for tissue classification |
| Morpho2 | Loads .mat, subsets indices | Minimal change — already lightweight |
| Morpho3 | Loads full AVI + full .mat | `streaming_stats` for vt_ever mean; `read_single` for context frame |
| Morpho4 | Loads full AVI + full .mat + allocates trace array | `process_chunks` for tracing loop; write traces per chunk |
| Morpho5 | Loads full AVI for interactive editing | `read_single` per frame on demand |

### Key implementation: `streaming_stats`
Uses Welford's online algorithm to compute per-pixel mean and variance in a single pass with O(H x W) memory, replacing the need to load all frames for variance (Morpho1) or mean frequency maps (Morpho3/4).

### Key implementation: `process_chunks`
Reads `chunkSize` frames (default 500) at a time, passes to a callback function, writes results incrementally. Maximum RAM usage bounded to ~chunkSize frames regardless of video length.

### `ismember` replacement
Morpho4 calls `ismember(pixel, vt_output_linear)` in tight loops — O(n) per call. Replace with direct logical matrix indexing: `mask(row, col)` — O(1) per lookup.

## Refactored Entry Point Example

```matlab
% Morpho1_masking.m (after refactor)
cfg = morpho.Config();

[files, groups] = morpho.io.discover_files(cfg.dir("avi_reg"), "*.avi");

for i = 1:numel(files)
    output_path = fullfile(cfg.dir("morph_mat"), rootname + ".mat");
    if morpho.io.is_locked(output_path), continue; end

    cfg.ensure("morph_mat");
    cfg.ensure("morph_avi");
    cfg.ensure("masks");

    % Streaming variance — no full video in RAM
    [~, frame_var] = morpho.video.streaming_stats(files(i), ...
        skipFirstN=round(fps));
    mask = morpho.masking.auto_variance_threshold(frame_var);
    mask = morpho.masking.morphological_cleanup(mask, cfg.masking);

    % Interactive mask editing on single context frame
    context = morpho.video.read_single(files(i), cfg.masking.context_frame);
    mask = morpho.ui.brush_edit_loop(context, mask, cfg.masking);

    % Chunk-process tissue classification
    morpho.video.process_chunks(files(i), ...
        @(chunk, idx) morpho.masking.classify_tissue(chunk, mask, cfg.masking), ...
        outputFile=output_path, chunkSize=500);

    morpho.io.lock(output_path);
end
```

## Migration Strategy

1. Build `+morpho/` package alongside existing scripts — no breaking changes
2. Refactor one stage at a time, starting with Morpho1 (most complex shared logic)
3. Run old and new side-by-side to verify identical outputs
4. Once all stages migrated, remove duplicated code from bonus_scripts/ (UI functions)

## Out of Scope

- Bonus scripts (unchanged, standalone tools)
- GUI framework or app designer conversion
- Parallel processing / parfor (can be added later within process_chunks)
- Python port
