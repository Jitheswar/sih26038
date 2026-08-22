function result = runDistrictSimulation(configOrPath, varargin)
%RUNDISTRICTSIMULATION Run one headless SimEvents capacity simulation.
%   RESULT = runDistrictSimulation(CONFIG, Name, Value, ...) loads named
%   parameters into the district_model workspace and runs the .slx model.

if nargin == 0 || isempty(configOrPath)
    configOrPath = fullfile(fileparts(mfilename('fullpath')), 'district_config.json');
end
config = validateDistrictConfig(configOrPath);
config = applyOverrides(config, varargin{:});
config = validateDistrictConfig(config);
overrideNames = lower(string(varargin(1:2:end)));
if ismember("annualscreeningvolume", overrideNames) && ...
        ~ismember("arrivalrate", overrideNames)
    % Recompute the rate only when the caller changes the target annual
    % volume without giving an explicit rate. A SimulationDurationDays
    % override alone (or an explicit ArrivalRate override) preserves
    % whatever rate is already configured, which is what the capacity
    % sweeps need: a short, wall-clock-cheap sample of steady-state
    % behaviour at a fixed annual pace, not a rescaled rate.
    config.arrivalRate = config.annualScreeningVolume / ...
        (config.simulationDurationDays * 86400);
end
config = validateDistrictConfig(config);

rng(config.randomSeed, 'twister');
simulinkDirectory = fileparts(mfilename('fullpath'));
addpath(simulinkDirectory);
modelPath = buildDistrictModel(false);
modelName = erase(modelPath, '.slx');
[~, modelName] = fileparts(modelName);

if bdIsLoaded(modelName)
    close_system(modelName, 0);
end
load_system(modelPath);
modelWorkspace = get_param(modelName, 'ModelWorkspace');
assignScalarConfiguration(modelWorkspace, config);
set_param(modelName, 'StopTime', num2str(config.simulationDurationDays * 86400, 17));

districtSimulationLog('reset');
districtNextArrival('reset');
cleanupModel = onCleanup(@() closeModel(modelName));

sim(modelName, 'StopTime', num2str(config.simulationDurationDays * 86400, 17));
eventState = districtSimulationLog('snapshot', config.simulationDurationDays * 86400);

phcSignal = queueSignal(eventState, 1, config.simulationDurationDays * 86400);
uploadSignal = queueSignal(eventState, 2, config.simulationDurationDays * 86400);
graderSignal = queueSignal(eventState, 3, config.simulationDurationDays * 86400);
turnaround = eventState.turnaroundSeconds(1:eventState.turnaroundCount).';
targetSeconds = config.turnaroundTargetHours * 3600;

result = struct();
result.configuration = config;
result.randomSeed = config.randomSeed;
result.simulationDurationDays = config.simulationDurationDays;
result.totalEntitiesGenerated = eventState.totalGenerated;
result.totalCompleted = eventState.totalCompleted;
result.totalAutoCleared = eventState.totalAutoCleared;
result.totalReferred = eventState.totalReferred;
result.totalEscalated = eventState.totalEscalated;
result.totalDeferralEscalations = eventState.totalDeferralEscalations;
result.totalRecaptureAttempts = eventState.totalRecaptureAttempts;
result.totalCaptureAttempts = eventState.totalCaptureAttempts;
result.failedCaptureAttempts = eventState.failedCaptureAttempts;
result.turnaroundTimeSeconds = turnaround;
result.meanTurnaroundTimeHours = safeMean(turnaround) / 3600;
result.p95TurnaroundTimeHours = safePercentile(turnaround, 95) / 3600;
result.graderHours = sum(eventState.graderServiceSeconds(1:eventState.turnaroundCount)) / 3600;
result.maximumPHCQueueLength = eventState.queueMaximum(1);
result.meanPHCQueueLength = eventState.queueArea(1) / ...
    (config.simulationDurationDays * 86400);
result.maximumUploadQueueLength = eventState.queueMaximum(2);
result.meanUploadQueueLength = eventState.queueArea(2) / ...
    (config.simulationDurationDays * 86400);
result.maximumGraderQueueLength = eventState.queueMaximum(3);
result.meanGraderQueueLength = eventState.queueArea(3) / ...
    (config.simulationDurationDays * 86400);
result.maximumQueueLength = max([result.maximumPHCQueueLength, ...
    result.maximumUploadQueueLength, result.maximumGraderQueueLength]);
result.meanQueueLength = mean([result.meanPHCQueueLength, ...
    result.meanUploadQueueLength, result.meanGraderQueueLength]);
result.graderUtilisation = min(1, result.graderHours / ...
    (config.numberOfGraders * config.simulationDurationDays * 24));
