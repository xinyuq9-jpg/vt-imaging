# VT-Imaging Code Reorganization — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extract shared logic from Morpho0–5 into a `+morpho/` MATLAB package with a Config class, shared utilities, and chunked video processing.

**Architecture:** Keep Morpho scripts as entry points. All shared logic (paths, params, lock files, UI, video I/O, masking, tracing) moves into `+morpho/` package classes with static methods. Video processing switches from full-RAM loading to chunked/streaming.

**Tech Stack:** MATLAB R2025a, Image Processing Toolbox. Uses `arguments` blocks, `dictionary`, `string` arrays, `classdef` with static methods, MATLAB packages (`+folder`).

**Design doc:** `docs/plans/2026-03-16-code-reorganization-design.md`

---

## Task 1: Create `+morpho/Config.m` — Central Configuration

**Files:**
- Create: `+morpho/Config.m`

**Step 1: Create the package directory and Config class**

```matlab
% +morpho/Config.m
classdef Config
    properties
        projectDir      string
        remoteBase      string = ""
        remoteLogDir    string = ""

        register    struct
        masking     struct
        subsetter   struct
        qa          struct
        outliner    struct
        finaliser   struct
    end

    methods
        function obj = Config(opts)
            arguments
                opts.projectDir string = string(pwd)
            end
            obj.projectDir = opts.projectDir;
            obj.register  = obj.defaultRegister();
            obj.masking   = obj.defaultMasking();
            obj.subsetter = obj.defaultSubsetter();
            obj.qa        = obj.defaultQA();
            obj.outliner  = obj.defaultOutliner();
            obj.finaliser = obj.defaultFinaliser();
        end

        function p = dir(obj, name)
            arguments
                obj
                name string
            end
            map = dictionary( ...
                "avi_raw",          "avi_raw", ...
                "avi_reg",          "avi_reg", ...
                "reg_transforms",   fullfile("avi_reg","reg_trasforms"), ...
                "reference_run",    "reference_run", ...
                "morph",            "morph", ...
                "morph_avi",        fullfile("morph","avi"), ...
                "morph_mat",        fullfile("morph","mat"), ...
                "mat_sub",          fullfile("morph","mat_sub"), ...
                "log_sub",          fullfile("morph","mat_sub","log_sub"), ...
                "mat_qa",           fullfile("morph","mat_QA"), ...
                "qa_masks",         fullfile("morph","mat_QA_masks"), ...
                "masks",            fullfile("morph","masks"), ...
                "vt_trace",         fullfile("morph","vt_trace"), ...
                "vt_trace_mat",     fullfile("morph","vt_trace_mat"), ...
                "vt_trace_avi",     fullfile("morph","vt_trace_avi"), ...
                "vt_skeleton",      fullfile("morph","vt_skeleton"), ...
                "vt_endpoints",     fullfile("morph","vt_endpoints"), ...
                "vt_trace_final",         fullfile("morph","vt_trace","finaliser"), ...
                "vt_trace_mat_final",     fullfile("morph","vt_trace_mat","finaliser"), ...
                "vt_trace_avi_final",     fullfile("morph","vt_trace_avi","finaliser"), ...
                "vt_endpoints_final",     fullfile("morph","vt_endpoints","finaliser"), ...
                "logs_local",       "logs" ...
            );
            p = fullfile(obj.projectDir, map(name));
        end

        function ensure(obj, name)
            d = obj.dir(name);
            if ~isfolder(d), mkdir(d); end
        end

        function names = all_dir_names(~)
            % Return all known directory keys (useful for batch ensure)
            names = ["avi_raw","avi_reg","reg_transforms","reference_run", ...
                     "morph","morph_avi","morph_mat","mat_sub","log_sub", ...
                     "mat_qa","qa_masks","masks","vt_trace","vt_trace_mat", ...
                     "vt_trace_avi","vt_skeleton","vt_endpoints", ...
                     "vt_trace_final","vt_trace_mat_final", ...
                     "vt_trace_avi_final","vt_endpoints_final","logs_local"];
        end
    end

    methods (Static)
        function s = defaultRegister()
            s = struct( ...
                'reference_frame', 100 ...
            );
        end

        function s = defaultMasking()
            s = struct( ...
                'skip_manual_mask_edit_if_shared_mask_loaded', false, ...
                'use_saved_mask_if_available', true, ...
                'warn_if_mask_missing', true, ...
                'use_saved_manual_threshold_if_available', false, ...
                'save_manual_threshold_for_group', true, ...
                'warn_if_manual_threshold_missing', true, ...
                'mask_opacity', 0.45, ...
                'automatic_var_threshold', true, ...
                'var_threshold', 0.01, ...
                'mask_thickening', 10, ...
                'final_erode', 3, ...
                'automatic_tissue_threshold', false, ...
                'manual_tissue_threshold_chooser', true, ...
                'manual_tissue_threshold', 62, ...
                'lip_clip', true, ...
                'context_frame_chooser', "manual", ...
                'context_frame_default', 100, ...
                'draw_mode', 'D', ...
                'brush_size', 10 ...
            );
        end

        function s = defaultSubsetter()
            s = struct();
        end

        function s = defaultQA()
            s = struct( ...
                'use_saved_QA_mask_if_available', false, ...
                'skip_manual_QA_if_shared_mask_loaded', true, ...
                'save_shared_QA_mask_for_group', true, ...
                'warn_if_QA_mask_missing', true, ...
                'brush_size', 50, ...
                'draw_mode', 'E' ...
            );
        end

        function s = defaultOutliner()
            s = struct( ...
                'draw_connector', "a_star", ...
                'a_star_weight', 999, ...
                'lambda', 0.5, ...
                'wantplot', false, ...
                'polynomial_degree', 2, ...
                'manual_check', false, ...
                'suspicion_threshold', 30, ...
                'vt_skel_thresh', 0.75, ...
                'scaling_factor', 5 ...
            );
        end

        function s = defaultFinaliser()
            s = struct( ...
                'scaling_factor', 1.5, ...
                'brush_size', 5, ...
                'draw_mode', 'E' ...
            );
        end
    end
end
```

**Step 2: Verify in MATLAB**

Run:
```matlab
cfg = morpho.Config();
disp(cfg.dir("avi_reg"))
disp(cfg.dir("vt_trace"))
disp(cfg.masking)
cfg.ensure("avi_reg")
```
Expected: paths resolve correctly, masking struct has all defaults, directory created.

**Step 3: Commit**

