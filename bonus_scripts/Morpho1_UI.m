function [draw_mode, brush_size, ink, context_frame, mask_opacity] = ...
    Morpho1_UI(draw_mode, brush_size, mask_size, context_frame, no_frames, mask_opacity)
%% Function description
% March 2022, Michel Belyk, Edge Hill University
%
% UPDATED:
% - add control of current display frame
% - add control of mask overlay opacity
%
% User can change:
%   [D]/[E] draw mode
%   brush size
%   current context frame
%   mask opacity

    prompt = { ...
        'Enter [D] to draw, [E] to Erase:', ...
        'Brush size (pixels):', ...
        ['Context frame (1-' int2str(no_frames) '):'], ...
        'Mask opacity (0 to 1):'};

    dlgtitle = 'Mask Editor Settings';
    dims = [1 40];

    definput = { ...
        draw_mode, ...
        int2str(brush_size), ...
        int2str(context_frame), ...
        num2str(mask_opacity)};

    draw_settings = inputdlg(prompt, dlgtitle, dims, definput);

    % if user cancels, keep old values
    if isempty(draw_settings)
        if draw_mode == 'D' || draw_mode == 'd'
            ink = 1;
        elseif draw_mode == 'E' || draw_mode == 'e'
            ink = 0;
        else
            draw_mode = 'D';
            ink = 1;
        end
        return
    end

    % -----------------------
    % draw / erase mode
    % -----------------------
    draw_mode = draw_settings{1};

    if draw_mode == 'D' || draw_mode == 'd'
        ink = 1;
        draw_mode = 'D';
    elseif draw_mode == 'E' || draw_mode == 'e'
        ink = 0;
        draw_mode = 'E';
    else
        draw_mode = 'D';
        ink = 1;
        disp("Invalid mode entered. Defaulting to D (Draw).")
    end

    % -----------------------
    % brush size
    % -----------------------
    new_brush_size = str2double(draw_settings{2});
    if isnan(new_brush_size)
        disp("Invalid brush size entered. Keeping previous value.")
    else
        brush_size = round(new_brush_size);
    end

    if brush_size < 0
        brush_size = 0;
        disp("Brush size too small, increased to: " + int2str(brush_size))
    elseif brush_size > min(mask_size)/4
        brush_size = floor(min(mask_size)/4);
        disp("Brush size too large, reduced to: " + int2str(brush_size))
    end

    % -----------------------
    % context frame
    % -----------------------
    new_context_frame = str2double(draw_settings{3});
    if isnan(new_context_frame)
        disp("Invalid context frame entered. Keeping previous value.")
    else
        context_frame = round(new_context_frame);
    end

    if context_frame < 1
        context_frame = 1;
        disp("Context frame too small, increased to: " + int2str(context_frame))
    elseif context_frame > no_frames
        context_frame = no_frames;
        disp("Context frame too large, reduced to: " + int2str(context_frame))
    end

    % -----------------------
    % mask opacity
    % -----------------------
    new_mask_opacity = str2double(draw_settings{4});
    if isnan(new_mask_opacity)
        disp("Invalid mask opacity entered. Keeping previous value.")
    else
        mask_opacity = new_mask_opacity;
    end

    if mask_opacity < 0
        mask_opacity = 0;
        disp("Mask opacity too small, increased to: " + num2str(mask_opacity))
    elseif mask_opacity > 1
        mask_opacity = 1;
        disp("Mask opacity too large, reduced to: " + num2str(mask_opacity))
    end

    % -----------------------
    % display selected outcome
    % -----------------------
    disp("Mode = " + draw_mode + ...
         "; Brush size = " + int2str(brush_size) + ...
         " pixels; Context frame = " + int2str(context_frame) + ...
         "; Mask opacity = " + num2str(mask_opacity))
end