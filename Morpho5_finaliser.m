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
cfg = morpho.Config();

input_vt_trace = cfg.dir("vt_trace");
input_vt_trace_mat = cfg.dir("vt_trace_mat");
input_vt_trace_avi = cfg.dir("vt_trace_avi");
input_vt_endpoints = cfg.dir("vt_endpoints");
input_avi_dir = cfg.dir("avi_reg");

output_vt_trace = cfg.dir("vt_trace_final");
output_vt_trace_mat = cfg.dir("vt_trace_mat_final");
output_vt_trace_avi = cfg.dir("vt_trace_avi_final");
output_vt_endpoints = cfg.dir("vt_endpoints_final");

cfg.ensure("vt_trace_final");
cfg.ensure("vt_trace_mat_final");
cfg.ensure("vt_trace_avi_final");
cfg.ensure("vt_endpoints_final");

%%%%%%%%%%%%%%%%%%%%%%%%
%%%Loop Through Files%%%
%%%%%%%%%%%%%%%%%%%%%%%%
list_input_files = morpho.select_input_files(input_vt_trace_mat, '.mat');

for iFile = 1:length(list_input_files) %loop through video files
    input_rootname = list_input_files(iFile).name(1:end-12); %remove file _outline.mat tag

    %initialize parameters from config at start of each iteration
    scaling_factor = cfg.finaliser.scaling_factor;
    brush_size = cfg.finaliser.brush_size;
    draw_mode = cfg.finaliser.draw_mode;
    ink = morpho.display.mode_to_ink(draw_mode);

    disp("%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%")
    disp("Processing: " + input_rootname);
    disp("%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%")

    %%%read in existing data%%%

    %dig out anatomy image for context
    %read subsetter logfile to get frame numbers
    avi_path = fullfile(input_avi_dir, [input_rootname '.avi']);
    v = VideoReader(avi_path);
    fps = v.FrameRate;

    logfilename = fullfile(cfg.dir("log_sub"), [input_rootname '_log.csv']);
    logfile = readtable(logfilename);
    frame_positions = logfile.Frame_Position;
    no_frames = numel(frame_positions);

    first_frame = morpho.video.read_single(avi_path, frame_positions(1));
    image_size = size(first_frame);

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
    cached_f = 1;
    this_frame = morpho.video.read_single(avi_path, frame_positions(1));
    morpho.display.show_pair(this_frame, trace_holder_edited(1).outline, scaling_factor=scaling_factor, position=[0, 0, 0.5, 1]);

    f = 1;
    while f <= no_frames
        %show on top of anatomy
        disp(strcat("Frame ", string(f), " of ", string(no_frames)))

        %read frame on demand (cache to avoid re-reading)
        if f ~= cached_f
            this_frame = morpho.video.read_single(avi_path, frame_positions(f));
            cached_f = f;
        end

        %%%show image
        morpho.display.show_pair(this_frame, trace_holder_edited(f).outline, scaling_factor=scaling_factor, position=[0, 0, 0.5, 1]);

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

            editor = morpho.Editor(trace_holder_edited(f).outline, ...
                background=this_frame, ...
                overlay_color="green", ...
                modes="DE", ...
                brush_size=cfg.finaliser.brush_size, ...
                draw_mode=cfg.finaliser.draw_mode, ...
                allow_line_draw=true, ...
                filename=input_rootname);
            trace_holder_edited(f).outline = editor.run();

            %%%%%%%%%%%%%%%%%%
            %%% redo trace %%%
            %%%%%%%%%%%%%%%%%%
            [top, bottom] = morpho.tracing.find_endpoints(trace_holder_edited(f).outline);
            [tx, ty, trace_mat_edited] = morpho.tracing.trace_boundary(trace_holder_edited(f).outline, top);
            trace_holder_edited(f).trace_y = ty;
            trace_holder_edited(f).trace_x = tx;
            trace_holder_edited(f).endpoints_top = [top(1), top(2)];
            trace_holder_edited(f).endpoints_bottom = [bottom(1), bottom(2)];
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
        %read frame on demand for save-off
        this_frame = morpho.video.read_single(avi_path, frame_positions(f));

        %save of avi
        morpho.display.show_pair(this_frame, trace_holder_edited(f).outline, scaling_factor=scaling_factor);
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