```bash
git add +morpho/Config.m
git commit -m "feat: add morpho.Config class with centralized paths and parameters"
```

---

## Task 2: Create `+morpho/io.m` — File I/O and Lock Utilities

**Files:**
- Create: `+morpho/io.m`

**Step 1: Write the io class**

```matlab
% +morpho/io.m
classdef io
    methods (Static)

        %% ---- Lock file management ----

        function tf = is_locked(filepath)
            tf = isfile(string(filepath) + ".lock");
        end

        function acquired = acquire_lock(filepath)
            lockpath = string(filepath) + ".lock";
            if isfile(lockpath)
                acquired = false;
                return;
            end
            fid = fopen(lockpath, 'wt');
            if fid < 0
                acquired = false;
                return;
            end
            fprintf(fid, 'locked_at,%s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
            fclose(fid);
            acquired = true;
        end

        function release_lock(filepath)
            lockpath = string(filepath) + ".lock";
            if isfile(lockpath)
                delete(lockpath);
            end
        end

        %% ---- Output validation ----

        function tf = is_done(outputs, min_bytes)
            % Check if all output files exist and exceed min_bytes.
            % outputs: string array or cell array of file paths
            arguments
                outputs
                min_bytes (1,1) double = 1
            end
            tf = true;
            for i = 1:numel(outputs)
                d = dir(outputs{i});
                if isempty(d) || d(1).bytes < min_bytes
                    tf = false;
                    return;
                end
            end
        end

        %% ---- ADB filename parsing ----

        function [adb_id, block_num] = parse_adb(rootname)
            % Parse ADB group and block number from filename root.
            % e.g. "ADB17block_2_lag_0.36667" -> ("ADB17", 2)
            tok = regexp(string(rootname), '^(ADB\d+)block_(\d+)', 'tokens', 'once');
            if isempty(tok)
                error("morpho:io:badFilename", ...
                    "Filename does not match ADB##block_#_... pattern: %s", rootname);
            end
            adb_id = string(tok{1});
            block_num = str2double(tok{2});
        end

        function rootname = strip_suffix(filename, suffix)
            % Remove known suffix from filename.
            % e.g. strip_suffix("ADB17block_1_lag_0.36_out.mat", "_out.mat")
            %   -> "ADB17block_1_lag_0.36"
            rootname = string(filename);
            if endsWith(rootname, suffix)
                rootname = extractBefore(rootname, strlength(rootname) - strlength(suffix) + 1);
            end
        end

        %% ---- File discovery ----

        function file_list = list_files(inputDir, extension)
            % List files in directory matching extension.
            % Returns struct array like dir() output.
            arguments
                inputDir string
                extension string = ".mat"
            end
            file_list = dir(fullfile(inputDir, "*" + extension));
            if isempty(file_list)
                error("morpho:io:noFiles", ...
                    "No files with extension %s found in %s", extension, inputDir);
            end
        end

        %% ---- Cached remote path prompting ----

        function remote_path = prompt_remote_dir(cache_file, prompt_title)
            % Prompt user for remote directory with caching.
            % If cache_file exists and path is valid, offers reuse.
            arguments
                cache_file string
                prompt_title string = "Select remote folder"
            end
            remote_path = "";

            if isfile(cache_file)
                S = load(cache_file);
                fnames = fieldnames(S);
                if ~isempty(fnames)
                    cached = string(S.(fnames{1}));
                    if isfolder(cached)
                        q = sprintf('Reuse cached folder?\n\n%s', cached);
                        choice = questdlg(q, 'Reuse cached folder?', 'Yes', 'No', 'Yes');
                        if strcmp(choice, 'Yes')
                            remote_path = cached;
                            return;
                        end
                    end
                end
            end

            remote_path = string(uigetdir(pwd, prompt_title));
            if remote_path == "0"
                error("morpho:io:cancelled", "No folder selected.");
            end
        end

        function save_cache(cache_file, var_name, value)
            % Save a single variable to a cache .mat file.
            S.(var_name) = value;
            save(cache_file, '-struct', 'S');
        end

        %% ---- Logging ----

        function logmsg(msg)
            ts = datestr(now, 'yyyy-mm-dd HH:MM:SS');
            fprintf('[%s] %s\n', ts, msg);
        end

    end
end
```

**Step 2: Verify in MATLAB**

Run:
```matlab
% Lock file round-trip
morpho.io.acquire_lock("/tmp/test_morpho");
assert(morpho.io.is_locked("/tmp/test_morpho"));
morpho.io.release_lock("/tmp/test_morpho");
assert(~morpho.io.is_locked("/tmp/test_morpho"));

% ADB parsing
[id, num] = morpho.io.parse_adb("ADB17block_2_lag_0.36667");
assert(id == "ADB17" && num == 2);

% Strip suffix
r = morpho.io.strip_suffix("ADB17block_1_lag_0.36_out.mat", "_out.mat");
assert(r == "ADB17block_1_lag_0.36");
```
Expected: all assertions pass.

**Step 3: Commit**

```bash
git add +morpho/io.m
git commit -m "feat: add morpho.io with lock files, ADB parsing, file discovery"
```

---

## Task 3: Create `+morpho/video.m` — Video I/O and Chunked Processing

**Files:**
- Create: `+morpho/video.m`

**Step 1: Write the video class**

