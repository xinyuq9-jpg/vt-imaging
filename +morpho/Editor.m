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

        filename        string  = ""
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
        hHelp
        hInfo
        hTitle
        overlay_rgb
        bg_normalized
        info_y_cached double = NaN

        undo_stack      cell
        undo_pos        double  = 0
        undo_count      double  = 0

        done            logical = false
        ink             double  = 1
        mask_size       double
        exit_box_size   double
        settings_box_size double
        status_dirty    logical = true
        bg_dirty        logical = true
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
                opts.filename string = ""
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
            obj.filename = opts.filename;
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
            obj.normalize_background();
            obj.redraw();

            while ~obj.done
                try
                    w = waitforbuttonpress;
                catch
                    break;
                end

                if w == 0
                    % Mouse click
                    cp = get(obj.ax, 'CurrentPoint');
                    x = round(cp(1,1));
                    y = round(cp(1,2));
                    obj.handle_click(x, y);
                else
                    % Key press
                    key = get(obj.fig, 'CurrentCharacter');
                    if ~isempty(key)
                        obj.handle_key_char(upper(key));
                    end
                end

                obj.redraw();
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
            set(obj.fig, 'Pointer', 'crosshair');
            obj.ax = axes('Parent', obj.fig, 'Position', [0 0 1 1]);

            obj.overlay_rgb = morpho.display.overlay_color_to_rgb( ...
                obj.overlay_color, obj.mask_size);

            [obj.hBase, obj.hOverlay] = morpho.display.init_mask_overlay( ...
                obj.ax, obj.background, obj.mask, obj.overlay_opacity, obj.overlay_rgb);

            obj.init_help_text();
            obj.init_info_text();
            obj.update_status();
        end

        function handle_key_char(obj, key)
            obj.status_dirty = true;
            switch key
                case 'S'
                    obj.open_settings();
                case {'U', char(26)}  % U or Ctrl+Z (ASCII 26)
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
                w = waitforbuttonpress;
            catch
                return;
            end
            if w ~= 0, return; end  % ignore key presses
            cp = get(obj.ax, 'CurrentPoint');
            x2 = round(cp(1,1));
            y2 = round(cp(1,2));

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

            obj.status_dirty = true;
        end

        function load_context_frame(obj)
            if obj.frame_source ~= "" && ~isempty(obj.frame_indices)
                frame_num = obj.frame_indices( ...
                    min(obj.current_frame, numel(obj.frame_indices)));
                obj.background = morpho.video.read_single(obj.frame_source, frame_num);
                obj.normalize_background();
            end
        end

        function push_undo(obj)
            obj.undo_pos = obj.undo_pos + 1;
            idx = mod(obj.undo_pos - 1, obj.max_undo) + 1;
            obj.undo_stack{idx} = obj.mask;
            obj.undo_count = min(obj.undo_count + 1, obj.max_undo);
        end

        function pop_undo(obj)
            if obj.undo_count < 1, return; end
            idx = mod(obj.undo_pos - 1, obj.max_undo) + 1;
            obj.mask = obj.undo_stack{idx};
            obj.undo_pos = obj.undo_pos - 1;
            obj.undo_count = obj.undo_count - 1;
        end

        function redraw(obj)
            if obj.bg_dirty
                obj.hBase.CData = obj.bg_normalized;
                obj.bg_dirty = false;
            end

            obj.hOverlay.AlphaData = single(obj.mask) * obj.overlay_opacity;

            if obj.status_dirty
                obj.update_status();
                obj.status_dirty = false;
            end

            drawnow limitrate;
        end

        function normalize_background(obj)
            bg = single(obj.background);
            bg = bg - min(bg(:));
            bg = bg ./ max(bg(:) + eps);
            obj.bg_normalized = bg;
            obj.bg_dirty = true;
        end

        function init_help_text(obj)
            help_lines = {};

            if contains(obj.modes, 'D')
                help_lines{end+1} = 'D = Draw';
            end
            help_lines{end+1} = 'E = Erase';
            if contains(obj.modes, 'R') && ~obj.allow_frame_nav
                help_lines{end+1} = 'R = Redraw';
            end
            help_lines{end+1} = 'S = Settings';
            help_lines{end+1} = 'U = Undo  (Ctrl+Z)';
            help_lines{end+1} = 'Q = Quit';

            if obj.allow_frame_nav
                help_lines{end+1} = 'N = Next frame';
                help_lines{end+1} = 'B = Back frame';
                help_lines{end+1} = 'R = Restore';
            end

            help_str = strjoin(help_lines, newline);

            obj.hHelp = text(obj.ax, 5, 100, help_str, ...
                'Units', 'pixels', ...
                'VerticalAlignment', 'top', ...
                'HorizontalAlignment', 'left', ...
                'FontSize', 9, 'FontName', 'FixedWidth', ...
                'Color', [1 1 1], ...
                'BackgroundColor', [0 0 0 0.5], ...
                'Margin', 4, ...
                'EdgeColor', 'none');
        end

        function init_info_text(obj)
            obj.hInfo = text(obj.ax, 5, 0, '', ...
                'Units', 'pixels', ...
                'VerticalAlignment', 'top', ...
                'HorizontalAlignment', 'left', ...
                'FontSize', 9, 'FontName', 'FixedWidth', ...
                'Color', [1 1 0.6], ...
                'BackgroundColor', [0 0 0 0.5], ...
                'Margin', 4, ...
                'EdgeColor', 'none');

            obj.hTitle = title(obj.ax, '', 'FontSize', 10, 'FontName', 'FixedWidth');
        end

        function update_status(obj)
            % Info text under help: filename + frame
            if obj.filename ~= "" || obj.show_context_frame || obj.allow_frame_nav
                info_parts = {};
                if obj.filename ~= ""
                    [~, name, ~] = fileparts(obj.filename);
                    info_parts{end+1} = char(name);
                end
                if obj.show_context_frame || obj.allow_frame_nav
                    info_parts{end+1} = sprintf('Frame %d/%d', obj.current_frame, obj.no_frames);
                end

                % Cache the y-position once (Extent query is expensive)
                if isnan(obj.info_y_cached)
                    drawnow;  % ensure Extent is valid
                    help_ext = get(obj.hHelp, 'Extent');
                    obj.info_y_cached = help_ext(2) - 4;
                    obj.hInfo.Position = [5, obj.info_y_cached, 0];
                end

                obj.hInfo.String = strjoin(info_parts, '  |  ');
            end

            % Title bar: mode, brush, opacity, undo
            obj.hTitle.String = sprintf('Mode: %s  |  Brush: %d%s  |  Undo: %d', ...
                obj.draw_mode, obj.brush_size, ...
                obj.opacity_str(), ...
                max(0, obj.undo_count));
        end

        function s = opacity_str(obj)
            if obj.show_opacity_control
                s = sprintf('  |  Opacity: %.2f', obj.overlay_opacity);
            else
                s = '';
            end
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
