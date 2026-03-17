% +morpho/display.m
classdef display
    methods (Static)

        function ink = mode_to_ink(draw_mode)
            if upper(draw_mode) == 'E'
                ink = 0;
            else
                ink = 1;
            end
        end

        function [x_brush, y_brush] = expand_brush(x, y, brush_size, mask_size)
            x = round(double(x));
            y = round(double(y));
            x_brush = max(1, x - brush_size) : min(mask_size(2), x + brush_size);
            y_brush = max(1, y - brush_size) : min(mask_size(1), y + brush_size);
        end

        function [draw_mode, brush_size, ink, varargout] = settings_dialog(draw_mode, brush_size, mask_size, opts)
            arguments
                draw_mode
                brush_size
                mask_size
                opts.modes string = "DE"
                opts.show_context_frame logical = false
                opts.show_opacity logical = false
                opts.no_frames (1,1) double = 1
                opts.context_frame (1,1) double = 1
                opts.mask_opacity (1,1) double = 0.5
            end

            prompt = {};
            definput = {};

            if contains(opts.modes, "R")
                prompt{end+1} = 'Enter [R] to redraw, [E] to Erase:';
            else
                prompt{end+1} = 'Enter [D] to draw, [E] to Erase:';
            end
            definput{end+1} = draw_mode;

            prompt{end+1} = 'Brush size (pixels):';
            definput{end+1} = int2str(brush_size);

            context_frame = opts.context_frame;
            mask_opacity = opts.mask_opacity;

            if opts.show_context_frame
                prompt{end+1} = sprintf('Context frame (1-%d):', opts.no_frames);
                definput{end+1} = int2str(context_frame);
            end

            if opts.show_opacity
                prompt{end+1} = 'Mask opacity (0 to 1):';
                definput{end+1} = num2str(mask_opacity);
            end

            draw_settings = inputdlg(prompt, 'Settings', [1 40], definput);

            if isempty(draw_settings)
                ink = morpho.display.mode_to_ink(draw_mode);
                if opts.show_context_frame, varargout{1} = context_frame; end
                if opts.show_opacity
                    varargout{1 + opts.show_context_frame} = mask_opacity;
                end
                return;
            end

            fi = 1;
            new_mode = upper(draw_settings{fi});
            if contains(opts.modes, new_mode)
                draw_mode = new_mode;
            else
                draw_mode = char(extract(opts.modes, 1));
                disp("Invalid mode. Defaulting to " + draw_mode);
            end
            ink = morpho.display.mode_to_ink(draw_mode);

            fi = 2;
            new_brush = str2double(draw_settings{fi});
            if ~isnan(new_brush)
                brush_size = round(new_brush);
            end
            brush_size = max(0, brush_size);
            max_brush = floor(min(mask_size) / 4);
            if brush_size > max_brush
                brush_size = max_brush;
                disp("Brush size clamped to " + int2str(brush_size));
            end

            fi = 3;
            if opts.show_context_frame
                new_cf = str2double(draw_settings{fi});
                if ~isnan(new_cf)
                    context_frame = max(1, min(opts.no_frames, round(new_cf)));
                end
                varargout{1} = context_frame;
                fi = fi + 1;
            end

            if opts.show_opacity
                new_op = str2double(draw_settings{fi});
                if ~isnan(new_op)
                    mask_opacity = max(0, min(1, new_op));
                end
                varargout{1 + opts.show_context_frame} = mask_opacity;
            end

            disp("Mode=" + draw_mode + " Brush=" + int2str(brush_size) + "px");
        end

        function show_pair(frame, overlay, opts)
            arguments
                frame
                overlay
                opts.scaling_factor (1,1) double = 1
                opts.position (1,4) double = [0.5, 0, 0.5, 1]
            end
            imshowpair(frame / opts.scaling_factor, overlay);
            set(gcf, 'Units', 'Normalized', 'OuterPosition', opts.position);
        end

        function [hBase, hOverlay] = init_mask_overlay(ax, frame2d, mask2d, mask_opacity, overlay_rgb)
            arguments
                ax
                frame2d
                mask2d
                mask_opacity (1,1) double = 0.45
                overlay_rgb = []
            end
            frame2d = single(frame2d);
            frame2d = frame2d - min(frame2d(:));
            frame2d = frame2d ./ max(frame2d(:) + eps);

            cla(ax);
            hold(ax, 'on');
            hBase = imshow(frame2d, 'Parent', ax);

            if isempty(overlay_rgb)
                overlay_rgb = cat(3, ones(size(mask2d)), zeros(size(mask2d)), zeros(size(mask2d)));
            end
            hOverlay = imshow(overlay_rgb, 'Parent', ax);
            hOverlay.AlphaData = double(mask2d > 0) * mask_opacity;

            hold(ax, 'off');
            axis(ax, 'image');
        end

        function update_mask_overlay(hBase, hOverlay, frame2d, mask2d, mask_opacity)
            frame2d = single(frame2d);
            frame2d = frame2d - min(frame2d(:));
            frame2d = frame2d ./ max(frame2d(:) + eps);

            hBase.CData = frame2d;
            hOverlay.AlphaData = double(mask2d > 0) * mask_opacity;
        end

        function fig = create_editor_figure(title_str)
            mp = get(0, 'MonitorPositions');
            mp = mp(1,:);
            pad = 40;
            fig_pos = [mp(1)+pad, mp(2)+pad, mp(3)-2*pad, mp(4)-2*pad];
            fig = figure('Name', title_str, ...
                         'NumberTitle', 'off', ...
                         'Units', 'pixels', ...
                         'Position', fig_pos);
        end

        function rgb = overlay_color_to_rgb(color_name, sz)
            arguments
                color_name string
                sz (1,2) double
            end
            switch lower(color_name)
                case "red"
                    rgb = cat(3, ones(sz), zeros(sz), zeros(sz));
                case "pink"
                    rgb = cat(3, ones(sz), zeros(sz), ones(sz)/2);
                case "green"
                    rgb = cat(3, zeros(sz), ones(sz), zeros(sz));
                otherwise
                    rgb = cat(3, ones(sz), zeros(sz), zeros(sz));
            end
        end

    end
end