```matlab
% +morpho/video.m
classdef video
    methods (Static)

        function n = frame_count(videoPath)
            % Get frame count from video file.
            v = VideoReader(string(videoPath));
            n = max(1, floor(v.Duration * v.FrameRate + 1e-6));
            try
                n = min(n, v.NumFrames);
            catch
            end
        end

        function fps = frame_rate(videoPath)
            v = VideoReader(string(videoPath));
            fps = v.FrameRate;
        end

        function frame = to_gray_single(frame)
            % Convert raw frame to 2D single-precision grayscale.
            % Handles RGB, 4D, squeeze, and cast in one place.
            % Replaces the 5-line block repeated in every script.
            if ndims(frame) == 4
                frame = frame(:,:,1,:);
                frame = squeeze(frame);
            elseif ndims(frame) == 3 && size(frame,3) == 3
                frame = frame(:,:,1);
            end
            frame = squeeze(frame);
            if ~isa(frame, 'single')
                frame = single(frame);
            end
        end

        function frame = read_single(videoPath, frameIdx)
            % Read one frame as single-precision grayscale.
            v = VideoReader(string(videoPath));
            raw = read(v, frameIdx);
            frame = morpho.video.to_gray_single(raw);
        end

        function frames = read_frames(videoPath, frameIndices)
            % Read specific frames as H x W x N single grayscale.
            % If frameIndices is empty, reads all frames.
            arguments
                videoPath string
                frameIndices = []
            end
            v = VideoReader(videoPath);

            if isempty(frameIndices)
                raw = read(v);
            else
                % read(v, [first last]) reads a contiguous range
                % For arbitrary indices, read contiguous then subset
                raw = read(v, [min(frameIndices) max(frameIndices)]);
                % Adjust indices relative to the range start
                adj = frameIndices - min(frameIndices) + 1;
                if ndims(raw) == 4
                    raw = raw(:,:,:,adj);
                else
                    raw = raw(:,:,adj);
                end
            end

            frames = morpho.video.to_gray_single(raw);
        end

        function [running_mean, running_var] = streaming_stats(videoPath, opts)
            % Welford's online algorithm for per-pixel mean and variance.
            % Single pass, O(H x W) memory regardless of frame count.
            %
            % Returns:
            %   running_mean: H x W single — mean intensity per pixel
            %   running_var:  H x W single — variance per pixel
            arguments
                videoPath string
                opts.frameIndices = []
                opts.skipFirstN (1,1) double = 0
            end
            v = VideoReader(videoPath);
            total_frames = morpho.video.frame_count(videoPath);

            if isempty(opts.frameIndices)
                opts.frameIndices = 1:total_frames;
            end

            % Skip first N frames (noisy)
            if opts.skipFirstN > 0
                opts.frameIndices = opts.frameIndices(opts.frameIndices > opts.skipFirstN);
            end

            running_mean = [];
            running_var = [];
            n = 0;

            for i = 1:numel(opts.frameIndices)
                idx = opts.frameIndices(i);
                raw = read(v, idx);
                frame = morpho.video.to_gray_single(raw);

                if isempty(running_mean)
                    running_mean = zeros(size(frame), 'single');
                    running_var  = zeros(size(frame), 'single');
                end

                n = n + 1;
                delta = frame - running_mean;
                running_mean = running_mean + delta / n;
                delta2 = frame - running_mean;
                running_var = running_var + delta .* delta2;
            end

            if n > 1
                running_var = running_var / (n - 1);
            end
        end

        function process_chunks(videoPath, processFn, opts)
            % Chunked frame processing. Never holds more than chunkSize
            % frames in RAM. processFn receives (chunk, frameIndices) and
            % returns a result array of same frame dimension.
            %
            % If outputMatFile is set, results are saved incrementally
            % to a -v7.3 matfile as vt_output(:,:,indices).
            arguments
                videoPath string
                processFn function_handle
                opts.chunkSize (1,1) double = 500
                opts.frameIndices = []
                opts.outputMatFile string = ""
            end

            total = morpho.video.frame_count(videoPath);
            if isempty(opts.frameIndices)
                opts.frameIndices = 1:total;
            end

            nFrames = numel(opts.frameIndices);
            v = VideoReader(videoPath);

            % Pre-create output matfile if requested
            mf = [];
            if opts.outputMatFile ~= ""
                % Read one frame to get dimensions
                sample = morpho.video.to_gray_single(read(v, opts.frameIndices(1)));
                [h, w] = size(sample);
                % Create -v7.3 file with pre-allocated array
                save(opts.outputMatFile, 'h', '-v7.3');
                mf = matfile(opts.outputMatFile, 'Writable', true);
                mf.vt_output = false(h, w, nFrames);
            end

            nChunks = ceil(nFrames / opts.chunkSize);

            for c = 1:nChunks
                startIdx = (c-1) * opts.chunkSize + 1;
                endIdx = min(c * opts.chunkSize, nFrames);
                chunkFrameNums = opts.frameIndices(startIdx:endIdx);

                % Read chunk — contiguous range then subset
                raw = read(v, [chunkFrameNums(1), chunkFrameNums(end)]);
                chunk = morpho.video.to_gray_single(raw);

                % Handle case where read returns more frames than needed
                needed = chunkFrameNums - chunkFrameNums(1) + 1;
                if size(chunk, 3) > numel(needed)
                    chunk = chunk(:,:,needed);
                end

                % Process
                result = processFn(chunk, chunkFrameNums);

                % Save incrementally
                if ~isempty(mf)
                    mf.vt_output(:,:,startIdx:endIdx) = result;
                end

                fprintf('  Chunk %d/%d complete (%d frames)\n', c, nChunks, endIdx - startIdx + 1);
            end

            % Clean up temp variable from matfile
            if ~isempty(mf) && isprop(mf, 'h')
                % Remove the placeholder 'h' variable
                % (can't remove from matfile, but it's harmless)
            end
        end

        function write_avi(filepath, frames, framerate, opts)
            % Write frames to AVI file.
            arguments
                filepath string
                frames
                framerate double
                opts.codec string = "Motion JPEG AVI"
                opts.quality double = 95
            end
            vw = VideoWriter(filepath, opts.codec);
            vw.FrameRate = framerate;
            if isprop(vw, 'Quality')
                vw.Quality = opts.quality;
            end
            open(vw);
            writeVideo(vw, frames);
            close(vw);
        end

    end
end
```

**Step 2: Verify in MATLAB**

Run (requires a test .avi in avi_reg/):
```matlab
% Test frame count
n = morpho.video.frame_count("avi_reg/some_test.avi");
disp(n)

% Test read_single
f = morpho.video.read_single("avi_reg/some_test.avi", 50);
assert(isa(f, 'single'))
assert(ismatrix(f))  % 2D

% Test streaming stats
[mu, v] = morpho.video.streaming_stats("avi_reg/some_test.avi", skipFirstN=30);
assert(all(size(mu) == size(f)))
```
Expected: frame count matches VideoReader, single frame is 2D single, stats match frame dimensions.

**Step 3: Commit**

```bash
git add +morpho/video.m
git commit -m "feat: add morpho.video with chunked processing and streaming stats"
```

---

## Task 4: Create `+morpho/ui.m` — Unified UI Utilities

**Files:**
- Create: `+morpho/ui.m`

**Step 1: Write the ui class**

This replaces `bonus_scripts/Morpho1_UI.m`, `Morpho3_UI.m`, `Morpho4_UI.m`, `Morpho5_UI.m`.

