%% Init

clear
clc

assert( ~isempty(which('ft_preprocessing')), 'FieldTrip library not detected. Check your MATLAB paths, or get : https://github.com/fieldtrip/fieldtrip' )
assert( ~isempty(which('farm_rootdir'))    ,      'FARM library not detected. Check your MATLAB paths, or get : https://github.com/benoitberanger/FARM' )


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


MRI_trigger_message = 'R128';


%% Load data
% Optimal length for a dataset is a bunch of seconds before the start of
% the fmri sequence, and a bunch of seconds after the end of the fmri
% sequence, before any other sequence.

% Read header & events
cfg           = [];
cfg.dataset   = fname_hdr;
raw_event     = ft_read_event (fname_mrk);
event         = farm_change_marker_value(raw_event, MRI_trigger_message, 'V'); % rename volume marker, just for comfort
event         = farm_delete_marker(event, 'Sync On');             % not useful, this marker comes from the clock synchronization device

% Load data
data                    = ft_preprocessing(cfg); % load data
data.cfg.event          = event;                 % store events
data.sequence           = sequence;              % store sequence parameters
data.volume_marker_name = 'V';                   % name of the volume event in data.cfg.event

% Plot
% ft_databrowser(data.cfg, data)


%% ------------------------------------------------------------------------
%% FARM
% Main FARM functions are below.

% A lot of functions use what is called "regular expressions" (regex). It allows to recognize patterns in strings of characters
% This a powerfull tool, which is common to almost all programing languages. Open some documentation with : doc regular-expressions


%% Check input data
farm_check_data( data )


%% Some channel selection
% In your dataset, you might have different nature of signal, for exemple EMG + Accelerometer.
% To perform FARM pipeline only on EMG, you need to select the corresponding channels.

% Select channel for the next processing steps
data = farm_select_channel( data, '.*' );

% Also the channel with the greater artifact will be detected amongst the selected channels
fprintf('channel selected : %s \n', data.selected_channels_name{:})
fprintf('channel with grater artifacts : %s \n', data.label{data.target_channel})

EMG_channels_idx = data.selected_channels_idx;


%% HPF @ 30Hz
% HPF @ 30 Hz removes the artifact due to electrode movement inside the static magnetic field B0
% This filtering step is MANDATORY for EMG, or any electrode with movements in B0
% I have to test/develop to check if FARM actual pipeline is feasable for EEG

data.trial{1}(EMG_channels_idx,:) = farm.filter(data.trial{1}(EMG_channels_idx,:), data.fsample, +30); % instead of default=6 because unstable


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

% Raw
farm_plot_carpet     (data, 1, 'raw'      , +[30 250])
farm_plot_FFT        (data, 1, 'raw'      , +[30 250])
farm_plot_spectrogram(data, 1, 'raw'      , +[30 250])

% After processing
farm_plot_carpet     (data, 1, 'pca_clean', +[30 250])
farm_plot_FFT        (data, 1, 'pca_clean', +[30 250])
farm_plot_spectrogram(data, 1, 'pca_clean', +[30 250])
