function [draw_mode,brush_size,ink] = Morpho1_UI(draw_mode, brush_size, vt_ever)
%% Function description
% March 2022, Michel Belyk, Edge Hill University

%draw_mode: [R]edraw or [E]rase pixels
%brush_size: How many pixels to draw/erase. pixels = 2*size+1
%vt_ever: a matrix noting the proportion of times any given pixel is within
%the vocal tract mask. This is the working copy to be dited

% simple UI to give user control over brush size and whether they draw or
% erase by clicking on the MR image
    prompt = {'Enter [r] to redraw, [E] to Erase:','Brush size (pixels):'};
    dlgtitle = 'Input';
    dims = [1 35];
    definput = {draw_mode,int2str(brush_size)}; %default to current settings
    draw_settings = inputdlg(prompt,dlgtitle,dims,definput);
    draw_mode = draw_settings{1};
    brush_size = draw_settings{2}; %get users preferred brush
    brush_size = str2num(brush_size); %convert back to integer
    mask_size = size(vt_ever);
    %convert input character to binary fordrawing
    if draw_mode == 'R' || draw_mode == 'r'
        ink = 1;
    elseif draw_mode == 'E'|| draw_mode == 'e'
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
        disp("Brush size too small, increased to:" + brush_size)

    elseif brush_size > min(mask_size)/4
        brush_size = min(mask_size)/4; 
        disp("Brush size too large, reduced to:" + brush_size)

    end %end safety net
end %end function