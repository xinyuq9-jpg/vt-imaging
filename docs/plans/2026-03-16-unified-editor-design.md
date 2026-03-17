# Unified Mask/Trace Editor — Design

**Date:** 2026-03-16
**Status:** Approved

## Problem

Interactive editing is duplicated across Morpho1, Morpho3, Morpho4, Morpho5, and Morpho1b with slight variations. Each has its own ginput loop, brush logic, corner-box mechanism, and settings dialog (Morpho1_UI, Morpho3_UI, Morpho4_UI, Morpho5_UI — near-identical with copy-paste bugs like `dis` instead of `disp`). Morpho3 lacks opacity and context frame controls that Morpho1 has. No undo capability in any stage.

## Solution

A single `morpho.Editor` handle class that all stages use, configured via options. Keyboard shortcuts replace most corner-box clicking. A 20-step undo stack. Opacity and context frame controls available to all stages that want them.

## File Structure

```
+morpho/
├── Editor.m          # handle class — interactive mask/trace editor
├── display.m         # static helpers (show_pair, init_mask_overlay,
│                     #   update_mask_overlay, show_pink_overlay,
│                     #   create_editor_figure, expand_brush, mode_to_ink)
├── Config.m
├── io.m
├── video.m
├── masking.m
├── registration.m
└── tracing.m
```

## Interaction Model

### Controls

**Keyboard shortcuts (always available):**
| Key | Action |
|-----|--------|
| S | Open settings dialog |
| U | Undo (up to 20 steps) |
| Ctrl+Z | Undo (alias) |
| D | Switch to Draw mode |
| E | Switch to Erase mode |
| Q | Quit editor |

**Keyboard shortcuts (when `allow_frame_nav=true`, Morpho5):**
| Key | Action |
|-----|--------|
| N | Next frame |
| B | Previous frame |
| R | Restore frame to original |

**Keyboard shortcuts (when `modes` contains 'R', Morpho3):**
| Key | Action |
|-----|--------|
| R | Switch to Redraw mode (restores original values on click) |

**Click targets:**
| Target | Action |
|--------|--------|
| Top-left box | Open settings dialog (same as S) |
| Top-right box | Quit editor (same as Q) |
| Anywhere else | Apply brush stroke (draw/erase/redraw depending on mode) |

### Status Bar

Persistent title showing all available shortcuts and current state:

```
S=Settings | U=Undo(3) | D=Draw | E=Erase | Q=Quit | Mode:D | Brush:10 | Opacity:0.45 | Frame:50/200
```

Updates after every action. Undo count shows remaining steps.

### Settings Dialog

One unified `inputdlg` popup (opened via S key or settings box). Fields shown depend on stage configuration:

| Field | Morpho1 | Morpho3 | Morpho4 | Morpho5 |
|-------|---------|---------|---------|---------|
| Draw/Erase mode | yes | yes (R/E) | yes | yes |
| Brush size | yes | yes | yes | yes |
| Context frame | yes | yes | no | no |
| Opacity | yes | yes | no | no |

### Undo Stack

- Circular buffer of 20 mask snapshots
- Push before every brush stroke
- Pop on U key
- Reset on frame navigation (Morpho5)

## Editor Configuration Per Stage

```matlab
% Morpho1 — mask editing with red overlay
editor = morpho.Editor(vt_mask_dilate, ...
    background=context_frame_img, ...
    overlay_color="red", ...
    modes="DE", ...
    show_opacity_control=true, ...
    show_context_frame=true, ...
    frame_source=input_filename, ...
    frame_indices=1:no_frames, ...
    current_frame=context_frame);
vt_mask_cleaned = editor.run();

% Morpho3 — QA editing with pink overlay, redraw from original
editor = morpho.Editor(vt_ever, ...
    background=anatomy_med, ...
    original=vt_ever_og, ...
    overlay_color="pink", ...
    modes="RE", ...
    show_opacity_control=true, ...
    show_context_frame=true, ...
    frame_source=input_avi_filename, ...
    frame_indices=1:no_frames);
vt_ever_cleaned = editor.run();

% Morpho4 — trace editing (manual check mode)
editor = morpho.Editor(trace_mat, ...
    background=frame_img, ...
    overlay_color="green", ...
    modes="DE");
edited_trace = editor.run();

% Morpho5 — frame-by-frame trace correction
editor = morpho.Editor(trace_outline, ...
    background=current_frame_img, ...
    original=original_trace, ...
    overlay_color="green", ...
    modes="DE", ...
    allow_line_draw=true, ...
    allow_frame_nav=true, ...
    frame_source=avi_path, ...
    frame_indices=logfile.Frame_Position);
edited_trace = editor.run();
```

