% +morpho/Editor.m
classdef Editor < handle

    properties
        mask                        % H x W working mask
        background                  % H x W background image
        original                    % H x W original (for restore)

        overlay_color   string  = "red"
        modes           string  = "DE"
        brush_size      double  = 10
        draw_mode       char    = 'D'
        overlay_opacity double  = 0.45

        show_opacity_control  logical = false
        show_context_frame    logical = false
        allow_line_draw       logical = false
        allow_frame_nav       logical = false

        frame_source    string  = ""
        frame_indices   double  = []
        current_frame   double  = 1
        no_frames       double  = 1
        max_undo        double  = 20
    end

    properties (Access = private)
        fig
        ax
        hBase
        hOverlay
        overlay_rgb

        undo_stack      cell
        undo_pos        double  = 0
        undo_count      double  = 0

        done            logical = false
        ink             double  = 1
        mask_size       double
        exit_box_size   double
        settings_box_size double
    end

    methods
        function obj = Editor(mask, opts)
            arguments
                mask
                opts.background = []
                opts.original = []
                opts.overlay_color string = "red"
                opts.modes string = "DE"
                opts.brush_size double = 10
                opts.draw_mode char = 'D'
                opts.overlay_opacity double = 0.45
                opts.show_opacity_control logical = false
                opts.show_context_frame logical = false
                opts.allow_line_draw logical = false
                opts.allow_frame_nav logical = false
                opts.frame_source string = ""
                opts.frame_indices double = []
                opts.current_frame double = 1
                opts.max_undo double = 20
            end

            obj.mask = mask;
            obj.mask_size = size(mask);
            obj.original = opts.original;
            if isempty(obj.original)
                obj.original = mask;
            end

            obj.background = opts.background;
            if isempty(obj.background)
                obj.background = zeros(obj.mask_size, 'single');
            end

            obj.overlay_color = opts.overlay_color;
            obj.modes = opts.modes;
            obj.brush_size = opts.brush_size;
            obj.draw_mode = opts.draw_mode;
            obj.ink = morpho.display.mode_to_ink(obj.draw_mode);
            obj.overlay_opacity = opts.overlay_opacity;
            obj.show_opacity_control = opts.show_opacity_control;
            obj.show_context_frame = opts.show_context_frame;
            obj.allow_line_draw = opts.allow_line_draw;
            obj.allow_frame_nav = opts.allow_frame_nav;
            obj.frame_source = opts.frame_source;
            obj.frame_indices = opts.frame_indices;
            obj.current_frame = opts.current_frame;
            obj.max_undo = opts.max_undo;

            if ~isempty(opts.frame_indices)
                obj.no_frames = numel(opts.frame_indices);
            end

            obj.undo_stack = cell(1, obj.max_undo);
        end

        function result = run(obj)
            obj.init_figure();
            obj.push_undo();

            while ~obj.done
                obj.redraw();

                try
                    [x, y] = ginput(1);
                catch
                    break;
                end

                if isempty(x), break; end

                x = round(double(x));
                y = round(double(y));
                obj.handle_click(x, y);
            end

            result = obj.mask;
            obj.cleanup_boxes();

            if ishghandle(obj.fig)
                close(obj.fig);
            end
        end
    end

    methods (Access = private)

        function init_figure(obj)
            obj.exit_box_size = round(min(obj.mask_size) / 20);
            obj.settings_box_size = obj.exit_box_size;

            obj.mask(1:obj.exit_box_size, end-obj.exit_box_size:end) = 1;
            obj.mask(1:obj.settings_box_size, 1:obj.settings_box_size) = 1;

            obj.fig = morpho.display.create_editor_figure('Editor');
            obj.ax = axes('Parent', obj.fig, 'Position', [0 0 1 1]);

            set(obj.fig, 'KeyPressFcn', @(~,evt) obj.handle_key(evt));

            obj.overlay_rgb = morpho.display.overlay_color_to_rgb( ...
                obj.overlay_color, obj.mask_size);

            [obj.hBase, obj.hOverlay] = morpho.display.init_mask_overlay( ...
                obj.ax, obj.background, obj.mask, obj.overlay_opacity, obj.overlay_rgb);

            obj.update_status();
        end

        function handle_key(obj, evt)
            key = upper(evt.Key);

            % Check for Ctrl+Z
            if strcmp(key, 'Z') && ~isempty(evt.Modifier) && any(strcmp(evt.Modifier, 'control'))
                obj.pop_undo();
                obj.redraw();
                return;
            end

            switch key
                case 'S'
                    obj.open_settings();
                case 'U'
                    obj.pop_undo();
                case 'D'
                    if contains(obj.modes, 'D')
                        obj.draw_mode = 'D';
                        obj.ink = 1;
                    end
                case 'E'
                    obj.draw_mode = 'E';
                    obj.ink = 0;
                case 'R'
                    if obj.allow_frame_nav
                        obj.restore_frame();
                    elseif contains(obj.modes, 'R')
                        obj.draw_mode = 'R';
                        obj.ink = 1;
                    end
                case 'Q'
                    obj.done = true;
                case 'N'
                    if obj.allow_frame_nav
                        obj.next_frame();
                    end
                case 'B'
                    if obj.allow_frame_nav
                        obj.prev_frame();
                    end
            end
            obj.update_status();
            obj.redraw();
        end

        function handle_click(obj, x, y)
            bs = obj.exit_box_size;
            ss = obj.settings_box_size;

            % Exit box (top-right)
            if x > obj.mask_size(2) - bs && y <= bs
                obj.done = true;
                return;
            end

            % Settings box (top-left)
            if x <= ss && y <= ss
                obj.open_settings();
                return;
            end

            obj.push_undo();

            if obj.allow_line_draw && obj.draw_mode == 'D'
                obj.draw_line(x, y);
            elseif contains(obj.modes, 'R') && obj.draw_mode == 'R'
                [xb, yb] = morpho.display.expand_brush(x, y, obj.brush_size, obj.mask_size);
                obj.mask(yb, xb) = obj.original(yb, xb) * obj.ink;
            else
                [xb, yb] = morpho.display.expand_brush(x, y, obj.brush_size, obj.mask_size);
                obj.mask(yb, xb) = obj.ink;
            end
        end

        function draw_line(obj, x1, y1)
            obj.redraw();
            try
                [x2, y2] = ginput(1);
            catch
                return;
            end
            if isempty(x2), return; end
            x2 = round(double(x2));
            y2 = round(double(y2));

            n = max(abs(x2 - x1), abs(y2 - y1)) * 2;
            n = max(n, 2);
            draw_x = round(linspace(x1, x2, n));
            draw_y = round(linspace(y1, y2, n));
            draw_x = max(1, min(obj.mask_size(2), draw_x));
            draw_y = max(1, min(obj.mask_size(1), draw_y));
            idx = sub2ind(obj.mask_size, draw_y, draw_x);
            obj.mask(idx) = obj.ink;
        end

        function open_settings(obj)
            if obj.show_context_frame && obj.show_opacity_control
                [obj.draw_mode, obj.brush_size, obj.ink, cf, op] = ...
                    morpho.display.settings_dialog( ...
                        obj.draw_mode, obj.brush_size, obj.mask_size, ...
                        modes=obj.modes, ...
                        show_context_frame=true, show_opacity=true, ...
                        no_frames=obj.no_frames, ...
                        context_frame=obj.current_frame, ...
                        mask_opacity=obj.overlay_opacity);
                obj.current_frame = cf;
                obj.overlay_opacity = op;
                obj.load_context_frame();

            elseif obj.show_context_frame
                [obj.draw_mode, obj.brush_size, obj.ink, cf] = ...
                    morpho.display.settings_dialog( ...
                        obj.draw_mode, obj.brush_size, obj.mask_size, ...
                        modes=obj.modes, ...
                        show_context_frame=true, ...
                        no_frames=obj.no_frames, ...
                        context_frame=obj.current_frame);
                obj.current_frame = cf;
                obj.load_context_frame();

            elseif obj.show_opacity_control
                [obj.draw_mode, obj.brush_size, obj.ink, op] = ...
                    morpho.display.settings_dialog( ...
                        obj.draw_mode, obj.brush_size, obj.mask_size, ...
                        modes=obj.modes, ...
                        show_opacity=true, ...
                        mask_opacity=obj.overlay_opacity);
                obj.overlay_opacity = op;

            else
                [obj.draw_mode, obj.brush_size, obj.ink] = ...
                    morpho.display.settings_dialog( ...
                        obj.draw_mode, obj.brush_size, obj.mask_size, ...
                        modes=obj.modes);
            end

            obj.update_status();
        end

        function load_context_frame(obj)
            if obj.frame_source ~= "" && ~isempty(obj.frame_indices)
                frame_num = obj.frame_indices( ...
                    min(obj.current_frame, numel(obj.frame_indices)));
                obj.background = morpho.video.read_single(obj.frame_source, frame_num);
            end
        end

        function push_undo(obj)
            obj.undo_pos = obj.undo_pos + 1;
            idx = mod(obj.undo_pos - 1, obj.max_undo) + 1;
            obj.undo_stack{idx} = obj.mask;
            obj.undo_count = min(obj.undo_count + 1, obj.max_undo);
        end

        function pop_undo(obj)
            if obj.undo_count <= 1, return; end
            obj.undo_pos = obj.undo_pos - 1;
            obj.undo_count = obj.undo_count - 1;
            idx = mod(obj.undo_pos - 1, obj.max_undo) + 1;
            obj.mask = obj.undo_stack{idx};
        end

        function redraw(obj)
            morpho.display.update_mask_overlay( ...
                obj.hBase, obj.hOverlay, ...
                obj.background, obj.mask, obj.overlay_opacity);
            obj.update_status();
            drawnow;
        end

        function update_status(obj)
            parts = {};
            parts{end+1} = 'S=Settings';
            parts{end+1} = sprintf('U=Undo(%d)', max(0, obj.undo_count - 1));

            if contains(obj.modes, 'D')
                parts{end+1} = 'D=Draw';
            end
            if contains(obj.modes, 'R') && ~obj.allow_frame_nav
                parts{end+1} = 'R=Redraw';
            end
            parts{end+1} = 'E=Erase';
            parts{end+1} = 'Q=Quit';

            if obj.allow_frame_nav
                parts{end+1} = 'N=Next';
                parts{end+1} = 'B=Back';
                parts{end+1} = 'R=Restore';
            end

            parts{end+1} = sprintf('Mode:%s', obj.draw_mode);
            parts{end+1} = sprintf('Brush:%d', obj.brush_size);

            if obj.show_opacity_control
                parts{end+1} = sprintf('Opacity:%.2f', obj.overlay_opacity);
            end

            if obj.show_context_frame || obj.allow_frame_nav
                parts{end+1} = sprintf('Frame:%d/%d', obj.current_frame, obj.no_frames);
            end

            status = strjoin(parts, ' | ');
            title(obj.ax, status, 'FontSize', 10, 'FontName', 'FixedWidth');
        end

        function cleanup_boxes(obj)
            bs = obj.exit_box_size;
            ss = obj.settings_box_size;
            obj.mask(1:bs, end-bs:end) = 0;
            obj.mask(1:ss, 1:ss) = 0;
        end

        function next_frame(obj)
            if obj.current_frame < obj.no_frames
                obj.current_frame = obj.current_frame + 1;
                obj.load_context_frame();
                obj.undo_stack = cell(1, obj.max_undo);
                obj.undo_pos = 0;
                obj.undo_count = 0;
                obj.push_undo();
            end
        end

        function prev_frame(obj)
            if obj.current_frame > 1
                obj.current_frame = obj.current_frame - 1;
                obj.load_context_frame();
                obj.undo_stack = cell(1, obj.max_undo);
                obj.undo_pos = 0;
                obj.undo_count = 0;
                obj.push_undo();
            end
        end

        function restore_frame(obj)
            obj.push_undo();
            obj.mask = obj.original;
        end
    end
end
