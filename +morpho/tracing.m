% +morpho/tracing.m
classdef tracing
    methods (Static)

        function vt_skel = compute_skeleton(vt_mean, threshold)
            % Compute mean VT skeleton via thinning.
            arguments
                vt_mean     % H x W mean VT frequency map
                threshold (1,1) double = 0.75
            end
            vt_skel = bwmorph(vt_mean > threshold, 'thin', 'Inf');
        end

        function [top, bottom] = find_endpoints(vt_mask)
            % Find VT endpoints (lips = most anterior, larynx = most ventral).
            % Returns [y, x] pairs.
            vt_linear = find(vt_mask);
            [vt_y, vt_x] = ind2sub(size(vt_mask), vt_linear);

            % Top (anterior/lips): most anterior pixel, then most dorsal of those
            top_x = min(vt_x);
            top_y = min(vt_y(vt_x == top_x));
            top = [top_y, top_x];

            % Bottom (larynx): most ventral pixel, then median x
            bottom_y = max(vt_y);
            bottom_x = round(median(vt_x(vt_y == bottom_y)));
            bottom = [bottom_y, bottom_x];
        end

        function [trace_x, trace_y, trace_mat] = trace_boundary(vt_mask, start_point)
            % Trace boundary clockwise from start_point.
            % start_point: [y, x]
            % Returns x coords, y coords, and binary trace matrix.
            arguments
                vt_mask logical
                start_point (1,2) double  % [y, x]
            end

            trace = bwtraceboundary(vt_mask, start_point, 'W', 8, Inf, 'clockwise');

            trace_y = trace(:,1);
            trace_x = trace(:,2);

            trace_mat = false(size(vt_mask));
            trace_ind = sub2ind(size(vt_mask), trace_y, trace_x);
            trace_mat(trace_ind) = true;
        end

        function [n_compartments, lab_mat, sorted_labels] = analyze_clusters(vt_frame)
            % Analyze connected components in a VT frame.
            % Returns cluster count (excluding background), label matrix,
            % and labels sorted by size (largest first).
            lab_mat = bwlabel(vt_frame);
            labs = unique(lab_mat);

            labs_sum = zeros(length(labs), 1);
            for l = 1:length(labs)
                labs_sum(l) = sum(lab_mat(:) == labs(l));
            end

            [~, ii] = sort(labs_sum, 'descend');
            sorted_labels = labs(ii);

            % Exclude background (0)
            sorted_labels = sorted_labels(sorted_labels > 0);
            n_compartments = numel(sorted_labels);
        end

        function bridge_mask = a_star_bridge(vt_frame, vt_ever, frame_data, a_star_weight)
            % Build A* bridge between disconnected compartments.
            % vt_frame: H x W binary mask for this frame
            % vt_ever: H x W binary — pixels that are ever VT
            % frame_data: H x W single — raw intensity for cost
            % a_star_weight: cost multiplier
            arguments
                vt_frame logical
                vt_ever logical
                frame_data
                a_star_weight (1,1) double = 999
            end

            map = vt_ever;
            costs = double(frame_data .* map * a_star_weight);

            [top, bottom] = morpho.tracing.find_endpoints(vt_frame);
            frame_size = size(vt_frame);

            start_idx = sub2ind(frame_size, top(1), top(2));
            goal_idx = sub2ind(frame_size, bottom(1), bottom(2));

            a_star_ind = a_star(map, costs, start_idx, goal_idx);

            bridge_mask = false(frame_size);
            bridge_mask(a_star_ind) = true;
            bridge_mask(vt_frame) = false; % don't duplicate existing pixels
        end

    end
end
