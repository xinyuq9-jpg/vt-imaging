%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% This script aligns vocal tract frames to a common orientation
% SMB-safe nested workflow (no Parallel Toolbox)
%
% CURRENT BEHAVIOR (matches your register_mri.m logic):
% - ONE reference per ADB: FIRST selected AVI provides the reference frame
% - ONE interactive mask selection (ginput) per ADB (same masking logic as register_mri)
% - Registration uses imregconfig('monomodal') + imregtform(...,'rigid',...)
% - Applies imwarp(...,'OutputView',imref2d(size(fixed)))
% - Outputs written ONLY to local avi_reg/ and avi_reg/reg_trasforms/
% - Resume-safe: skip if final local outputs already exist and non-empty
%
% PERFORMANCE / I/O UPDATES:
% - Clear staging folders between ADB runs: reference_run/ and avi_raw/ are deleted+recreated
% - Eliminate big regmatrix and double disk reads:
%     -> stream register frame-by-frame and write output AVI + CSV as we go
% - NEW FIX (your request):
%     -> Reference file is already staged into avi_raw BEFORE inner loop,
%        so inside inner loop SKIP copying remote_ref again; reuse avi_raw copy.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

clc;
tAll = tic;

%% ========================= ENV SETUP =========================
script_dir = fileparts(mfilename('fullpath'));
cd(script_dir);

% Local folders (existence)
if ~isfolder('avi_raw'), mkdir('avi_raw'); end
if ~isfolder('avi_reg'), mkdir('avi_reg'); end
if ~isfolder(fullfile('avi_reg','reg_trasforms')), mkdir(fullfile('avi_reg','reg_trasforms')); end
if ~isfolder('reference_run'), mkdir('reference_run'); end

addpath('bonus_scripts');

%% ========================= CACHED REMOTE BASE =========================
cache_file = fullfile(script_dir, 'Morpho0_register_paths.mat');
remote_base = [];

if isfile(cache_file)
    S = load(cache_file);
    if isfield(S,'remote_base'), remote_base = S.remote_base; end

    cache_ok = ~isempty(remote_base) && isfolder(remote_base);
    if cache_ok
        q = sprintf('Reuse cached REMOTE BASE?\n\nREMOTE BASE:\n%s', remote_base);
        choice = questdlg(q, 'Reuse cached folder?', 'Yes', 'No', 'Yes');
        if isempty(choice), error('Cancelled.'); end
        if strcmp(choice,'No')
            remote_base = [];
        else
            logmsg('Using cached remote_base.');
        end
    else
        logmsg('Cached remote_base not valid/mounted. Will prompt.');
        remote_base = [];
    end
end

if isempty(remote_base)
    remote_base = uigetdir(pwd, 'Select REMOTE BASE folder (contains ADB** folders)');
    if isequal(remote_base, 0)
        error('No remote base folder selected.');
    end
end

% Save/update cache
try
    save(cache_file, 'remote_base');
    logmsg(['Saved cached remote_base to: ' cache_file]);
catch ME
    logmsg(['WARNING: Could not save cache file: ' ME.message]);
end

%% ========================= DISCOVER ADB FOLDERS =========================
adb_list = dir(fullfile(remote_base, 'ADB*'));
adb_list = adb_list([adb_list.isdir]);
adb_names = {adb_list.name};
keep = ~strcmp(adb_names,'.') & ~strcmp(adb_names,'..');
adb_list = adb_list(keep);

if isempty(adb_list)
    error('No ADB** folders found under remote base.');
end

[~, order] = sort({adb_list.name});
adb_list = adb_list(order);

