function [avi_filename] = trim_frames(dir,avi_filename, drop_first, drop_last, flag)
%% Function description
% March 2022, Michel Belyk
%remove initial and final frames from rtMRI run
%initial/final frames are often of little value as magnetic gradients ramp
%up/down. Sometimes these are discarded at the imaging centre, if not this
%function may be useful
%beware its position in the pipeline! You may want to consider how it
%affects frame selection during morpho2_subsetter

%avi_filename: the file to work on
%drop_first: omit frames 1:drop_first
%drop_last: omit frames drop_last:end
%flag: a token to add to the filename


%read vodep
v = VideoReader(avi_filename);
  no_frames = v.Duration*v.FrameRate;
  fps = v.FrameRate;
  frames = read(v);
  
%subset to requested frames
keep_first = drop_first + 1;
keep_last = no_frames - drop_last;
frames = frames(:,:, keep_first:keep_last);
no_frames_selected = size(frames, 3);

%wite output
output_dir = 'avi_trim/';
input_rootname = avi_filename(1:end-4); %remove file enxtension
output_avi= char(fullfile(output_dir,string(input_rootname)+'_tr.avi')); %tr for trim
if isfolder(output_dir) == 0; mkdir(output_dir); end %make it if it doesn't exist

writerObj = VideoWriter(output_avi);
writerObj.FrameRate = v.FrameRate;
open(writerObj); %open file for writing
  for f = 1:no_frames_selected %loop through frames
        disp("Working on " + output_avi + " frame "+ f + " of " + no_frames_selected);
        writeVideo(writerObj,frames(:,:,f));       %add to file
  end
  close(writerObj); %close up shop

end