%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Michel Belyk, UCL
% April 2020
% belykm@gmail.com
% Check Morpho_ outputs
% takes input from Morpho_masking.m or Morpho_subsetter.m
%
% UPDATED:
% - Reuse one shared QA mask per ADB group
% - Example:
%     ADB17block_1_lag_0.36667_out.mat
%     ADB17block_2_lag_1.20000_out.mat
%     ADB17block_3_lag_-0.50000_out.mat
%
%   All of these can reuse the SAME shared QA mask:
%     morph/mat_QA_masks/ADB17block_1_QA_mask.mat
%
% - If shared QA mask exists and flag is enabled:
%     * skip popup QA drawing window
%     * apply shared QA mask automatically
%
% Made for R2018b on macOS 10.15.1
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%
% SETABLE PARAMETERS %
%%%%%%%%%%%%%%%%%%%%%%

cfg = morpho.Config();

%%%%%%%%%%%%%%%%%%%%%%%%
%%% manage directories %
%%%%%%%%%%%%%%%%%%%%%%%%
input_mat_dir = cfg.dir("mat_sub");
input_avi_dir = cfg.dir("avi_reg");
cfg.ensure("mat_qa");
cfg.ensure("qa_masks");

%%%%%%%%%%%%%%%%%%%%%%
% Iterate through files
%%%%%%%%%%%%%%%%%%%%%%

% find .mat files
list_input_files = morpho.select_input_files(input_mat_dir, '.mat');

for iFile = 1:length(list_input_files) % loop through video files

    input_rootname = list_input_files(iFile).name(1:end-8); % remove _out.mat
    input_mat_filename = fullfile(input_mat_dir, list_input_files(iFile).name);
    input_avi_filename = fullfile(input_avi_dir, strcat(input_rootname, '.avi')); % corresponding OG avi images

    % ============================================================
    % Parse ADB group from filename
    % Expected examples:
    %   ADB17block_1_lag_0.36667
    %   ADB36block_2_lag_18.8
    %   ADB24block_1_lag_-0.9
    %
    % We ignore lag and use ONE shared QA mask per ADB group:
    %   ADB17block_1_QA_mask.mat
    % ============================================================
    [adb_id, block_num] = morpho.io.parse_adb(input_rootname);

    % Shared canonical QA mask path for the whole ADB group
    shared_QA_mask_path = char(fullfile(cfg.dir("qa_masks"), adb_id + "block_1_QA_mask.mat"));

    % Optional exact-file diagnostic QA mask path
    perfile_QA_mask_path = char(fullfile(cfg.dir("qa_masks"), string(input_rootname) + "_QA_mask.mat"));

    disp("Processing: " + input_rootname);
    disp("ADB group: " + adb_id + " | block: " + block_num);
    disp("Shared QA mask path: " + string(shared_QA_mask_path));

    %%% read vt mask images data
    mframes = load(input_mat_filename).vt_output;
    size_mframes = size(mframes);
    no_mframes = size_mframes(3);

    % read image data (streaming stats avoids loading all frames)
    [anatomy_med, ~] = morpho.video.streaming_stats(input_avi_filename);

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Build initial QA mask from vt output
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    vt_ever = mean(mframes, 3);       % pixel frequency map
    mask_size = size(vt_ever);

    shared_QA_mask_loaded = false;

    % --------------------------------------------------
    % Option A: load shared ADB QA mask
    % --------------------------------------------------
    if cfg.qa.use_saved_QA_mask_if_available == 1 && isfile(shared_QA_mask_path)
        try
            S = load(shared_QA_mask_path);  % expects vt_ever_cleaned inside

            if isfield(S, 'vt_ever_cleaned')
                vt_ever_cleaned = logical(S.vt_ever_cleaned);

                if ~isequal(size(vt_ever_cleaned), mask_size)
                    disp("WARNING: Shared QA mask size doesn't match current file. Falling back to manual QA.");
                else
                    shared_QA_mask_loaded = true;
                    disp("Loaded shared QA mask: " + string(shared_QA_mask_path));
                end
            else
                disp("WARNING: Shared QA mask file found but 'vt_ever_cleaned' not present. Falling back to manual QA.");
            end

        catch ME
            disp("WARNING: Failed to load shared QA mask. Falling back to manual QA.");
            disp("Reason: " + string(ME.message));
        end

    elseif cfg.qa.use_saved_QA_mask_if_available == 1 && cfg.qa.warn_if_QA_mask_missing == 1
        disp("No shared QA mask found for ADB group " + adb_id + ". QA editor will open.");
    end

    %%%%%%%%%%%%%%%%%%%%%%%%
    % Interactive part. Yay!
    %%%%%%%%%%%%%%%%%%%%%%%%
    if shared_QA_mask_loaded && cfg.qa.skip_manual_QA_if_shared_mask_loaded == 1

        vt_ever = vt_ever_cleaned;
        disp("Skipping manual QA editing because shared ADB QA mask was loaded.");

    else

        disp("ERASE/REDRAW pixels using Editor. R=Redraw, E=Erase, S=Settings, Q=Quit.")

        vt_ever_og = vt_ever;

        editor = morpho.Editor(vt_ever, ...
            original=vt_ever_og, ...
            background=anatomy_med, ...
            overlay_color="pink", ...
            modes="RE", ...
            brush_size=cfg.qa.brush_size, ...
            draw_mode=cfg.qa.draw_mode, ...
            filename=input_rootname);
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

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Mask .mat frames with cleaned QA mask
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    if shared_QA_mask_loaded && cfg.qa.skip_manual_QA_if_shared_mask_loaded == 1
        vt_ever = logical(vt_ever);
    else
        vt_ever = logical(vt_ever_cleaned);
    end

    mframes = mframes .* vt_ever;

    vt_output = mframes; % rename object for inter-script consistency
    output_dat = char(fullfile(cfg.dir("mat_qa"), string(input_rootname) + '_QA.mat'));
    save(output_dat, 'vt_output');

end % end for .mat file

close all
