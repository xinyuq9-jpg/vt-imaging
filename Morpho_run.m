function Morpho_run(opts)
%MORPHO_RUN Run the VT-imaging pipeline (stages 0-5).
%   Morpho_run()              — prompt which stages to run
%   Morpho_run(stages=3:5)    — run stages 3 to 5
%   Morpho_run(stages=[1 3])  — run stages 1 and 3
    arguments
        opts.stages (1,:) double = double.empty
    end

    stage_names = ["register", "masking", "subsetter", "QA", "outliner", "finaliser"];

    if isempty(opts.stages)
        labels = arrayfun(@(i) sprintf("%d: %s", i, stage_names(i+1)), 0:5);
        [sel, ok] = listdlg( ...
            'ListString',       labels, ...
            'SelectionMode',    'multiple', ...
            'InitialValue',     1:6, ...
            'ListSize',         [220 160], ...
            'Name',             'Morpho Pipeline', ...
            'PromptString',     'Select stages to run:');
        if ~ok
            fprintf('Pipeline cancelled.\n');
            return;
        end
        opts.stages = sel - 1;  % listdlg returns 1-based indices
    end
    stage_scripts = [ ...
        "Morpho0_register", ...
        "Morpho1_masking", ...
        "Morpho2_subsetter", ...
        "Morpho3_QA", ...
        "Morpho4_outliner", ...
        "Morpho5_finaliser"];

    for stage_num = opts.stages
        idx = stage_num + 1;  % 0-based stage -> 1-based index
        if idx < 1 || idx > numel(stage_scripts)
            warning("Skipping unknown stage %d", stage_num);
            continue;
        end

        fprintf('\n========================================\n');
        fprintf('=== Stage %d: %s ===\n', stage_num, stage_names(idx));
        fprintf('========================================\n\n');

        % Note: run() executes scripts in this function's workspace, so
        % variables persist between stages. Each stage reinitializes its own
        % state via morpho.Config(), so this is safe in practice.
        run(stage_scripts(idx));
    end

    fprintf('\n=== Pipeline complete ===\n');
end
