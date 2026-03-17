%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Michel Belyk, UCL 
% June 2021
% belykm@gmail.com

% retrace outputs from Morpho4 or 5
% useful for changing point of origin or direction of trace
% Made for R2019b on macOS 10.15.7
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%
%%%setable parameters%%%
%%%%%%%%%%%%%%%%%%%%%%%%

starting_point = "Lips"; %or  "Larynx". Where to start tracting from
direction = 'clockwise'; %or Counterclockwise. Which direction to step
fps = 8;
scaling_factor = 1.5; %for brightening anatomical reference image. Of no analytical consequence

base_dir = 'morph';
input_vt_trace = fullfile(base_dir,'vt_trace'); %as processed by morpho_masking.m. csv
input_vt_trace_mat = fullfile(base_dir,'vt_trace_mat'); %as processed by morpho_masking.m. 3d-array
input_vt_trace_avi = fullfile(base_dir,'vt_trace_avi'); %as processed by morpho_masking.m. 3video
input_vt_endpoints = fullfile(base_dir,'vt_endpoints'); 

input_avi_dir = 'avi_reg/'; %where to find video file data

output_vt_trace = fullfile(input_vt_trace,'retrace');
output_vt_trace_mat = fullfile(input_vt_trace_mat,'retrace'); %subdirectory for finaliseredd version
output_vt_trace_avi = fullfile(input_vt_trace_avi,'retrace');
output_vt_endpoints = fullfile(input_vt_endpoints,'retrace');

%make output directories if they don't already exist
if isfolder(output_vt_trace) == 0; mkdir(output_vt_trace); end
if isfolder(output_vt_trace_mat) == 0; mkdir(output_vt_trace_mat); end
if isfolder(output_vt_trace_avi) == 0; mkdir(output_vt_trace_avi); end
if isfolder(output_vt_endpoints) == 0; mkdir(output_vt_endpoints); end

%%%%%%%%%%%%%%%%%%%%%%%%
%%%Loop Through Files%%%
%%%%%%%%%%%%%%%%%%%%%%%%
list_input_files = dir([input_vt_trace_mat '/*.mat']); %list all mat files
for iFile = 1:length(list_input_files) %loop through video files
    input_rootname = list_input_files(iFile).name(1:end-12); %remove file _outline.mat tag
    disp("Processing: " + input_rootname);
    
    %%%read in existing data%%%
    
    %dig out anatomy image for context
    %read subsetter logfile to get frame numbers
    logfilename=fullfile(base_dir, 'mat_sub','log_sub',strcat(input_rootname,'_log.csv'));
    logfile = readtable(logfilename);

    %read raw image from .avi for anatomical reference
    v = VideoReader([input_avi_dir input_rootname '.avi']);
    no_frames = v.Duration*v.FrameRate;
    frames = read(v);
    if length(size(frames))>3 %if anatomical image reads as rgb rather than greyscale
        frames = frames(:,:,1,:);
    end
    frames = squeeze(frames); %remove unwanted dimension
    frames = cast(frames, 'single');
    frames = frames(:,:,logfile.Frame_Position); %reduce to analyzable frames
    frames_size = size(frames);
    image_size = frames_size(1:2);
    no_frames = frames_size(3);
  
    %read outline.mat
    outline_mat_filname = strcat(input_rootname, '_outline.mat');
    load(fullfile(input_vt_trace_mat, outline_mat_filname)); %loads trace_outline.mat <-----This is what we are retracing from

    %read vt_trace.csv
    trace_x_filename=fullfile(input_vt_trace, strcat(input_rootname,'_X.csv')); %build filename
    trace_y_filename=fullfile(input_vt_trace, strcat(input_rootname,'_Y.csv'));
    
    trace_x=readmatrix(trace_x_filename); %read file. introduces tailing NaNs that need removing later
    trace_y=readmatrix(trace_y_filename);

    %read endpoints
    endpoints_bottom_filename=fullfile(input_vt_endpoints, strcat(input_rootname,'_vt_bottom.csv')); %build filename
    endpoints_top_filename=fullfile(input_vt_endpoints, strcat(input_rootname,'_vt_top.csv'));
    
    endpoints_bottom=readmatrix(endpoints_bottom_filename); %read file for larynx point. frame_no, X_coord, Y_coord 
    endpoints_top=readmatrix(endpoints_bottom_filename);    %read file for lips point.

   %%%%%%%%%%%%%%%%%%%%%%%%%
   %%%Loop Through Frames%%%
   %%%%%%%%%%%%%%%%%%%%%%%%%
   %prepare .avi file for output
    output_avi = fullfile(output_vt_trace_avi, [input_rootname  '.avi']);
    writerObj = VideoWriter(output_avi);
    writerObj.FrameRate = fps;
    open(writerObj);
    
    for f = 1:no_frames
        this_trace_outline=trace_outline(:,:,f); %copy to new matrix to avoid overwriting original

        %%%redo trace
        %get interpretable indices
        vt_out_linear_edited = find(this_trace_outline); %linear index of vt pixels
        [vt_out_y_edited,vt_out_x_edited]  = ind2sub(size(this_trace_outline), vt_out_linear_edited); %more interpretable x,y index

        if starting_point == "Larynx"
            vt_out_tracestart_y_edited = max(vt_out_y_edited); %ventral-most pixels
            vt_out_tracestart_x_edited = min(vt_out_x_edited(vt_out_y_edited == vt_out_tracestart_y_edited)); %of these, which is most anterior (seems more reliable than posterior)
        end

        if starting_point == "Lips"
            vt_out_tracestart_x_edited = min(vt_out_x_edited); %find most anterior pixels
            vt_out_tracestart_y_edited = min(vt_out_y_edited(vt_out_x_edited == vt_out_tracestart_x_edited)); %of these, which is most dorsal (up)
        end

        %do trace
        vt_trace_edited = bwtraceboundary(this_trace_outline,[vt_out_tracestart_y_edited,vt_out_tracestart_x_edited],'W',8,Inf,direction);       
        trace_mat_edited = zeros(image_size);%%%make matrix form
        trace_ind_edited = sub2ind(image_size, vt_trace_edited(:,1),vt_trace_edited(:,2));
        trace_mat_edited(trace_ind_edited) =1;

        %write new trace to file
        X = vt_trace_edited(:,2);
        Y = vt_trace_edited(:,1);

        dlmwrite(fullfile(output_vt_trace, strcat(input_rootname,'_X.csv')),X', 'delimiter',',','-append') %save by appending  
        dlmwrite(fullfile(output_vt_trace, strcat(input_rootname,'_Y.csv')),Y', 'delimiter',',','-append') %save by appending  

        %update frame in trace_mat
        trace_outline(:,:,f) = trace_mat_edited;
        
        
        
        %save image frame to avi
        imshowpair(frames(:,:,f)/scaling_factor, trace_mat_edited);
        F = getframe(gca);
        writeVideo(writerObj,F); 

    end %end frames loop
close(writerObj); %close video file,writing done
    
%save trace outline_finaliser
output_trace_mat_filename=char(fullfile(output_vt_trace_mat,string(input_rootname)+'_outline.mat'));
save(output_trace_mat_filename,'trace_outline'); %save outline for later diagnostics

end %endfile loop