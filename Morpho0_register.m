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

cfg = morpho.Config();

% Local folders (existence)
cfg.ensure("avi_raw");
cfg.ensure("avi_reg");
cfg.ensure("reg_transforms");
cfg.ensure("reference_run");

%% ========================= CACHED REMOTE BASE =========================
cache_file = fullfile(script_dir, 'Morpho0_register_paths.mat');
try
    remote_base = morpho.io.prompt_remote_dir(cache_file, 'Select REMOTE BASE folder (contains ADB** folders)');
catch
    error('No remote base folder selected.');
end
morpho.io.save_cache(cache_file, 'remote_base', remote_base);
morpho.io.logmsg(['Using remote_base: ' char(remote_base)]);

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
    morpho.io.logmsg('Resetting staging folders (reference_run, avi_raw)...');
    if isfolder('reference_run'), rmdir('reference_run','s'); end
    mkdir('reference_run');
    if isfolder('avi_raw'), rmdir('avi_raw','s'); end
    mkdir('avi_raw');

    morpho.io.logmsg('============================================================');
    morpho.io.logmsg(sprintf('ADB %d/%d: %s', iADB, numel(adb_list), adb_name));
    morpho.io.logmsg(['Recon path: ' recon_path]);

    if ~isfolder(recon_path)
        morpho.io.logmsg('Skipping (no recon folder).');
        continue;
    end

    % Find AVI candidates under recon (recursive)
    candidates = dir(fullfile(recon_path,'**','*.avi'));
    if isempty(candidates)
        morpho.io.logmsg('No AVI files found under recon.');
        continue;
    end

    cand_full = fullfile({candidates.folder}, {candidates.name});
    cand_rel  = erase(cand_full, [recon_path filesep]);

    %% ============ Pre-check LOCAL output BEFORE prompting ============
    done_mask = false(size(cand_full));
    for ii = 1:numel(cand_full)
        [~, bname, ext] = fileparts(cand_full{ii});

        expected_local_avi = fullfile('avi_reg', [bname ext]);
        expected_local_csv = fullfile('avi_reg', 'reg_trasforms', [bname '_transform.csv']);

        dA = dir(expected_local_avi);
        dC = dir(expected_local_csv);

        if ~isempty(dA) && dA(1).bytes > 0 && ~isempty(dC) && dC(1).bytes > 0
            done_mask(ii) = true;
        end
    end

    n_done  = sum(done_mask);
    n_total = numel(done_mask);
    n_todo  = n_total - n_done;
    morpho.io.logmsg(sprintf('Local pre-check: %d/%d already done, %d remaining.', n_done, n_total, n_todo));

    if n_todo == 0
        morpho.io.logmsg('All AVIs in this ADB appear complete in local output. Skipping ADB.');
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
        morpho.io.logmsg('No files selected. Moving to next ADB.');
        continue;
    end

    remote_selected = cand_full_todo(idx);
    morpho.io.logmsg(sprintf('Selected %d AVI(s) to process in %s', numel(remote_selected), adb_name));

    %% ========================= ONE REFERENCE PER ADB =========================
    % Reference is the FIRST selected AVI for this ADB
    remote_ref = remote_selected{1};
    [~, ref_base, ref_ext] = fileparts(remote_ref);

    local_ref_src = fullfile('avi_raw', [ref_base ref_ext]);
    ref_dst       = fullfile('reference_run', [adb_name '_REFERENCE' ref_ext]); % stable name per ADB

    % Copy REMOTE reference -> LOCAL avi_raw
    morpho.io.logmsg(['Copy REMOTE reference -> LOCAL (avi_raw): ' remote_ref '  -->  ' local_ref_src]);
    tCopyInRef = tic;
    ok = copyfile(remote_ref, local_ref_src);
    if ~ok
        morpho.io.logmsg('ERROR: Copy REMOTE reference -> LOCAL failed. Skipping this ADB.');
        continue;
    end
    morpho.io.logmsg(sprintf('Reference copy-in finished (%.1fs).', toc(tCopyInRef)));

    % Copy LOCAL reference -> reference_run
    morpho.io.logmsg(['Copy LOCAL reference -> reference_run: ' local_ref_src '  -->  ' ref_dst]);
    tCopyRef = tic;
    ok = copyfile(local_ref_src, ref_dst);
    if ~ok
        morpho.io.logmsg('ERROR: Copy LOCAL reference -> reference_run failed. Skipping this ADB.');
        continue;
    end
    morpho.io.logmsg(sprintf('Reference staging finished (%.1fs).', toc(tCopyRef)));

    % Read reference frame ONCE (shared for this whole ADB)
    reference_frame = cfg.register.reference_frame;
    try
        reference_video = VideoReader(ref_dst);
    catch ME
        morpho.io.logmsg(['ERROR: Cannot open reference AVI: ' ME.message]);
        continue;
    end

    try
        reference_image = read(reference_video, reference_frame);
    catch
        morpho.io.logmsg('WARNING: reference_frame out of range for reference AVI. Using frame 1.');
        reference_image = read(reference_video, 1);
    end
    clear reference_video;

    reference_image = morpho.registration.ensure_gray_2d(reference_image);
    morpho.io.logmsg(['ADB reference set to FIRST selected AVI: ' remote_ref]);

    %% ========================= ONE ginput (mask selection) PER ADB =========================
    low  = min(reference_image(:));
    high = max(reference_image(:));
    imshow(reference_image, [low high]);
    set(gca,'Ydir','normal')
    x = ginput(1);
    close(gcf)

    cutoff_X = round(x(1));
    cutoff_Y = round(x(2));

    morpho.io.logmsg(sprintf('Mask cutoff chosen (per ADB): cutoff_X=%d, cutoff_Y=%d', cutoff_X, cutoff_Y));

    %% ========================= INNER LOOP (ONE AVI AT A TIME) =========================
    for k = 1:numel(remote_selected)

        remote_src = remote_selected{k};
        [~, base_name, ext] = fileparts(remote_src);

        expected_local_avi = fullfile('avi_reg', [base_name ext]);
        expected_local_csv = fullfile('avi_reg', 'reg_trasforms', [base_name '_transform.csv']);

        morpho.io.logmsg('------------------------------------------------------------');
        morpho.io.logmsg(sprintf('File %d/%d in %s', k, numel(remote_selected), adb_name));
        morpho.io.logmsg(['Remote source: ' remote_src]);

        din = dir(remote_src);
        if ~isempty(din)
            morpho.io.logmsg(['Remote size: ' morpho.registration.bytestr(din(1).bytes)]);
        end

        % Per-file skip check (resume-safe)
        dA = dir(expected_local_avi);
        dC = dir(expected_local_csv);
        if ~isempty(dA) && dA(1).bytes > 0 && ~isempty(dC) && dC(1).bytes > 0
            morpho.io.logmsg('SKIP: local outputs already exist (non-empty):');
            morpho.io.logmsg(['  AVI: ' expected_local_avi]);
            morpho.io.logmsg(['  CSV: ' expected_local_csv]);
            continue;
        end

        % Stage/copy THIS AVI into avi_raw
        % FIX: if this is the reference file, it's ALREADY in avi_raw (local_ref_src).
        local_src = fullfile('avi_raw', [base_name ext]);

        if strcmp(remote_src, remote_ref)
            % Reference already staged before inner loop
            if isfile(local_src) && dir(local_src).bytes > 0
                morpho.io.logmsg('Reference file already staged in avi_raw. Skipping duplicate copy.');
            else
                morpho.io.logmsg('WARNING: Expected reference file missing in avi_raw. Re-copying once.');
                ok = copyfile(remote_src, local_src);
                if ~ok
                    morpho.io.logmsg('ERROR: Copy REMOTE->LOCAL failed. Skipping this file.');
                    continue;
                end
            end
        else
            morpho.io.logmsg(['Copy REMOTE -> LOCAL (avi_raw): ' remote_src '  -->  ' local_src]);
            tCopyIn = tic;
            ok = copyfile(remote_src, local_src);
            if ~ok
                morpho.io.logmsg('ERROR: Copy REMOTE->LOCAL failed. Skipping this file.');
                continue;
            end
            morpho.io.logmsg(sprintf('Copy-in finished (%.1fs).', toc(tCopyIn)));
        end

        input_path = local_src;

        %% ========================= PROCESSING (STREAMING, SAME LOGIC) =========================
        morpho.io.logmsg('Starting registration processing (streaming, behavior-matched)...');
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

            % Setup registration
            fixed_masked = morpho.registration.apply_cutoff_mask(reference_image, cutoff_X, cutoff_Y);
            [optimizer, metric] = imregconfig('monomodal');
            outView = imref2d(size(fixed_masked));

            % Output video writer
            vw = VideoWriter(tmp_out_avi, 'Grayscale AVI');
            vw.FrameRate = aviObj.FrameRate;
            open(vw);

            % CSV header
            fid = fopen(tmp_out_csv, 'wt');
            fprintf(fid, '%s,%s,%s\n', 'x_translation', 'y_translation', 'rotation');
            fclose(fid);

            no_frames = morpho.video.frame_count(input_path);

            for f = 1:no_frames
                [tform, reg] = morpho.registration.register_frame( ...
                    read(aviObj, f), fixed_masked, optimizer, metric, outView);
                writeVideo(vw, reg);
                dlmwrite(tmp_out_csv, [tform.T(3,1), tform.T(3,2), tform.T(1,2)], ...
                    'delimiter', ',', '-append');
                fprintf('\n   Registering frame %d of %d ... ', f, no_frames);
            end
            close(vw);

        catch ME
            morpho.io.logmsg(['ERROR during streaming registration: ' ME.message]);
            continue;
        end

        % Move temp outputs into place (overwrite only targets)
        if isfile(out_avi), delete(out_avi); end
        if isfile(out_csv), delete(out_csv); end
        movefile(tmp_out_avi, out_avi, 'f');
        movefile(tmp_out_csv, out_csv, 'f');

        morpho.io.logmsg(sprintf('Processing finished (%.1fs).', toc(tProc)));

        % Validate outputs
        dA = dir(out_avi);
        dC = dir(out_csv);
        if isempty(dA) || dA(1).bytes == 0 || isempty(dC) || dC(1).bytes == 0
            morpho.io.logmsg('WARNING: Output validation failed (missing/empty).');
        else
            morpho.io.logmsg('Done with this file (local outputs written).');
            morpho.io.logmsg(['  AVI: ' out_avi]);
            morpho.io.logmsg(['  CSV: ' out_csv]);
        end

    end

    morpho.io.logmsg(['Finished ADB folder: ' adb_name]);

end

morpho.io.logmsg(sprintf('ALL DONE. Total runtime: %.1f minutes', toc(tAll)/60));
