function [diff_image] = compare_mri(image1_filename, image2_filename, output_filename)
%% Function description
% 2021, Michel Belyk

% get a subset of frames from an avi file
% useful for exploring outputs from morpho_masking rtMRI pipeline

% Inputs
%   1-2) directory/filenames for images to comapre
%   2) directory/filename for output image

image1 = imread(image1_filename);
image2 = imread(image2_filename);

imshowpair(image1, image2)      %show comparison
diff_image = getframe(gca);     %capture comparison
imwrite(diff_image.cdata, output_filename)

end