%% ========================= OUTER LOOP (AUTO ADB ORDER) =========================
for iADB = 1:numel(adb_list)

    adb_name   = adb_list(iADB).name;
    adb_path   = fullfile(remote_base, adb_name);
    recon_path = fullfile(adb_path, 'recon');

    %% ========================= CLEAN STAGING BETWEEN ADB RUNS =========================
    logmsg('Resetting staging folders (reference_run, avi_raw)...');
    if isfolder('reference_run'), rmdir('reference_run','s'); end
    mkdir('reference_run');
    if isfolder('avi_raw'), rmdir('avi_raw','s'); end
    mkdir('avi_raw');

    logmsg('============================================================');
    logmsg(sprintf('ADB %d/%d: %s', iADB, numel(adb_list), adb_name));
    logmsg(['Recon path: ' recon_path]);

    if ~isfolder(recon_path)
        logmsg('Skipping (no recon folder).');
        continue;
    end

    % Find AVI candidates under recon (recursive)
    candidates = dir(fullfile(recon_path,'**','*.avi'));
    if isempty(candidates)
        logmsg('No AVI files found under recon.');
        continue;
    end

    cand_full = fullfile({candidates.folder}, {candidates.name});
    cand_rel  = erase(cand_full, [recon_path filesep]);

    %% ============ Pre-check LOCAL output BEFORE prompting ============
    done_mask = false(size(cand_full));
    for ii = 1:numel(cand_full)
        [~, bname, ext] = fileparts(cand_full{ii});

        expected_local_avi = fullfile('avi_reg', [adb_name '_' bname ext]);
        expected_local_csv = fullfile('avi_reg', 'reg_trasforms', [adb_name '_' bname '_transform.csv']);

        dA = dir(expected_local_avi);
        dC = dir(expected_local_csv);

        if ~isempty(dA) && dA(1).bytes > 0 && ~isempty(dC) && dC(1).bytes > 0
            done_mask(ii) = true;
        end
    end

    n_done  = sum(done_mask);
    n_total = numel(done_mask);
    n_todo  = n_total - n_done;
    logmsg(sprintf('Local pre-check: %d/%d already done, %d remaining.', n_done, n_total, n_todo));

    if n_todo == 0
        logmsg('All AVIs in this ADB appear complete in local output. Skipping ADB.');
        continue;
    end

    % Only show unfinished candidates in UI
    cand_full_todo = cand_full(~done_mask);
    cand_rel_todo  = cand_rel(~done_mask);

    %% ========================= PROMPT SELECTION (unfinished only) =========================
    [idx, tf] = listdlg( ...
        'PromptString', sprintf('Select AVI(s) to register in %s (unfinished only):', adb_name), ...
        'ListString', cand_rel_todo, ...
        'SelectionMode', 'multiple', ...
        'ListSize', [900 500]);

    if ~tf || isempty(idx)
        logmsg('No files selected. Moving to next ADB.');
        continue;
    end

    remote_selected = cand_full_todo(idx);
    logmsg(sprintf('Selected %d AVI(s) to process in %s', numel(remote_selected), adb_name));

    %% ========================= ONE REFERENCE PER ADB =========================
    % Reference is the FIRST selected AVI for this ADB
    remote_ref = remote_selected{1};
    [~, ref_base, ref_ext] = fileparts(remote_ref);

    local_ref_src = fullfile('avi_raw', [ref_base ref_ext]);
    ref_dst       = fullfile('reference_run', [adb_name '_REFERENCE' ref_ext]); % stable name per ADB

    % Copy REMOTE reference -> LOCAL avi_raw
    logmsg(['Copy REMOTE reference -> LOCAL (avi_raw): ' remote_ref '  -->  ' local_ref_src]);
    tCopyInRef = tic;
    ok = copyfile(remote_ref, local_ref_src);
    if ~ok
        logmsg('ERROR: Copy REMOTE reference -> LOCAL failed. Skipping this ADB.');
        continue;
    end
    logmsg(sprintf('Reference copy-in finished (%.1fs).', toc(tCopyInRef)));

    % Copy LOCAL reference -> reference_run
    logmsg(['Copy LOCAL reference -> reference_run: ' local_ref_src '  -->  ' ref_dst]);
    tCopyRef = tic;
    ok = copyfile(local_ref_src, ref_dst);
    if ~ok
        logmsg('ERROR: Copy LOCAL reference -> reference_run failed. Skipping this ADB.');
        continue;
    end
    logmsg(sprintf('Reference staging finished (%.1fs).', toc(tCopyRef)));

    % Read reference frame ONCE (shared for this whole ADB)
    reference_frame = 100;
    try
        reference_video = VideoReader(ref_dst);
    catch ME
        logmsg(['ERROR: Cannot open reference AVI: ' ME.message]);
        continue;
    end

    try
        reference_image = read(reference_video, reference_frame);
    catch
        logmsg('WARNING: reference_frame out of range for reference AVI. Using frame 1.');
        reference_image = read(reference_video, 1);
    end
    clear reference_video;

    reference_image = ensure_gray_2d(reference_image);
    logmsg(['ADB reference set to FIRST selected AVI: ' remote_ref]);

    %% ========================= ONE ginput (mask selection) PER ADB =========================
    low  = min(reference_image(:));
    high = max(reference_image(:));
    imshow(reference_image, [low high]);
    set(gca,'Ydir','normal')
    x = ginput(1);
    close(gcf)

    cutoff_X = round(x(1));
    cutoff_Y = round(x(2));

    logmsg(sprintf('Mask cutoff chosen (per ADB): cutoff_X=%d, cutoff_Y=%d', cutoff_X, cutoff_Y));

    %% ========================= INNER LOOP (ONE AVI AT A TIME) =========================
    for k = 1:numel(remote_selected)

        remote_src = remote_selected{k};
        [~, base_name, ext] = fileparts(remote_src);

        expected_local_avi = fullfile('avi_reg', [base_name ext]);
        expected_local_csv = fullfile('avi_reg', 'reg_trasforms', [base_name '_transform.csv']);

        logmsg('------------------------------------------------------------');
        logmsg(sprintf('File %d/%d in %s', k, numel(remote_selected), adb_name));
        logmsg(['Remote source: ' remote_src]);

        din = dir(remote_src);
        if ~isempty(din)
            logmsg(['Remote size: ' bytestr(din(1).bytes)]);
        end

        % Per-file skip check (resume-safe)
        dA = dir(expected_local_avi);
        dC = dir(expected_local_csv);
        if ~isempty(dA) && dA(1).bytes > 0 && ~isempty(dC) && dC(1).bytes > 0
            logmsg('SKIP: local outputs already exist (non-empty):');
            logmsg(['  AVI: ' expected_local_avi]);
            logmsg(['  CSV: ' expected_local_csv]);
            continue;
        end

        % Stage/copy THIS AVI into avi_raw
        % FIX: if this is the reference file, it's ALREADY in avi_raw (local_ref_src).
        local_src = fullfile('avi_raw', [base_name ext]);

        if strcmp(remote_src, remote_ref)
            % Reference already staged before inner loop
            if isfile(local_src) && dir(local_src).bytes > 0
                logmsg('Reference file already staged in avi_raw. Skipping duplicate copy.');
            else
                logmsg('WARNING: Expected reference file missing in avi_raw. Re-copying once.');
                ok = copyfile(remote_src, local_src);
                if ~ok
                    logmsg('ERROR: Copy REMOTE->LOCAL failed. Skipping this file.');
                    continue;
                end
            end
        else
            logmsg(['Copy REMOTE -> LOCAL (avi_raw): ' remote_src '  -->  ' local_src]);
            tCopyIn = tic;
            ok = copyfile(remote_src, local_src);
            if ~ok
                logmsg('ERROR: Copy REMOTE->LOCAL failed. Skipping this file.');
                continue;
            end
            logmsg(sprintf('Copy-in finished (%.1fs).', toc(tCopyIn)));
        end

        input_path = local_src;

        %% ========================= PROCESSING (STREAMING, SAME LOGIC) =========================
        logmsg('Starting registration processing (streaming, behavior-matched)...');
        tProc = tic;

        % Ensure output transform dir exists
        tdir = fullfile('avi_reg', 'reg_trasforms');
        if ~isfolder(tdir), mkdir(tdir); end

        out_avi = expected_local_avi;
        out_csv = expected_local_csv;

        % Atomic temp outputs
        tmp_out_avi = [out_avi '.tmp.avi'];
        tmp_out_csv = [out_csv '.tmp.csv'];

        if isfile(tmp_out_avi), delete(tmp_out_avi); end
        if isfile(tmp_out_csv), delete(tmp_out_csv); end

        try
            aviObj = VideoReader(input_path);

            register_mri_stream_same( ...
                aviObj, ...
                reference_image, ...
                cutoff_X, cutoff_Y, ...
                tmp_out_avi, ...
                tmp_out_csv);

        catch ME
            logmsg(['ERROR during streaming registration: ' ME.message]);
            continue;
        end

        % Move temp outputs into place (overwrite only targets)
        if isfile(out_avi), delete(out_avi); end
        if isfile(out_csv), delete(out_csv); end
        movefile(tmp_out_avi, out_avi, 'f');
        movefile(tmp_out_csv, out_csv, 'f');

        logmsg(sprintf('Processing finished (%.1fs).', toc(tProc)));

        % Validate outputs
        dA = dir(out_avi);
        dC = dir(out_csv);
        if isempty(dA) || dA(1).bytes == 0 || isempty(dC) || dC(1).bytes == 0
            logmsg('WARNING: Output validation failed (missing/empty).');
        else
            logmsg('Done with this file (local outputs written).');
            logmsg(['  AVI: ' out_avi]);
            logmsg(['  CSV: ' out_csv]);
        end

    end

    logmsg(['Finished ADB folder: ' adb_name]);

