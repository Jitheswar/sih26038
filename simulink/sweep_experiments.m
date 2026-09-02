function summary = sweep_experiments(configPath, varargin)
%SWEEP_EXPERIMENTS Run capacity-planning experiments E1-E6 (SS9.5).
%   SUMMARY = sweep_experiments(CONFIGPATH) runs all six experiments
%   against the district SimEvents model and returns a struct with one
%   field per experiment (E1..E6), each holding the sweep table and the
%   dated results directory it was written to.
%
%   SUMMARY = sweep_experiments(CONFIGPATH, 'Experiments', {'E1','E4'})
%   runs only the named experiments.
%
%   Every sweep point is a short, wall-clock-cheap window
%   (windowDays, below) simulated at the FULL configured annual arrival
%   rate: setting only SimulationDurationDays (never AnnualScreeningVolume)
%   in the call to runDistrictSimulation preserves that rate (see the
%   comment in runDistrictSimulation.m). This yields steady-state queueing
%   statistics without paying the wall-clock cost of a full 365-day,
%   100,000-entity discrete-event run for every sweep point. Reported
%   annual figures (grader-hours/year, minimum graders for the configured
%   annual volume) are computed by scaling that steady-state sample, and
%   this scaling is stated alongside every result, per docs/simulation_assumptions.md.

if nargin < 1 || isempty(configPath)
    configPath = fullfile(fileparts(mfilename('fullpath')), 'district_config.json');
end
baseConfig = validateDistrictConfig(configPath);
rng(baseConfig.randomSeed, 'twister');

parser = inputParser;
parser.addParameter('Experiments', {'E1', 'E2', 'E3', 'E4', 'E5', 'E6'});
parser.addParameter('WindowDays', 14);
parser.parse(varargin{:});
opts = parser.Results;
windowDays = opts.WindowDays;

summary = struct();
if ismember('E1', opts.Experiments)
    summary.E1 = runE1MinimumGraders(configPath, baseConfig, windowDays);
end
if ismember('E2', opts.Experiments)
    summary.E2 = runE2SensitivityVersusWorkload(configPath, baseConfig, windowDays);
end
if ismember('E3', opts.Experiments)
    summary.E3 = runE3DeferralThreshold(configPath, baseConfig, windowDays);
end
if ismember('E4', opts.Experiments)
    summary.E4 = runE4Bandwidth(configPath, baseConfig, windowDays);
end
if ismember('E5', opts.Experiments)
    summary.E5 = runE5QualityGate(configPath, baseConfig, windowDays);
end
if ismember('E6', opts.Experiments)
    summary.E6 = runE6ArrivalPattern(configPath, baseConfig, windowDays);
end
end

% ------------------------------------------------------------------
% E1: minimum grader count at the configured annual volume, plus a
% minimum-graders-versus-annual-volume curve for a small set of volumes.
% ------------------------------------------------------------------
function out = runE1MinimumGraders(configPath, baseConfig, windowDays)
graderCandidates = 1:12;
[rows, minGradersAtBaseVolume] = localSearchMinimumGraders( ...
    configPath, baseConfig.annualScreeningVolume, windowDays, graderCandidates);
resultsDir = localNewExperimentDirectory('E1_minimum_grader_count');
writetable(rows, fullfile(resultsDir, 'grader_sweep.csv'));

fig = figure('Visible', 'off');
plot(rows.numberOfGraders, rows.percentMeetingTurnaroundTarget, '-o');
hold on;
yline(95, '--', '95% target');
xlabel('Number of graders');
ylabel('Percent of reports within turnaround target');
title(sprintf('E1: grader sweep at %d screenings/year', ...
    baseConfig.annualScreeningVolume));
exportgraphics(fig, fullfile(resultsDir, 'grader_utilisation.png'));
close(fig);

volumeCandidates = [50000, 100000, 150000];
volumeRows = table();
for i = 1:numel(volumeCandidates)
    volume = volumeCandidates(i);
    if volume == baseConfig.annualScreeningVolume
        minGraders = minGradersAtBaseVolume;
    else
        [~, minGraders] = localSearchMinimumGraders( ...
            configPath, volume, windowDays, graderCandidates);
    end
    volumeRows = [volumeRows; table(volume, minGraders, ...
        'VariableNames', {'annualScreeningVolume', 'minimumGraders'})]; %#ok<AGROW>
end
writetable(volumeRows, fullfile(resultsDir, 'minimum_graders_versus_volume.csv'));

fig = figure('Visible', 'off');
plot(volumeRows.annualScreeningVolume, volumeRows.minimumGraders, '-o');
xlabel('Annual screening volume');
ylabel('Minimum graders meeting turnaround target');
title('E1: minimum graders versus annual volume');
exportgraphics(fig, fullfile(resultsDir, 'minimum_graders_versus_volume.png'));
close(fig);

