%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Michel Belyk, UCL 
% January 2020
% belykm@gmail.com

% Mask image to high variance voxels. If speech sounds are varied enough
%   this should localize the vocal tract.
% Then Mask image to low intensity pixels. Pixels distribution is bimodal so
%   this nicely separates soft tissue like tongue from the rest
% DO NOT resize the matlab figure during processing. script will crash
% Made for R2018b on macOS 10.14.6
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%
%SETABLE PARAMETERS%%%
%%%%%%%%%%%%%%%%%%%%%%
fps = 10;  %frame rate frames/seconds
context_frame = 10; %which frame to show for anatomical context

automatic_tissue_threhold=1; %set to 0 to manually set threshold. useful if the automatic method gives a poor result
manual_tissue_threshold = 62;
if automatic_tissue_threhold==0
    tissue_threshold = manual_tissue_threshold; %threshold value that separates air from soft tissue
                                      % ksdensity(vt(vt>0)) is probably bimodal. use the
end                                   % local minimum. Or consider the value in the oesophegus wall              

exit_box_size = 15; %size in pixels of box for exiting edit mode                     
online_viewer = 0;     %0 to view at fastest speed, 1 to control view speed                     
viewer_acceleration = 1; %how much to speed up video display. 1x is natural time

%%%%%%%%%%%%%%%%%%%%%%%%
%%%manage directories%%%
%%%%%%%%%%%%%%%%%%%%%%%%
out_base_dir = 'morph';
input_dir = fullfile(out_base_dir,'masks'); %where are the masks to redraw?

output_avi_dir = fullfile(out_base_dir,'avi');  %where to send ouput .avi files?
output_dat_dir = fullfile(out_base_dir,'mat');  %where to send output .mat files
output_mask_dir = fullfile(out_base_dir,'masks'); %where to save vocal tractd masks? maybe useful for diagnostics later


%%%%%%%%%%%%%%%%%%%%%%
%Iterate through files
%%%%%%%%%%%%%%%%%%%%%%
%make output directories if they don't already exist
if isfolder(out_base_dir) == 0; mkdir(out_base_dir); end
if isfolder(output_avi_dir) == 0; mkdir(output_avi_dir); end
if isfolder(output_dat_dir) == 0; mkdir(output_dat_dir); end
if isfolder(output_mask_dir) == 0; mkdir(output_mask_dir); end


list_input_files = dir([input_dir '/*.mat']); %list all avi files

