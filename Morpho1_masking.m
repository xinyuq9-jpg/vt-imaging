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

skip_manual_mask_edit_if_shared_mask_loaded = 0;   % if shared ADB mask exists, do not open mask editor


use_saved_manual_threshold_if_available = 0;   % reuse block_1 threshold for all blocks in same ADB group
save_manual_threshold_for_group = 1;           % save chosen threshold for group reuse
warn_if_manual_threshold_missing = 1;          % warn if threshold not found yet

use_saved_mask_if_available = 1;  % 1=yes: try load prior mask and refine; 0=no: always auto-detect
warn_if_mask_missing = 1;         % 1=yes: show message when no prior mask found

mask_opacity = 0.45;   % 0 = invisible mask, 1 = fully opaque

automatic_var_threhold=1; %should we try to automatically find a good variance mask threshold?
if automatic_var_threhold==0 %if no you can specify var_threshold manually here
    var_threshold = 0.01;  %how exclusive to make vt mask. higher is more exclusive range 0-1. is proportion of max variance
end
mask_thickening = 10;      %how much to increase the size of vocal tract mask
final_erode = 3;           %how much to decrease it. this kills some some extra clusters

automatic_tissue_threhold=0; %set to 0 to manually set threshold. useful if the automatic method gives a poor result
manual_tissue_threhold_chooser=1; %use a helper tool to sample pixel values and manually select a threshold. Superseded by automatic_tissue_threhold
manual_tissue_threshold =62; %only relevant if if automatic_tissue_threhold=0;

lip_clip = 1; %clip_pixels anterior to lips 1 = yes

context_frame_chooser = "manual"; %change to manual if you don't like the automatic choose
context_frame_default = 100; %this setting irrelevant unless context_frame_chooser = manual. The series number of the frame you'd like to use for anatomical context

online_viewer = 0;     %0 to view at fastest speed, 1 to control view speed                     
viewer_acceleration = 1; %how much to speed up video display. 1x is native time of the data

%set defaults for drawing. These can also be set interactively
draw_mode = 'D'; %D for Draw, E for Erase
if draw_mode == 'D'
    ink = 1;
elseif draw_mode == 'E'
    ink = 0;
end
    
%%%%%%%%%%%%%%%%%%%%%%%%
%%%manage directories%%%
%%%%%%%%%%%%%%%%%%%%%%%%
input_dir = 'avi_reg'; %where are the .avi files?

out_base_dir = 'morph';
output_avi_dir = fullfile(out_base_dir,'avi');  %where to send output .avi files?
output_dat_dir = fullfile(out_base_dir,'mat');  %where to send output .mat files
output_mask_dir = fullfile(out_base_dir,'masks'); %where to save vocal tract masks
addpath("bonus_scripts") %where to find helper scripts

%%%%%%%%%%%%%%%%%%%%%%
%Iterate through files
%%%%%%%%%%%%%%%%%%%%%%
%make output directories if they don't already exist
if isfolder(out_base_dir) == 0; mkdir(out_base_dir); end
if isfolder(output_avi_dir) == 0; mkdir(output_avi_dir); end
if isfolder(output_dat_dir) == 0; mkdir(output_dat_dir); end
if isfolder(output_mask_dir) == 0; mkdir(output_mask_dir); end

