function data = farm_optimize_sdur_dtime( data )
% FARM_OPTIMIZE_SDUR_DTIME will use the previously computed sdur_v & dtime_v,
% as initializing point to optimize the final sdur & dtime
%
% Ref : Van der Meer, J. N., Tijssen, M. A. J., Bour, L. J., van Rootselaar, A. F., & Nederveen, A. J. (2010).
%       Robust EMG–fMRI artifact reduction for motion (FARM).
%       Clinical Neurophysiology, 121(5), 766–776.
%       https://doi.org/10.1016/j.clinph.2009.12.035
%

if nargin==0, help(mfilename); return; end

%% Paramters

hpf          = 250; % hertz
interpfactor = 10;  % interpolation factor : upsampling
% Shortcuts
sequence           = data.sequence;
volume_marker_name = data.volume_marker_name;


%% Retrive some variables already computed
% computed by farm_add_slice_marker

sdur_v  = data.sdur_v;
dtime_v = data.dtime_v;

%% Define some other variables

volume_event = ft_filter_event(data.cfg.event,'value',volume_marker_name);

onset_first_volume = volume_event(1).sample;
% onset_last_volume  = volume_event(end).sample + data.fsample*sequence.TR + round(mean(sdur_v)); % last marker onset + 1 TR + 1 sdur


%% Prepare time serie we will be working on

data = farm_detect_channel_with_greater_artifact( data ); % simple routine, defines data.target_channel

% Remove low frequencies, including EMG, we only need the gradients
hpf_target_channel = ft_preproc_highpassfilter(...
    data.trial{1}(data.target_channel,:), ...
    data.fsample                   , ...
    hpf                            );

% hpf_target_channel = hpf_target_channel(onset_first_volume : onset_last_volume);
% new_data_time      = data.time{1}(onset_first_volume) : 1/(data.fsample*interpfactor) : data.time{1}(onset_last_volume);
new_data_time      = data.time{1}(1) : 1/(data.fsample*interpfactor) : data.time{1}(end);


% Upsample, using matlab builtin function 'interp1'. 'pchip' = shape-preserving piecewise cubic interpolation
% Note : ft_resampledata uses the same function 'interp1'
signal = interp1( data.time{1}, hpf_target_channel, new_data_time, 'pchip' );
signal = [ signal zeros(1, length(signal)) ]; % padding

% 'signal' is now an upsmapled time serie, containing only the gradients artifacts, no EMG
% We will use this 'signal' to optimize the sdur and dtime paramters


%% Optimization
% sdur & dtime precision greatly impacts the quality of the template correction.
% The article presents a strategy to determine sdur & dtime with high precision.
% How ? use unconstrained nonlinear optimization, where the cost function is similar
% to the Sum of Variance SV ( eq(2) ), but computed for all volumes, not volume-per-volume.

% Initialization of parameters to optimize
init_param    = [mean(sdur_v) mean(dtime_v)] / data.fsample; % we need a vector of paramters in order to use 'fminsearch'
% sdur & dtime are expressed in seconds, to avoid sampling mismatch

% cost function constant variables
const                    = struct;
const.onset_first_volume = onset_first_volume*interpfactor;
const.signal             = signal;
const.fsample            = data.fsample*interpfactor;
const.nVol               = length(volume_event);
if isfield(sequence,'MB')
    const.nSlice         = sequence.nSlice / sequence.MB;
else
    const.nSlice         = sequence.nSlice;
end
const.isvolume           = data.slice_info.isvolume;
const.good_slice_idx     = data.slice_info.good_slice_idx;

% Unconstrained nonlinear optimization using Nelder-Mead algorithm
fprintf('[%s]: Starting sdur & dtime optimization \n', mfilename)


% Initializiation points
%-----------------------
% In our case, we have a vector of 2 paramters x0 = [ sdur dtime ],
% but for the algorithm, we need to create 3 starting point (a simplex, in our case a triangle),
% and the algorithm will look and around this triangle, and update it's position & dimension
% I choose to start with points that are a few µs next to sdur (and follow the rule dtime = TR - nSlice x sdur)
sdur = init_param(1);
x_init = [
    sdur      , sequence.TR-const.nSlice*(sdur     ) % initial sdur
    sdur+1e-5 , sequence.TR-const.nSlice*(sdur+1e-5) % sdur + 1ms
    sdur-1e-5 , sequence.TR-const.nSlice*(sdur-1e-5) % sdur - 1ms
    
    ]; % reminder : in seconds

% Go !
tic
x_opt = farm_nelder_mead ( x_init,  @(param,speed) farm_cost_function(param, speed, const) );
toc
final_param = x_opt;

fprintf('initial   sdur | dtime : %fµs %fµs - initial TR : %fs \n',  init_param(1)*1e6,  init_param(2)*1e6, const.nSlice*init_param (1) + init_param (2) )
fprintf('final     sdur | dtime : %fµs %fµs - final   TR : %fs \n', final_param(1)*1e6, final_param(2)*1e6, const.nSlice*final_param(1) + final_param(2))
fprintf('variation sdur | dtime : %fµs %fµs \n', (final_param(1)-init_param(1))*1e6, (final_param(2)-init_param(2))*1e6)

sdur  = final_param(1);
dtime = final_param(2);

data.sdur  = sdur;
data.dtime = dtime;


%% Store new slice onsets, using original fsample
% Note : they are stored as float

nVol     = const.nVol;
nSlice   = const.nSlice;
isvolume = const.isvolume;
fsample  = const.fsample;

slice_onset = zeros( nSlice * nVol, 1 );
round_error = zeros( nSlice * nVol, 1 );

for iSlice = 1 : nSlice * nVol
    
    iVolume = sum( isvolume(1:iSlice) );
    
    slice_onset(iSlice) = onset_first_volume + ( ( iSlice - 1 ) * sdur + (iVolume - 1) * dtime ) * fsample;
    round_error(iSlice) = slice_onset(iSlice) - round(slice_onset(iSlice));
    
end

data.slice_onset = slice_onset;
data.round_error = round_error;

data.interpfactor = interpfactor;


end % function