```matlab
% +morpho/ui.m
classdef ui
    methods (Static)

        function [draw_mode, brush_size, ink, varargout] = settings_dialog(draw_mode, brush_size, mask_size, opts)
            % Unified settings dialog replacing Morpho1_UI, Morpho3_UI,
            % Morpho4_UI, Morpho5_UI.
            %
            % Base fields: draw_mode + brush_size (always shown)
            % Optional fields controlled by opts:
            %   show_context_frame, show_opacity
            %
            % Returns: [draw_mode, brush_size, ink]
            %   Plus optional: context_frame, mask_opacity (via varargout)
            arguments
                draw_mode
                brush_size
                mask_size
                opts.modes string = "DE"              % allowed mode chars
                opts.show_context_frame logical = false
                opts.show_opacity logical = false
                opts.no_frames (1,1) double = 1
                opts.context_frame (1,1) double = 1
                opts.mask_opacity (1,1) double = 0.5
                opts.draw_mode_help string = ""       % extra text for draw help
            end

            % Build prompt and defaults dynamically
            prompt = {};
            definput = {};

            if contains(opts.modes, "R")
                prompt{end+1} = 'Enter [R] to redraw, [E] to Erase:';
            else
                prompt{end+1} = 'Enter [D] to draw, [E] to Erase:';
            end
            definput{end+1} = draw_mode;

            prompt{end+1} = 'Brush size (pixels):';
            definput{end+1} = int2str(brush_size);

            context_frame = opts.context_frame;
            mask_opacity = opts.mask_opacity;

            if opts.show_context_frame
                prompt{end+1} = sprintf('Context frame (1-%d):', opts.no_frames);
                definput{end+1} = int2str(context_frame);
            end

            if opts.show_opacity
                prompt{end+1} = 'Mask opacity (0 to 1):';
                definput{end+1} = num2str(mask_opacity);
            end

            draw_settings = inputdlg(prompt, 'Settings', [1 40], definput);

            % Handle cancel
            if isempty(draw_settings)
                ink = morpho.ui.mode_to_ink(draw_mode);
                if opts.show_context_frame, varargout{1} = context_frame; end
                if opts.show_opacity
                    idx = 1 + opts.show_context_frame;
                    varargout{idx} = mask_opacity;
                end
                return;
            end

            % Parse draw mode
            field_idx = 1;
            new_mode = upper(draw_settings{field_idx});
            if contains(opts.modes, new_mode)
                draw_mode = new_mode;
            else
                draw_mode = char(extract(opts.modes, 1)); % default to first allowed
                disp("Invalid mode. Defaulting to " + draw_mode);
            end
            ink = morpho.ui.mode_to_ink(draw_mode);

            % Parse brush size
            field_idx = 2;
            new_brush = str2double(draw_settings{field_idx});
            if ~isnan(new_brush)
                brush_size = round(new_brush);
            else
                disp("Invalid brush size. Keeping previous value.");
            end
            brush_size = max(0, brush_size);
            max_brush = floor(min(mask_size) / 4);
            if brush_size > max_brush
                brush_size = max_brush;
                disp("Brush size too large, reduced to: " + int2str(brush_size));
            end

            % Parse optional context frame
            field_idx = 3;
            if opts.show_context_frame
                new_cf = str2double(draw_settings{field_idx});
                if ~isnan(new_cf)
                    context_frame = max(1, min(opts.no_frames, round(new_cf)));
                end
                varargout{1} = context_frame;
                field_idx = field_idx + 1;
            end

            % Parse optional opacity
            if opts.show_opacity
                new_op = str2double(draw_settings{field_idx});
                if ~isnan(new_op)
                    mask_opacity = max(0, min(1, new_op));
                end
                idx = 1 + opts.show_context_frame;
                varargout{idx} = mask_opacity;
            end

            if opts.draw_mode_help ~= "" && draw_mode == 'D'
                disp(opts.draw_mode_help);
            end

            disp("Mode = " + draw_mode + "; Brush size = " + int2str(brush_size) + " pixels");
        end

        function ink = mode_to_ink(draw_mode)
            % Convert draw mode character to ink value.
            if draw_mode == 'E' || draw_mode == 'e'
                ink = 0;
            else
                ink = 1;  % D, R, or any other mode = draw
            end
        end

        function show_pair(frame, overlay, opts)
            % Standardized frame+overlay display.
            arguments
                frame
                overlay
                opts.scaling_factor (1,1) double = 1
                opts.position (1,4) double = [0.5, 0, 0.5, 1]
            end
            imshowpair(frame / opts.scaling_factor, overlay);
            set(gcf, 'Units', 'Normalized', 'OuterPosition', opts.position);
        end

        function [x_brush, y_brush] = expand_brush(x, y, brush_size, mask_size)
            % Expand click coordinates to brush range, clamped to image bounds.
            x = round(double(x));
            y = round(double(y));
            x_brush = max(1, x - brush_size) : min(mask_size(2), x + brush_size);
            y_brush = max(1, y - brush_size) : min(mask_size(1), y + brush_size);
        end

        function [hBase, hOverlay] = init_mask_overlay(ax, frame2d, mask2d, mask_opacity)
            % Create initial mask overlay display (from Morpho1).
            frame2d = single(frame2d);
            frame2d = frame2d - min(frame2d(:));
            frame2d = frame2d ./ max(frame2d(:) + eps);

            cla(ax);
            hold(ax, 'on');

            hBase = imshow(frame2d, 'Parent', ax);

            red_overlay = cat(3, ones(size(mask2d)), zeros(size(mask2d)), zeros(size(mask2d)));
            hOverlay = imshow(red_overlay, 'Parent', ax);
            hOverlay.AlphaData = double(mask2d > 0) * mask_opacity;

            hold(ax, 'off');
            axis(ax, 'image');
        end

        function update_mask_overlay(hBase, hOverlay, frame2d, mask2d, mask_opacity)
            % Update existing mask overlay (fast redraw without recreating figure).
            frame2d = single(frame2d);
            frame2d = frame2d - min(frame2d(:));
            frame2d = frame2d ./ max(frame2d(:) + eps);

            hBase.CData = frame2d;
            hOverlay.AlphaData = double(mask2d > 0) * mask_opacity;
        end

        function show_pink_overlay(anatomy, mask, mask_size)
            % Show anatomy with pink overlay for QA (Morpho3 style).
            imshow(anatomy / max(anatomy(:)), 'InitialMag', 'fit');
            pink = cat(3, ones(mask_size), zeros(mask_size), ones(mask_size)/2);
            hold on;
            h = imshow(pink);
            hold off;
            set(h, 'AlphaData', mask);
            set(gcf, 'Units', 'Normalized', 'OuterPosition', [0.5, 0, 0.5, 1]);
        end

        function fig = create_editor_figure(title_str)
            % Create a maximized editor figure.
            mp = get(0, 'MonitorPositions');
            mp = mp(1,:);
            pad = 40;
            fig_pos = [mp(1)+pad, mp(2)+pad, mp(3)-2*pad, mp(4)-2*pad];

            fig = figure('Name', title_str, ...
                         'NumberTitle', 'off', ...
                         'Units', 'pixels', ...
                         'Position', fig_pos);
        end

    end
end
```