localWriteExperimentConfig(resultsDir, baseConfig, ...
    struct('graderCandidates', graderCandidates, ...
    'volumeCandidates', volumeCandidates, 'windowDays', windowDays));

out = struct('table', rows, 'minimumGraders', minGradersAtBaseVolume, ...
    'volumeTable', volumeRows, 'resultsDirectory', resultsDir);
fprintf('E1: minimum graders at %d/year = %d\n', ...
    baseConfig.annualScreeningVolume, minGradersAtBaseVolume);
end

function [rows, minGraders] = localSearchMinimumGraders( ...
    configPath, annualVolume, windowDays, graderCandidates)
% Holds the arrival rate at annualVolume/365 days regardless of the
% shorter windowDays actually simulated (see the file header comment),
% by passing an explicit ArrivalRate override instead of
% AnnualScreeningVolume, which would otherwise be recomputed against the
% short window and inflate the rate.
annualPeriodSeconds = 365 * 86400;
arrivalRate = annualVolume / annualPeriodSeconds;
rows = table();
minGraders = NaN;
for i = 1:numel(graderCandidates)
    graders = graderCandidates(i);
    result = runDistrictSimulation(configPath, ...
        'ArrivalRate', arrivalRate, ...
        'SimulationDurationDays', windowDays, ...
        'NumberOfGraders', graders);
    row = localSummaryRow(result);
    row.numberOfGraders = graders;
    row.representedAnnualVolume = annualVolume;
    rows = [rows; row]; %#ok<AGROW>
    if isnan(minGraders) && result.percentMeetingTurnaroundTarget >= 95
        minGraders = graders;
        break
    end
end
if isnan(minGraders) && ~isempty(rows)
    minGraders = rows.numberOfGraders(end);
end
end

% ------------------------------------------------------------------
% E2: sensitivity versus grader workload. A generous grader count keeps
% the review queue from being the bottleneck, so grader-hours reflect
% referral volume, not queueing artefacts.
% ------------------------------------------------------------------
function out = runE2SensitivityVersusWorkload(configPath, baseConfig, windowDays)
sensitivities = [0.80, 0.85, 0.90, 0.93, 0.95, 0.97];
amplGraders = 12;
rows = table();
for i = 1:numel(sensitivities)
    sensitivity = sensitivities(i);
    result = runDistrictSimulation(configPath, ...
        'SimulationDurationDays', windowDays, ...
        'NumberOfGraders', amplGraders, ...
        'ModelSensitivity', sensitivity);
    row = localSummaryRow(result);
    row.modelSensitivity = sensitivity;
    row.annualGraderHours = result.graderHours * (365 / windowDays);
    expectedPrevalent = baseConfig.referablePrevalence;
    expectedFalsePositiveRate = (1 - baseConfig.modelSpecificity) * ...
        (1 - expectedPrevalent);
    row.analyticFalsePositiveWorkloadFraction = expectedFalsePositiveRate;
    rows = [rows; row]; %#ok<AGROW>
end
resultsDir = localNewExperimentDirectory('E2_sensitivity_versus_workload');
writetable(rows, fullfile(resultsDir, 'sensitivity_sweep.csv'));

fig = figure('Visible', 'off');
plot(rows.modelSensitivity, rows.annualGraderHours, '-o');
xlabel('AI sensitivity (referable DR)');
ylabel('Annualised grader-hours (extrapolated)');
title('E2: sensitivity versus grader workload');
exportgraphics(fig, fullfile(resultsDir, 'sensitivity_versus_grader_hours.png'));
close(fig);

localWriteExperimentConfig(resultsDir, baseConfig, ...
    struct('sensitivities', sensitivities, 'numberOfGraders', amplGraders, ...
    'windowDays', windowDays));
out = struct('table', rows, 'resultsDirectory', resultsDir);
end

% ------------------------------------------------------------------
% E3: deferral threshold sweep.
% ------------------------------------------------------------------
function out = runE3DeferralThreshold(configPath, baseConfig, windowDays)
% The scenario grid stops at 0.30 and the pipeline that ships defers well
% past it, so sweeping the grid alone would report the human-review cost of
% a system nobody runs. The measured rate is appended as its own sweep
% point and is read from measuredDeferralRate in the configuration rather
% than typed here, so it follows the shipped pipeline instead of going
% stale behind it (see docs/simulation_assumptions.md).
scenarioRates = [0.02, 0.05, 0.10, 0.15, 0.20, 0.30];
measuredRate = [];
if isfield(baseConfig, 'measuredDeferralRate')
    measuredRate = baseConfig.measuredDeferralRate;