for iFile = 1:length(list_input_files) %loop through video files
  input_rootname = list_input_files(iFile).name(1:end-8); %remove _msk.mat from filename
  input_msk_filename = fullfile(input_dir,list_input_files(iFile).name);
  input_avi_filename = fullfile("avi_reg", input_rootname + ".avi"); %original input file
  
  disp("Processing: " + input_rootname);
  %read image data
  v = VideoReader(input_avi_filename);
  no_frames = v.Duration*v.FrameRate;
  frames = read(v);
  if length(size(frames))>3 %if anatomical image reads as rgb rather than greyscale
    frames = frames(:,:,1,:);
  end
  frames = squeeze(frames); %remove unwanted dimension
  frames = cast(frames, 'single');
  
  vt_mask_initial = load(input_msk_filename); %load previously defined mask
  vt_mask_initial = vt_mask_initial.vt_mask_cleaned; %unpact struct
  
  
  
  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  %%%MANUL ADJUSTMENT OF VOCAL TRACT MASK%%%
  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  disp("Draw masks over pixels likely to contain vocal tract.")
  disp("Pay particular attention to the oesophegus, velum, lower teeth, below the tongue, and beyond the lips.")
  disp("Click the corner box to move on.")
  
  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  %phase 1: large brush pixel adding%
  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  mask_size = size(vt_mask_initial); %get 2d size
  vt_mask_cleaned =   vt_mask_initial; %copy over for clean
  exit_box_size = 15; %size of box for exiting edit mode
  x= 1; %starting values
  y=mask_size(1);
  brush_size = 2; %add this many pixels to each side of your selection; set to 0 for finest brush
  vt_mask_cleaned(1:exit_box_size, end-exit_box_size:end) = 1; %draw box in corner of mask
  
  disp("ADD pixels (big brush)")
  
  while x < mask_size(2)-exit_box_size || y > exit_box_size %while cursor is not in the corner box
    
    imshowpair(frames(:,:,context_frame)*100,vt_mask_cleaned) %show mask with mr image for context
    set(gcf, 'Units', 'Normalized', 'OuterPosition', [0.5, 0, 0.5, 1]);
    AxesHandle=findobj(gcf,'Type','axes');  
    Axisdefault = get(AxesHandle,'Position');        
    set(gca,'Position',[0 0 1 1]) %embiggen
    
    [x,y] = ginput(1); %click on one voxel whose value needs to change
    x = uint16(x); %make integer so they can be used as indices
    y = uint16(y);
    x_brush = x-brush_size:x+brush_size; %expand for larger selection brush
    y_brush = y-brush_size:y+brush_size;
    x_brush(x_brush>mask_size(2)) = mask_size(2); %in case the brush spills out of frame
    y_brush(y_brush>mask_size(1)) = mask_size(1);
    x_brush(x_brush<1) = 1; %and the other side
    y_brush(y_brush<1) = 1;
    
    vt_mask_cleaned(y_brush,x_brush) = 1; %draw only
  end
  
  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  %phase 2: large brush pixel removal%
  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  x= 1; %starting values
  y=mask_size(1);
  brush_size = 2; %add this many pixels to each side of your selection; set to 0 for finest brush
  vt_mask_cleaned(1:exit_box_size, end-exit_box_size:end) = 1; %draw box in corner of mask

   disp("REMOVE pixels (big brush)")

  
  while x < mask_size(2)-exit_box_size || y > exit_box_size %while cursor is not in the corner box
    
    imshowpair(frames(:,:,context_frame),vt_mask_cleaned) %show mask with mr image for context
    set(gcf, 'Units', 'Normalized', 'OuterPosition', [0.5, 0, 0.5, 1]);
    AxesHandle=findobj(gcf,'Type','axes');  
    Axisdefault = get(AxesHandle,'Position');        
    set(gca,'Position',[0 0 1 1]) %embiggen
    
    [x,y] = ginput(1); %click on one voxel whose value needs to change
    x = uint16(x); %make integer so they can be used as indices
    y = uint16(y);
    x_brush = x-brush_size:x+brush_size; %expand for larger selection brush
    y_brush = y-brush_size:y+brush_size;
    x_brush(x_brush>mask_size(2)) = mask_size(2); %in case the brush spills out of frame
    y_brush(y_brush>mask_size(1)) = mask_size(1);
    x_brush(x_brush<1) = 1; %and the other side
    y_brush(y_brush<1) = 1;
    
    vt_mask_cleaned(y_brush,x_brush) = 0; %erase only
  end
  
  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  %phase 3: small brush pixel add or remove pixels%
  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  disp("ADD/REMOVE pixels (small brush)")

  x= 1; %starting values
  y=mask_size(1);
  brush_size = 0; %add this many pixels to each side of your selection; set to 0 for finest brush
  vt_mask_cleaned(1:exit_box_size, end-exit_box_size:end) = 1; %draw box in corner of mask
  