**Step 2: Verify in MATLAB**

Run:
```matlab
% Test mode_to_ink
assert(morpho.ui.mode_to_ink('D') == 1);
assert(morpho.ui.mode_to_ink('E') == 0);
assert(morpho.ui.mode_to_ink('R') == 1);

% Test expand_brush
[xb, yb] = morpho.ui.expand_brush(5, 5, 2, [10 10]);
assert(isequal(xb, 3:7));
assert(isequal(yb, 3:7));

% Test edge clamping
[xb, yb] = morpho.ui.expand_brush(1, 1, 5, [10 10]);
assert(xb(1) == 1);
assert(yb(1) == 1);
```
Expected: all assertions pass.

**Step 3: Commit**

```bash
git add +morpho/ui.m
git commit -m "feat: add morpho.ui with unified settings dialog and display helpers"
```

---

## Task 5: Create `+morpho/masking.m` — Mask Operations

**Files:**
- Create: `+morpho/masking.m`

**Step 1: Write the masking class**

```matlab
% +morpho/masking.m
classdef masking
    methods (Static)

        function threshold = auto_variance_threshold(frames_var_scaled)
            % KSD-based optimal variance threshold.
            % Input: H x W scaled variance image (0-1 range).
            % Output: scalar threshold.
            [var_density_function, var_density_index] = ksdensity(frames_var_scaled(:));
            var_density_min = islocalmin(var_density_function);
            threshold = var_density_index(var_density_min);
            threshold = min(threshold);
            disp("Applying variance threshold: " + threshold);
        end

        function mask = variance_to_mask(frames_var, threshold)
            % Convert variance image to binary VT mask via thresholding +
            % largest cluster selection.
            frames_var_max = max(frames_var(:));
            frames_var_scaled = frames_var / frames_var_max;

            frames_var_mask = frames_var_scaled > threshold;

            % Find largest non-background cluster
            lab_mat = bwlabel(frames_var_mask);
            labs = unique(lab_mat);
            labs_sum = zeros(length(labs), 1);
            for l = 1:length(labs)
                labs_sum(l) = sum(lab_mat(:) == labs(l));
            end
            [~, ii] = sort(labs_sum);
            vt_cluster_number = labs(ii(end-1)); % second largest (largest is background)
            mask = lab_mat == vt_cluster_number;
        end

        function mask = morphological_cleanup(mask, opts)
            % Morphological pipeline: thicken, bridge, close, erode.
            arguments
                mask
                opts.thicken (1,1) double = 10
                opts.bridge logical = true
                opts.close logical = true
                opts.erode (1,1) double = 3
            end
            if opts.thicken > 0
                mask = bwmorph(mask, 'thicken', opts.thicken);
            end
            if opts.bridge
                mask = bwmorph(mask, 'bridge');
            end
            if opts.close
                mask = bwmorph(mask, 'close');
            end
            if opts.erode > 0
                mask = bwmorph(mask, 'erode', opts.erode);
            end
        end

        function threshold = auto_tissue_threshold(frames, vt_mask, no_frames)
            % KSD-based tissue classification threshold.
            % Computes per-frame thresholds and returns median.
            arguments
                frames          % H x W x N single
                vt_mask         % H x W logical
                no_frames (1,1) double
            end
            vt_threshold_vec = zeros(no_frames, 1);

            for f = 1:no_frames
                vt = frames(:,:,f);
                [tdf, tdi] = ksdensity(vt(vt_mask));
                tdm = islocalmin(tdf);
                tt = tdi(tdm);
                tt = min(tt);
                vt_threshold_vec(f) = tt;
            end

            failed = vt_threshold_vec == 0 | isnan(vt_threshold_vec);
            threshold = median(vt_threshold_vec(~failed));
        end

        function tissue_mask = classify_tissue_frame(frame, vt_mask, threshold, opts)
            % Classify tissue for a single frame.
            % Returns binary tissue mask.
            arguments
                frame           % H x W single
                vt_mask         % H x W logical
                threshold (1,1) double
                opts.lip_clip logical = true
            end
            vt = frame .* vt_mask;
            tissue_mask = vt < threshold & vt_mask > 0;

            % Lip clip
            if opts.lip_clip
                soft_tissue_mask = frame >= threshold & vt_mask > 0;
                soft_tissue_colsums = sum(soft_tissue_mask, 1);
                lip_col = find(soft_tissue_colsums, 1, 'first') - 1;
                if ~isempty(lip_col) && lip_col >= 1
                    tissue_mask(:, 1:lip_col) = 0;
                end
            end

            % Morphological cleanup
            tissue_mask = bwmorph(tissue_mask, 'spur');
            tissue_mask = bwmorph(tissue_mask, 'clean');
            tissue_mask = bwmorph(tissue_mask, 'close');
            tissue_mask = bwmorph(tissue_mask, 'fill');
        end

    end
end
```

**Step 2: Verify in MATLAB**

Run:
```matlab
% Test morphological_cleanup
test_mask = false(20, 20);
test_mask(5:15, 5:15) = true;
cleaned = morpho.masking.morphological_cleanup(test_mask, thicken=2, erode=1);
assert(islogical(cleaned) || all(cleaned(:) == 0 | cleaned(:) == 1));
```
Expected: returns a valid binary mask.

**Step 3: Commit**

```bash
git add +morpho/masking.m
git commit -m "feat: add morpho.masking with threshold detection and tissue classification"
```

---

## Task 6: Create `+morpho/registration.m` — Registration Helpers

**Files:**
- Create: `+morpho/registration.m`

**Step 1: Write the registration class**

Extracts logic from `Morpho0_register.m`'s `register_mri_stream_same` function.

