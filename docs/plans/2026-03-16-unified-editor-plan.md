# Unified Editor — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a single `morpho.Editor` class that replaces all interactive mask/trace editing across Morpho1, 3, 4, 5 with keyboard shortcuts, undo stack, and configurable features per stage.

**Architecture:** `morpho.Editor` is a `handle` class using `figure` + `ginput` + `KeyPressFcn`. `morpho.display` holds static helper functions. Each Morpho script creates an Editor with stage-specific options and calls `editor.run()`.

**Tech Stack:** MATLAB R2025a. `handle` class, `arguments` blocks, `KeyPressFcn` callback, `ginput`, `imshow`.

**Design doc:** `docs/plans/2026-03-16-unified-editor-design.md`

---

## Task 1: Create `+morpho/display.m` — Static Display Helpers

**Files:**
- Create: `+morpho/display.m`

**Step 1: Write the display class**

```matlab
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
```

**Step 2: Verify in MATLAB**

```matlab
assert(morpho.display.mode_to_ink('D') == 1);
assert(morpho.display.mode_to_ink('E') == 0);
assert(morpho.display.mode_to_ink('R') == 1);

[xb, yb] = morpho.display.expand_brush(5, 5, 2, [10 10]);
assert(isequal(xb, 3:7));

rgb = morpho.display.overlay_color_to_rgb("pink", [100 100]);
assert(size(rgb, 3) == 3);
```

**Step 3: Commit**

```bash
git add +morpho/display.m
git commit -m "feat: add morpho.display with static UI helpers and overlay utilities"
```

---

## Task 2: Create `+morpho/Editor.m` — Core Editor Class

**Files:**
- Create: `+morpho/Editor.m`

**Step 1: Write the Editor class**

```matlab
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
```

**Step 2: Verify in MATLAB**

```matlab
% Test construction
test_mask = false(50, 50);
test_mask(10:40, 10:40) = true;
bg = single(rand(50, 50));

editor = morpho.Editor(test_mask, ...
    background=bg, ...
    overlay_color="red", ...
    modes="DE", ...
    brush_size=5);

assert(editor.brush_size == 5);
assert(editor.draw_mode == 'D');
assert(editor.max_undo == 20);
assert(isequal(editor.mask_size, [50 50]));
```

**Step 3: Interactive test**

```matlab
% Run the editor on a test mask — verify:
% - Figure opens maximized with red overlay
% - Status bar shows shortcuts
% - Clicking draws/erases
% - S key opens settings dialog
% - U key undoes last stroke
% - Ctrl+Z undoes last stroke
% - D/E keys toggle mode
% - Q key exits
% - Top-left box opens settings
% - Top-right box exits
% - Returned mask has boxes removed

test_mask = false(100, 100);
test_mask(20:80, 20:80) = true;
bg = single(rand(100, 100) * 255);

editor = morpho.Editor(test_mask, background=bg, overlay_color="red", modes="DE");
result = editor.run();
assert(result(1,1) == 0);  % corner boxes cleaned up
```

**Step 4: Commit**

```bash
git add +morpho/Editor.m
git commit -m "feat: add morpho.Editor — unified interactive mask/trace editor with undo"
```

---

## Task 3: Test Editor with Pink Overlay + Redraw Mode (Morpho3 config)

**Files:** None (testing only)

**Step 1: Test Morpho3-style configuration**

```matlab
test_mask = rand(100, 100);  % frequency map (not binary)
test_original = test_mask;
bg = single(rand(100, 100) * 255);

editor = morpho.Editor(test_mask, ...
    background=bg, ...
    original=test_original, ...
    overlay_color="pink", ...
    modes="RE", ...
    show_opacity_control=true, ...
    show_context_frame=true, ...
    brush_size=10, ...
    draw_mode='E', ...
    no_frames=100, ...
    current_frame=50);

result = editor.run();
```