end

logmsg(sprintf('ALL DONE. Total runtime: %.1f minutes', toc(tAll)/60));

%% ========================= HELPER FUNCTIONS =========================
function logmsg(msg)
    ts = datestr(now, 'yyyy-mm-dd HH:MM:SS');
    fprintf('[%s] %s\n', ts, msg);
end

function I = ensure_gray_2d(I)
    if ndims(I) == 3
        I = I(:,:,1);
        I = squeeze(I);
    elseif ndims(I) == 4
        I = I(:,:,1,1);
        I = squeeze(I);
    end
end

function s = bytestr(n)
    units = {'B','KB','MB','GB','TB'};
    s = double(n);
    u = 1;
    while s >= 1024 && u < numel(units)
        s = s/1024;
        u = u + 1;
    end
    s = sprintf('%.2f %s', s, units{u});
end

%% ========================= STREAMING (SAME AS register_mri) =========================
function register_mri_stream_same(avi, fixed, cutoff_X, cutoff_Y, outAviPath, outCsvPath)
% Streaming, behavior-matched version of your register_mri():
% - Same no_frames logic (Duration*FrameRate, plus NumFrames guard)
% - Same fixed masking: fixed(cutoff_Y:size_Y, 1:cutoff_X) = 0
% - Same imregconfig('monomodal') and imregtform(...,'rigid',...)
% - Same imwarp OutputView
% - Writes reg frames directly to AVI; appends transform rows to CSV

    % ---- Same frame count logic ----
    no_frames = max(1, floor(avi.Duration * avi.FrameRate + 1e-6));
    try
        no_frames = min(no_frames, avi.NumFrames);
    catch
    end

    fixed_masked = fixed;

    size_Y = size(fixed_masked, 2);
    fixed_masked(cutoff_Y:size_Y, 1:cutoff_X, :) = 0;

    fixed_masked = ensure_gray_2d_local(fixed_masked);

    [optimizer, metric] = imregconfig('monomodal');
    outView = imref2d(size(fixed_masked));

    % Output video writer
    vw = VideoWriter(outAviPath, 'Grayscale AVI');
    vw.FrameRate = avi.FrameRate;
    open(vw);

    % CSV header
    fid = fopen(outCsvPath, 'wt');
    fprintf(fid, '%s\t%s\t%s\n', 'x_translation,', 'y_translation,', 'rotation');
    fclose(fid);

    for f = 1:no_frames
        this_frame = read(avi, f);
        this_frame = ensure_gray_2d_local(this_frame);

        tform = imregtform(this_frame, fixed_masked, 'rigid', optimizer, metric);
        reg   = imwarp(this_frame, tform, 'OutputView', outView);

        if ~isa(reg, 'uint8')
            reg = im2uint8(reg);
        end

        writeVideo(vw, reg);

        dlmwrite(outCsvPath, [tform.T(3,1), tform.T(3,2), tform.T(1,2)], ...
            'delimiter', ',', '-append');

        fprintf('\n   Registering frame %d of %d ... ', f, no_frames);
    end

    close(vw);
end

function I = ensure_gray_2d_local(I)
    if ndims(I) == 3
        I = I(:,:,1);
        I = squeeze(I);
    elseif ndims(I) == 4
        I = I(:,:,1,1);
        I = squeeze(I);
    end
end