```matlab
% +morpho/registration.m
classdef registration
    methods (Static)

        function frame = ensure_gray_2d(frame)
            % Ensure frame is 2D grayscale.
            if ndims(frame) == 4
                frame = frame(:,:,1,1);
                frame = squeeze(frame);
            elseif ndims(frame) == 3
                frame = frame(:,:,1);
                frame = squeeze(frame);
            end
        end

        function [tform, registered] = register_frame(frame, fixed_masked, optimizer, metric, outView)
            % Register one frame to reference using rigid transform.
            arguments
                frame
                fixed_masked
                optimizer
                metric
                outView
            end
            frame = morpho.registration.ensure_gray_2d(frame);
            tform = imregtform(frame, fixed_masked, 'rigid', optimizer, metric);
            registered = imwarp(frame, tform, 'OutputView', outView);
            if ~isa(registered, 'uint8')
                registered = im2uint8(registered);
            end
        end

        function fixed_masked = apply_cutoff_mask(reference, cutoff_X, cutoff_Y)
            % Apply the upper-region mask to reference image.
            fixed_masked = morpho.registration.ensure_gray_2d(reference);
            size_Y = size(fixed_masked, 2);
            fixed_masked(cutoff_Y:size_Y, 1:cutoff_X, :) = 0;
        end

        function s = bytestr(n)
            % Format byte count as human-readable string.
            units = {'B','KB','MB','GB','TB'};
            s = double(n);
            u = 1;
            while s >= 1024 && u < numel(units)
                s = s / 1024;
                u = u + 1;
            end
            s = sprintf('%.2f %s', s, units{u});
        end

    end
end
```

**Step 2: Verify in MATLAB**

Run:
```matlab
% Test ensure_gray_2d
rgb = uint8(rand(100,100,3)*255);
gray = morpho.registration.ensure_gray_2d(rgb);
assert(ismatrix(gray));

% Test bytestr
assert(contains(morpho.registration.bytestr(1024), 'KB'));
assert(contains(morpho.registration.bytestr(1048576), 'MB'));
```
Expected: assertions pass.

**Step 3: Commit**

```bash
git add +morpho/registration.m
git commit -m "feat: add morpho.registration with rigid frame registration helpers"
```

---

## Task 7: Create `+morpho/tracing.m` — Boundary Tracing

**Files:**
- Create: `+morpho/tracing.m`

**Step 1: Write the tracing class**

Extracts logic from `Morpho4_outliner.m`. The core tracing logic is complex — this task extracts the reusable parts. The connector methods (a_star, spline, polynomial, etc.) are left as calls to existing `bonus_scripts/` functions since they're already standalone.

```matlab
% +morpho/tracing.m
classdef tracing
    methods (Static)

        function vt_skel = compute_skeleton(vt_mean, threshold)
            % Compute mean VT skeleton via thinning.
            arguments
                vt_mean     % H x W mean VT frequency map
                threshold (1,1) double = 0.75
            end
            vt_skel = bwmorph(vt_mean > threshold, 'thin', 'Inf');
        end

        function [top, bottom] = find_endpoints(vt_mask)
            % Find VT endpoints (lips = most anterior, larynx = most ventral).
            % Returns [y, x] pairs.
            vt_linear = find(vt_mask);
            [vt_y, vt_x] = ind2sub(size(vt_mask), vt_linear);

            % Top (anterior/lips): most anterior pixel, then most dorsal of those
            top_x = min(vt_x);
            top_y = min(vt_y(vt_x == top_x));
            top = [top_y, top_x];

            % Bottom (larynx): most ventral pixel, then median x
            bottom_y = max(vt_y);
            bottom_x = round(median(vt_x(vt_y == bottom_y)));
            bottom = [bottom_y, bottom_x];
        end

        function [trace_x, trace_y, trace_mat] = trace_boundary(vt_mask, start_point)
            % Trace boundary clockwise from start_point.
            % start_point: [y, x]
            % Returns x coords, y coords, and binary trace matrix.
            arguments
                vt_mask logical
                start_point (1,2) double  % [y, x]
            end

            trace = bwtraceboundary(vt_mask, start_point, 'W', 8, Inf, 'clockwise');

            trace_y = trace(:,1);
            trace_x = trace(:,2);

            trace_mat = false(size(vt_mask));
            trace_ind = sub2ind(size(vt_mask), trace_y, trace_x);
            trace_mat(trace_ind) = true;
        end

        function [n_compartments, lab_mat, sorted_labels] = analyze_clusters(vt_frame)
            % Analyze connected components in a VT frame.
            % Returns cluster count (excluding background), label matrix,
            % and labels sorted by size (largest first).
            lab_mat = bwlabel(vt_frame);
            labs = unique(lab_mat);

            labs_sum = zeros(length(labs), 1);
            for l = 1:length(labs)
                labs_sum(l) = sum(lab_mat(:) == labs(l));
            end

            [~, ii] = sort(labs_sum, 'descend');
            sorted_labels = labs(ii);

            % Exclude background (0)
            sorted_labels = sorted_labels(sorted_labels > 0);
            n_compartments = numel(sorted_labels);
        end

        function bridge_mask = a_star_bridge(vt_frame, vt_ever, frame_data, a_star_weight)
            % Build A* bridge between disconnected compartments.
            % vt_frame: H x W binary mask for this frame
            % vt_ever: H x W binary — pixels that are ever VT
            % frame_data: H x W single — raw intensity for cost
            % a_star_weight: cost multiplier
            arguments
                vt_frame logical
                vt_ever logical
                frame_data
                a_star_weight (1,1) double = 999
            end

            map = vt_ever;
            costs = double(frame_data .* map * a_star_weight);

            [top, bottom] = morpho.tracing.find_endpoints(vt_frame);
            frame_size = size(vt_frame);

            start_idx = sub2ind(frame_size, top(1), top(2));
            goal_idx = sub2ind(frame_size, bottom(1), bottom(2));

            a_star_ind = a_star(map, costs, start_idx, goal_idx);

            bridge_mask = false(frame_size);
            bridge_mask(a_star_ind) = true;
            bridge_mask(vt_frame) = false; % don't duplicate existing pixels
        end

    end
end
```

**Step 2: Verify in MATLAB**

Run:
```matlab
% Test find_endpoints
test_mask = false(50, 50);
test_mask(10:40, 5:20) = true;
[top, bottom] = morpho.tracing.find_endpoints(test_mask);
assert(top(2) == 5);  % most anterior x
assert(bottom(1) == 40);  % most ventral y

% Test analyze_clusters
test2 = false(50, 50);
test2(5:10, 5:10) = true;
test2(30:40, 30:40) = true;
[n, ~, ~] = morpho.tracing.analyze_clusters(test2);
assert(n == 2);
```
Expected: endpoints correct, 2 clusters detected.

