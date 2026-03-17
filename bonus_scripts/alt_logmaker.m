%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Michel Belyk, Edge Hill University 
% March 2022
% belykm@gmail.com
% reduce rtmri dataset to analysable frames
% takes input from Morpho_masking.m and Morpho_sounding.praat
% Resave subset of frames to output_mat_dir/*_sub.mat
% N.B. log_dir must contain one logfile per run with matching root names
%       e.g. morph/mat/example_run_out.mat matched to logs/example_run.csv
% Made for R2019b on macOS 10.15.7
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%this  script provides an  alternative  method for  making logfiles as
%inputs to morpho2_subsetter.m
%ideally  we would have in scanner audio as a means to  identify periods
%of  vocalisation for  further analysis.  But if these  are lacking or not
%readily syncronised with the rtMRI data then this  approach provides  a
%way forward
%Open each  run, plots the  number of pixels classified as vocal tract,
%invites  user to identify a cutoff  threshold. Frames with  VT pixel
%counts below this level are discarded
%this script produces logfiles only, use morpho2_subsetter.m to execute
%frame  removal

%%%%%%%%%%%%%%%%%%%%%%%%
%%%manage directories%%%
%%%%%%%%%%%%%%%%%%%%%%%%
base_dir = 'morph';
input_dir = fullfile(base_dir,'mat');
output_log_dir = 'logs/'; %where should they go?

%make folder if doesn't yet exist
if isfolder(output_log_dir) == 0; mkdir(output_log_dir); end %make if doesn't exist

%read subset data
list_input_files = dir([input_dir '/*.mat']); %lisat all mat files

for iFile = 1:length(list_input_files) %loop through video files
    input_rootname = list_input_files(iFile).name(1:end-8); %remove file enxtension and _skel tag
    disp("Processing: " + input_rootname);
    
    %read vodeo
    input_filename = fullfile(input_dir,list_input_files(iFile).name);
    load(input_filename);  
    vt_input = vt_output;  %output from previous stages is input here
    no_frames = size(vt_input, 3);
    
    %plot distribution of pixel counts
    vt_count = squeeze(sum(vt_input, 1:2));
    vt_count_max = max(vt_count);
    vt_count_density=ksdensity(vt_count, 0:max(vt_count_max)); %get density for finding local min
    index_of_mins = find(islocalmin(vt_count_density));  %find local minimal
    
    %%%plots
    tiledlayout(2,1)

    % pixel counts
    nexttile
    plot(vt_count);
    title('Count')
    xlabel('Frame  Number') 
    ylabel('Pixel Count')

    % Bottom plot
    nexttile
    plot(vt_count_density);
    for i = 1:numel(index_of_mins)   %mark local minima
        this_min =   index_of_mins(i);
        xline(this_min); 
    end
    title('Density')
    xlabel('Pixel  Count') 
    ylabel('Density')

    %select cutoff
    prompt = {['Consult the  plots to select cutoff (in percentile of pixels).' newline 'Frames with fewer than this many vocal tract pixels will me removed.'  newline  'Default is a local  minimum.' newline  'N.B. This  may turn out to  be too aggressive.']};
    dlgtitle = 'Input';
    dims = [1 70];
    definput = {int2str(index_of_mins(1))}; %default to current settings
    cutoff = inputdlg(prompt,dlgtitle,dims,definput);
    cutoff  =  str2num(cutoff{1});
    
    %filter VT frames with low pixel counts
    %here convert to pixelssomehow
    which_keep = find(vt_count>cutoff);
    no_kept = size(which_keep,1);
    disp(['Keeping ' int2str(size(which_keep, 1)) ' frames'])
    vt_output = vt_input(:,:,which_keep);
     
    %save off
    %save long format logs.  each frame  as   one  segment
    log_filename = char(fullfile(output_log_dir,string(input_rootname) + '.csv'));
    segment_label = repmat("Exceeds_high_pixel_count_filter", 1,no_kept);
    segment_number = 1:no_kept;
    
    log_table = table(segment_number',segment_label',which_keep,which_keep);
    log_table.Properties.VariableNames = {'SEGMENT_NUMBER','SEGMENT_LABEL','ONSET','OFFSET'};
    writetable(log_table, log_filename, 'Delimiter', ',')
end  %end file loop