list_input_files = select_input_files(input_dir, '.avi');

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
    tok = regexp(input_rootname, '^(ADB\d+)block_(\d+)', 'tokens', 'once');

    if isempty(tok)
        error("Filename does not match expected pattern ADB##block_#_... : " + string(input_rootname));
    end

    adb_id = string(tok{1});          % e.g. "ADB17"
    block_num = str2double(tok{2});   % e.g. 1,2,3...

    % Shared canonical mask path for the whole ADB group
    shared_mask_path = char(fullfile(output_mask_dir, adb_id + "block_1_msk.mat"));

    % Optional exact-file diagnostic mask path
    perfile_mask_path = char(fullfile(output_mask_dir, string(input_rootname) + "_msk.mat"));

    % Shared canonical manual threshold path
    shared_manual_threshold_path = char(fullfile(output_mask_dir, adb_id + "block_1_manual_threshold.mat"));
    
    % Optional diagnostic threshold path
    perfile_manual_threshold_path = char(fullfile(output_mask_dir, string(input_rootname) + "_manual_threshold.mat"));

    disp("Processing: " + input_rootname);
    disp("ADB group: " + adb_id + " | block: " + block_num);
    disp("Shared mask path: " + string(shared_mask_path));

    %read image data
    v = VideoReader(input_filename);
    no_frames = v.Duration*v.FrameRate;
    fps = v.FrameRate;
    frames = read(v);

    if length(size(frames))>3 %if anatomical image reads as rgb rather than greyscale
        frames = frames(:,:,1,:);
    end

    frames = squeeze(frames); %remove unwanted dimension
    frames = cast(frames, 'single');

    if context_frame_chooser == "auto"
        context_frame = round(no_frames/2); %which frame to show for anatomical context
    else
        context_frame = context_frame_default;
    end

    vt_mask_dilate = [];      % will become the starting mask for manual refinement
    shared_mask_loaded = false;

    % ------------------------------
    % Option A: load shared ADB mask
    % ------------------------------
    if use_saved_mask_if_available == 1 && isfile(shared_mask_path)
        try
            S = load(shared_mask_path);  % expects vt_mask_cleaned inside
            if isfield(S, 'vt_mask_cleaned')
                vt_mask_dilate = logical(S.vt_mask_cleaned);

                if ~isequal(size(vt_mask_dilate), [size(frames,1), size(frames,2)])
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

    elseif use_saved_mask_if_available == 1 && warn_if_mask_missing == 1
        disp("No shared mask found for ADB group " + adb_id + ". Building auto mask...");
    end
    
    % -----------------------------------------
    % Option B: build auto mask if none loaded
    % -----------------------------------------
    if isempty(vt_mask_dilate)
    
        %variance over time at each pixel. this finds the vocal tract
        frames_var = frames(:,:,[round(fps):no_frames]); %omit first second worth of frames. These tend to be noisy
        frames_var = var(frames_var, 0, 3);
        frames_var_max = max(frames_var(:));
        frames_var_scaled = frames_var/frames_var_max;
    
        %%%automatic variance threshold
        if automatic_var_threhold==1
            [var_density_function,var_density_index] =  ksdensity(frames_var_scaled(:));
            var_density_min = islocalmin(var_density_function);
            var_threshold = var_density_index(var_density_min);
            var_threshold = min(var_threshold);
            disp("Applying variance threshold: " + var_threshold);
        end
    
        frames_var_mask = frames_var_scaled>var_threshold;
    
        %find the cluster
        lab_mat = bwlabel(frames_var_mask);
        labs = unique(lab_mat);
    
        %find cluster sizes
        labs_sum = zeros(length(labs),1);
        for l = 1:length(labs)
            labs_sum(l) = sum(sum(lab_mat == labs(l)));
        end
    
        [~,ii] = sort(labs_sum);
        vt_cluster_size = labs_sum(ii(end-1));
        vt_cluster_loc = labs_sum == vt_cluster_size;
        vt_cluster_number = labs(vt_cluster_loc);
        vt_mask = lab_mat == vt_cluster_number(1);
    
        %embiggen the mask and clean it up
        vt_mask_dilate = bwmorph(vt_mask,'thicken',mask_thickening);
        vt_mask_dilate = bwmorph(vt_mask_dilate,'bridge');
        vt_mask_dilate = bwmorph(vt_mask_dilate,'close');
        vt_mask_dilate = bwmorph(vt_mask_dilate,'erode',final_erode);
    
    end

    if shared_mask_loaded && skip_manual_mask_edit_if_shared_mask_loaded == 1
    
        vt_mask_cleaned = vt_mask_dilate;
        disp("Skipping manual mask editing because shared ADB mask was loaded.");
    
    else
    
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %%%MANUAL ADJUSTMENT OF VOCAL TRACT MASK%%%
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        disp(" ")
        disp("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
        disp("Draw masks over pixels likely to contain vocal tract.")
        disp("Pay particular attention to the oesophagus, velum, lower teeth, below the tongue, and beyond the lips.")
        disp("Click the top-LEFT corner box to access BRUSH SETTINGS.")
        disp("Click the top-RIGHT corner box when FINISHED.")
        disp("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~")
        disp(" ")
    
        mask_size = size(vt_mask_dilate); %get 2d size
        vt_mask_cleaned = vt_mask_dilate; %copy over for clean
        exit_box_size = round(min(mask_size)/20); %size of box for exiting edit mode
        settings_box_size = exit_box_size; %size of box for changing edit settings
        brush_size = exit_box_size; %default size for drawing brush
      
        x = 1; %starting values
        y = mask_size(1);
        vt_mask_cleaned(1:exit_box_size, end-exit_box_size:end) = 1; %draw box in top right corner of mask
        vt_mask_cleaned(1:settings_box_size, 1:settings_box_size) = 1; %draw box in top left corner of mask
    
        % ---- create masking figure ONCE (BIG window) ----
        mp = get(0,'MonitorPositions');        % [left bottom width height] for each monitor
        mp = mp(1,:);                          % use primary monitor
    
        pad = 40;                              % padding from screen edges
        fig_pos = [mp(1)+pad, mp(2)+pad, mp(3)-2*pad, mp(4)-2*pad];
    
        hMaskFig = figure('Name',['Mask Editor: ' char(input_rootname)], ...
                          'NumberTitle','off', ...
                          'Units','pixels', ...
                          'Position', fig_pos);
    
        ax = axes('Parent', hMaskFig, 'Position',[0 0 1 1]);
  

        current_context_frame = context_frame;
        current_mask_opacity = mask_opacity;
        
        [hBase, hOverlay] = init_mask_overlay(ax, ...
            frames(:,:,current_context_frame), ...
            vt_mask_cleaned, ...
            current_mask_opacity);
        
        title(ax, sprintf('Mask editor | frame %d / %d | opacity %.2f | mode %s | brush %d', ...
            current_context_frame, no_frames, current_mask_opacity, draw_mode, brush_size));
        
        % zoom(ax, 5.0);
      
        while x < mask_size(2)-exit_box_size || y > exit_box_size %while cursor is not in the corner box
        
            update_mask_overlay(hBase, hOverlay, ...
            frames(:,:,current_context_frame), ...
            vt_mask_cleaned, ...
            current_mask_opacity);
        
            title(ax, sprintf('Mask editor | frame %d / %d | opacity %.2f | mode %s | brush %d', ...
                current_context_frame, no_frames, current_mask_opacity, draw_mode, brush_size));
            
            drawnow;
    
            [x,y] = ginput(1);
    
            x = uint16(x); %make integer so they can be used as indices
            y = uint16(y);
    
            x_brush = x-brush_size:x+brush_size; %expand for larger selection brush
            y_brush = y-brush_size:y+brush_size;
    
            x_brush(x_brush>mask_size(2)) = mask_size(2); %in case the brush spills out of frame
            y_brush(y_brush>mask_size(1)) = mask_size(1);
            x_brush(x_brush<1) = 1; %and the other side
            y_brush(y_brush<1) = 1;
        
            %check if UI settings request has been triggered
            if x <= settings_box_size && y <= settings_box_size
            
            [draw_mode, brush_size, ink, current_context_frame, current_mask_opacity] = ...
                Morpho1_UI(draw_mode, brush_size, mask_size, current_context_frame, no_frames, current_mask_opacity);
            
            else %otherwise do drawing. Avoid erasing the corner boxes
                vt_mask_cleaned(y_brush,x_brush) = ink; %draw or erase depending on outcome
            end
        end
      
        %remove boxes
        vt_mask_cleaned(1:exit_box_size, end-exit_box_size:end) = 0;
        vt_mask_cleaned(1:settings_box_size, 1:settings_box_size) = 0;
    
        %close holes if any
        vt_mask_cleaned = bwmorph(vt_mask_cleaned,'close');
    
        if ishghandle(hMaskFig)
            close(hMaskFig);
        end
    
    end
  
    

    % ============================================================
    % SAVE MASKS
    % 1) Save exact-file mask for diagnostics
    % 2) Save shared ADB mask so ALL blocks in that ADB reuse it
    % ============================================================

    if ~(shared_mask_loaded && skip_manual_mask_edit_if_shared_mask_loaded == 1)
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
    output_avi= char(fullfile(output_avi_dir,string(input_rootname)+'_out.avi'));
    output_dat= char(fullfile(output_dat_dir,string(input_rootname)+'_out.mat'));

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
    if automatic_tissue_threhold == 0 && manual_tissue_threhold_chooser == 1 ...
            && use_saved_manual_threshold_if_available == 1 ...
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
    
    elseif automatic_tissue_threhold == 0 && manual_tissue_threhold_chooser == 1 ...
            && use_saved_manual_threshold_if_available == 1 ...
            && warn_if_manual_threshold_missing == 1
    
        disp("No shared manual threshold found for ADB group " + adb_id + ". Manual chooser will open.");
    end
    
    
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %%% AUTOMATIC THRESHOLD
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    
    if automatic_tissue_threhold==1
    
        vt_threshold_vec = zeros(no_frames, 1);
    
        for f = 1:no_frames
            vt = frames(:,:,f);
    
            [tissue_density_function,tissue_density_index] = ksdensity(vt(vt_mask_cleaned));
    
            tissue_density_min = islocalmin(tissue_density_function);
    
            tissue_threshold = tissue_density_index(tissue_density_min);
    
            tissue_threshold = min(tissue_threshold);
    
            vt_threshold_vec(f) = tissue_threshold;
        end
    
        tissue_threshold_failed = vt_threshold_vec==0 | isnan(vt_threshold_vec);
    
        tissue_threshold = median(vt_threshold_vec(tissue_threshold_failed==0));
    
        if isempty(tissue_threshold)
    
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
    
    elseif manual_tissue_threhold_chooser==1
    
        if ~manual_threshold_loaded
    
            manual_threshold = manual_threshold_chooser(frames);
    
            tissue_threshold = manual_threshold;
    
            if save_manual_threshold_for_group == 1 && ~isnan(manual_threshold)
    
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
    
        tissue_threshold = manual_tissue_threshold;
    
    end
  
    vt_output = zeros(size(frames)); %placeholder for output

    for f = 1:no_frames %loop through frames
        disp("Working on frame " + f + " of " + no_frames);

        vt = frames(:,:,f) .* vt_mask_cleaned; %apply hand cleaned mask
        vt_tissue_mask = vt < tissue_threshold & vt_mask_cleaned > 0; %classify tissue within mask

        %%%lip_clip
        if lip_clip == 1
            soft_tissue_mask = vt >= tissue_threshold & vt_mask_cleaned > 0;
            soft_tissue_colsums = sum(soft_tissue_mask, 1); %sum of rows. first non-zero should contain lips
            soft_tissue_lip_col = find(soft_tissue_colsums,1,'first')-1;
            if ~isempty(soft_tissue_lip_col) && soft_tissue_lip_col >= 1
                vt_tissue_mask(:, 1:soft_tissue_lip_col) = 0;
            end
        end

        %clean up the vocal tract
        vt_tissue_mask = bwmorph(vt_tissue_mask, 'spur');
        vt_tissue_mask = bwmorph(vt_tissue_mask, 'clean');
        vt_tissue_mask = bwmorph(vt_tissue_mask, 'close');
        vt_tissue_mask = bwmorph(vt_tissue_mask, 'fill');

        %build 3d array of tissue masks. that's data.
        vt_output(:,:,f) = vt_tissue_mask; 

        I = frames(:,:,f);
        I = I / max(I(:) + eps);
        I = im2uint8(I);
        rgb = repmat(I,[1 1 3]);
        mask = uint8(vt_tissue_mask)*255;
        rgb(:,:,1) = max(rgb(:,:,1), mask);

        writeVideo(writerObj, rgb);
    end

    close(writerObj); %close video file, writing done
    save(output_dat,'vt_output');

    hQAFig = figure;
    imshowpair(frames(:,:,no_frames), vt_output(:,:,no_frames), 'falsecolor');
    title('Final frame: vocal tract mask QA');

    pause(5);   % keep figure open for 5 seconds

    if ishghandle(hQAFig)
        close(hQAFig);
    end

