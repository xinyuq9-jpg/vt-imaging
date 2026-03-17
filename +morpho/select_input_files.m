function selected_files = select_input_files(input_dir, extension)
% SELECT_INPUT_FILES
% Displays files in input_dir and lets user choose which ones to process.
%
% Usage:
%   selected_files = select_input_files('avi_reg', '.avi');
%
% Returns:
%   selected_files → struct array (like dir output)

    if nargin < 2
        extension = '.avi'; % default extension
    end

    % Get file list
    file_list = dir(fullfile(input_dir, ['*' extension]));

    if isempty(file_list)
        error("No files with extension %s found in %s", extension, input_dir);
    end

    % Display files
    fprintf('\nFiles found in %s:\n', input_dir);
    fprintf('-------------------------------------\n');
    for i = 1:length(file_list)
        fprintf('%2d) %s\n', i, file_list(i).name);
    end
    fprintf('-------------------------------------\n');

    % Ask user for selection
    user_input = input( ...
        'Enter file numbers (e.g. 1 3 5), range (e.g. 2:6), or "all": ', ...
        's');

    % Process input
    if strcmpi(user_input, 'all')
        selected_files = file_list;
    else
        try
            indices = eval(['[' user_input ']']); %#ok<EVLC>
        catch
            error('Invalid input format.');
        end

        % Validate indices
        if any(indices < 1) || any(indices > length(file_list))
            error('Selected index out of range.');
        end

        selected_files = file_list(indices);
    end

    fprintf('\nSelected %d file(s).\n\n', length(selected_files));

end