## Editor Class API

```matlab
classdef Editor < handle

    % --- Public properties (set via constructor) ---
    properties
        mask                    % H x W working mask
        background              % H x W background image for display
        original                % H x W original mask (for restore/redraw)

        overlay_color   string  = "red"     % "red", "pink", "green"
        modes           string  = "DE"      % allowed mode chars
        brush_size      double  = 10
        draw_mode       char    = 'D'
        overlay_opacity double  = 0.45

        show_opacity_control  logical = false
        show_context_frame    logical = false
        allow_line_draw       logical = false   % two-click line (Morpho5)
        allow_frame_nav       logical = false   % N/B/R keys (Morpho5)

        frame_source    string  = ""        % video path for context switching
        frame_indices   double  = []
        current_frame   double  = 1
        no_frames       double  = 1
        max_undo        double  = 20
    end

    % --- Private state ---
    properties (Access = private)
        fig, ax, hBase, hOverlay        % figure handles
        undo_stack cell                  % circular buffer
        undo_pos double = 0
        undo_count double = 0
        done logical = false
        ink double = 1
        mask_size double
        exit_box_size double
        settings_box_size double
    end

    methods
        function obj = Editor(mask, opts)
            % Constructor — accepts mask + name-value options
        end

        function result = run(obj)
            % Main loop. Blocks until user quits.
            % Returns edited mask.
        end
    end

    methods (Access = private)
        function init_figure(obj)
            % Create figure, axes, overlay, set KeyPressFcn
        end

        function handle_key(obj, evt)
            % Dispatch keyboard shortcuts
        end

        function handle_click(obj, x, y)
            % Process click: exit box, settings box, or brush/line stroke
        end

        function open_settings(obj)
            % Open unified settings dialog via morpho.display.settings_dialog
        end

        function load_context_frame(obj)
            % Read frame from video source for display
        end

        function push_undo(obj)
            % Save current mask to circular buffer
        end

        function pop_undo(obj)
            % Restore previous mask from buffer
        end

        function redraw(obj)
            % Update overlay and status bar
        end

        function update_status(obj)
            % Rebuild title string with shortcuts + current state
        end

        function cleanup_boxes(obj)
            % Remove corner boxes from mask before returning
        end

        function next_frame(obj), end
        function prev_frame(obj), end
        function restore_frame(obj), end
    end
end
```

## Display Helpers (`+morpho/display.m`)

Static utility functions used by Editor and directly by stage scripts:

```matlab
classdef display
    methods (Static)
        function ink = mode_to_ink(draw_mode)
        function [x_brush, y_brush] = expand_brush(x, y, brush_size, mask_size)
        function [draw_mode, brush_size, ink, varargout] = settings_dialog(...)
        function show_pair(frame, overlay, opts)
        function [hBase, hOverlay] = init_mask_overlay(ax, frame2d, mask2d, opacity)
        function update_mask_overlay(hBase, hOverlay, frame2d, mask2d, opacity)
        function show_pink_overlay(anatomy, mask, mask_size)
        function fig = create_editor_figure(title_str)
    end
end
```

## Overlay Colors

| Color | RGB | Used by |
|-------|-----|---------|
| red | `[1 0 0]` | Morpho1 (mask editing) |
| pink | `[1 0 0.5]` | Morpho3 (QA editing) |
| green | `[0 1 0]` | Morpho4, Morpho5 (trace editing) |

The Editor builds the overlay from `overlay_color`:
```matlab
switch obj.overlay_color
    case "red"
        rgb = cat(3, ones(sz), zeros(sz), zeros(sz));
    case "pink"
        rgb = cat(3, ones(sz), zeros(sz), ones(sz)/2);
    case "green"
        rgb = cat(3, zeros(sz), ones(sz), zeros(sz));
end
```

## Out of Scope

- `uifigure` / App Designer migration (keep using `figure` + `ginput`)
- Zoom/pan tools (MATLAB's built-in figure tools handle this)
- Redo (only undo — keeps it simple)