end
deferralRates = unique([scenarioRates, measuredRate]);
generousGraders = 12;
rows = table();
for i = 1:numel(deferralRates)
    deferralRate = deferralRates(i);
    result = runDistrictSimulation(configPath, ...
        'SimulationDurationDays', windowDays, ...
        'NumberOfGraders', generousGraders, ...
        'DeferralRate', deferralRate);
    row = localSummaryRow(result);
    row.deferralRate = deferralRate;
    row.isMeasuredPipelineRate = ~isempty(measuredRate) && ...
        deferralRate == measuredRate;
    row.autonomousCoveragePercent = 100 * result.totalAutoCleared / ...
        max(1, result.totalEntitiesGenerated);
    row.humanReviewVolume = result.totalReferred + result.totalEscalated;
    row.safetyEscalationVolume = result.totalDeferralEscalations;
    row.annualGraderHours = result.graderHours * (365 / windowDays);
    rows = [rows; row]; %#ok<AGROW>
end
resultsDir = localNewExperimentDirectory('E3_deferral_threshold');
writetable(rows, fullfile(resultsDir, 'deferral_sweep.csv'));

fig = figure('Visible', 'off');
plot(rows.deferralRate, rows.autonomousCoveragePercent, '-o', ...
    'DisplayName', 'scenario sweep');
if any(rows.isMeasuredPipelineRate)
    hold on;
    measuredRow = rows(rows.isMeasuredPipelineRate, :);
    plot(measuredRow.deferralRate, measuredRow.autonomousCoveragePercent, ...
        'r*', 'MarkerSize', 12, 'DisplayName', ...
        sprintf('measured pipeline rate %.4f', measuredRow.deferralRate));
    legend('Location', 'best');
end
xlabel('Deferral rate');
ylabel('Autonomous coverage (%)');
title('E3: deferral rate versus autonomous coverage');
exportgraphics(fig, fullfile(resultsDir, 'deferral_versus_coverage.png'));
close(fig);

localWriteExperimentConfig(resultsDir, baseConfig, ...
    struct('deferralRates', deferralRates, 'scenarioRates', scenarioRates, ...
    'measuredPipelineRate', measuredRate, 'numberOfGraders', generousGraders, ...
    'windowDays', windowDays));
out = struct('table', rows, 'resultsDirectory', resultsDir);
end

% ------------------------------------------------------------------
% E4: bandwidth and connectivity availability sweep.
% ------------------------------------------------------------------
function out = runE4Bandwidth(configPath, baseConfig, windowDays)
bandwidths = [1, 5, 20];
connectivities = [0.3, 0.9];
rows = table();
for i = 1:numel(bandwidths)
    for j = 1:numel(connectivities)
        result = runDistrictSimulation(configPath, ...
            'SimulationDurationDays', windowDays, ...
            'BandwidthMegabitsPerSecond', bandwidths(i), ...
            'ConnectivityAvailability', connectivities(j));
        row = localSummaryRow(result);
        row.bandwidthMegabitsPerSecond = bandwidths(i);
        row.connectivityAvailability = connectivities(j);
        row.resultDelayHours = row.meanTurnaroundTimeHours;
        rows = [rows; row]; %#ok<AGROW>
    end
end
resultsDir = localNewExperimentDirectory('E4_bandwidth');
writetable(rows, fullfile(resultsDir, 'bandwidth_sweep.csv'));

fig = figure('Visible', 'off');
hold on;
for j = 1:numel(connectivities)
    subset = rows(rows.connectivityAvailability == connectivities(j), :);
    plot(subset.bandwidthMegabitsPerSecond, subset.meanTurnaroundTimeHours, '-o', ...
        'DisplayName', sprintf('connectivity=%.1f', connectivities(j)));
end
xlabel('Bandwidth (Mbps)');
ylabel('Mean turnaround time (hours)');
legend('Location', 'best');
title('E4: bandwidth versus turnaround time');
exportgraphics(fig, fullfile(resultsDir, 'bandwidth_versus_turnaround.png'));
close(fig);

localWriteExperimentConfig(resultsDir, baseConfig, ...
    struct('bandwidths', bandwidths, 'connectivities', connectivities, ...
    'windowDays', windowDays));
out = struct('table', rows, 'resultsDirectory', resultsDir);
end

% ------------------------------------------------------------------
% E5: quality gate enabled versus disabled.
% ------------------------------------------------------------------
function out = runE5QualityGate(configPath, baseConfig, windowDays)
labels = {'quality_gate_enabled', 'quality_gate_disabled'};
enabledValues = [true, false];
rows = table();
for i = 1:2
    result = runDistrictSimulation(configPath, ...
        'SimulationDurationDays', windowDays, ...
        'QualityGateEnabled', enabledValues(i));
    row = localSummaryRow(result);
    row.qualityGateEnabled = enabledValues(i);
    row.failedCaptures = result.failedCaptureAttempts;
    row.recaptureAttempts = result.totalRecaptureAttempts;
    row.graderHours = result.graderHours;
    rows = [rows; row]; %#ok<AGROW>
