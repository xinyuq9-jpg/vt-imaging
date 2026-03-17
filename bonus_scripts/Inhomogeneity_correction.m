clear all;
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Michel Belyk, UCL 
% August 2020
% belykm@gmail.com

% Perform intensity inhomogeneity corrections for rtMRI data
% weights each pixel by the inverse of local intensity
% not tested extensively
% Made for R2019b on macOS 10.15.1
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%
%%%Setable Parameters%%%
%%%%%%%%%%%%%%%%%%%%%%%%
sigma_weight = 0.05; %how smooth shoud image intensity be, in proportion of image size

%%%%%%%%%%%%%%%%%%%%%%%%
%%%Manage Directories%%%
%%%%%%%%%%%%%%%%%%%%%%%%
input_avi_dir = 'avi_raw/'; %as processed by morpho_masking.m. 3d-array
output_dir = 'avi_imho/'; %as processed by morpho_masking.m. 3d-array

if isfolder(output_dir) == 0; mkdir(output_dir); end %make it if it doesn't exist

%%%%%%%%%%%%%%%%%%%%%%%%
%%%Loop Through Files%%%
%%%%%%%%%%%%%%%%%%%%%%%%
list_input_files = dir([input_avi_dir '/*.avi']); %list all mat files

for iFile = 1:length(list_input_files) %loop through video files
    input_rootname = list_input_files(iFile).name(1:end-4); %remove file enxtension
    disp("Processing: " + input_rootname);
    
    %read raw image from .avi for anatomical reference
    v = VideoReader([input_avi_dir input_rootname '.avi']);
    no_frames = v.Duration*v.FrameRate;
    fps = v.FrameRate;
    frames = read(v);
    frames = squeeze(frames); %remove unwanted dimension
    frames = cast(frames, 'single');
    
    %%%%%%%%%%%%%%%%%%%%%%%%%
    %%%Loop Through Frames%%%
    %%%%%%%%%%%%%%%%%%%%%%%%%
    %prepare .avi file for output
    output_avi = fullfile(output_dir, [input_rootname  '.avi']);
    writerObj = VideoWriter(output_avi);
    writerObj.FrameRate = fps;
    open(writerObj);
    
        for f = 1:no_frames
            disp(strcat("Frame ", string(f), " of ", string(no_frames)))

            %find image background
            this_frame = frames(:,:,f);
            [bg_function,bg_index] =  ksdensity(this_frame(:)); %distribtuon of pixel values, hopefully bimodal
            bg_min = islocalmin(bg_function); %find index of local minimum
            bg_threshold = bg_index(bg_min); %find value at local minimum
            bg_threshold = min(bg_threshold);  %in case there are multiple minima
            bg_mask=this_frame<bg_threshold;
            %imshow(bg_mask)

            %do intensity correction, this primarily affects tissue
            imsize = size(this_frame);
            sigma = imsize(1)*sigma_weight; %peg sigma to the image size 5-10% fullwidth seems good
            this_frame_blur = imgaussfilt(this_frame,sigma);
            blur_mean = mean(mean(this_frame_blur));
            this_frame_blur = this_frame_blur - blur_mean;
            this_frame_weight = rescale(this_frame_blur,0.5,2); 

            this_frame_homogenous = this_frame ./ this_frame_weight;

            %rescale to original image range
            low = min(min(this_frame));
            high = max(max(this_frame)); 
            this_frame_homogenous = rescale(this_frame_homogenous, low, high);
            
            %return the original background
            this_frame_homogenous(bg_mask) = this_frame(bg_mask); %this
         
            
            %this_frame_homogenous = imsharpen(this_frame_homogenous);
            close
            subplot(1,3,1), imshowpair(this_frame,this_frame);
            subplot(1,3,2), imshowpair(this_frame,this_frame_homogenous);
            subplot(1,3,3), imshowpair(this_frame_homogenous,this_frame_homogenous);
            
            F = uint8(this_frame_homogenous);

            %view & save
            writeVideo(writerObj,F);
        end
        close(writerObj);
end