end %end video loop


function draw_mask_overlay(ax, frame2d, mask2d, mask_opacity)

    frame2d = single(frame2d);
    frame2d = frame2d - min(frame2d(:));
    frame2d = frame2d ./ max(frame2d(:) + eps);

    imshow(frame2d, 'Parent', ax);
    hold(ax, 'on');

    red_overlay = cat(3, ones(size(mask2d)), zeros(size(mask2d)), zeros(size(mask2d)));
    h = imshow(red_overlay, 'Parent', ax);

    set(h, 'AlphaData', double(mask2d > 0) * mask_opacity);

    hold(ax, 'off');
end

function [hBase, hOverlay] = init_mask_overlay(ax, frame2d, mask2d, mask_opacity)

    frame2d = single(frame2d);
    frame2d = frame2d - min(frame2d(:));
    frame2d = frame2d ./ max(frame2d(:) + eps);

    cla(ax);
    hold(ax, 'on');

    % background grayscale image
    hBase = imshow(frame2d, 'Parent', ax);

    % constant red overlay
    red_overlay = cat(3, ones(size(mask2d)), zeros(size(mask2d)), zeros(size(mask2d)));
    hOverlay = imshow(red_overlay, 'Parent', ax);

    % transparency only where mask exists
    hOverlay.AlphaData = double(mask2d > 0) * mask_opacity;

    hold(ax, 'off');
    axis(ax, 'image');
end

function update_mask_overlay(hBase, hOverlay, frame2d, mask2d, mask_opacity)

    frame2d = single(frame2d);
    frame2d = frame2d - min(frame2d(:));
    frame2d = frame2d ./ max(frame2d(:) + eps);

    hBase.CData = frame2d;
    hOverlay.AlphaData = double(mask2d > 0) * mask_opacity;
end