Verify:
- Pink overlay displayed
- Status bar shows `R=Redraw | E=Erase` (not `D=Draw`)
- R key switches to redraw mode
- Clicking in redraw mode restores original values
- Opacity control appears in settings dialog
- Context frame control appears in settings dialog

**Step 2: Document any issues found and fix**

---

## Task 4: Test Editor with Line Draw + Frame Nav (Morpho5 config)

**Files:** None (testing only)

**Step 1: Test Morpho5-style configuration**

```matlab
test_trace = false(100, 100);
test_trace(50, 20:80) = true;  % horizontal line
bg = single(rand(100, 100) * 255);

editor = morpho.Editor(test_trace, ...
    background=bg, ...
    original=test_trace, ...
    overlay_color="green", ...
    modes="DE", ...
    allow_line_draw=true, ...
    allow_frame_nav=true, ...
    brush_size=3, ...
    draw_mode='D', ...
    frame_indices=1:50, ...
    current_frame=1);

result = editor.run();
```

Verify:
- Green overlay displayed
- Status bar shows `N=Next | B=Back | R=Restore`
- D mode: first click waits for second click, draws line between them
- E mode: single click erases with brush
- N/B keys change frame counter in status bar
- R key restores mask to original
- Undo stack resets on frame navigation

**Step 2: Document any issues found and fix**

---

## Task 5: Test Editor with Video Frame Source (context frame switching)

**Files:** None (testing only)

Requires `+morpho/video.m` from the main reorganization plan (Task 3 there).

**Step 1: Test context frame switching**

```matlab
% Use a real video file
video_path = "avi_reg/some_test.avi";
n = morpho.video.frame_count(video_path);
first_frame = morpho.video.read_single(video_path, 50);
test_mask = false(size(first_frame));
test_mask(20:end-20, 20:end-20) = true;

editor = morpho.Editor(test_mask, ...
    background=first_frame, ...
    overlay_color="red", ...
    modes="DE", ...
    show_context_frame=true, ...
    show_opacity_control=true, ...
    frame_source=video_path, ...
    frame_indices=1:n, ...
    current_frame=50);

result = editor.run();
```

Verify:
- Changing context frame in settings dialog updates the background image
- No full video loaded into RAM (check with `whos` in workspace)

---

## Task 6: Update the Main Reorganization Plan

**Files:**
- Modify: `docs/plans/2026-03-16-code-reorganization-plan.md`
- Modify: `docs/plans/2026-03-16-code-reorganization-design.md`

**Step 1: Update design doc**

Replace Section 4 (UI Utilities `+morpho/ui.m`) with:
- `+morpho/display.m` — static helpers
- `+morpho/Editor.m` — interactive editor class

Reference `docs/plans/2026-03-16-unified-editor-design.md` for full details.

**Step 2: Update implementation plan**

In Task 4 (Create `+morpho/ui.m`), replace with reference to this plan's Tasks 1-2.

In Tasks 9, 11, 12, 13 (Morpho1, 3, 4, 5 refactors), update the UI refactor steps:
- Replace `morpho.ui.brush_edit_loop(...)` calls with `morpho.Editor(...).run()`
- Replace `morpho.ui.settings_dialog(...)` with `morpho.display.settings_dialog(...)`
- Replace `morpho.ui.expand_brush(...)` with `morpho.display.expand_brush(...)`

**Step 3: Commit**

```bash
git add docs/plans/
git commit -m "docs: add unified editor design and implementation plan"
```

---

## Summary of Dependencies

```
Task 1 (display.m)    — no dependencies
Task 2 (Editor.m)     — depends on Task 1 (display.m)
                         depends on morpho.video.read_single (from main plan Task 3)
                         for context frame switching only
Task 3 (test pink/RE) — depends on Tasks 1-2
Task 4 (test line/nav)— depends on Tasks 1-2
Task 5 (test video)   — depends on Tasks 1-2 + main plan Task 3 (video.m)
Task 6 (update plans) — depends on all above
```
