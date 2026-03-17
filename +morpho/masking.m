% +morpho/masking.m
classdef masking
    methods (Static)

        function threshold = auto_variance_threshold(frames_var_scaled)
            % KSD-based optimal variance threshold.
            % Input: H x W scaled variance image (0-1 range).
            % Output: scalar threshold.
            [var_density_function, var_density_index] = ksdensity(frames_var_scaled(:));
            var_density_min = islocalmin(var_density_function);
            threshold = var_density_index(var_density_min);
            threshold = min(threshold);
            disp("Applying variance threshold: " + threshold);
        end

        function mask = variance_to_mask(frames_var, threshold)
            % Convert variance image to binary VT mask via thresholding +
            % largest cluster selection.
            frames_var_max = max(frames_var(:));
            frames_var_scaled = frames_var / frames_var_max;

            frames_var_mask = frames_var_scaled > threshold;

            % Find largest non-background cluster
            lab_mat = bwlabel(frames_var_mask);
            labs = unique(lab_mat);
            labs_sum = zeros(length(labs), 1);
            for l = 1:length(labs)
                labs_sum(l) = sum(lab_mat(:) == labs(l));
            end
            [~, ii] = sort(labs_sum);
            vt_cluster_number = labs(ii(end-1)); % second largest (largest is background)
            mask = lab_mat == vt_cluster_number;
        end

        function mask = morphological_cleanup(mask, opts)
            % Morphological pipeline: thicken, bridge, close, erode.
            arguments
                mask
                opts.thicken (1,1) double = 10
                opts.bridge logical = true
                opts.close logical = true
                opts.erode (1,1) double = 3
            end
            if opts.thicken > 0
                mask = bwmorph(mask, 'thicken', opts.thicken);
            end
            if opts.bridge
                mask = bwmorph(mask, 'bridge');
            end
            if opts.close
                mask = bwmorph(mask, 'close');
            end
            if opts.erode > 0
                mask = bwmorph(mask, 'erode', opts.erode);
            end
        end

        function threshold = auto_tissue_threshold(frames, vt_mask, no_frames)
            % KSD-based tissue classification threshold.
            % Computes per-frame thresholds and returns median.
            arguments
                frames          % H x W x N single
                vt_mask         % H x W logical
                no_frames (1,1) double
            end
            vt_threshold_vec = zeros(no_frames, 1);

            for f = 1:no_frames
                vt = frames(:,:,f);
                [tdf, tdi] = ksdensity(vt(vt_mask));
                tdm = islocalmin(tdf);
                tt = tdi(tdm);
                tt = min(tt);
                vt_threshold_vec(f) = tt;
            end

            failed = vt_threshold_vec == 0 | isnan(vt_threshold_vec);
            threshold = median(vt_threshold_vec(~failed));
        end

        function tissue_mask = classify_tissue_frame(frame, vt_mask, threshold, opts)
            % Classify tissue for a single frame.
            % Returns binary tissue mask.
            arguments
                frame           % H x W single
                vt_mask         % H x W logical
                threshold (1,1) double
                opts.lip_clip logical = true
            end
            vt = frame .* vt_mask;
            tissue_mask = vt < threshold & vt_mask > 0;

            % Lip clip
            if opts.lip_clip
                soft_tissue_mask = frame >= threshold & vt_mask > 0;
                soft_tissue_colsums = sum(soft_tissue_mask, 1);
                lip_col = find(soft_tissue_colsums, 1, 'first') - 1;
                if ~isempty(lip_col) && lip_col >= 1
                    tissue_mask(:, 1:lip_col) = 0;
                end
            end

            % Morphological cleanup
            tissue_mask = bwmorph(tissue_mask, 'spur');
            tissue_mask = bwmorph(tissue_mask, 'clean');
            tissue_mask = bwmorph(tissue_mask, 'close');
            tissue_mask = bwmorph(tissue_mask, 'fill');
        end

    end
end