**Step 3: Commit**

```bash
git add +morpho/tracing.m
git commit -m "feat: add morpho.tracing with boundary tracing, cluster analysis, and A* bridging"
```

---

## Task 8: Refactor Morpho0_register.m

**Files:**
- Modify: `Morpho0_register.m`

**Step 1: Back up the original**

```bash
cp Morpho0_register.m Morpho0_register.m.bak
```

**Step 2: Refactor to use +morpho package**

Replace directory setup, helper functions, and shared logic with package calls. Keep the overall structure and flow identical. Key changes:

- Replace inline `logmsg` with `morpho.io.logmsg`
- Replace inline `ensure_gray_2d` / `ensure_gray_2d_local` with `morpho.registration.ensure_gray_2d`
- Replace inline `bytestr` with `morpho.registration.bytestr`
- Replace manual `mkdir` calls with `cfg.ensure(...)`
- Replace manual directory paths with `cfg.dir(...)`
- Replace cached remote path logic with `morpho.io.prompt_remote_dir`
- Replace inline `register_mri_stream_same` with calls to `morpho.registration`
- Keep `addpath('bonus_scripts')` until all scripts migrated

The refactored script should call `cfg = morpho.Config()` at the top and use `cfg.dir("avi_reg")`, `cfg.dir("reg_transforms")`, etc.

**Step 3: Test manually**

Run `Morpho0_register` in MATLAB on a test ADB folder. Verify:
- Same registration output AVIs and CSVs produced
- Same interactive flow (ginput for mask, file selection)

**Step 4: Delete backup if successful**

```bash
rm Morpho0_register.m.bak
```

**Step 5: Commit**

```bash
git add Morpho0_register.m
git commit -m "refactor: Morpho0_register to use +morpho package utilities"
```

---

## Task 9: Refactor Morpho1_masking.m

**Files:**
- Modify: `Morpho1_masking.m`

This is the most complex refactor — it touches Config, io, video, ui, and masking.

**Step 1: Back up the original**

```bash
cp Morpho1_masking.m Morpho1_masking.m.bak
```

**Step 2: Refactor**

Key changes:
- `cfg = morpho.Config()` at top, all paths via `cfg.dir(...)`
- Replace `frames = read(v)` + squeeze/cast block with streaming approach:
  - `morpho.video.streaming_stats(...)` for variance computation
  - `morpho.video.read_single(...)` for context frame in mask editor
  - `morpho.video.process_chunks(...)` for tissue classification loop
