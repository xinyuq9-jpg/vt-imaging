function [manual_select_image, selected_frame, manual_threshold, median_mode] = manual_threshold_chooser_UI(frames, selected_frame, manual_threshold, median_mode)
%% Function description
% August 2022, Michel Belyk, Edge Hill University

%wedian_mode: 1 to plot median image, 0 to select a frame number
%selected_frame: Integer between 1 and no_frames to select a frame for sampling
%frames: array of pixel values for the imaging run

% simple UI to give user control over brush size and whether they draw or
% erase by clicking on the MR image

    prompt = {'Use median image?:','Select a frame:', 'Selected Threshold'};
    dlgtitle = 'Input';
    dims = [1 35];
    definput = {median_mode,int2str(selected_frame), int2str(manual_threshold)}; %default to current settings
    selection = inputdlg(prompt,dlgtitle,dims,definput);
    
    no_frames = size(frames, 3);
    median_mode = selection{1};
    selected_frame = selection{2};
    selected_frame = str2num(selected_frame);
    manual_threshold = str2num(selection{3});

    %safety net
    if selected_frame>no_frames
        selected_frame = no_frames;
        dis('Selection out of range. Nudging to last frame in run.')
    elseif selected_frame<1
         selected_frame = 1;
        dis('Selection out of range. Nudging to first frame in run.')
    end %end safety net

    %arrange output
    if median_mode == 'T' | median_mode == 'TRUE'
        manual_select_image = median(frames, 3);
    else
        manual_select_image=frames(:,:,selected_frame);
    end    

end %end function