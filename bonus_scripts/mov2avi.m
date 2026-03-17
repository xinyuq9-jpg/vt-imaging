clear all;
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Michel Belyk, UCL 
% May 2021
% belykm@gmail.com

% Convert .mov, .mp4 (and maybe other formats) to .avi
% Made for R2019b on macOS 10.15.1
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

input_filetype = '.mp4';
output_filetype = '.avi';

%%%%%%%%%%%%%%%%%%%%%%%%
%%%Manage Directories%%%
%%%%%%%%%%%%%%%%%%%%%%%%
input_dir = 'originals/'; %as processed by morpho_masking.m. 3d-array
output_dir = 'avi_raw/'; %as processed by morpho_masking.m. 3d-array

if isfolder(output_dir) == 0; mkdir(output_dir); end %make it if it doesn't exist

%%%list files
list_input_files = dir([input_dir '*' input_filetype]); %list all mat files

for iFile = 1:length(list_input_files) %loop through video files
    input_rootname = list_input_files(iFile).name(1:end-4); %remove file enxtension
    disp("Loading: " + input_rootname + input_filetype);
    
    %read raw image from .mov for anatomical reference
    v = VideoReader([input_dir input_rootname input_filetype]);
    fps= v.FrameRate;
    no_frames = v.NumFrames;
    frames = read(v);
    if length(size(frames))==4 %sometime .avi encodes an extra dimension for RGB
      frames = frames(:,:,1,:); %if so drop dim3
      frames = squeeze(frames); %remove unwanted dimension
    end
    frames = cast(frames, 'single');
    
    %prepare .avi file for output
    output_avi = fullfile(output_dir, [input_rootname  output_filetype]);
    writerObj = VideoWriter(output_avi);
    writerObj.FrameRate = fps;
    open(writerObj);
    
    %loop through frames and write to file
    for frame = 1:no_frames
        disp("Converting: " + input_rootname + " Frame " + frame + " of " + no_frames);
        F = frames(:,:,frame); %dig out frame
        F = uint8(F); %data type conversion
        writeVideo(writerObj,F);
    end
    close(writerObj)
end