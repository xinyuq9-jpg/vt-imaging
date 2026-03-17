%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Michel Belyk, UCL 
% August 2022
% belykm@gmail.com

% find velocity, acceleration, and jerk of pixels of pixel values
% highlights location of labile structures
% also fairly sensitive to background noise. 
% Maybe benefits from some kind
% of smoothing first
% Made for R2022a on windows11
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%
%SETABLE PARAMETERS%%%
%%%%%%%%%%%%%%%%%%%%%%
online_viewer = 0;     %0 to view at fastest speed, 1 to control view speed                     
viewer_acceleration = 1; %how much to speed up video display. 1x is natural time


%%%%%%%%%%%%%%%%%%%%%%%%
%%%manage directories%%%
%%%%%%%%%%%%%%%%%%%%%%%%
input_dir = 'avi_reg'; %where are the .avi files?

out_base_dir = 'morph';
deriv_avi_dir = fullfile(out_base_dir,'avi');  %where to send ouput .avi files?
deriv_mat_dir = fullfile(out_base_dir,'mat');  %where to send output .mat files


%%%%%%%%%%%%%%%%%%%%%%
%Iterate through files
%%%%%%%%%%%%%%%%%%%%%%
%make output directories if they don't already exist
if isfolder(out_base_dir) == 0; mkdir(out_base_dir); end
if isfolder(deriv_avi_dir) == 0; mkdir(output_avi_dir); end
if isfolder(deriv_mat_dir) == 0; mkdir(output_dat_dir); end

list_input_files = dir([input_dir '/*.avi']); %lisat all avi files

for iFile = 1:length(list_input_files) %loop through video files
  input_rootname = list_input_files(iFile).name(1:end-4); %remove file enxtension
  input_filename = fullfile(input_dir,list_input_files(iFile).name);

  disp("Processing: " + input_rootname);

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

  t = 1:size(frames, 3);% %time
  
  %make placeholders
  frames_velocity = zeros(size(frames));
  frames_acceleration = zeros(size(frames));
  frames_jerk = zeros(size(frames));
  frames_max = zeros(size(frames));

  %loop pixles. Maybe vectorisable?
  for y = 1:size(frames, 1) %loop y pixels
      for x = 1:size(frames, 2) %loop x pixels
          %calculate derivatives
          sp = spline(t, frames(y,x,:));
          velocity = fnder(sp, 1);
          accelaration = fnder(sp, 2);
          jerk = fnder(sp, 3);

          %store in placeholders, abslute values only
          frames_velocity(y,x,:) = abs(fnval(velocity, t));
          frames_acceleration(y,x,:) = abs(fnval(accelaration, t));
          frames_jerk(y,x,:) = abs(fnval(jerk, t));

      end %end x
  end %end y

  %write outputs
    %filenames
    %prepare video for export
    velocity_avi_file= char(fullfile(deriv_avi_dir,string(input_rootname)+'_velocity.avi'));
    velocity_dat= char(fullfile(deriv_mat_dir,string(input_rootname)+'_velocity.mat'));
    acceleration_avi_file= char(fullfile(deriv_avi_dir,string(input_rootname)+'_acceleration.avi'));
    acceleration_dat= char(fullfile(deriv_mat_dir,string(input_rootname)+'_acceleration.mat'));
    jerk_avi_file= char(fullfile(deriv_avi_dir,string(input_rootname)+'_jerk.avi'));
    jerk_dat= char(fullfile(deriv_mat_dir,string(input_rootname)+'_jerk.mat'));
 
   save(velocity_dat,'frames_velocity');
   save(acceleration_dat,'frames_acceleration'); 
   save(jerk_dat,'frames_jerk');

    %velocity
    writerObj = VideoWriter(velocity_avi_file);
    writerObj.FrameRate = fps;
    open(writerObj);
    for f = 1:no_frames %loop through frames
       disp("Working Velocity frame " + f + " of " + no_frames);

       %display image
        %imshowpair(frames_velocity(:,:,f),frames,'falsecolor');
        image(frames_velocity(:,:,f));
        F = getframe(gca); %capture display to file

        if online_viewer==1 %pause so we can watch
            pause(viewer_acceleration/v.FrameRate);
        end

        %capture image
        writeVideo(writerObj,F); 
    end %end velocity loop
   close(writerObj); %close video file,writing done

    %acceleration
    writerObj = VideoWriter(acceleration_avi_file);
    writerObj.FrameRate = fps;
    open(writerObj);


    for f = 1:no_frames %loop through frames
       disp("Working acceleration frame " + f + " of " + no_frames);

       %display image
        image(frames_acceleration(:,:,f));
        
        F = getframe(gca); %capture display to file

        if online_viewer==1 %pause so we can watch
            pause(viewer_acceleration/v.FrameRate);
        end

        %capture image
        writeVideo(writerObj,F); 
    end %end frames loop
   close(writerObj); %close video file,writing done

    %jerk
    writerObj = VideoWriter(jerk_avi_file);
    writerObj.FrameRate = fps;
    open(writerObj);
    for f = 1:no_frames %loop through frames
       disp("Working jerk frame " + f + " of " + no_frames);


       %display image
        %imshowpair(framesjerk(:,:,f),frames,'falsecolor');
        image(frames_jerk(:,:,f));
        F = getframe(gca); %capture display to file

        if online_viewer==1 %pause so we can watch
            pause(viewer_acceleration/v.FrameRate);
        end

        %capture image
        writeVideo(writerObj,F); 
    end %end frames loop
   close(writerObj); %close video file,writing done


end %end iFile



