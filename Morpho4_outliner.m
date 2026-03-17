%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Michel Belyk, UCL
% April 2022
% belykm@gmail.com

% Trace vocal tract masks produdced by morpho_masking.m
% In case the vt has two separate compartment it builds a bridge estimating
%   the closed portion of the vocal tract.
%   soft method estimates this connection based on usual course of the
%       vocal trast. More biological plausible, under most conditions
%    hard method draws a straight line connecting the two cavities
%       may be less plausible, but is more robust
% Made for R2019b on macOS 10.15.1
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%%%%%%%%%%%%%%%%%%%%%%%%
%%%setable parameters%%%
%%%%%%%%%%%%%%%%%%%%%%%%
cfg = morpho.Config();
addpath("bonus_scripts");

%%%%%%%%%%%%%%%%%%%%%%%%
%%%manage directories%%%
%%%%%%%%%%%%%%%%%%%%%%%%
input_vt_dir = cfg.dir("mat_qa");
input_avi_dir = cfg.dir("avi_reg");
output_trace_dir = cfg.dir("vt_trace");
output_trace_avi_dir = cfg.dir("vt_trace_avi");
output_trace_mat_dir = cfg.dir("vt_trace_mat");
output_skel_dir = cfg.dir("vt_skeleton");
output_endpoints_dir = cfg.dir("vt_endpoints");

cfg.ensure("vt_trace");
cfg.ensure("vt_trace_avi");
cfg.ensure("vt_trace_mat");
cfg.ensure("vt_skeleton");
cfg.ensure("vt_endpoints");

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%Read in vocal tract mask produced by morpho_masking.m%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

list_input_files = morpho.select_input_files(input_vt_dir, '.mat');


