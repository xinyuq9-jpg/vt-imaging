function [draw_mode,brush_size,ink] = Morpho1_UI(draw_mode, brush_size, mask_size)
%% Function description
% March 2022, Michel Belyk, Edge Hill University

% simple UI to give user control over brush size and whether they draw or
% erase by clicking on the MR image
    disp("Toggle draw vs. Erase mode. N.B. Brush size ingored in Draw Mode.")
    prompt = {'Enter [D] to draw, [E] to Erase:','Brush size (pixels):'};
    dlgtitle = 'Input';
    dims = [1 35];
    definput = {draw_mode,int2str(brush_size)}; %default to current settings
    draw_settings = inputdlg(prompt,dlgtitle,dims,definput);
    if isempty(draw_settings)==0 %empty if user clicked cancel, take no action
        draw_mode = draw_settings{1};
        brush_size = draw_settings{2}; %get users preferred brush
        brush_size = str2num(brush_size); %convert back to integer
    end
    %convert input character to binary for drawing
    if draw_mode == 'D' || draw_mode == 'd'
        draw_mode = 'D';
        ink = 1;
        disp('click two pixels to draw a straight line between them.')
    elseif draw_mode == 'E'|| draw_mode == 'e'
        draw_mode = 'E';
        ink = 0;
    else
        draw_mode='D';
        ink=1;
    end
    
    %display selected outcome to user
    disp("Mode = "+ draw_mode + "; Brush size = " + int2str(brush_size)+ " pixels")

    %convert draw_mode
    %prevent nonsensical brush sizes
    if brush_size <0
        brush_size =0;
        dis("Brush size too small, increased to:" + brush_size)

    elseif brush_size > min(mask_size)/4
        brush_size = min(mask_size)/4; 
        dis("Brush size too large, reduced to:" + brush_size)

    end %end safety net
end %end function