% +morpho/io.m
classdef io
    methods (Static)

        %% ---- Lock file management ----

        function tf = is_locked(filepath)
            tf = isfile(string(filepath) + ".lock");
        end

        function acquired = acquire_lock(filepath)
            lockpath = string(filepath) + ".lock";
            if isfile(lockpath)
                acquired = false;
                return;
            end
            fid = fopen(lockpath, 'wt');
            if fid < 0
                acquired = false;
                return;
            end
            fprintf(fid, 'locked_at,%s\n', datestr(now, 'yyyy-mm-dd HH:MM:SS'));
            fclose(fid);
            acquired = true;
        end

        function release_lock(filepath)
            lockpath = string(filepath) + ".lock";
            if isfile(lockpath)
                delete(lockpath);
            end
        end

        %% ---- Output validation ----

        function tf = is_done(outputs, min_bytes)
            % Check if all output files exist and exceed min_bytes.
            % outputs: string array or cell array of file paths
            arguments
                outputs
                min_bytes (1,1) double = 1
            end
            tf = true;
            for i = 1:numel(outputs)
                d = dir(outputs{i});
                if isempty(d) || d(1).bytes < min_bytes
                    tf = false;
                    return;
                end
            end
        end

        %% ---- ADB filename parsing ----

        function [adb_id, block_num] = parse_adb(rootname)
            % Parse ADB group and block number from filename root.
            % e.g. "ADB17block_2_lag_0.36667" -> ("ADB17", 2)
            tok = regexp(string(rootname), '^(ADB\d+)block_(\d+)', 'tokens', 'once');
            if isempty(tok)
                error("morpho:io:badFilename", ...
                    "Filename does not match ADB##block_#_... pattern: %s", rootname);
            end
            adb_id = string(tok{1});
            block_num = str2double(tok{2});
        end

        function rootname = strip_suffix(filename, suffix)
            % Remove known suffix from filename.
            % e.g. strip_suffix("ADB17block_1_lag_0.36_out.mat", "_out.mat")
            %   -> "ADB17block_1_lag_0.36"
            rootname = string(filename);
            if endsWith(rootname, suffix)
                rootname = extractBefore(rootname, strlength(rootname) - strlength(suffix) + 1);
            end
        end

        %% ---- File discovery ----

        function file_list = list_files(inputDir, extension)
            % List files in directory matching extension.
            % Returns struct array like dir() output.
            arguments
                inputDir string
                extension string = ".mat"
            end
            file_list = dir(fullfile(inputDir, "*" + extension));
            if isempty(file_list)
                error("morpho:io:noFiles", ...
                    "No files with extension %s found in %s", extension, inputDir);
            end
        end

        %% ---- Cached remote path prompting ----

        function remote_path = prompt_remote_dir(cache_file, prompt_title)
            % Prompt user for remote directory with caching.
            % If cache_file exists and path is valid, offers reuse.
            arguments
                cache_file string
                prompt_title string = "Select remote folder"
            end
            remote_path = "";

            if isfile(cache_file)
                S = load(cache_file);
                fnames = fieldnames(S);
                if ~isempty(fnames)
                    cached = string(S.(fnames{1}));
                    if isfolder(cached)
                        q = sprintf('Reuse cached folder?\n\n%s', cached);
                        choice = questdlg(q, 'Reuse cached folder?', 'Yes', 'No', 'Yes');
                        if strcmp(choice, 'Yes')
                            remote_path = cached;
                            return;
                        end
                    end
                end
            end

            remote_path = string(uigetdir(pwd, prompt_title));
            if remote_path == "0"
                error("morpho:io:cancelled", "No folder selected.");
            end
        end

        function save_cache(cache_file, var_name, value)
            % Save a single variable to a cache .mat file.
            S.(var_name) = value;
            save(cache_file, '-struct', 'S');
        end

        %% ---- Logging ----

        function logmsg(msg)
            ts = datestr(now, 'yyyy-mm-dd HH:MM:SS');
            fprintf('[%s] %s\n', ts, msg);
        end

    end
end
