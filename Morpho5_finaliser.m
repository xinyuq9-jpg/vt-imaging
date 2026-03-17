%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Michel Belyk, UCL 
% April 2022
% belykm@gmail.com

% Check vocal tract masks produdced by morpho_oultine.m
% visually inspect morph/vt_trace_avi and run this script only on files
% that need some manual correction
% Made for R2019b on macOS 10.15.1
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%
%%%setable parameters%%%
%%%%%%%%%%%%%%%%%%%%%%%%
scaling_factor = 1.5; %for brightening anatomical reference image. Of no analytical consequence

%set defaults for drawing/erasing. These can also be set interactively
brush_size = 5; %add this many pixles to each side of the cursor to make a square
draw_mode = 'E'; %D for Draw, E for Erase
    if draw_mode == 'D' %Derived from draw mode
        ink = 1;
    elseif draw_mode == 'E'
        ink = 0;
    end

base_dir = 'morph';
input_vt_trace = fullfile(base_dir,'vt_trace'); %as processed by morpho_masking.m. csv
input_vt_trace_mat = fullfile(base_dir,'vt_trace_mat'); %as processed by morpho_masking.m. 3d-array
input_vt_trace_avi = fullfile(base_dir,'vt_trace_avi'); %as processed by morpho_masking.m. 3video
input_vt_endpoints = fullfile(base_dir,'vt_endpoints'); 

input_avi_dir = 'avi_reg/'; %where to find video file data

output_vt_trace = fullfile(input_vt_trace,'finaliser');
output_vt_trace_mat = fullfile(input_vt_trace_mat,'finaliser'); %subdirectory for finaliseredd version
output_vt_trace_avi = fullfile(input_vt_trace_avi,'finaliser');
output_vt_endpoints = fullfile(input_vt_endpoints,'finaliser');

%make output directories if they don't already exist
if isfolder(output_vt_trace) == 0; mkdir(output_vt_trace); end
if isfolder(output_vt_trace_mat) == 0; mkdir(output_vt_trace_mat); end
if isfolder(output_vt_trace_avi) == 0; mkdir(output_vt_trace_avi); end
if isfolder(output_vt_endpoints) == 0; mkdir(output_vt_endpoints); end
addpath("bonus_scripts") %where to find

%%%%%%%%%%%%%%%%%%%%%%%%
%%%Loop Through Files%%%
%%%%%%%%%%%%%%%%%%%%%%%%
list_input_files = select_input_files(input_vt_trace_mat, '.mat');

