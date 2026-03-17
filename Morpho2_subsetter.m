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
% - REFACTORED: uses +morpho package utilities
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

clc;

cfg = morpho.Config();

%%%%%%%%%%%%%%%%%%%%%%%%
%%%manage directories%%%
%%%%%%%%%%%%%%%%%%%%%%%%
input_dir = cfg.dir("morph_mat");
log_dir_local = cfg.dir("logs_local");
output_mat_dir = cfg.dir("mat_sub");
output_log_dir = cfg.dir("log_sub");

%% ---- Prompt + cache REMOTE log folder (only if using logfiles) ----
if cfg.subsetter.use_logfile
    disp('Reading logs');

    script_dir = fileparts(mfilename('fullpath'));
    cd(script_dir);

    cache_file = fullfile(script_dir, 'Morpho_reduce_paths.mat');

    try
        remote_log_dir = morpho.io.prompt_remote_dir(cache_file, 'Select REMOTE LOG folder (contains *.csv logs)');
    catch
        error('No remote log folder selected.');
    end

    morpho.io.save_cache(cache_file, 'remote_log_dir', remote_log_dir);
    morpho.io.logmsg(['Using remote_log_dir: ' char(remote_log_dir)]);

    cfg.ensure("logs_local");
else
    disp('Processing entire videos (use_logfile=false, no log subsetting)');
end

%% Ensure local dirs exist
cfg.ensure("mat_sub");
cfg.ensure("log_sub");

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
  if morpho.io.is_done(outputs, 10) % >=10 bytes to avoid empty files counting as done
      morpho.io.logmsg(['SKIP (already processed): ' input_rootname]);
      continue;
  end

  % ---- Lock to prevent partial work being mistaken as done ----
  if ~morpho.io.acquire_lock(output_mat)
      morpho.io.logmsg(['SKIP (lock exists): ' input_rootname]);
      continue;
  end

  try
      morpho.io.logmsg(['Processing: ' input_rootname]);

      % Load frames
      frames = load(input_filename).vt_output;
      no_frames = size(frames,3);
      max_valid_frame = no_frames;

      % Placeholders
      useful_frames  = false(1,no_frames);
      segment_number = zeros(1,no_frames);
      segment_label  = strings(1,no_frames);

      if cfg.subsetter.use_logfile
          % Remote log file (SMB) + local cached copy
          remote_log_filename = fullfile(remote_log_dir, [input_rootname '.csv']);
          local_log_filename  = fullfile(log_dir_local, [input_rootname '.csv']);

          % Missing remote log -> skip safely
          if ~isfile(remote_log_filename)
              morpho.io.logmsg(['MISSING LOG (skip): ' remote_log_filename]);
              morpho.io.release_lock(output_mat);
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

          morpho.io.logmsg(['Using log (local cache): ' local_log_filename]);

          % Read log
          logfile = readtable(local_log_filename);
          no_segments = size(logfile,1);

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
      else
          % No logfile: process entire video
          useful_frames(:)  = true;
          segment_number(:) = 1;
          segment_label(:)  = "all";
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
      if ~morpho.io.is_done(outputs, 10)
          error('Outputs failed final validation for %s', input_rootname);
      end

      morpho.io.logmsg(['DONE: ' input_rootname]);

  catch ME
      morpho.io.logmsg(['ERROR processing ' input_rootname ': ' ME.message]);
  end

  % Always release lock at end of iteration
  morpho.io.release_lock(output_mat);

end

morpho.io.logmsg('ALL DONE.');
