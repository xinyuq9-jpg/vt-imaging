%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Michel Belyk, UCL
% July 2022
% belykm@gmail.com
%
% UPDATED:
% Use one shared mask per ADB group.
% Example:
%   ADB17block_1_lag_0.36667.avi
%   ADB17block_2_lag_1.20000.avi
%   ADB17block_3_lag_-0.50000.avi
%
% All of these will use the SAME shared mask:
%   morph/masks/ADB17block_1_msk.mat
%
% Lag suffix is ignored for mask lookup.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%
%SETABLE PARAMETERS%%%
%%%%%%%%%%%%%%%%%%%%%%

cfg = morpho.Config();
addpath("bonus_scripts");

%%%%%%%%%%%%%%%%%%%%%%%%
%%%manage directories%%%
%%%%%%%%%%%%%%%%%%%%%%%%

input_dir = cfg.dir("avi_reg");
cfg.ensure("morph");
cfg.ensure("morph_avi");
cfg.ensure("morph_mat");
cfg.ensure("masks");

%%%%%%%%%%%%%%%%%%%%%%
%Iterate through files
%%%%%%%%%%%%%%%%%%%%%%

list_input_files = morpho.select_input_files(input_dir, '.avi');

for iFile = 1:length(list_input_files) %loop through video files

    input_rootname = list_input_files(iFile).name(1:end-4); %remove file extension
    input_filename = fullfile(input_dir,list_input_files(iFile).name);

    % ============================================================
    % Parse ADB group from filename
    % Expected examples:
    %   ADB17block_1_lag_0.36667
    %   ADB36block_2_lag_18.8
    %   ADB24block_1_lag_-0.9
    %
    % We ignore lag and use ONE shared mask per ADB group:
    %   ADB17block_1_msk.mat
    % ============================================================
    [adb_id, block_num] = morpho.io.parse_adb(input_rootname);

    % Shared canonical mask path for the whole ADB group
    shared_mask_path = char(fullfile(cfg.dir("masks"), adb_id + "block_1_msk.mat"));

    % Optional exact-file diagnostic mask path
    perfile_mask_path = char(fullfile(cfg.dir("masks"), string(input_rootname) + "_msk.mat"));

    % Shared canonical manual threshold path
    shared_manual_threshold_path = char(fullfile(cfg.dir("masks"), adb_id + "block_1_manual_threshold.mat"));

    % Optional diagnostic threshold path
    perfile_manual_threshold_path = char(fullfile(cfg.dir("masks"), string(input_rootname) + "_manual_threshold.mat"));

    disp("Processing: " + input_rootname);
    disp("ADB group: " + adb_id + " | block: " + block_num);
    disp("Shared mask path: " + string(shared_mask_path));

    %read image data (streaming - do not load all frames into memory)
    v = VideoReader(input_filename);
    no_frames = floor(v.Duration * v.FrameRate);
    fps = v.FrameRate;

    if cfg.masking.context_frame_chooser == "auto"
        context_frame = round(no_frames/2); %which frame to show for anatomical context
    else
        context_frame = cfg.masking.context_frame_default;
    end

    vt_mask_dilate = [];      % will become the starting mask for manual refinement
    shared_mask_loaded = false;

    % ------------------------------
    % Option A: load shared ADB mask
    % ------------------------------
    if cfg.masking.use_saved_mask_if_available == 1 && isfile(shared_mask_path)
        try
            S = load(shared_mask_path);  % expects vt_mask_cleaned inside
            if isfield(S, 'vt_mask_cleaned')
                vt_mask_dilate = logical(S.vt_mask_cleaned);

                sample_frame = morpho.video.read_single(input_filename, 1);
                if ~isequal(size(vt_mask_dilate), [size(sample_frame,1), size(sample_frame,2)])
                    disp("WARNING: Shared mask size doesn't match current video frames. Falling back to auto mask.");
                    vt_mask_dilate = [];
                else
                    disp("Loaded shared ADB mask: " + string(shared_mask_path));
                    shared_mask_loaded = true;
                end

            else
                disp("WARNING: Shared mask file found but 'vt_mask_cleaned' not present. Falling back to auto mask.");
            end

        catch ME
            disp("WARNING: Failed to load shared ADB mask. Falling back to auto mask.");
            disp("Reason: " + string(ME.message));
        end

    elseif cfg.masking.use_saved_mask_if_available == 1 && cfg.masking.warn_if_mask_missing == 1
        disp("No shared mask found for ADB group " + adb_id + ". Building auto mask...");
    end

    % -----------------------------------------
    % Option B: build auto mask if none loaded
    % -----------------------------------------
    if isempty(vt_mask_dilate)

        %variance over time at each pixel. this finds the vocal tract
        [~, frames_var] = morpho.video.streaming_stats(input_filename, skipFirstN=round(fps));

        %%%automatic variance threshold
        if cfg.masking.automatic_var_threshold
            frames_var_max = max(frames_var(:));
            frames_var_scaled = frames_var / frames_var_max;
            var_threshold = morpho.masking.auto_variance_threshold(frames_var_scaled);
        else
            var_threshold = cfg.masking.var_threshold;
        end

        vt_mask_dilate = morpho.masking.variance_to_mask(frames_var, var_threshold);
        vt_mask_dilate = morpho.masking.morphological_cleanup(vt_mask_dilate, ...
            thicken=cfg.masking.mask_thickening, erode=cfg.masking.final_erode);

    end

    if shared_mask_loaded && cfg.masking.skip_manual_mask_edit_if_shared_mask_loaded == 1

        vt_mask_cleaned = vt_mask_dilate;
        disp("Skipping manual mask editing because shared ADB mask was loaded.");

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
            filename=input_rootname, ...
            frame_source=input_filename, ...
            frame_indices=1:no_frames, ...
            current_frame=context_frame);
        vt_mask_cleaned = editor.run();
        vt_mask_cleaned = bwmorph(vt_mask_cleaned, 'close');

    end



    % ============================================================
    % SAVE MASKS
    % 1) Save exact-file mask for diagnostics
    % 2) Save shared ADB mask so ALL blocks in that ADB reuse it
    % ============================================================

    if ~(shared_mask_loaded && cfg.masking.skip_manual_mask_edit_if_shared_mask_loaded == 1)
        save(perfile_mask_path,'vt_mask_cleaned');
        save(shared_mask_path,'vt_mask_cleaned');

        disp("Saved per-file mask: " + string(perfile_mask_path));
        disp("Saved shared ADB mask: " + string(shared_mask_path));
    else
        disp("Reused existing shared mask; no mask re-save needed.");
    end

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %%%GET VOCAL TRACT AND SAVE TO VIDEO%%%
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    output_avi = char(fullfile(cfg.dir("morph_avi"), string(input_rootname) + '_out.avi'));
    output_dat = char(fullfile(cfg.dir("morph_mat"), string(input_rootname) + '_out.mat'));

    writerObj = VideoWriter(output_avi);
    writerObj.FrameRate = fps;
    open(writerObj);

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %%% FIND TISSUE CLASSIFICATION THRESHOLD
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    manual_threshold_loaded = false;
    tissue_threshold = NaN;

    % --------------------------------------------------
    % Attempt to load saved manual threshold for ADB group
    % --------------------------------------------------
    if cfg.masking.automatic_tissue_threshold == 0 && cfg.masking.manual_tissue_threshold_chooser == 1 ...
            && cfg.masking.use_saved_manual_threshold_if_available == 1 ...
            && isfile(shared_manual_threshold_path)

        try
            T = load(shared_manual_threshold_path);

            if isfield(T,'manual_threshold') && ~isempty(T.manual_threshold) && ~isnan(T.manual_threshold)
                tissue_threshold = T.manual_threshold;
                manual_threshold_loaded = true;

                disp("Loaded shared manual threshold for ADB group " + adb_id + ": " + tissue_threshold);
            else
                disp("WARNING: Threshold file exists but has no valid 'manual_threshold'");
            end

        catch ME
            disp("WARNING: Failed to load shared manual threshold");
            disp("Reason: " + string(ME.message));
        end

    elseif cfg.masking.automatic_tissue_threshold == 0 && cfg.masking.manual_tissue_threshold_chooser == 1 ...
            && cfg.masking.use_saved_manual_threshold_if_available == 1 ...
            && cfg.masking.warn_if_manual_threshold_missing == 1

        disp("No shared manual threshold found for ADB group " + adb_id + ". Manual chooser will open.");
    end


    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %%% AUTOMATIC THRESHOLD
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    if cfg.masking.automatic_tissue_threshold == 1

        % Sample frames for threshold estimation
        sample_indices = round(linspace(1, no_frames, min(50, no_frames)));
        sample_frames = morpho.video.read_frames(input_filename, sample_indices);
        tissue_threshold = morpho.masking.auto_tissue_threshold(sample_frames, vt_mask_cleaned, numel(sample_indices));

        if isempty(tissue_threshold) || isnan(tissue_threshold)

            disp(" ")
            disp("WARNING: Failed to classify tissue. No local minimum found.")
            disp("Try this run again later with the manual tissue threshold option.")
            disp(" ")

            close(writerObj);
            continue
        end

        disp("Applying automatic tissue threshold: " + tissue_threshold);


    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %%% MANUAL THRESHOLD
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    elseif cfg.masking.manual_tissue_threshold_chooser == 1

        if ~manual_threshold_loaded

            % Sample frames for manual threshold chooser
            sample_indices = round(linspace(1, no_frames, min(50, no_frames)));
            sample_frames = morpho.video.read_frames(input_filename, sample_indices);
            manual_threshold = manual_threshold_chooser(sample_frames);

            tissue_threshold = manual_threshold;

            if cfg.masking.save_manual_threshold_for_group == 1 && ~isnan(manual_threshold)

                save(shared_manual_threshold_path,'manual_threshold');
                save(perfile_manual_threshold_path,'manual_threshold');

                disp("Saved shared manual threshold: " + string(shared_manual_threshold_path));
                disp("Saved per-file threshold: " + string(perfile_manual_threshold_path));

            end

        else

            manual_threshold = tissue_threshold;

            disp("Reusing saved manual threshold: " + string(tissue_threshold));

        end

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %%% FIXED MANUAL VALUE
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

    else

        tissue_threshold = cfg.masking.manual_tissue_threshold;

    end

    % Pre-allocate output in matfile for streaming write
    save(output_dat, 'no_frames', '-v7.3');
    mf = matfile(output_dat, 'Writable', true);
    sample = morpho.video.to_gray_single(read(v, 1));
    [h, w] = size(sample);
    mf.vt_output = zeros(h, w, no_frames, 'single');

    for f = 1:no_frames %loop through frames
        disp("Working on frame " + f + " of " + no_frames);

        frame = morpho.video.to_gray_single(read(v, f));

        vt_tissue_mask = morpho.masking.classify_tissue_frame(frame, vt_mask_cleaned, tissue_threshold, ...
            lip_clip=cfg.masking.lip_clip);

        mf.vt_output(:,:,f) = single(vt_tissue_mask);

        I = frame / max(frame(:) + eps);
        I = im2uint8(I);
        rgb = repmat(I, [1 1 3]);
        mask_u8 = uint8(vt_tissue_mask) * 255;
        rgb(:,:,1) = max(rgb(:,:,1), mask_u8);

        writeVideo(writerObj, rgb);
    end

    close(writerObj); %close video file, writing done

    last_frame = morpho.video.to_gray_single(read(v, no_frames));
    last_vt = mf.vt_output(:,:,no_frames);
    hQAFig = figure;
    imshowpair(last_frame, last_vt, 'falsecolor');
    title('Final frame: vocal tract mask QA');

    pause(5);   % keep figure open for 5 seconds

    if ishghandle(hQAFig)
        close(hQAFig);
    end

end %end video loop
