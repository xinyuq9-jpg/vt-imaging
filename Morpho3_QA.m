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

% set defaults for drawing. These can also be set interactively
brush_size = 50; % add this many pixels to each side of the cursor to make a square
draw_mode = 'E'; % D for Draw/Restore, E for Erase

if draw_mode == 'R' % Derived from draw mode
    ink = 1;
elseif draw_mode == 'E'
    ink = 0;
end

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%% Shared QA mask reuse across ADB blocks
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
use_saved_QA_mask_if_available = 1;              % reuse block_1 QA mask for all blocks in same ADB group
skip_manual_QA_if_shared_mask_loaded = 0;        % if shared QA mask exists, do not open QA editor
save_shared_QA_mask_for_group = 1;               % save cleaned QA mask for group reuse
warn_if_QA_mask_missing = 1;                     % warn if no saved QA mask exists yet

%%%%%%%%%%%%%%%%%%%%%%%%
%%% manage directories %
%%%%%%%%%%%%%%%%%%%%%%%%
input_mat_dir = 'morph/mat_sub';      % where are the .mat files?
input_avi_dir = 'avi_reg';            % where are the OG (registered) .avi files?
output_mat_dir = 'morph/mat_QA';      % where should QA .mat files go?
output_QA_mask_dir = 'morph/mat_QA_masks'; % where to save shared QA masks?

addpath('bonus_scripts')

%%%%%%%%%%%%%%%%%%%%%%
% Iterate through files
%%%%%%%%%%%%%%%%%%%%%%

% make output directories if they don't already exist
if isfolder(output_mat_dir) == 0; mkdir(output_mat_dir); end
if isfolder(output_QA_mask_dir) == 0; mkdir(output_QA_mask_dir); end