utilSignal = utilisationSignal(result.graderUtilisation, ...
    config.simulationDurationDays * 86400);
result.uploadQueueLength = result.maximumUploadQueueLength;
result.percentMeetingTurnaroundTarget = 100 * mean(turnaround <= targetSeconds);
if isempty(turnaround)
    result.percentMeetingTurnaroundTarget = 0;
end

result.resultsDirectory = saveRunArtifacts(result, phcSignal, uploadSignal, ...
    graderSignal, utilSignal);
clear cleanupModel
end

function config = applyOverrides(config, varargin)
if mod(numel(varargin), 2) ~= 0
    error('district:InvalidOverrides', 'Overrides must be name-value pairs.');
end

for i = 1:2:numel(varargin)
    name = char(varargin{i});
    field = lower(regexprep(name, '[^a-zA-Z0-9]', ''));
    switch field
        case 'annualscreeningvolume'
            config.annualScreeningVolume = varargin{i + 1};
        case 'simulationdurationdays'
            config.simulationDurationDays = varargin{i + 1};
        case 'numberofphcs'
            config.numberOfPHCs = varargin{i + 1};
        case 'arrivalmode'
            config.arrivalMode = varargin{i + 1};
        case 'numberofgraders'
            config.numberOfGraders = varargin{i + 1};
        case 'modelsensitivity'
            config.modelSensitivity = varargin{i + 1};
        case 'modelspecificity'
            config.modelSpecificity = varargin{i + 1};
        case 'deferralrate'
            config.deferralRate = varargin{i + 1};
        case 'bandwidthmegabitspersecond'
            config.bandwidthMegabitsPerSecond = varargin{i + 1};
        case 'connectivityavailability'
            config.connectivityAvailability = varargin{i + 1};
        case 'qualitygateenabled'
            config.qualityGateEnabled = varargin{i + 1};
        case 'randomseed'
            config.randomSeed = varargin{i + 1};
        case 'arrivalrate'
            config.arrivalRate = varargin{i + 1};
        otherwise
            error('district:UnknownOverride', 'Unknown configuration override: %s.', name);
    end
end
end

function assignScalarConfiguration(modelWorkspace, config)
assignin(modelWorkspace, 'districtAnnualScreeningVolume', config.annualScreeningVolume);
assignin(modelWorkspace, 'districtSimulationDurationDays', config.simulationDurationDays);
assignin(modelWorkspace, 'districtNumberOfPHCs', config.numberOfPHCs);
assignin(modelWorkspace, 'districtArrivalRate', config.arrivalRate);
assignin(modelWorkspace, 'districtArrivalModeCode', ...
    double(~strcmpi(char(config.arrivalMode), 'smooth')));
assignin(modelWorkspace, 'districtCampBurstMultiplier', config.campBurstMultiplier);
assignin(modelWorkspace, 'districtCaptureTimeSeconds', config.captureTimeSeconds);
assignin(modelWorkspace, 'districtQualityGateTimeSeconds', config.qualityGateTimeSeconds);
assignin(modelWorkspace, 'districtQualityRejectionRate', config.qualityRejectionRate);
assignin(modelWorkspace, 'districtMaximumRecaptureAttempts', config.maximumRecaptureAttempts);
assignin(modelWorkspace, 'districtQualityGateEnabled', double(config.qualityGateEnabled));
assignin(modelWorkspace, 'districtInferenceTimeSeconds', config.inferenceTimeSeconds);
assignin(modelWorkspace, 'districtImageSizeMegabytes', config.imageSizeMegabytes);
assignin(modelWorkspace, 'districtBandwidthMegabitsPerSecond', config.bandwidthMegabitsPerSecond);
assignin(modelWorkspace, 'districtConnectivityAvailability', config.connectivityAvailability);
assignin(modelWorkspace, 'districtConnectivityCycleSeconds', config.connectivityCycleSeconds);
assignin(modelWorkspace, 'districtNumberOfGraders', config.numberOfGraders);
assignin(modelWorkspace, 'districtGraderServiceTimeSeconds', config.graderServiceTimeSeconds);
assignin(modelWorkspace, 'districtModelSensitivity', config.modelSensitivity);
assignin(modelWorkspace, 'districtModelSpecificity', config.modelSpecificity);
assignin(modelWorkspace, 'districtDeferralRate', config.deferralRate);
assignin(modelWorkspace, 'districtReferablePrevalence', config.referablePrevalence);
end

function values = signalValues(signal)
values = [];
if isstruct(signal) && isfield(signal, 'signals') && ...
        isfield(signal.signals, 'values')
    values = double(signal.signals.values);
elseif isnumeric(signal)
    values = double(signal);
end
end