end
resultsDir = localNewExperimentDirectory('E5_quality_gate');
rows.Properties.RowNames = labels;
writetable(rows, fullfile(resultsDir, 'quality_gate_comparison.csv'), ...
    'WriteRowNames', true);

localWriteExperimentConfig(resultsDir, baseConfig, struct('windowDays', windowDays));
out = struct('table', rows, 'resultsDirectory', resultsDir);
fprintf(['E5: quality gate enabled vs disabled — failed captures %d vs %d, ' ...
    'grader-hours %.2f vs %.2f\n'], rows.failedCaptures(1), rows.failedCaptures(2), ...
    rows.graderHours(1), rows.graderHours(2));
end

% ------------------------------------------------------------------
% E6: smooth versus bursty (screening-camp) arrivals.
% ------------------------------------------------------------------
function out = runE6ArrivalPattern(configPath, baseConfig, windowDays)
modes = {'smooth', 'bursty'};
rows = table();
for i = 1:numel(modes)
    result = runDistrictSimulation(configPath, ...
        'SimulationDurationDays', windowDays, ...
        'ArrivalMode', modes{i});
    row = localSummaryRow(result);
    row.arrivalMode = string(modes{i});
    rows = [rows; row]; %#ok<AGROW>
end
resultsDir = localNewExperimentDirectory('E6_arrival_pattern');
writetable(rows, fullfile(resultsDir, 'arrival_pattern_comparison.csv'));

fig = figure('Visible', 'off');
bar(categorical(rows.arrivalMode), rows.maximumQueueLength);
ylabel('Peak queue length (any queue)');
title('E6: smooth versus bursty arrivals — peak queue length');
exportgraphics(fig, fullfile(resultsDir, 'peak_queue_length.png'));
close(fig);

localWriteExperimentConfig(resultsDir, baseConfig, struct('windowDays', windowDays));
out = struct('table', rows, 'resultsDirectory', resultsDir);
smoothRow = rows(rows.arrivalMode == "smooth", :);
burstyRow = rows(rows.arrivalMode == "bursty", :);
fprintf(['E6: smooth vs bursty — peak queue %g vs %g, mean turnaround %.3f ' ...
    'vs %.3f hours\n'], smoothRow.maximumQueueLength, burstyRow.maximumQueueLength, ...
    smoothRow.meanTurnaroundTimeHours, burstyRow.meanTurnaroundTimeHours);
end

% ------------------------------------------------------------------
% Shared helpers.
% ------------------------------------------------------------------
function row = localSummaryRow(result)
row = table( ...
    result.totalEntitiesGenerated, result.totalCompleted, ...
    result.totalAutoCleared, result.totalReferred, result.totalEscalated, ...
    result.totalRecaptureAttempts, result.meanTurnaroundTimeHours, ...
    result.p95TurnaroundTimeHours, result.maximumQueueLength, ...
    result.meanQueueLength, result.graderUtilisation, ...
    result.uploadQueueLength, result.percentMeetingTurnaroundTarget, ...
    result.graderHours, 'VariableNames', ...
    {'totalEntitiesGenerated', 'totalCompleted', 'totalAutoCleared', ...
    'totalReferred', 'totalEscalated', 'totalRecaptureAttempts', ...
    'meanTurnaroundTimeHours', 'p95TurnaroundTimeHours', ...
    'maximumQueueLength', 'meanQueueLength', 'graderUtilisation', ...
    'uploadQueueLength', 'percentMeetingTurnaroundTarget', 'graderHours'});
end

function directory = localNewExperimentDirectory(label)
root = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'results');
if ~isfolder(root)
    mkdir(root);
end
stamp = datestr(now, 'yyyymmdd_HHMMSS_FFF'); %#ok<TNOW1,DATST>
directory = fullfile(root, [stamp '_' label]);
suffix = 0;
while isfolder(directory)
    suffix = suffix + 1;
    directory = fullfile(root, sprintf('%s_%s_%02d', stamp, label, suffix));
end
mkdir(directory);
end

function localWriteExperimentConfig(resultsDir, baseConfig, sweepParameters)
payload = struct('baseConfiguration', baseConfig, ...
    'sweepParameters', sweepParameters, ...
    'randomSeed', baseConfig.randomSeed);
fid = fopen(fullfile(resultsDir, 'experiment_config.json'), 'w');
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, jsonencode(payload, 'PrettyPrint', true), 'char');
end
