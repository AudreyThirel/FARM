%% Init

clear
clc

assert( ~isempty(which('ft_preprocessing')), 'FieldTrip library not detected. Check your MATLAB paths, or get : https://github.com/fieldtrip/fieldtrip' )
assert( ~isempty(which('farm_rootdir'))    ,      'FARM library not detected. Check your MATLAB paths, or get : https://github.com/benoitberanger/FARM' )

% Initialize FieldTrip
ft_defaults


%% Get file & sequence paramters

sampledata_path = fullfile(farm_rootdir,'sample_dataset');
fname     = 'me3mb3_tr1600_sl54';
fname_eeg = fullfile(sampledata_path, [fname '.eeg' ]);
fname_hdr = fullfile(sampledata_path, [fname '.vhdr']);
fname_mrk = fullfile(sampledata_path, [fname '.vmrk']);

sequence.TR     = 1.6; % in seconds
sequence.nSlice = 54;
sequence.MB     = 3;   % multiband factor
sequence.nVol   = [];  % integer or NaN, if [] it means use all volumes
% Side note : if the fMRI sequence has been manually stopped, the last volume will probably be incomplete.
% But this incomplete volume will stil generate a marker. In this case, you need to define sequence.nVol

MRI_trigger_message = 'R128';

% In this sample dataset, channels are { 'EXT_D' 'FLE_D' 'EXT_G' 'FLE_G' }
% FARM will be performed on all 4 channels, so I create a regex that will fetch them :
channel_regex = 'EXT|FLE';


%% Load data
% Optimal length for a dataset is a bunch of seconds before the start of
% the fmri sequence, and a bunch of seconds after the end of the fmri
% sequence, before any other sequence.

% Read header & events
cfg           = [];
cfg.dataset   = fname_hdr;
raw_event     = ft_read_event (fname_mrk);
event         = farm_change_marker_value(raw_event, MRI_trigger_message, 'V'); % rename volume marker, just for comfort
event         = farm_delete_marker(event, 'Sync On');                          % not useful for FARM, this marker comes from the clock synchronization device

% Load data
data                    = ft_preprocessing(cfg); % load data
data.cfg.event          = event;                 % store events
data.sequence           = sequence;              % store sequence parameters
data.volume_marker_name = 'V';                   % name of the volume event in data.cfg.event

% Some paramters tuning
data.cfg.intermediate_results_overwrite = false; % don't overwrite files
data.cfg.intermediate_results_save      = true;  % write on disk intermediate results
data.cfg.intermediate_results_load      = true;  % if intermediate result file is detected, to not re-do step and load file

% Plot
% ft_databrowser(data.cfg, data)


%% ------------------------------------------------------------------------
%% FARM
% Main FARM functions are below.

% A lot of functions use what is called "regular expressions" (regex). It allows to recognize patterns in strings of characters
% This a powerfull tool, which is common to almost all programing languages. Open some documentation with : doc regular-expressions


%% Check input data
farm_check_data( data )


%% Channel selection
% In your dataset, you might have different nature of signal, for exemple EMG + Accelerometer.
% To perform FARM pipeline only on EMG, you need to select the corresponding channels.

% Select channel for the next processing steps
data = farm_select_channel( data, channel_regex );

fprintf('channel selected : %s \n', data.selected_channels_name{:})


%% Initial HPF @ 30Hz

data = farm_initial_hpf( data );


%% Which channel with greater artifacts ?

data = farm_detect_channel_with_greater_artifact( data );
fprintf('channel with greater artifacts : %s \n', data.label{data.target_channel})


%% Add slice markers : initialize sdur & dtime

data = farm_add_slice_marker( data );


%% Prepare slice candidates for the template generation

data = farm_pick_slice_for_template( data );


%% Optimize slice markers : optimize sdur & dtime
% with an unconstrained non-linear optimization

data = farm_optimize_sdur_dtime( data );


%% Slice correction : compute slice template using best candidates

data = farm_compute_slice_template( data );


%% Volume correction : replace volume-segment (dtime) by 0
% In the FARM article, this method is more advanced, and overwrite less points
% But I didn't succed to code it properly, so I used a "zero filling"

data = farm_volume_correction( data );


%% Revove noise residuals using PCA
% Here, the templates will be substracted, then PCA will be perform on the residuals.
% PCs will bi fitted to theses residials, and substracted.

data = farm_optimize_slice_template_using_PCA( data );


%% Revove noise residuals using ANC
% ANC will remove the last residuals not fitted by the PCs

% Don't know why ANC diverges in this dataset
% Clue : in Niazy et al., they think the filtering diverges when the amplitude is large,
% which is the case for EMG burst compared to EEG.

% data = farm_adaptive_noise_cancellation( data );


%% Remove slice markers
% More convenient

data = farm_remove_slice_marker( data );

%% Plot

% % Raw
farm_plot_carpet     (data, 'EXT_D', 'raw'      , +[30 250])
farm_plot_FFT        (data, 'EXT_D', 'raw'      , +[30 250])
farm_plot_spectrogram(data, 'EXT_D', 'raw'      , +[30 250])

% After processing
farm_plot_carpet     (data, 'EXT_D', 'pca_clean', +[30 250])
farm_plot_FFT        (data, 'EXT_D', 'pca_clean', +[30 250])
farm_plot_spectrogram(data, 'EXT_D', 'pca_clean', +[30 250])


%% Convert clean EMG to regressors

% Use 1 channel : EXT_D
EXT_D         = farm_get_timeseries( data, 'EXT_D', 'pca_clean', +[30 250] );              % (1 x nSamples)
EXT_D_reginfo = farm_emg_regressor ( data,  EXT_D );
farm_plot_regressor(EXT_D_reginfo,'EXT_D')

% Use 1 channel : FLE_D
FLE_D         = farm_get_timeseries( data, 'FLE_D', 'pca_clean', +[30 250] );              % (1 x nSamples)
FLE_D_reginfo = farm_emg_regressor ( data,  FLE_D );
farm_plot_regressor(FLE_D_reginfo,'FLE_D')

% Use 2 channels and combine them : EXT_D + FLE_D
EXTFLE_D         = farm_get_timeseries( data, {'EXT_D','FLE_D'}, 'pca_clean', +[30 250] ); % (2 x nSamples)
EXTFLE_D_reginfo = farm_emg_regressor ( data,  EXTFLE_D, 'mean' );
farm_plot_regressor(EXTFLE_D_reginfo,'EXTFLE_D')


%% Save regressors on disk

farm_save_regressor( data, EXT_D_reginfo,   'EXT_D' )
outname = fullfile(sampledata_path, [fname '_FLE_D']);
farm_save_regressor( data, FLE_D_reginfo,  outname)

