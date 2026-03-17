%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%CONVERT dicom data to AVI for further rtMRI analyses%
%treats each image in the current directory as a frame in one run
%Michel Belyk, February 2020
%University College London
%belykm@gmail.com
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%test for .ima and .dcm formats on only

%%%%%%%%%%%%%%%%%%%%%%%
%%%PARAMETERS TO SET%%%
%%%%%%%%%%%%%%%%%%%%%%%
fps = 10;                            %frame rate frames/seconds
output_avi = 'Arabic_Tt_3.avi';  %what should we call the file
image_format = '.dcm';              %what file extension do component images have

%%%%%%%%%%%%%%%
%%%Find Data%%%
%%%%%%%%%%%%%%%
list_input_files = dir(strcat('*',image_format)); %list all image files


%%%%%%%%%%%%%%%
%%%Loop Data%%%
%%%%%%%%%%%%%%%

%initialise video file
writerObj = VideoWriter(output_avi);
writerObj.FrameRate = 10;
open(writerObj);

for iFile = 1:length(list_input_files) %loop through video files
    image = list_input_files(iFile).name; %remove file enxtension and _skel tag
    disp("Processing image: " + string(iFile));
    
    frame = dicomread(image); %read image data
    frame = uint8(frame); %force class
    writeVideo(writerObj,frame);  %add to avi file
end

close(writerObj); %close video file,writing done