% find .mat files
list_input_files = select_input_files(input_mat_dir, '.mat');

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
    tok = regexp(input_rootname, '^(ADB\d+)block_(\d+)', 'tokens', 'once');

    if isempty(tok)
        error("Filename does not match expected pattern ADB##block_#_... : " + string(input_rootname));
    end

    adb_id = string(tok{1});          % e.g. "ADB17"
    block_num = str2double(tok{2});   % e.g. 1,2,3...

    % Shared canonical QA mask path for the whole ADB group
    shared_QA_mask_path = char(fullfile(output_QA_mask_dir, adb_id + "block_1_QA_mask.mat"));

    % Optional exact-file diagnostic QA mask path
    perfile_QA_mask_path = char(fullfile(output_QA_mask_dir, string(input_rootname) + "_QA_mask.mat"));

    disp("Processing: " + input_rootname);
    disp("ADB group: " + adb_id + " | block: " + block_num);
    disp("Shared QA mask path: " + string(shared_QA_mask_path));

    %%% read vt mask images data
    mframes = load(input_mat_filename).vt_output;
    size_mframes = size(mframes);
    no_mframes = size_mframes(3);

    % read image data
    v = VideoReader(input_avi_filename);
    no_frames = v.Duration * v.FrameRate;
    aframes = read(v);

    if length(size(aframes)) > 3 % if anatomical image reads as rgb rather than greyscale
        aframes = aframes(:,:,1,:);
    end

    aframes = squeeze(aframes); % remove unwanted dimension
    aframes = cast(aframes, 'single');

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Build initial QA mask from vt output
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    vt_ever = mean(mframes, 3);       % pixel frequency map
    anatomy_med = median(aframes, 3); % anatomical context
    mask_size = size(vt_ever);

    shared_QA_mask_loaded = false;

    % --------------------------------------------------
    % Option A: load shared ADB QA mask
    % --------------------------------------------------
    if use_saved_QA_mask_if_available == 1 && isfile(shared_QA_mask_path)
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

    elseif use_saved_QA_mask_if_available == 1 && warn_if_QA_mask_missing == 1
        disp("No shared QA mask found for ADB group " + adb_id + ". QA editor will open.");
    end

    %%%%%%%%%%%%%%%%%%%%%%%%
    % Interactive part. Yay!
    %%%%%%%%%%%%%%%%%%%%%%%%
    if shared_QA_mask_loaded && skip_manual_QA_if_shared_mask_loaded == 1

        vt_ever = vt_ever_cleaned;
        disp("Skipping manual QA editing because shared ADB QA mask was loaded.");

    else

        disp("ERASE/REDRAW pixels");

        vt_ever_og = vt_ever; % set aside original copy for use later

        exit_box_size = round(min(mask_size)/20); % size of box for exiting edit mode
        settings_box_size = exit_box_size;        % size of box for changing edit settings

        x = 1; % starting values
        y = mask_size(1);

        vt_ever(1:exit_box_size, end-exit_box_size:end) = 1; % draw box in corner of mask
        vt_ever(1:settings_box_size, 1:settings_box_size) = 1; % draw box in top left corner of mask

        imshow(anatomy_med/max(max(anatomy_med)),'InitialMag', 'fit');
        pink = cat(3, ones(mask_size), zeros(mask_size), ones(mask_size)/2);
        hold on;
        image_pink = imshow(pink);
        hold off;
        set(image_pink, 'AlphaData', vt_ever);
        set(gcf, 'Units', 'Normalized', 'OuterPosition', [0.5, 0, 0.5, 1]);

        while x < mask_size(2)-exit_box_size || y > exit_box_size % while cursor is not in the corner box

            % this colour scheme is different from the other morpho scripts
            % imshowpair was problematic here
            imshow(anatomy_med/max(max(anatomy_med)),'InitialMag', 'fit');
            pink = cat(3, ones(mask_size), zeros(mask_size), ones(mask_size)/2);
            hold on;
            image_pink = imshow(pink);
            hold off;
            set(image_pink, 'AlphaData', vt_ever);

            [x,y] = ginput(1); % click on one voxel whose value needs to change
            x = uint16(x); % make integer so they can be used as indices
            y = uint16(y);

            x_brush = x-brush_size:x+brush_size; % expand for larger selection brush
            y_brush = y-brush_size:y+brush_size;

            x_brush(x_brush>mask_size(2)) = mask_size(2); % in case the brush spills out of frame
            y_brush(y_brush>mask_size(1)) = mask_size(1);
            x_brush(x_brush<1) = 1; % and the other side
            y_brush(y_brush<1) = 1;

            % if cursor in setting size box, open settings prompt
            if x <= settings_box_size && y <= settings_box_size

                % call UI for drawing settings
                [draw_mode,brush_size, ink] = Morpho3_UI(draw_mode, brush_size, vt_ever);

            % otherwise do re-drawing
            else
                vt_ever(y_brush,x_brush) = vt_ever_og(y_brush,x_brush) * ink; % change mask value at clicked pixel
            end
        end

        vt_ever(1:exit_box_size, end-exit_box_size:end) = 0; % remove the end box
        vt_ever(1:settings_box_size, 1:settings_box_size) = 0; % remove settings box
        vt_ever = vt_ever > 0; % binarize

        vt_ever_cleaned = vt_ever;

        % Save QA masks only when manually created/edited
        if save_shared_QA_mask_for_group == 1
            save(shared_QA_mask_path, 'vt_ever_cleaned');
            save(perfile_QA_mask_path, 'vt_ever_cleaned');

            disp("Saved shared QA mask: " + string(shared_QA_mask_path));
            disp("Saved per-file QA mask: " + string(perfile_QA_mask_path));
        end
    end

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % Mask .mat frames with cleaned QA mask
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    if shared_QA_mask_loaded && skip_manual_QA_if_shared_mask_loaded == 1
        vt_ever = logical(vt_ever);
    else
        vt_ever = logical(vt_ever_cleaned);
    end

    for mf = 1:no_mframes
        mframes(:,:,mf) = mframes(:,:,mf) .* vt_ever;
    end

    vt_output = mframes; % rename object for inter-script consistency
    output_dat = char(fullfile(output_mat_dir, string(input_rootname) + '_QA.mat'));
    save(output_dat, 'vt_output');

end % end for .mat file

close all