for iFile = 1:length(list_input_files) %loop through video files
    input_rootname = list_input_files(iFile).name(1:end-12); %remove file _outline.mat tag
    
    disp("%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%")
    disp("Processing: " + input_rootname);
    disp("%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%")

    %%%read in existing data%%%
    
    %dig out anatomy image for context
    %read subsetter logfile to get frame numbers
    logfilename=fullfile(base_dir, 'mat_sub','log_sub',strcat(input_rootname,'_log.csv'));
    logfile = readtable(logfilename);

    %read raw image from .avi for anatomical reference
    v = VideoReader([input_avi_dir input_rootname '.avi']);
    fps=v.FrameRate;
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
  
    exit_box_size = round(min(image_size)/20); %size of box for exiting edit mode
    settings_box_size = exit_box_size; %size of box for changing edit settings

    %read outline.mat
    outline_mat_filname = strcat(input_rootname, '_outline.mat');
    load(fullfile(input_vt_trace_mat, outline_mat_filname)); %loads trace_outline.mat

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

   %%%%%%%%%%%%%%%%%%%%%%%%%%%
   %%%read in previous data%%%
   %%%%%%%%%%%%%%%%%%%%%%%%%%%
    %%%build a struct to contain all existing data
    trace_holder(no_frames) = struct('trace_x',[],'trace_y', [], 'outline',[],'endpoints_bottom',[],'endpoints_top',[]); %pre-allocate memory
                                                                                                                     %depth corresponds to frames eg %trace_holder(f)                                                                             % trace_holder(1).x x-coordinates forframe 1
    %populate struct                                                                                                     % trace_holder(1).y y-coordinates forframe 1
    for f = 1:no_frames
        %wrangle existing trace
        this_trace_x = trace_x(f,:);
        this_trace_x_isnum = ~isnan(this_trace_x); %find non-NAN values
        this_trace_x= this_trace_x(this_trace_x_isnum); %remove trailing NaNs introduced by readmatrix
        
        this_trace_y = trace_y(f,:);
        this_trace_y_isnum = ~isnan(this_trace_y); %find non-NAN values
        this_trace_y=this_trace_y(this_trace_y_isnum); %remove trailing NaNs introduced by readmatrix
        
        %%%place existing data into trace_holder
        trace_holder(f).trace_x = this_trace_x;
        trace_holder(f).trace_y = this_trace_y;
        trace_holder(f).outline = trace_outline(:,:,f);
        trace_holder(f).endpoints_top = endpoints_top(f, 2:3);
        trace_holder(f).endpoints_bottom = endpoints_bottom(f, 2:3);
    end
    trace_holder_edited = trace_holder; % a working copu so we keep originals

   %%%%%%%%%%%%%%%%%%%%%%%%%
   %%%Loop Through Frames%%%
   %%%%%%%%%%%%%%%%%%%%%%%%%
    %%%show image
    imshowpair(frames(:,:,f)/scaling_factor, trace_holder_edited(f).outline);
    set(gcf, 'Units', 'Normalized', 'OuterPosition', [0, 0, 0.5, 1]);        
    %AxesHandle=findobj(gcf,'Type','axes');
    %Axisdefault = get(AxesHandle,'Position');        
    %set(gca,'Position',[0 0 1 1]) %embiggen

    f = 1;
    while f <= no_frames
        %show on top of anatomy        
        disp(strcat("Frame ", string(f), " of ", string(no_frames)))

        %%%show image
        imshowpair(frames(:,:,f)/scaling_factor, trace_holder_edited(f).outline);
        set(gcf, 'Units', 'Normalized', 'OuterPosition', [0, 0, 0.5, 1]);        
        %AxesHandle=findobj(gcf,'Type','axes');
        %Axisdefault = get(AxesHandle,'Position');        
        %set(gca,'Position',[0 0 1 1]) %embiggen

        %click past or edit
        user_input=input('Does this need fixing? (f = fix, n = next frame, b = back, r = restore original): ', 's'); %work in this image (f)m move on to next (n), or back to previous (b)
   
        if isempty(user_input); user_input = 'n'; end %protect against sloppy user input. empty = 'n'
                
        %%%carry over existing data if editing not needed
        if user_input == 'n' || user_input == 'N'
            f = f+1; %increment and take no further action

        elseif (user_input == 'b'&& f > 1) || (user_input == 'B'  && f >1)
            f = f-1; %de-increment and take no further action
                     %protected against walking below frame 1

        elseif user_input == 'r' || user_input == 'R'
            disp(strcat("Restoring original values to frame ", string(f), " of ", string(no_frames)))
            trace_holder_edited(f) = trace_holder(f);

        else
            %%%%%%%%%%%%%%%%%%%%%%%%%
            %%% editing procedure %%%
            %%%%%%%%%%%%%%%%%%%%%%%%%
            x1=1; %reset cursor to bottom left corner
            y1=image_size(1);

            %draw corner box
            trace_holder_edited(f).outline(1:exit_box_size, end-exit_box_size:end) = 1;   %draw box in corner of mask
            trace_holder_edited(f).outline(1:settings_box_size, 1:settings_box_size) = 1; %draw box in corner of mask

            while x1 < image_size(2)-exit_box_size || y1 > exit_box_size %while cursor is not in the corner box

                %show plot
                imshowpair(frames(:,:,f)/scaling_factor, trace_holder_edited(f).outline);
                set(gcf, 'Units', 'Normalized', 'OuterPosition', [0, 0, 0.5, 1]);        
                %AxesHandle=findobj(gcf,'Type','axes');
                %Axisdefault = get(AxesHandle,'Position');        
                %set(gca,'Position',[0 0 1 1]) %embiggen

                %get input
                [x1,y1] = ginput(1); %click on one pixel whose value needs to change
                x1 = round(x1);
                y1 = round(y1);

                %close this dialog if we 
                if x1 > image_size(2)-exit_box_size && y1 < exit_box_size
                    break
                
                %behaviour if user clicks the settings box. borrowed from moprho1
                elseif x1 <= settings_box_size && y1 <= settings_box_size
                    
                    %call UI settings dialog. Gives user options
                    [draw_mode,brush_size, ink] = Morpho5_UI(draw_mode, brush_size, image_size);

                %behaviour if erasing. Do erasure based on brush size
                elseif draw_mode == 'E'
                    %set brush
                    x_brush = x1-brush_size:x1+brush_size; %expand for larger selection brush
                    y_brush = y1-brush_size:y1+brush_size;
                    x_brush(x_brush>image_size(2)) = image_size(2); %in case the brush spills out of frame
                    y_brush(y_brush>image_size(1)) = image_size(1);
                    x_brush(x_brush<1) = 1; %and the other side
                    y_brush(y_brush<1) = 1;

                    %do erasing
                    trace_holder_edited(f).outline(y_brush,x_brush) = 0; %erase depending on outcome
                
                %behaviour if drawing. Connect points
                elseif draw_mode == 'D'
                    disp('Click a second point to draw a straight line.')
                    %wait for second user input
                    [x2,y2] = ginput(1); %click on one pixel whose value needs to change
                    x2 = round(x2);
                    y2 = round(y2);

                    %coordinates connecting user input 1 to user input 2
                    oversampling = max(range([x1, x2]), range([y1, y2]))*2; %prevents gaps
                    draw_x = linspace(x1,x2,oversampling);
                    draw_y = linspace(y1,y2,oversampling);
                    draw_x = round(draw_x);
                    draw_y = round(draw_y);
                    draw_linear = sub2ind(frames_size, draw_y, draw_x); %linear index

                    %draw line in image matrix
                    trace_holder_edited(f).outline(draw_linear) = 1;
                end %end if clicked buttons conditional
            end %end while no in exit box

            %erase corner button boxes
            trace_holder_edited(f).outline(1:exit_box_size, end-exit_box_size:end) = 0;   %erasure box in corner of mask
            trace_holder_edited(f).outline(1:settings_box_size, 1:settings_box_size) = 0; %erasure box in corner of mask
            
            %%%%%%%%%%%%%%%%%%
            %%% redo trace %%%
            %%%%%%%%%%%%%%%%%%
            %get interpretable indices
            vt_out_linear_edited = find(trace_holder_edited(f).outline); %linear index of vt pixels
            [vt_out_y_edited,vt_out_x_edited]  = ind2sub(image_size, vt_out_linear_edited); %more interpretable x,y index

            %starting point for main trace at bottom of vocal tract
            trace_holder_edited(f).endpoints_top(2) = min(vt_out_x_edited); %find most anterior pixels
            trace_holder_edited(f).endpoints_top(1) = min(vt_out_y_edited(vt_out_x_edited == min(vt_out_x_edited))); %of these, which is most dorsal (up)
            
            %also get the bottom in case useful
            trace_holder_edited(f).endpoints_bottom(2) = min(vt_out_x_edited(vt_out_y_edited == min(vt_out_y_edited)));
            trace_holder_edited(f).endpoints_bottom(1) =  min(vt_out_y_edited);

            trace_start_x = trace_holder_edited(f).endpoints_top(2); %start drawing from front
            trace_start_y = trace_holder_edited(f).endpoints_top(1);

            %do trace
            trace_edited = bwtraceboundary(trace_holder_edited(f).outline,[trace_start_y,trace_start_x],'W',8,Inf,'clockwise');       
            
            %store trace values
            trace_holder_edited(f).trace_y = trace_edited(:,1);
            trace_holder_edited(f).trace_x = trace_edited(:,2);
            
            trace_mat_edited = zeros(image_size);%%%make matrix form
            trace_ind_edited = sub2ind(image_size, trace_holder_edited(f).trace_y,trace_holder_edited(f).trace_x);
            trace_mat_edited(trace_ind_edited) =1;

            %store outline matrix
            trace_holder_edited(f).outline = trace_mat_edited;

        end %else edit procedure for current frame terminates here 
    end %end while loop through frames

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %%% save off from struct %%%
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%
    %save off .mat data
    output_trace_mat_filename=char(fullfile(output_vt_trace_mat,string(input_rootname)+'_outline.mat'));
    trace_outline = trace_holder_edited(:).outline;
    save(output_trace_mat_filename,'trace_outline'); %save outline for later diagnostics
    
    %prepare .avi file for output
    output_avi = fullfile(output_vt_trace_avi, [input_rootname  '.avi']);
    writerObj = VideoWriter(output_avi);
    writerObj.FrameRate = fps;
    open(writerObj);
        
    disp("Saving off data for "+ input_rootname + ". Please hold.")
    for f = 1:no_frames
        disp(strcat("Frame ", string(f), " of ", string(no_frames)))
        %save of avi
        imshowpair(frames(:,:,f)/scaling_factor, trace_holder_edited(f).outline);
        %set(gcf, 'Units', 'Normalized', 'OuterPosition', [0.5, 0.5, 0.5, 1]);        
        AxesHandle=findobj(gcf,'Type','axes');
        Axisdefault = get(AxesHandle,'Position');        
        set(gca,'Position',[0 0 1 1]) %embiggen

        F = getframe(gca);
        writeVideo(writerObj,F);

        %save off string data
        dlmwrite(fullfile(output_vt_trace, strcat(input_rootname,'_X.csv')),trace_holder_edited(f).trace_x, 'delimiter',',','-append') %save by appending  
        dlmwrite(fullfile(output_vt_trace, strcat(input_rootname,'_Y.csv')),trace_holder_edited(f).trace_y, 'delimiter',',','-append') %save by appending  

        dlmwrite(fullfile(output_vt_endpoints, strcat(input_rootname,'_vt_bottom.csv')),[f,trace_holder_edited(f).endpoints_bottom(1), trace_holder_edited(f).endpoints_bottom(2)] , 'delimiter',',','-append') %save by appending  
        dlmwrite(fullfile(output_vt_endpoints, strcat(input_rootname,'_vt_top.csv'))   ,[f,trace_holder_edited(f).endpoints_top(1)   , trace_holder_edited(f).endpoints_top(2)   ] , 'delimiter',',','-append') %save by appending        
    end
    close(writerObj); %close video file,writing done

    
end %end file loop
close