- Replace parameter block at top with `cfg.masking` struct access
- Replace `select_input_files(...)` with `morpho.io.list_files(...)` (or keep using `select_input_files` — it's a good standalone function)
- Replace `Morpho1_UI(...)` call with `morpho.ui.settings_dialog(..., show_context_frame=true, show_opacity=true)`
- Replace inline `init_mask_overlay`, `update_mask_overlay`, `draw_mask_overlay` with `morpho.ui.init_mask_overlay`, `morpho.ui.update_mask_overlay`
- Replace ADB parsing block with `morpho.io.parse_adb(input_rootname)`
- Replace `mkdir` calls with `cfg.ensure(...)`
- Replace lock/resume logic with `morpho.io.acquire_lock` / `morpho.io.release_lock`
- Keep the interactive mask editing loop in the script (it's stage-specific flow), but use `morpho.ui.expand_brush` and `morpho.ui.settings_dialog` within it

**Step 3: Test manually**

Run `Morpho1_masking` on a previously processed ADB. Verify:
- Same mask output (.mat files)
- Interactive mask editor still works
- Memory usage lower (check with `whos` — no full `frames` array)

**Step 4: Delete backup**

```bash
rm Morpho1_masking.m.bak
```

**Step 5: Commit**

```bash
git add Morpho1_masking.m
git commit -m "refactor: Morpho1_masking to use +morpho package with chunked video processing"
```

---

## Task 10: Refactor Morpho2_subsetter.m

**Files:**
- Modify: `Morpho2_subsetter.m`

**Step 1: Back up the original**

```bash
cp Morpho2_subsetter.m Morpho2_subsetter.m.bak
```

**Step 2: Refactor**

Key changes:
- `cfg = morpho.Config()` at top
- Replace directory setup with `cfg.ensure(...)` calls
- Replace remote log caching with `morpho.io.prompt_remote_dir` + `morpho.io.save_cache`
- Replace `logmsg` with `morpho.io.logmsg`
- Replace `is_done`, `acquire_lock`, `release_lock`, `lock_file_for` helper functions with `morpho.io.is_done`, `morpho.io.acquire_lock`, `morpho.io.release_lock`
- Replace hardcoded paths with `cfg.dir("morph_mat")`, `cfg.dir("mat_sub")`, `cfg.dir("log_sub")`
- This stage loads .mat (not video), so no chunked video changes needed
- Remove the inline helper functions at bottom (they're now in `morpho.io`)

**Step 3: Test manually**

Run `Morpho2_subsetter`. Verify same `_sub.mat` and `_log.csv` outputs.

**Step 4: Delete backup, commit**

```bash
rm Morpho2_subsetter.m.bak
git add Morpho2_subsetter.m
git commit -m "refactor: Morpho2_subsetter to use +morpho package utilities"
```

---

## Task 11: Refactor Morpho3_QA.m

**Files:**
- Modify: `Morpho3_QA.m`

**Step 1: Back up the original**

```bash
cp Morpho3_QA.m Morpho3_QA.m.bak
```

**Step 2: Refactor**

Key changes:
- `cfg = morpho.Config()` at top, paths via `cfg.dir(...)`
- Replace parameter block with `cfg.qa`
- Replace `aframes = read(v)` full video load with:
  - `morpho.video.read_single(...)` for the context frame (anatomy_med)
  - For `vt_ever = mean(mframes, 3)`: this uses the .mat data not video, so it stays
  - For `anatomy_med = median(aframes, 3)`: use `morpho.video.streaming_stats(...)` to compute mean instead (or read a single representative frame since median across all frames is expensive and mean is close enough for display context)
- Replace `Morpho3_UI(...)` with `morpho.ui.settings_dialog(..., modes="RE")`
- Replace ADB parsing with `morpho.io.parse_adb`
- Replace brush expansion with `morpho.ui.expand_brush`
- Replace pink overlay display with `morpho.ui.show_pink_overlay`
- Replace `mkdir` with `cfg.ensure`

**Step 3: Test manually**

Run `Morpho3_QA`. Verify same `_QA.mat` outputs and interactive QA editor works.

**Step 4: Delete backup, commit**

```bash
rm Morpho3_QA.m.bak
git add Morpho3_QA.m
git commit -m "refactor: Morpho3_QA to use +morpho package with reduced memory usage"
```

---

## Task 12: Refactor Morpho4_outliner.m

**Files:**
- Modify: `Morpho4_outliner.m`

**Step 1: Back up the original**

```bash
cp Morpho4_outliner.m Morpho4_outliner.m.bak
```

**Step 2: Refactor**

This is the second most complex refactor. Key changes:
- `cfg = morpho.Config()` at top
- Replace parameter block with `cfg.outliner`
- Replace `frames = read(v)` full video load — this is tricky because Morpho4 needs both the raw frame (for A* cost) and the vt_output mask per frame. Strategy:
  - Load `vt_output` from .mat (already done)
  - For raw frames: use `morpho.video.read_single(...)` inside the per-frame loop (only one frame in RAM at a time)
  - For `mean_vt = mean(vt_output, 3)`: keep as-is (operates on .mat data)
- Replace cluster analysis with `morpho.tracing.analyze_clusters`
- Replace A* bridging block with `morpho.tracing.a_star_bridge`
- Replace endpoint finding with `morpho.tracing.find_endpoints`
- Replace `bwtraceboundary` calls with `morpho.tracing.trace_boundary`
- Replace `ismember(pixel_to_check, vt_output_linear)` in spline/poly loops with direct `vt_mask(row, col)` logical indexing
- Replace `Morpho4_UI(...)` with `morpho.ui.settings_dialog`
- Replace `morpho.ui.expand_brush` for brush operations
- Keep `addpath('bonus_scripts')` for `a_star`, `circfit`, `lowess_custom`, `fLOESS_marsh`

**Step 3: Test manually**

Run `Morpho4_outliner` on a test file. Verify:
- Same trace outputs (X.csv, Y.csv, _outline.mat)
- Same diagnostic AVI
- Faster execution on long videos (less RAM, no full video load)
- A* bridging still works correctly

**Step 4: Delete backup, commit**

```bash
rm Morpho4_outliner.m.bak
git add Morpho4_outliner.m
git commit -m "refactor: Morpho4_outliner to use +morpho package with per-frame video loading"
```

---

## Task 13: Refactor Morpho5_finaliser.m

**Files:**
- Modify: `Morpho5_finaliser.m`

**Step 1: Back up the original**

```bash
cp Morpho5_finaliser.m Morpho5_finaliser.m.bak
```

**Step 2: Refactor**

Key changes:
- `cfg = morpho.Config()` at top
- Replace parameter block with `cfg.finaliser`
- Replace `frames = read(v)` full video load with `morpho.video.read_single(...)` per frame on demand. The interactive loop only shows one frame at a time, so this is straightforward:
  - Before the `while f <= no_frames` loop, read frames on demand
  - Cache the current frame; when `f` changes, read the new one
- Replace `Morpho5_UI(...)` with `morpho.ui.settings_dialog(..., draw_mode_help="click two pixels to draw a straight line between them.")`
- Replace display calls with `morpho.ui.show_pair`
- Replace brush expansion with `morpho.ui.expand_brush`
- Replace endpoint/trace logic with `morpho.tracing.find_endpoints` and `morpho.tracing.trace_boundary`
- Replace `mkdir` with `cfg.ensure`
- Replace hardcoded paths with `cfg.dir(...)`

**Step 3: Test manually**

Run `Morpho5_finaliser` on a test file. Verify:
- Interactive frame editing still works (n/b/f/r keys)
- Draw and erase modes work
- Output traces match expected format
- Much lower memory usage

**Step 4: Delete backup, commit**

```bash
rm Morpho5_finaliser.m.bak
git add Morpho5_finaliser.m
git commit -m "refactor: Morpho5_finaliser to use +morpho package with on-demand frame loading"
```

---

## Task 14: Cleanup and Final Verification

**Files:**
- Modify: `Morpho2_subsetter_v4.m` (remove or mark as deprecated — it's a duplicate)
- Review: `bonus_scripts/Morpho*_UI.m` (now replaced by `morpho.ui.settings_dialog`)

**Step 1: Mark old UI functions as deprecated**

Add a deprecation notice to the top of each old UI file:
```matlab
% DEPRECATED: Use morpho.ui.settings_dialog() instead.
% This file is kept for backward compatibility with bonus_scripts.
```

**Step 2: Remove `addpath('bonus_scripts')` from refactored scripts**

Only if all used bonus_scripts functions are now in `+morpho/`. If `a_star.m`, `circfit.m`, etc. are still called directly, keep the addpath.

Check which bonus_scripts are still needed:
- `a_star.m` — still called by `morpho.tracing.a_star_bridge` → keep
- `circfit.m` — only used by deprecated circfit method → keep for now
- `lowess_custom.m`, `fLOESS_marsh.m` — used by lowess method → keep
- `manual_threshold_chooser.m` — still called by Morpho1 → keep
- `select_input_files.m` — still used as entry point file selector → keep (it's in root, not bonus_scripts)
- `Morpho*_UI.m` — replaced → mark deprecated

**Step 3: Run full pipeline end-to-end**

Process one complete ADB through Morpho0 → Morpho5. Verify:
- All outputs match expected format
- No MATLAB errors
- Memory usage stays bounded
- Interactive editors all work

**Step 4: Final commit**

```bash
git add -A
git commit -m "chore: mark deprecated UI functions, clean up addpath calls"
```

---

## Summary of Dependencies

```
Task 1 (Config)          — no dependencies
Task 2 (io)              — no dependencies
Task 3 (video)           — no dependencies (uses morpho.video internally)
Task 4 (ui)              — no dependencies
Task 5 (masking)         — no dependencies
Task 6 (registration)    — no dependencies
Task 7 (tracing)         — uses a_star from bonus_scripts
Tasks 1-7 can be done in parallel.

Task 8  (Morpho0)  — depends on Tasks 1, 2, 6
Task 9  (Morpho1)  — depends on Tasks 1, 2, 3, 4, 5
Task 10 (Morpho2)  — depends on Tasks 1, 2
Task 11 (Morpho3)  — depends on Tasks 1, 2, 3, 4
Task 12 (Morpho4)  — depends on Tasks 1, 2, 3, 4, 7
Task 13 (Morpho5)  — depends on Tasks 1, 2, 3, 4, 7
Task 14 (Cleanup)  — depends on all above
```