for iFile = 1:length(list_input_files) %loop through video files
    input_rootname = list_input_files(iFile).name(1:end-7); %remove file enxtension and _skel tag
    disp("Processing: " + input_rootname);

    % Load config parameters at start of each file iteration
    draw_connector = cfg.outliner.draw_connector;
    a_star_weight = cfg.outliner.a_star_weight;
    lambda = cfg.outliner.lambda;
    wantplot = cfg.outliner.wantplot;
    polynomial_degree = cfg.outliner.polynomial_degree;
    manual_check = cfg.outliner.manual_check;
    suspicion_threshold = cfg.outliner.suspicion_threshold;
    vt_skel_thresh = cfg.outliner.vt_skel_thresh;
    scaling_factor = cfg.outliner.scaling_factor;

    %read 3d area Height x Width x Frames
    vt_filename = fullfile(input_vt_dir,strcat(input_rootname,'_QA.mat'));
    load(vt_filename); %load vt_output as prodcued by morpho_QA.m

    %read subsetter logfile to get frame numbers
    logfilename = fullfile(cfg.dir("log_sub"), [input_rootname '_log.csv']);
    logfile = readtable(logfilename);
    frame_positions = logfile.Frame_Position;
    no_frames = numel(frame_positions);

    %%%Make Skeleton VT%%%
    vt_mean = mean(vt_output, 3);
    vt_skel = morpho.tracing.compute_skeleton(vt_mean, vt_skel_thresh);
    %imshow(vt_skel)
    save(char(fullfile(output_skel_dir,string(input_rootname)+'_skel.mat')),'vt_skel'); %save mask for later diagnostics

    %where to find video file data for diagnostics
    v = VideoReader(fullfile(input_avi_dir, [input_rootname '.avi']));
    fps = v.FrameRate;

    % Get frame size from first frame (reuse v opened above)
    first_frame = morpho.video.to_gray_single(read(v, frame_positions(1)));
    frame_size = size(first_frame);

    trace_outline = zeros(frame_size(1), frame_size(2), no_frames);

    % Compute vt_ever ONCE before the frame loop
    vt_ever = max(vt_output, [], 3) == 1;

    %write avi for diagnostics
    output_avi = fullfile(output_trace_avi_dir, [input_rootname  '.avi']);

    writerObj = VideoWriter(output_avi, 'Motion JPEG AVI');
    writerObj.Quality = 95;   % 0-100 (higher = better)
    writerObj.FrameRate = fps;
    open(writerObj);

    for f = 1:no_frames
        disp(strcat("Frame ", string(f), " of ", string(no_frames)))

        % Read single frame on demand (reuse VideoReader — no per-frame open/close)
        this_frame = morpho.video.to_gray_single(read(v, frame_positions(f)));

        %%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %%%analyze clusters sizes%%%
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%


        %find clusters, used by soft and  hard link methods
        [n_compartments, lab_mat, sorted_labels] = morpho.tracing.analyze_clusters(vt_output(:,:,f));

        %if there is one cluster, we can simply tract it
        %if there are two clusters, we need to draw a connection
        %if ther are more, then some junk was missed at cleaning

        %imshow(lab_mat>0)
        %remove background
        %cluster ID 0 = background
        %cluster ID 1 = larger VT part. Either whole thing or anterior part
        %cluster ID 2 = smaller VT part. Probably the back. Possibly noise if
        %things are going badly. Excercise caution!
        %cluster ID 3+ = probably noise. maybe relevant for some vt
        %configurations

        %remove all but 2 largest clusters which are almost certainly junk.
        %lab_mat(lab_mat>2) = 0;

        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %%%Draw Connector if needed%%% %ie if vocal tract has 2 or more compartments
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

        if n_compartments >= 2 && (draw_connector== "a_star")

            bridge = morpho.tracing.a_star_bridge(vt_output(:,:,f) > 0, vt_ever, this_frame, a_star_weight);
            vt_output(:,:,f) = vt_output(:,:,f) + bridge;
            %imshowpair(vt_output(:,:,f),bridge)


        %%%mean spline method
        elseif n_compartments >= 2 && (draw_connector== "mean_spline" || draw_connector== "upper_spline")
            vt_output_linear = find(vt_output(:,:,f) >0); %linear index of vt pixels

            %get top bottom of mean vt
            vt_mean_bin = vt_mean >0;
            vt_mean_linear = find(vt_mean_bin); %linear index of vt pixels
            [vt_mean_y,vt_mean_x]  = ind2sub(frame_size, vt_mean_linear); %more interpretable x,y index

            %vocal tract endpoints
            vt_mean_top_x = min(vt_mean_x);                             %find most anterior pixels
            vt_mean_top_y = round(median(vt_mean_y(vt_mean_x == vt_mean_top_x))); %of these, which is most dorsal (up)

            vt_mean_bottom_y = max(vt_mean_y);                           %find most ventral pixels
            vt_mean_bottom_x = round(median(vt_mean_x(vt_mean_y == vt_mean_bottom_y))); %of these, which is most posterior (up)

            %hollow meant vt
            vt_mean_hollow = bwmorph(vt_mean_bin,'remove');

            %remove top/bottom pixels from trace
            %also removes neighbours for good measure
            top_mat = zeros(frame_size);
            top_mat(vt_mean_top_y, vt_mean_top_x) = 1;
            top_mat = imdilate(top_mat,strel('square',2));

            bottom_mat = zeros(frame_size);
            bottom_mat(vt_mean_bottom_y, vt_mean_bottom_x) = 1;
            bottom_mat = imdilate(bottom_mat,strel('square',2));

            top_mat = top_mat==0;
            bottom_mat = bottom_mat==0;

            vt_mean_hollow = vt_mean_hollow .* top_mat;
            vt_mean_hollow = vt_mean_hollow .* bottom_mat;

            %clustering to separate top bottom
            holow_mat_lab = bwlabel(vt_mean_hollow);
            holow_mat_labs = unique(holow_mat_lab);

            vt_mean_mat_upper = holow_mat_lab==1;
            vt_mean_mat_lower = holow_mat_lab==2;

            %get new endpoints for upper
            vt_mean_upper_linear = find(vt_mean_mat_upper); %linear index of vt pixels
            [vt_mean_upper_y,vt_mean_upper_x]  = ind2sub(frame_size, vt_mean_upper_linear); %more interpretable x,y index

            vt_mean_upper_top_x = min(vt_mean_upper_x);                             %find most anterior pixels
            vt_mean_upper_top_y = round(median(vt_mean_upper_y(vt_mean_upper_x == vt_mean_upper_top_x))); %of these, which is most dorsal (up)

            vt_mean_upper_bottom_y = max(vt_mean_upper_y);                           %find most ventral pixels
            vt_mean_upper_bottom_x = round(median(vt_mean_upper_x(vt_mean_upper_y == vt_mean_upper_bottom_y))); %of these, which is most posterior (up)

            %get new endpoints for lower
            vt_mean_lower_linear = find(vt_mean_mat_lower); %linear index of vt pixels
            [vt_mean_lower_y,vt_mean_lower_x]  = ind2sub(frame_size, vt_mean_lower_linear); %more interpretable x,y index

            vt_mean_lower_top_x = min(vt_mean_lower_x);                             %find most anterior pixels
            vt_mean_lower_top_y = round(median(vt_mean_lower_y(vt_mean_lower_x == vt_mean_lower_top_x))); %of these, which is most dorsal (up)

            vt_mean_lower_bottom_y = max(vt_mean_lower_y);                           %find most ventral pixels
            vt_mean_lower_bottom_x = round(median(vt_mean_lower_x(vt_mean_lower_y == vt_mean_lower_bottom_y))); %of these, which is most posterior (up)

            %trace bottom/top..each likely gets done twice...
            vt_trace_upper = bwtraceboundary(vt_mean_mat_upper,[vt_mean_upper_bottom_y,vt_mean_upper_bottom_x],'W',8,Inf,'clockwise');
            vt_trace_lower = bwtraceboundary(vt_mean_mat_lower,[vt_mean_lower_bottom_y,vt_mean_lower_bottom_x],'W',8,Inf,'clockwise');

            %bwtraceboundary will go from bottom to top...and back again.
            %here we delete the back again part
            upper_stop = find(ismember(vt_trace_upper,[vt_mean_upper_top_y,vt_mean_upper_top_x],'rows')); %find point where trace hits top
            upper_stop = upper_stop(1); %first instance in case of multiple
            vt_trace_upper = vt_trace_upper(1:upper_stop, :); %keep only the first pass through

            lower_stop = find(ismember(vt_trace_lower,[vt_mean_lower_top_y,vt_mean_lower_top_x],'rows')); %find point where trace hits top
            lower_stop = lower_stop(1); %first instance in case of multiple
            vt_trace_lower = vt_trace_lower(1:lower_stop,:); %keep only the first pass through

            %median at duplicate x's
            vt_trace_upper_uniquex = unique(vt_trace_upper(:,2)); %col 1  =y col 2 = x
            vt_trace_lower_uniquex = unique(vt_trace_lower(:,2));

            vt_trace_upper_med = NaN(size(vt_trace_upper_uniquex));
            for i = 1:length(vt_trace_upper_uniquex)
                u = vt_trace_upper_uniquex(i);
                vt_trace_upper_med(i,2) = u;      %place unique x value
                u_ind = vt_trace_upper(:,2) == u; %index of all rows with this x vaalue
                vt_trace_upper_med(i,1) =  median(vt_trace_upper(u_ind,1));       %median of y at those x values
            end %end unique upppers for

            vt_trace_lower_med = NaN(size(vt_trace_lower_uniquex));
            for i = 1:length(vt_trace_lower_uniquex)
                u = vt_trace_lower_uniquex(i);
                vt_trace_lower_med(i,2) = u;      %place unique x value
                u_ind = vt_trace_lower(:,2) == u; %index of all rows with this x vaalue
                vt_trace_lower_med(i,1) =  median(vt_trace_lower(u_ind,1));       %median of y at those x values
            end %end unique upppers for
            %plot(vt_trace_upper_med(:,2), vt_trace_upper_med(:,1))
            %plot(vt_trace_lower_med(:,2), vt_trace_lower_med(:,1))

            %x values at which to evaluate
            xrange_upper = [min(vt_trace_upper_med(:,2)), max(vt_trace_upper_med(:,2))]; %range of x values, upper trace
            xrange_lower = [min(vt_trace_lower_med(:,2)), max(vt_trace_lower_med(:,2))]; %range of x values, lower trace
            desired_length_out = range(vt_trace_upper_med(:,1))*range(vt_trace_lower_med(:,1)); %evaluate at many location
            oversampling_upper = range(xrange_upper)/desired_length_out;
            oversampling_lower = range(xrange_lower)/desired_length_out;
            newx_upper = xrange_upper(1):oversampling_upper:xrange_upper(2);  %x-values at which to evaluate nonlinear regression
            newx_lower = xrange_lower(1):oversampling_lower:xrange_lower(2);  %x-values at which to evaluate nonlinear regression
            newx_mean = round(mean([newx_upper;newx_lower],1));

            spline_upper = interp1(vt_trace_upper_med(:,2),vt_trace_upper_med(:,1),newx_upper, 'spline');
            spline_lower = interp1(vt_trace_lower_med(:,2),vt_trace_lower_med(:,1),newx_lower, 'spline');

            spline_mean = round(mean([spline_upper;spline_lower],1));
            spline_upper = round(spline_upper);
            spline_lower = round(spline_lower);

            %upper splnine
            spline_upper_ind = sub2ind(frame_size,spline_upper, round(newx_upper));  %liner index form
            spline_upper_mat= zeros(frame_size); %empty matrix sized to frame
            spline_upper_mat(spline_upper_ind) =1;             %matrix saving off lowess estimate
            %imshow(spline_upper_mat)

            spline_lower_ind = sub2ind(frame_size,spline_lower, round(newx_lower));  %liner index form
            spline_lower_mat= zeros(frame_size); %empty matrix sized to frame
            spline_lower_mat(spline_lower_ind) =1;             %matrix saving off lowess estimate
            %imshow(spline_lower_mat)
            %imshowpair(spline_upper_mat,spline_lower_mat) %sanity check

            spline_mean_ind = sub2ind(frame_size,spline_mean, round(newx_mean));  %liner index form
            spline_mean_mat= zeros(frame_size); %empty matrix sized to frame
            spline_mean_mat(spline_mean_ind) =1;             %matrix saving off lowess estimate
            %imshowpair(vt_output(:,:,f),spline_mean_mat)
            %imshowpair(frame(:,:,f),spline_mean_mat)
            %imshowpair(frame(:,:,f),spline_upper_mat)
            %imshowpair(frame(:,:,f),spline_lower_mat)


            if draw_connector== "mean_spline"  %option to us the runwise mean
                %check for overreach
                %under some conditions predictions may extend past the bottom of vt
                %walking back from the bottom of the prediction until we hit VT
                checking_bottoms = true; %toggle on
                while checking_bottoms
                    pixel_to_check = spline_mean_ind(end); %walk back from end
                    if vt_output(pixel_to_check + (f-1)*frame_size(1)*frame_size(2)) > 0
                          checking_bottoms = false;

                    else  %remove last pixel as dudd
                        disp(strcat("Removed pixel ", string(pixel_to_check), " from bottom of trace."));
                        spline_mean_ind = spline_mean_ind(spline_mean_ind~=pixel_to_check);

                    end %end if
                end %end while: checking bottoms

                checking_fronts = true; %toggle on
                while checking_fronts
                    pixel_to_check = spline_mean_ind(1); %walk back from end
                    if vt_output(pixel_to_check + (f-1)*frame_size(1)*frame_size(2)) > 0
                          checking_fronts = false;
                    else  %remove last pixel as dudd
                        disp(strcat("Removed pixel ", string(pixel_to_check), "from front of trace."));
                        spline_mean_ind = spline_mean_ind(spline_mean_ind~=pixel_to_check);
                    end %end if
                end %end while: checking fronts


                spline_mean_mat(vt_output(:,:,f)==1) =0; %remove pixels that are already in the image
                vt_output(:,:,f) = vt_output(:,:,f) + spline_mean_mat;
                %imshow(vt_output(:,:,f))
            end %end if mean_spline

            if draw_connector== "upper_spline" %option to us the runwise upper boundary
                checking_bottoms = true; %toggle on
                while checking_bottoms
                    pixel_to_check = spline_upper_ind(end); %walk back from end
                    if vt_output(pixel_to_check + (f-1)*frame_size(1)*frame_size(2)) > 0
                          checking_bottoms = false;

                    else  %remove last pixel as dudd
                        disp(strcat("Removed pixel ", string(pixel_to_check), " from bottom of trace."));
                        spline_upper_ind = spline_upper_ind(spline_upper_ind~=pixel_to_check);
                    end %end if
                end %end while: checking bottoms

                checking_fronts = true; %toggle on
                while checking_fronts
                    pixel_to_check = spline_upper_ind(1); %walk back from end
                    if vt_output(pixel_to_check + (f-1)*frame_size(1)*frame_size(2)) > 0
                          checking_fronts = false;
                    else  %remove last pixel as dudd
                        disp(strcat("Removed pixel ", string(pixel_to_check), "from front of trace."));
                        spline_upper_ind = spline_upper_ind(spline_upper_ind~=pixel_to_check);
                    end %end if
                end %end while: checking fronts

                spline_upper_mat(vt_output(:,:,f)==1) =0; %remove pixels that are already in the image
                vt_output(:,:,f) = vt_output(:,:,f) + spline_upper_mat;
                %imshow(vt_output(:,:,f))
            end

        %%%circle fit method.
        elseif n_compartments >= 2 && draw_connector== "circfit"

            %best fit circle
            vt_output_linear = find(vt_output(:,:,f) >0); %linear index of vt pixels
            [vt_out_y,vt_out_x]  = ind2sub(size(vt_output(:,:,f)), vt_output_linear); %more interpretable x,y index
            [xfit,yfit,Rfit] = circfit(vt_out_x,vt_out_y);

            %pixels along circle
            theta = 0 : 0.01 : 2*pi;
            circle_x = Rfit * cos(theta) + xfit;
            circle_y = Rfit * sin(theta) + yfit;

            %round to nearest pixel coordinates
            circle_y = round(circle_y);
            circle_x = round(circle_x);

            %constrain circle to the frame
            circle_y = circle_y(circle_y<=frame_size(1) & circle_y>0);
            circle_x = circle_x(circle_y<=frame_size(1) & circle_y>0);

            circle_x = circle_x(circle_x<=frame_size(2) & circle_x>0);
            circle_y = circle_y(circle_x<=frame_size(2) & circle_x>0);

            circle_front_x = min(vt_out_x);
            circle_bottom_y = max(vt_out_y);

            circle_ind = sub2ind(frame_size,circle_x,circle_y);  %liner index form
            circle_mat= zeros(frame_size); %empty matrix sized to frame
            circle_mat(circle_ind) =1;             %only circle pixels that are ever vt

            circle_mat = circle_mat .*vt_ever;
            circle_ind = find(circle_mat); %back to linear form for end checking

            circle_mat= zeros(frame_size); %empty matrix sized to frame
            circle_mat(circle_ind) =1;             %matrix saving off lowess estimate

            circle_mat(vt_output(:,:,f)==1) =0; %remove pixels that are already in the image
            vt_output(:,:,f) = vt_output(:,:,f) + circle_mat; %add circle prediction to primary image
        end %end circfit method



        %%%edge_detection method.
        if n_compartments >= 2 && draw_connector== "edges"

            %derive mask

            %edge detection
            edges = edge(this_frame, 'canny');
            edges = edges .* vt_ever; %mask edges to vt
            edges_ind = find(edges);  %liner index form

            checking_bottoms = true; %toggle on
            while checking_bottoms
                pixel_to_check = edges_ind(end); %walk back from end
                if vt_output(pixel_to_check + (f-1)*frame_size(1)*frame_size(2)) > 0
                      checking_bottoms = false;

                else  %remove last pixel as dudd
                    disp(strcat("Removed pixel ", string(pixel_to_check), " from bottom of trace."));
                    edges_ind = edges_ind(edges_ind~=pixel_to_check);

                end %end if
            end %end while: checking bottoms

            checking_fronts = true; %toggle on
            while checking_fronts
                pixel_to_check = edges_ind(1); %walk back from end
                if vt_output(pixel_to_check + (f-1)*frame_size(1)*frame_size(2)) > 0
                      checking_fronts = false;
                else  %remove last pixel as dudd
                    disp(strcat("Removed pixel ", string(pixel_to_check), "from front of trace."));
                    edges_ind = edges_ind(edges_ind~=pixel_to_check);
                end %end if
            end %end while: checking fronts

            edges_mat= zeros(frame_size); %empty matrix sized to frame
            edges_mat(edges_ind) =1;             %matrix saving off lowess estimate

            edges_mat(vt_output(:,:,f)==1) =0; %remove pixels that are already in the image
            vt_output(:,:,f) = vt_output(:,:,f) + edges_mat; %add edge prediction to primary image

        %%%polynomial method.
        elseif n_compartments >= 2 && draw_connector== "polynomial"

            %fit
            vt_output_linear = find(vt_output(:,:,f) >0); %linear index of vt pixels
            [vt_out_y,vt_out_x]  = ind2sub(size(vt_output(:,:,f)), vt_output_linear); %more interpretable x,y index
            poly_fit=polyfit(vt_out_x,vt_out_y, polynomial_degree); %last parameter is degree of polynomial. Consider ramping up. 5?

            %estimate
            oversampling = 1/range(vt_out_y); %predictions close together to avoide gaps where y changes rapidly
                                              %this should give prdict() scope to cover the entire range of possible values
            newx = min(vt_out_x):oversampling:max(vt_out_x);  %x-values at which to evaluate nonlinear regression
                                                              %ovresampled to avoid gaps
            poly_est=polyval(poly_fit, newx);

            poly_x = round(newx); %dig out x values of prediction line. Round to integers because they are indices
            poly_y = round(poly_est); %dig out y values of prediction line  Round to integers because they are indices
            poly_sub2ind =sub2ind(frame_size, poly_y,poly_x); %convenient index format

            %check for overreach
            %under some conditions predictions may extend past the bottom of vt
            %walking back from the bottom of the prediction until we hit VT
            checking_bottoms = true; %toggle on
            while checking_bottoms
                pixel_to_check = poly_sub2ind(end); %walk back from end
                if vt_output(pixel_to_check + (f-1)*frame_size(1)*frame_size(2)) > 0
                      checking_bottoms = false;

                else  %remove last pixel as dudd
                    disp(strcat("Removed pixel ", string(pixel_to_check), " from bottom of trace."));
                    poly_sub2ind = poly_sub2ind(poly_sub2ind~=pixel_to_check);

                end %end if
            end %end while: checking bottoms

            checking_fronts = true; %toggle on
            while checking_fronts
                pixel_to_check = poly_sub2ind(1); %walk back from end
                if vt_output(pixel_to_check + (f-1)*frame_size(1)*frame_size(2)) > 0
                      checking_fronts = false;
                else  %remove last pixel as dudd
                    disp(strcat("Removed pixel ", string(pixel_to_check), "from front of trace."));
                    poly_sub2ind = poly_sub2ind(poly_sub2ind~=pixel_to_check);
                end %end if
            end %end while: checking fronts

            poly_mat= zeros(frame_size); %empty matrix sized to frame
            poly_mat(poly_sub2ind) =1;             %matrix saving off lowess estimate
            poly_mat  = bwmorph(poly_mat, 'bridge'); %bridge small gaps if they exist

            poly_mat(vt_output(:,:,f)==1) =0; %remove pixels that are already in the image
            vt_output(:,:,f) = vt_output(:,:,f) + poly_mat; %add poly prediction to primary image

        %%%lowess method. good but slow
        elseif n_compartments >= 2 && draw_connector== "lowess"  %run only if selected and there are multiple clusters to collect

            vt_output_linear = find(vt_output(:,:,f) >0); %linear index of vt pixels
            [vt_out_y,vt_out_x]  = ind2sub(size(vt_output(:,:,f)), vt_output_linear); %more interpretable x,y index

            %nonlinear regression method for connecting.
            %some commented out parameters in case of need for testing
            %lambda = 0.25; %smoothing parameter 0-1
            %wantplot= 1; %suppress plot with 0
            %imagefile = "lowess_debugging.png";

            oversampling = 1/range(vt_out_y); %predictions close together to avoide gaps where y changes rapidly
                                              %this should give prdict() scope to cover the entire range of possible values
            newx = min(vt_out_x):oversampling:max(vt_out_x);  %x-values at which to evaluate nonlinear regression
                                                              %ovresampled to avoid gaps

            [dataout, lowerLimit, upperLimit, xy]=lowess_custom([vt_out_x,vt_out_y],lambda,wantplot,'lowess.png',newx');

            lowess_x = round(xy(:,1)); %dig out x values of prediction line. Round to integers because they are indices
            lowess_y = round(xy(:,2)); %dig out y values of prediction line  Round to integers because they are indices
            lowess_sub2ind =sub2ind(frame_size, lowess_y,lowess_x); %convenient index format


            %check for overreach
            %under some conditions predictions may extend past the bottom of vt
            %walking back from the bottom of the prediction until we hit VT
            checking_bottoms = true; %toggle on
            while checking_bottoms
                pixel_to_check = lowess_sub2ind(end); %walk back from end
                if vt_output(pixel_to_check + (f-1)*frame_size(1)*frame_size(2)) > 0
                      checking_bottoms = false;

                else  %remove last pixel as dudd
                    disp(strcat("Removed pixel ", string(pixel_to_check), " from bottom of trace."));
                    lowess_sub2ind = lowess_sub2ind(lowess_sub2ind~=pixel_to_check);

                end %end if
            end %end while: checking bottoms

            checking_fronts = true; %toggle on
            while checking_fronts
                pixel_to_check = lowess_sub2ind(1); %walk back from end
                if vt_output(pixel_to_check + (f-1)*frame_size(1)*frame_size(2)) > 0
                      checking_fronts = false;
                else  %remove last pixel as dudd
                    disp(strcat("Removed pixel ", string(pixel_to_check), "from front of trace."));
                    lowess_sub2ind = lowess_sub2ind(lowess_sub2ind~=pixel_to_check);
                end %end if
            end %end while: checking fronts


            lowess_mat= zeros(frame_size); %empty matrix sized to frame
            lowess_mat(lowess_sub2ind) =1;             %matrix saving off lowess estimate
            lowess_mat  = bwmorph(lowess_mat, 'bridge'); %bridge small gaps if they exist

            lowess_mat(vt_output(:,:,f)==1) =0; %remove pixels that are already in the image
            vt_output(:,:,f) = vt_output(:,:,f) + lowess_mat; %add lowess prediction to primary image

        %%%soft link and hard link methods
        %%%slated for deprication
        elseif n_compartments >= 2 && draw_connector=="soft" %if there are two clusters. if fewer no further action needed
          %get posterior-most and dorsal-most coords for both clusters
          ind_1_linear = find(lab_mat==1); %linear index of cluster 1 pixels
          [ind_1_y,ind_1_x]  = ind2sub(size(lab_mat), ind_1_linear); %more interpretable x,y index
          ind_1_anterior = min(ind_1_x); %big values posterior
          ind_1_ventral = max(ind_1_y); %big values ventral

          ind_2_linear = find(lab_mat==2); %linear index of cluster 2 pixels
          [ind_2_y,ind_2_x]  = ind2sub(size(lab_mat), ind_2_linear); %more interpretable x,y index
          ind_2_anterior = min(ind_2_x); %big values posterior
          ind_2_ventral = max(ind_2_y); %big values ventral

          %%%which cluster is the anterior one?
          %As is they are ordered by size which is not particularly useful
          if ind_1_anterior < ind_2_anterior %cluster 1 is anterior

            %back of cluster 1
            posterior_x = max(ind_1_x); %back
            posterior_y = min(ind_1_y(ind_1_x == posterior_x)); %which of back-most pizels is most ventral

            %top of cluster 2
            dorsal_y = min(ind_2_y); %top
            dorsal_x = min(ind_2_x(ind_2_y == dorsal_y)); %which of top-most is front
          end %endif cluster 1 is anterior

          if ind_1_anterior > ind_2_anterior
            %back of cluster 2
            posterior_x = max(ind_2_x); %back
            posterior_y = min(ind_2_y(ind_2_x == posterior_x)); %which of back-most pizels is most ventral

            %top of cluster 1
            dorsal_y = min(ind_1_y); %top
            dorsal_x = min(ind_1_x(ind_1_y == dorsal_y)); %which of top-most is front
          end %endif cluster 2 is anterior

          link_x = dorsal_x;
          link_y = dorsal_y;

          %hardlink
          %if link_x ~= posterior_x || link_y ~= posterior_y %check if 2 cavities already connected
        elseif n_compartments >= 2 && draw_connector == "hard"
              %hardlink line x
              hardlink_x = sort([posterior_x link_x]); %matlab doesn't like descending sequences
              hardlink_line_x = hardlink_x(1):hardlink_x(2);
              hardlink_x_len = length(hardlink_line_x);

              %hardlink line y
              hardlink_y = sort([posterior_y link_y]); %matlab doesn't like descending sequences
              hardlink_line_y = hardlink_y(1):hardlink_y(2);
              hardlink_y_len = length(hardlink_line_y);

              %upsample x if it is shorter
              if hardlink_x_len < hardlink_y_len %if x is shorter, upsample it
                hardlink_x_increment = abs(posterior_x-link_x)/(hardlink_y_len-1);
                hardlink_line_x = hardlink_x(1):hardlink_x_increment:hardlink_x(2);
                hardlink_line_x = round(hardlink_line_x);

                if hardlink_x_increment == 0; hardlink_line_x = repmat(posterior_x,1,hardlink_y_len); end %special case

              end %end upsample

              %upsample y if it is shorter
              if hardlink_y_len < hardlink_x_len %if x is shorter, upsample it
                hardlink_y_increment = abs(posterior_y-link_y)/(hardlink_x_len-1);
                hardlink_line_y = hardlink_y(1):hardlink_y_increment:hardlink_y(2);
                hardlink_line_y = round(hardlink_line_y);

                if hardlink_y_increment == 0; hardlink_line_y = repmat(posterior_y,1,hardlink_x_len); end %special case

              end %end upsample

               %add hardlink to mask
               hardlink_mat = zeros(size(lab_mat));
               hardlink_mat(sub2ind(size(hardlink_mat), hardlink_line_y,hardlink_line_x)) =1;
               hardlink_mat(vt_output(:,:,f)==1) =0; %remove pixels that are already in the image

               vt_output(:,:,f) = vt_output(:,:,f) + hardlink_mat;  %CHECK THIS

               %%%soflink v2
        elseif draw_connector == "soft"

                soft_link = vt_skel; %base link between covaities on typical vocal tract trajectory
                soft_link(1:posterior_x,:) = 0; %keep only pixels behind the anterior cavity
                soft_link(:,dorsal_y:end) = 0;  %keep only pixels below the dorsal cavity

                vt_output(:,:,f) = vt_output(:,:,f) + soft_link; %add soft line to vocal tract
                vt_output(:,:,f) = vt_output(:,:,f)>0; %just in case there was some overlap


                %imshow(vt_output(:,:,f)) %look see
        end %end draw connectons

        %%%%%%%%%%%
        %%%TRACE%%%
        %%%%%%%%%%%
        %find anterior corner of bottom of vocal tract

        [top, ~] = morpho.tracing.find_endpoints(vt_output(:,:,f) > 0);
        [trace_x_coords, trace_y_coords, trace_mat] = morpho.tracing.trace_boundary(vt_output(:,:,f) > 0, top);
        vt_trace_result = [trace_y_coords, trace_x_coords]; % for compatibility

        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %%%Suspiciously few pixels?%%% manually fix a frequent problem
        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%% even hardlink sometimes fails

        if manual_check %switch for turning this part off
            pixel_count = sum(sum(trace_mat));
           if pixel_count < suspicion_threshold
              do_edit='y';
              while do_edit == 'y' || do_edit =='Y'

                  disp("ADD/REMOVE pixels to build contiguous outline. D=Draw, E=Erase, Q=Done.")

                  vt_mask = vt_output(:,:,f) > 0;

                  editor = morpho.Editor(vt_mask, ...
                      background=this_frame, ...
                      overlay_color="green", ...
                      modes="DE", ...
                      brush_size=0, ...
                      filename=input_rootname);
                  vt_mask = editor.run();

                  %%%redo trace
                  [top_edited, ~] = morpho.tracing.find_endpoints(vt_mask);
                  [tx_edited, ty_edited, trace_mat_edited] = morpho.tracing.trace_boundary(vt_mask, top_edited);
                  vt_trace_edited = [ty_edited, tx_edited];

                  % Show result for evaluation
                  scaling_factor_local = max(max(this_frame))*1.5;
                  imshowpair(this_frame/scaling_factor_local+vt_mask, trace_mat_edited)

                  do_edit=input('would you like a redo? (y/n)', 's');
                  if isempty(do_edit); do_edit = 'y'; end
              end %end do_edit while
              trace_mat = trace_mat_edited;
              vt_trace_result = vt_trace_edited;

              %%%take notes in case a frame is unfixably bad
              take_note=input('Note this frame down as a failure to revisit? (y/n)', 's');
              if isempty(take_note); take_note = 'y'; end
              if take_note == 'y' || take_note == 'Y'
                  note=strcat(input_rootname, "_Frame_",int2str(f));
                  fid = fopen(fullfile(output_trace_dir, "failed_traces.txt"), 'a+');
                    fprintf(fid, '%s \n', note);
                  fclose(fid);
              end

           end %end suspsicion check
        end %end manual check switch

        %%%back to your regularly scheduled programming

        %write to file
        %rows = frames, columns = pixels
        %rows are likely to have different numbers of columns as the vocal
        %tract changes size
        X = vt_trace_result(:,2);
        Y = vt_trace_result(:,1);

        dlmwrite(fullfile(output_trace_dir, strcat(input_rootname,'_X.csv')),X', 'delimiter',',','-append') %save by appending
        dlmwrite(fullfile(output_trace_dir, strcat(input_rootname,'_Y.csv')),Y', 'delimiter',',','-append') %save by appending

        %get coordinates for the vocal tract endpoints
        %get posterior-most and dorsal-most coords for both clusters

        vt_bottom_y =  max(vt_trace_result(:,1)); %bottom most Y
        vt_bottom_x = mean(vt_trace_result(vt_trace_result(:,1)==vt_bottom_y ,2));  %X at bottom most Y

        vt_top_x =  min(vt_trace_result(:,2)); %front most X
        vt_top_y = mean(vt_trace_result(vt_trace_result(:,2)==vt_top_x ,1));  %Y at frontmost most X

        dlmwrite(fullfile(output_endpoints_dir, strcat(input_rootname,'_vt_bottom.csv')),[f,vt_bottom_y vt_bottom_x] , 'delimiter',',','-append') %save by appending
        dlmwrite(fullfile(output_endpoints_dir, strcat(input_rootname,'_vt_top.csv')),[f,vt_top_y vt_top_x], 'delimiter',',','-append') %save by appending

        %also fill out big 3d matrix
        trace_outline(:,:,f) = trace_mat;

        % Normalize frame to uint8
        I = this_frame;
        I = I / max(I(:) + eps);
        I = im2uint8(I);

        % RGB base
        rgb = repmat(I,[1 1 3]);

        % Overlay trace in red
        mask = uint8(trace_mat) * 255;
        rgb(:,:,1) = max(rgb(:,:,1), mask);

        writeVideo(writerObj, rgb);


    end %end frame loop
    close(writerObj); %close video file,writing done
    save(char(fullfile(output_trace_mat_dir,string(input_rootname)+'_outline.mat')),'trace_outline'); %save outline for later diagnostics

end %end run loop
close
