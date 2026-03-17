% +morpho/video.m
classdef video
    methods (Static)

        function n = frame_count(videoPath)
            % Get frame count from video file.
            v = VideoReader(string(videoPath));
            n = max(1, floor(v.Duration * v.FrameRate + 1e-6));
            try
                n = min(n, v.NumFrames);
            catch
            end
        end

        function fps = frame_rate(videoPath)
            v = VideoReader(string(videoPath));
            fps = v.FrameRate;
        end

        function frame = to_gray_single(frame)
            % Convert raw frame to 2D single-precision grayscale.
            % Handles RGB, 4D, squeeze, and cast in one place.
            % Replaces the 5-line block repeated in every script.
            if ndims(frame) == 4
                frame = frame(:,:,1,:);
                frame = squeeze(frame);
            elseif ndims(frame) == 3 && size(frame,3) == 3
                frame = frame(:,:,1);
            end
            frame = squeeze(frame);
            if ~isa(frame, 'single')
                frame = single(frame);
            end
        end

        function frame = read_single(videoPath, frameIdx)
            % Read one frame as single-precision grayscale.
            v = VideoReader(string(videoPath));
            raw = read(v, frameIdx);
            frame = morpho.video.to_gray_single(raw);
        end

        function frames = read_frames(videoPath, frameIndices)
            % Read specific frames as H x W x N single grayscale.
            % If frameIndices is empty, reads all frames.
            arguments
                videoPath string
                frameIndices = []
            end
            v = VideoReader(videoPath);

            if isempty(frameIndices)
                raw = read(v);
            else
                % read(v, [first last]) reads a contiguous range
                % For arbitrary indices, read contiguous then subset
                raw = read(v, [min(frameIndices) max(frameIndices)]);
                % Adjust indices relative to the range start
                adj = frameIndices - min(frameIndices) + 1;
                if ndims(raw) == 4
                    raw = raw(:,:,:,adj);
                else
                    raw = raw(:,:,adj);
                end
            end

            frames = morpho.video.to_gray_single(raw);
        end

        function [running_mean, running_var] = streaming_stats(videoPath, opts)
            % Welford's online algorithm for per-pixel mean and variance.
            % Single pass, O(H x W) memory regardless of frame count.
            %
            % Returns:
            %   running_mean: H x W single — mean intensity per pixel
            %   running_var:  H x W single — variance per pixel
            arguments
                videoPath string
                opts.frameIndices = []
                opts.skipFirstN (1,1) double = 0
            end
            v = VideoReader(videoPath);
            total_frames = morpho.video.frame_count(videoPath);

            if isempty(opts.frameIndices)
                opts.frameIndices = 1:total_frames;
            end

            % Skip first N frames (noisy)
            if opts.skipFirstN > 0
                opts.frameIndices = opts.frameIndices(opts.frameIndices > opts.skipFirstN);
            end

            running_mean = [];
            running_var = [];
            n = 0;

            for i = 1:numel(opts.frameIndices)
                idx = opts.frameIndices(i);
                raw = read(v, idx);
                frame = morpho.video.to_gray_single(raw);

                if isempty(running_mean)
                    running_mean = zeros(size(frame), 'single');
                    running_var  = zeros(size(frame), 'single');
                end

                n = n + 1;
                delta = frame - running_mean;
                running_mean = running_mean + delta / n;
                delta2 = frame - running_mean;
                running_var = running_var + delta .* delta2;
            end

            if n > 1
                running_var = running_var / (n - 1);
            end
        end

        function process_chunks(videoPath, processFn, opts)
            % Chunked frame processing. Never holds more than chunkSize
            % frames in RAM. processFn receives (chunk, frameIndices) and
            % returns a result array of same frame dimension.
            %
            % If outputMatFile is set, results are saved incrementally
            % to a -v7.3 matfile as vt_output(:,:,indices).
            arguments
                videoPath string
                processFn function_handle
                opts.chunkSize (1,1) double = 500
                opts.frameIndices = []
                opts.outputMatFile string = ""
            end

            total = morpho.video.frame_count(videoPath);
            if isempty(opts.frameIndices)
                opts.frameIndices = 1:total;
            end

            nFrames = numel(opts.frameIndices);
            v = VideoReader(videoPath);

            % Pre-create output matfile if requested
            mf = [];
            if opts.outputMatFile ~= ""
                % Read one frame to get dimensions
                sample = morpho.video.to_gray_single(read(v, opts.frameIndices(1)));
                [h, w] = size(sample);
                % Create -v7.3 file with pre-allocated array
                save(opts.outputMatFile, 'h', '-v7.3');
                mf = matfile(opts.outputMatFile, 'Writable', true);
                mf.vt_output = false(h, w, nFrames);
            end

            nChunks = ceil(nFrames / opts.chunkSize);

            for c = 1:nChunks
                startIdx = (c-1) * opts.chunkSize + 1;
                endIdx = min(c * opts.chunkSize, nFrames);
                chunkFrameNums = opts.frameIndices(startIdx:endIdx);

                % Read chunk — contiguous range then subset
                raw = read(v, [chunkFrameNums(1), chunkFrameNums(end)]);
                chunk = morpho.video.to_gray_single(raw);

                % Handle case where read returns more frames than needed
                needed = chunkFrameNums - chunkFrameNums(1) + 1;
                if size(chunk, 3) > numel(needed)
                    chunk = chunk(:,:,needed);
                end

                % Process
                result = processFn(chunk, chunkFrameNums);

                % Save incrementally
                if ~isempty(mf)
                    mf.vt_output(:,:,startIdx:endIdx) = result;
                end

                fprintf('  Chunk %d/%d complete (%d frames)\n', c, nChunks, endIdx - startIdx + 1);
            end
        end

        function write_avi(filepath, frames, framerate, opts)
            % Write frames to AVI file.
            arguments
                filepath string
                frames
                framerate double
                opts.codec string = "Motion JPEG AVI"
                opts.quality double = 95
            end
            vw = VideoWriter(filepath, opts.codec);
            vw.FrameRate = framerate;
            if isprop(vw, 'Quality')
                vw.Quality = opts.quality;
            end
            open(vw);
            writeVideo(vw, frames);
            close(vw);
        end

    end
end
