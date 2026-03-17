function [regmatrix,tforms] = register_mri(avi,fixed)
%% Function description
% 2018, Christopher Carignan

% Rigid transformation (translation and rotation) of the MR image matrix from
% concat_mri.m

% Image registration is based on:
%   1) pick first frame as reference image
%   2) manually identifying the region of the speaker's head above which point
%       there will be no movement related to the vocal tract, i.e., make
%       sure it is above the velum
%   3) compare all images to the first image in the matrix, and transform
%       translation and rotation accordingly

% Input arguments:
%   matrix:     concatenated image matrix from concat_mri.m

% Output arguments:
%   regmatrix:  registered image matrix
%   tforms:     transformation matrices

% Example:
% [regmatrix,tforms] = register_mri(matrix);

%small modes by Michel Belyk November, 2019
%mask out antero-ventral corner, instead of ventral half
%register to user specified image instead of first image

%% Function starts here

 % Duration*FrameRate can be fractional; force an integer frame count
no_frames = max(1, floor(avi.Duration * avi.FrameRate + 1e-6));

% Also guard against reading past end (VideoReader.NumFrames may be available in some versions)
try
    no_frames = min(no_frames, avi.NumFrames);
catch
end
 display_frame = read(avi, 1);
 if ndims(display_frame) == 3
    display_frame = display_frame(:,:,1); %collpse dimension 3, these are .avi channels
    display_frame = squeeze(display_frame); %there was an extra dimension floating around
 end



 frame_size = size (display_frame);
 size_X = frame_size(1);
 size_Y = frame_size(2);
 matrix_size = [size_X, size_Y, no_frames];

% preallocate image matrix
regmatrix = uint8(zeros(matrix_size));

% show image and get user selection
low = min(min(display_frame)); %for scaling
high = max(max(display_frame));
imshow(display_frame, [low high]);
set(gca,'Ydir','normal')
x = ginput(1);
close(gcf)

% get y value of user selection for image masking
cutoff_X = round(x(1));
cutoff_Y = round(x(2));

% mask out image below y value of user selection
fixed(cutoff_Y:size_Y,1:cutoff_X,:) = 0; %mask out antero-ventral corner of reference image

%imshow(fixed); %check that we are masking the right part of the image


% initialize image registration
[optimizer,metric] = imregconfig('monomodal');

% first frame used as fixed comparison
%fixed = frames(:,:,1); %first frame as reference
tic

% preallocate cell array for transformation matrices
tforms = cell(no_frames,1);

for f = 1:no_frames
    % create the transformation matrix
    this_frame = read(avi, f);

    if ndims(this_frame) == 3
        this_frame = this_frame(:,:,1); %collpse dimension 3, these are .avi channels
        this_frame = squeeze(this_frame); %there was an extra dimension floating around
    end

    tforms{f} = imregtform(this_frame,fixed,'rigid',optimizer,metric); % compute transformation
    
    
    % apply the transformation to the image
    regmatrix(:,:,f) = imwarp(this_frame,tforms{f},'OutputView',imref2d(size(fixed)));
    eval(['fprintf( ''\n   Registering frame ',num2str(f),' of ',num2str(no_frames),' ... '' );'])
end
toc
end

