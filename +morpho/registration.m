% +morpho/registration.m
classdef registration
    methods (Static)

        function frame = ensure_gray_2d(frame)
            % Ensure frame is 2D grayscale.
            if ndims(frame) == 4
                frame = frame(:,:,1,1);
                frame = squeeze(frame);
            elseif ndims(frame) == 3
                frame = frame(:,:,1);
                frame = squeeze(frame);
            end
        end

        function [tform, registered] = register_frame(frame, fixed_masked, optimizer, metric, outView)
            % Register one frame to reference using rigid transform.
            arguments
                frame
                fixed_masked
                optimizer
                metric
                outView
            end
            frame = morpho.registration.ensure_gray_2d(frame);
            tform = imregtform(frame, fixed_masked, 'rigid', optimizer, metric);
            registered = imwarp(frame, tform, 'OutputView', outView);
            if ~isa(registered, 'uint8')
                registered = im2uint8(registered);
            end
        end

        function fixed_masked = apply_cutoff_mask(reference, cutoff_X, cutoff_Y)
            % Apply the upper-region mask to reference image.
            fixed_masked = morpho.registration.ensure_gray_2d(reference);
            size_Y = size(fixed_masked, 2);
            fixed_masked(cutoff_Y:size_Y, 1:cutoff_X, :) = 0;
        end

        function s = bytestr(n)
            % Format byte count as human-readable string.
            units = {'B','KB','MB','GB','TB'};
            s = double(n);
            u = 1;
            while s >= 1024 && u < numel(units)
                s = s / 1024;
                u = u + 1;
            end
            s = sprintf('%.2f %s', s, units{u});
        end

    end
end
