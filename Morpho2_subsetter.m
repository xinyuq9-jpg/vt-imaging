%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Michel Belyk, UCL 
% April 2020
% reduce rtmri dataset to analysable frames
%
% UPDATED:
% - Remote log folder selection + local caching
% - Resume-safe: skip if outputs already exist, lock file to avoid partial results
% - FIX: tmp CSV uses ".tmp.csv" so writetable recognizes file type
% - FIX: missing remote log -> skip (with log) instead of hard error
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

clc;

%%%%%%%%%%%%%%%%%%%%%%%%
%%%manage directories%%%
%%%%%%%%%%%%%%%%%%%%%%%%
input_dir = 'morph/mat';          % LOCAL .mat inputs
log_dir_local = 'logs';           % LOCAL cache for remote log CSVs
output_mat_dir = 'morph/mat_sub'; % output .mat
output_log_dir = fullfile(output_mat_dir,'log_sub'); % output logs

disp('Reading logs');

%% ---- NEW: prompt + cache REMOTE log folder ----
script_dir = fileparts(mfilename('fullpath'));
cd(script_dir);

cache_file = fullfile(script_dir, 'Morpho_reduce_paths.mat');
remote_log_dir = [];

if isfile(cache_file)
    S = load(cache_file);
    if isfield(S,'remote_log_dir')
        remote_log_dir = S.remote_log_dir;
    end

    cache_ok = ~isempty(remote_log_dir) && isfolder(remote_log_dir);
    if cache_ok
        q = sprintf('Reuse cached REMOTE log folder?\n\nREMOTE LOG DIR:\n%s', remote_log_dir);
        choice = questdlg(q, 'Reuse cached folder?', 'Yes', 'No', 'Yes');
        if isempty(choice), error('Cancelled.'); end
        if strcmp(choice,'No')
            remote_log_dir = [];
        else
            logmsg('Using cached remote_log_dir.');
        end
    else
        logmsg('Cached remote_log_dir not valid/mounted. Will prompt.');
        remote_log_dir = [];
    end
end

if isempty(remote_log_dir)
    remote_log_dir = uigetdir(pwd, 'Select REMOTE LOG folder (contains *.csv logs)');
    if isequal(remote_log_dir, 0)
        error('No remote log folder selected.');
    end
end

try
    save(cache_file, 'remote_log_dir');
    logmsg(['Saved cached remote_log_dir to: ' cache_file]);
catch ME
    logmsg(['WARNING: Could not save cache file: ' ME.message]);
end

%% Ensure local dirs exist
if ~isfolder(log_dir_local), mkdir(log_dir_local); end
if ~isfolder(output_mat_dir), mkdir(output_mat_dir); end
if ~isfolder(output_log_dir), mkdir(output_log_dir); end

%% List input .mat files
list_input_files = dir(fullfile(input_dir, '*.mat'));
if isempty(list_input_files)
    error('No input .mat files found in %s', input_dir);
end

