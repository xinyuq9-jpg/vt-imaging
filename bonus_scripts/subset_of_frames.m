function [output_avi] = subset_of_frames(avi_filename, indices_filename, flag)
%% Function description
% 2021, Michel Belyk

% get a subset of frames from an avi file
% useful for exploring outputs from morpho_masking rtMRI pipeline

% Inputs
%   1) avi_filename: directory/filename for an RBG avi file
%   2) indices_filename: directory/filename for a single column .csv file with header Frame_Position containing the
%   index number for frames that you would like to retrieve
%   3) flag: a postcript to add to the output filename

%%function starts here

%read vodep
v = VideoReader(avi_filename);
  no_frames = v.Duration*v.FrameRate;
  frames = read(v);

%read_indices
frame_indices =  readtable(indices_filename);
  
%subset to requested frames
frames_select = frames(:,:,:,frame_indices.Frame_Position);
no_frames_selected = size(frames_select);
no_frames_selected = no_frames_selected(4);
%arrange a new filename
avi_rootname = string(avi_filename(1:end-4)); %remove extension
flag = string(flag); %make sure is string
output_avi = strcat(avi_rootname,"_",flag,".avi"); %add flag plus extenstion
output_avi = char(output_avi);

%write a median image in case that is somehow useful
output_median = strcat(avi_rootname,"_median_",flag,".png");
median_image = median(frames_select, 4);
imwrite(median_image,output_median)

%write a mean image in case that is somehow useful
output_mean = strcat(avi_rootname,"_mean_",flag,".png");
mean_image = mean(frames_select, 4);
mean_image = mean_image/max(max(max(mean_image)));
imwrite(mean_image,output_mean)

% %write output
writerObj = VideoWriter(output_avi);
writerObj.FrameRate = v.FrameRate;
open(writerObj); %open file for writing
  for f = 1:no_frames_selected %loop through frames
        disp("Working on " + output_avi + " frame "+ f + " of " + no_frames_selected);
  
        imshow(frames_select(:,:,:,f)) %display frame
        F = getframe(gca);             %capture display
        writeVideo(writerObj,F);       %add to file
  end
  close(writerObj); %close up shop

end