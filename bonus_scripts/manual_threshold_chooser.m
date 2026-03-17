function [manual_threshold] = manual_threshold_chooser(frames)
%% Function description
% August 2022, Michel Belyk, Edge Hill University

%helper tool for manual tissue threshold selection
% click pixels to see their value
% click top right box to see settings
% including box in which to type your selected tissue threshold

no_frames = size(frames, 3);
frame_size = size(frames, 1:2);
selected_frame = round(no_frames/2); %default context image, arbitrary one in the middle
manual_select_image = frames(:,:,selected_frame);
pixelValue = NaN; %for the sake of having a default
manual_threshold = NaN; %for the sake of having a default

%setup button boxes
mask_size = size(manual_select_image(:,:,1));
exit_box_size = round(min(mask_size)/20); %size of box for exiting edit mode
settings_box_size = exit_box_size; %size of box for changing edit settings
max_value = max(max(max(frames)));
min_value = min(min(min(frames)));

%set a degault value

if exist('median_mode', 'var') == 0
    median_mode = 'F';
end

x= 1; %starting values
y=mask_size(1);
manual_select_image(1:exit_box_size, end-exit_box_size:end) = max_value; %draw box in top right corner of mask
manual_select_image(1:settings_box_size, 1:settings_box_size) = max_value; %draw box in to left corner of mask

%continue until clicked exit box
while x < mask_size(2)-exit_box_size || y > exit_box_size %while cursor is n

    %show image and wait for pixel click
    %image(manual_select_image)
    imshow(manual_select_image, [min_value max_value])
    set(gcf, 'Units', 'Normalized', 'OuterPosition', [0.5, 0, 0.5, 1]);
    
    %get location of clicked pixels
    [x, y] = ginput(1);
    row = round(y);
    column = round(x);

    %user proofing, in case they click out of frame
    if row > frame_size(1)
        row = frame_size(1);
    end
    if row < 0
        row = 0;
    end
    if column > frame_size(2)
        column = frame_size(2);
    end
    if column < 0
        column = 0;
    end

    %call UI settings dialog. Gives user options
    if x <= settings_box_size && y <= settings_box_size
        [manual_select_image, selected_frame, manual_threshold, median_mode] = manual_threshold_chooser_UI(frames,selected_frame, manual_threshold,median_mode);
        manual_select_image(1:exit_box_size, end-exit_box_size:end) = max_value; %draw box in top right corner of mask
        manual_select_image(1:settings_box_size, 1:settings_box_size) = max_value; %draw box in to left corner of mask

    %sample pixel
    elseif x >= exit_box_size && y <= exit_box_size
        %do nothing
    else
        pixelValue = manual_select_image(row, column) %store and print value at pixel

    end
end

%remove corner boxes
manual_select_image(1:exit_box_size, end-exit_box_size:end) = 0; 
manual_select_image(1:settings_box_size, 1:settings_box_size) = 0;

try
    fig = gcf;
    close(fig);
catch
end

end %end function