%%%%%%%%%%%%%%%%%%%%%%
%Iterate through files
%%%%%%%%%%%%%%%%%%%%%%
for iFile = 1:length(list_input_files)

  input_rootname = list_input_files(iFile).name(1:end-8); % remove _out.mat
  input_filename = fullfile(input_dir, list_input_files(iFile).name);

  % Define outputs (resume-safe)
  output_mat = char(fullfile(output_mat_dir, [input_rootname '_sub.mat']));
  out_log_filename = char(fullfile(output_log_dir, [input_rootname '_log.csv']));
  outputs = {output_mat, out_log_filename};

  % ---- Resume-safe skip: outputs already exist ----
  if is_done(outputs, 10) % >=10 bytes to avoid empty files counting as done
      logmsg(['SKIP (already processed): ' input_rootname]);
      continue;
  end

  % ---- Lock to prevent partial work being mistaken as done ----
  if ~acquire_lock(output_mat)
      logmsg(['SKIP (lock exists): ' input_rootname]);
      continue;
  end

  try
      logmsg(['Processing: ' input_rootname]);

      % Remote log file (SMB) + local cached copy
      remote_log_filename = fullfile(remote_log_dir, [input_rootname '.csv']);
      local_log_filename  = fullfile(log_dir_local, [input_rootname '.csv']);

      % ---- FIX: Missing remote log -> skip safely ----
      if ~isfile(remote_log_filename)
          logmsg(['MISSING LOG (skip): ' remote_log_filename]);
          release_lock(output_mat);
          continue;
      end

        if isfile(local_log_filename)
            delete(local_log_filename);
        end
        
        [copy_ok, msg, msgid] = copyfile(remote_log_filename, local_log_filename, 'f');
        if ~copy_ok
            error(['Failed copying remote log.\n' ...
                   'SOURCE: %s\nDEST: %s\nMSGID: %s\nMSG: %s'], ...
                   remote_log_filename, local_log_filename, msgid, msg);
        end

      logmsg(['Using log (local cache): ' local_log_filename]);

      % Load frames
      frames = load(input_filename).vt_output;
      no_frames = size(frames,3);
      max_valid_frame = no_frames;

      % Read log
      logfile = readtable(local_log_filename);
      no_segments = size(logfile,1);

      % Placeholders
      useful_frames  = false(1,no_frames);
      segment_number = zeros(1,no_frames);
      segment_label  = strings(1,no_frames);

      for segment=1:no_segments
          onset_frame  = min(logfile.ONSET(segment),  max_valid_frame);
          offset_frame = min(logfile.OFFSET(segment), max_valid_frame);
          if onset_frame > offset_frame
              continue;
          end

          seg_frames = onset_frame:offset_frame;
            if ~isfinite(onset_frame) || ~isfinite(offset_frame) || ...
               onset_frame < 1 || offset_frame < 1 || ...
               mod(onset_frame,1) ~= 0 || mod(offset_frame,1) ~= 0
                error(['Invalid frame indices in log for %s at row %d. ' ...
                       'ONSET=%g, OFFSET=%g, max_valid_frame=%d'], ...
                       input_rootname, segment, logfile.ONSET(segment), logfile.OFFSET(segment), max_valid_frame);
            end
          useful_frames(seg_frames)  = 1;
          segment_number(seg_frames) = logfile.SEGMENT_NUMBER(segment);
          segment_label(seg_frames)  = string(logfile.SEGMENT_LABEL{segment});
      end

      % Subset
      vt_output = frames(:,:,useful_frames);
      segment_number_out = segment_number(useful_frames);
      segment_label_out  = segment_label(useful_frames);
      frame_position     = find(useful_frames);

      % Write outputs (write temp then rename for extra safety)
      tmp_mat = [output_mat '.tmp'];
      tmp_csv = [out_log_filename '.tmp.csv'];  % ---- FIX: recognized by writetable ----

      if isfile(tmp_mat), delete(tmp_mat); end
      if isfile(tmp_csv), delete(tmp_csv); end

      save(tmp_mat, 'vt_output');

      log_table = table(segment_number_out', frame_position', segment_label_out');
      log_table.Properties.VariableNames = {'Segment_Number','Frame_Position','Segment_Label'};
      writetable(log_table, tmp_csv, 'Delimiter', ',');

      % Move into place (overwrite)
      if isfile(output_mat), delete(output_mat); end
      if isfile(out_log_filename), delete(out_log_filename); end

      movefile(tmp_mat, output_mat, 'f');
      movefile(tmp_csv, out_log_filename, 'f');

      % Final done check
      if ~is_done(outputs, 10)
          error('Outputs failed final validation for %s', input_rootname);
      end

      logmsg(['DONE: ' input_rootname]);

  catch ME
      logmsg(['ERROR processing ' input_rootname ': ' ME.message]);
  end

  % Always release lock at end of iteration
  release_lock(output_mat);

end

logmsg('ALL DONE.');

%% ========================= GENERIC HELPERS =========================
function tf = is_done(outputs, min_bytes)
    if nargin < 2 || isempty(min_bytes)
        min_bytes = 1;
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

function lockpath = lock_file_for(primary_output)
    lockpath = [primary_output '.lock'];
end

function acquired = acquire_lock(primary_output)
    lockpath = lock_file_for(primary_output);
    if isfile(lockpath)
        acquired = false;
        return;
    end
    fid = fopen(lockpath,'wt');
    if fid < 0
        acquired = false;
        return;
    end
    fprintf(fid, 'locked_at,%s\n', datestr(now,'yyyy-mm-dd HH:MM:SS'));
    fclose(fid);
    acquired = true;
end

function release_lock(primary_output)
    lockpath = lock_file_for(primary_output);
    if isfile(lockpath)
        delete(lockpath);
    end
end

function logmsg(msg)
    ts = datestr(now, 'yyyy-mm-dd HH:MM:SS');
    fprintf('[%s] %s\n', ts, msg);
end