function value = safeMean(values)
if isempty(values)
    value = NaN;
else
    value = mean(values);
end
end

function value = safePercentile(values, percentile)
if isempty(values)
    value = NaN;
else
    sorted = sort(values);
    index = max(1, min(numel(sorted), ceil(percentile / 100 * numel(sorted))));
    value = sorted(index);
end
end

function directory = saveRunArtifacts(result, phcSignal, uploadSignal, graderSignal, utilSignal)
root = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'results');
if ~isfolder(root)
    mkdir(root);
end
stamp = datestr(now, 'yyyymmdd_HHMMSS_FFF');
directory = fullfile(root, stamp);
suffix = 0;
while isfolder(directory)
    suffix = suffix + 1;
    directory = fullfile(root, sprintf('%s_%02d', stamp, suffix));
end
mkdir(directory);

configText = jsonencode(result.configuration, 'PrettyPrint', true);
writeText(fullfile(directory, 'config.json'), configText);
save(fullfile(directory, 'simulation_result.mat'), 'result', ...
    'phcSignal', 'uploadSignal', 'graderSignal', 'utilSignal');
summary = table(result.totalEntitiesGenerated, result.totalCompleted, ...
    result.totalAutoCleared, result.totalReferred, result.totalEscalated, ...
    result.totalRecaptureAttempts, result.meanTurnaroundTimeHours, ...
    result.p95TurnaroundTimeHours, result.maximumQueueLength, ...
    result.graderUtilisation, result.uploadQueueLength, ...
    result.percentMeetingTurnaroundTarget, 'VariableNames', ...
    {'totalEntitiesGenerated', 'totalCompleted', 'totalAutoCleared', ...
    'totalReferred', 'totalEscalated', 'totalRecaptureAttempts', ...
    'meanTurnaroundTimeHours', 'p95TurnaroundTimeHours', ...
    'maximumQueueLength', 'graderUtilisation', 'uploadQueueLength', ...
    'percentMeetingTurnaroundTarget'});
writetable(summary, fullfile(directory, 'summary.csv'));
savePlots(result, phcSignal, uploadSignal, graderSignal, utilSignal, directory);
end

function savePlots(result, phcSignal, uploadSignal, graderSignal, utilSignal, directory)
fig = figure('Visible', 'off');
plotQueue(phcSignal, 'PHC capture queue');
hold on;
plotQueue(uploadSignal, 'Upload queue');
plotQueue(graderSignal, 'Human grader queue');
xlabel('Simulation time (s)');
ylabel('Entities in queue');
legend('Location', 'best');
title('Queue length over time');
exportgraphics(fig, fullfile(directory, 'queue_length_over_time.png'));
close(fig);

fig = figure('Visible', 'off');
plotSignal(utilSignal, 'Grader utilisation');
xlabel('Simulation time (s)');
ylabel('Utilisation');
ylim([0 1.05]);
title('Grader utilisation');
exportgraphics(fig, fullfile(directory, 'grader_utilisation.png'));
close(fig);

fig = figure('Visible', 'off');
if isempty(result.turnaroundTimeSeconds)
    text(0.1, 0.5, 'No completed reports in the simulation horizon');
else
    histogram(result.turnaroundTimeSeconds / 3600, 30);
end
xlabel('Turnaround time (hours)');
ylabel('Completed reports');
title('Turnaround-time distribution');
exportgraphics(fig, fullfile(directory, 'turnaround_time_distribution.png'));
close(fig);
end

function plotQueue(signal, label)
plotSignal(signal, label);
end

function plotSignal(signal, label)
values = signalValues(signal);
if isstruct(signal) && isfield(signal, 'time') && ~isempty(values)
    plot(signal.time, values, 'DisplayName', label);
elseif ~isempty(values)
    plot(values, 'DisplayName', label);
else
    plot(NaN, NaN, 'DisplayName', label);
end
end

function writeText(path, textValue)
fid = fopen(path, 'w');
if fid < 0
    error('district:CannotWriteResults', 'Cannot write %s.', path);
end
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, textValue, 'char');
end

function closeModel(modelName)
if bdIsLoaded(modelName)
    close_system(modelName, 0);
end
end

function signal = queueSignal(state, queueId, stopTime)
count = state.queueTraceCount(queueId);
signal = struct('time', state.queueTraceTime(queueId, 1:count).', ...
    'signals', struct('values', state.queueTraceValue(queueId, 1:count).'));
if isempty(signal.time)
    signal.time = [0; stopTime];
    signal.signals.values = [0; 0];
end
end

function signal = utilisationSignal(value, stopTime)
signal = struct('time', [0; stopTime], ...
    'signals', struct('values', [0; value]));
end