%%%%Do it again with a finer brush
  while x < mask_size(2)-exit_box_size || y > exit_box_size %while cursor is not in the corner box
    
    imshowpair(frames(:,:,context_frame),vt_mask_cleaned) %show mask with mr image for context
    set(gcf, 'Units', 'Normalized', 'OuterPosition', [0.5, 0, 0.5, 1]);
    AxesHandle=findobj(gcf,'Type','axes');  
    Axisdefault = get(AxesHandle,'Position');        
    set(gca,'Position',[0 0 1 1]) %embiggen
    
    [x,y] = ginput(1); %click on one voxel whose value needs to change
    x = uint16(x); %make integer so they can be used as indices
    y = uint16(y);
    x_brush = x-brush_size:x+brush_size; %expand for larger selection brush
    y_brush = y-brush_size:y+brush_size;
    x_brush(x_brush>mask_size(2)) = mask_size(2); %in case the brush spills out of frame
    y_brush(y_brush>mask_size(1)) = mask_size(1);
    x_brush(x_brush<1) = 1; %and the other side
    y_brush(y_brush<1) = 1;
    
    vt_mask_cleaned(y_brush,x_brush) = vt_mask_cleaned(y_brush,x_brush) == 0; %change mask value at clicked pixel
  end
  
  vt_mask_cleaned(1:exit_box_size, end-exit_box_size:end) = 0; %remove the corner box
  save(char(fullfile(output_mask_dir,string(input_rootname)+'_msk.mat')),'vt_mask_cleaned'); %save mask for later diagnostics

  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  %%%GET VOCAL TRACT AND SAVE TO VIDEO%%%
  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  %prepare video for export
  output_avi= char(fullfile(output_avi_dir,string(input_rootname)+'_out.avi'));
  output_dat= char(fullfile(output_dat_dir,string(input_rootname)+'_out.mat'));

  writerObj = VideoWriter(output_avi);
  writerObj.FrameRate = fps;
  open(writerObj);

  %%%find tissue classification threshold
  
  %assuming that pixels are now either tissue or vocal tract
  %pixel values follow a bimodal distribution
  %the local minimum is probably the best we can do to separate these
  %if this fails, see parameter section for manual option
  if automatic_tissue_threhold==1
    frames_median = median(frames, 3).* vt_mask_cleaned; %median of images, performs better than mean
    [tissue_density_function,tissue_density_index] =  ksdensity(frames_median(vt_mask_cleaned)); %distribtuon of pixel values, hopefully bimodal
    %[tissue_density_function,tissue_density_index] = ksdensity(vt(vt>0));%from nonzero pixels
    tissue_density_min = islocalmin(tissue_density_function); %find index of local minimum
    tissue_threshold = tissue_density_index(tissue_density_min); %find value at local minimum
    tissue_threshold = min(tissue_threshold); %in case there are multiple minima
    
    %in case this gets borked
    if isempty(tissue_threshold)
        disp(" ")
        disp("WARNING: Failed to classify tissue. No local minimum found.")
        disp("Try this run again later with the manual tissue threshold option.");
        disp("Note threshold values that were automatically selected for other runs.");
        disp(" ")

        continue %move on to the next run
    end
    
    disp("Applying tissue threshold: " + tissue_threshold);
  end  
  
  vt_output = zeros(size(frames)); %placeholder for output
  for f = 1:no_frames %loop through frames
        disp("Working on frame " + f + " of " + no_frames);

        vt = frames(:,:,f) .* vt_mask_cleaned; %apply hand cleaned mask
        vt_tissue_mask = vt < tissue_threshold & vt > 0; %classify tissue within mask

        %this would be a good place to stop for diagnostics if things are going poorly
        %image(vt) 
        %imshow(vt_tissue_mask)

        %clean up the vocal tract
        vt_tissue_mask = bwmorph(vt_tissue_mask, 'spur');
        vt_tissue_mask = bwmorph(vt_tissue_mask, 'clean');
        vt_tissue_mask = bwmorph(vt_tissue_mask, 'close');
        vt_tissue_mask = bwmorph(vt_tissue_mask, 'fill');
        %imshow(vt_tissue_mask)

        %build 3d array of tissue masks. that's data.
        vt_output(:,:,f) = vt_tissue_mask; 

        %display tissue mask
        imshowpair(frames(:,:,f),vt_tissue_mask,'falsecolor');

        F = getframe(gca); %capture display to file

        if online_viewer==1 %pause so we can watch
            pause(viewer_acceleration/v.FrameRate);
        end

        writeVideo(writerObj,F); 
   end %end frames loop
   close(writerObj); %close video file,writing done
   save(output_dat,'vt_output');
end %end video loop
  