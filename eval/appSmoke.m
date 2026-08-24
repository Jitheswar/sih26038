function outputs = appSmoke()
%APPSMOKE Run the deterministic integrated screening demo on one APTOS image.

rng(42, 'twister');
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(fullfile(projectRoot, 'src')));

imagePath = fullfile(projectRoot, 'data', 'raw', 'aptos2019', ...
    'train_images', '001639a390f0.png');
if ~isfile(imagePath)
    candidates = dir(fullfile(projectRoot, 'data', 'raw', 'aptos2019', ...
        'train_images', '*.png'));
    if isempty(candidates)
        error('app:SmokeInputMissing', 'No APTOS training image was found.');
    end
    imagePath = fullfile(candidates(1).folder, candidates(1).name);
end

% The demo must run the model the reported numbers describe.  These paths
% were hardcoded to the 22 August checkpoint and its calibration, which
% predate the operating point frozen on 23 August, so the smoke demo graded
% with one model while every published figure came from another.  Read them
% from config/default.json instead, which is where the freeze is recorded.
configPath = fullfile(projectRoot, 'config', 'default.json');
if ~isfile(configPath)
    error('app:SmokeDependencyMissing', ...
        'Smoke dependency does not exist: %s', configPath);
end
config = jsondecode(fileread(configPath));
if ~isfield(config, 'operating_point') || ...
        ~isfield(config.operating_point, 'model') || ...
        ~isfield(config.operating_point, 'calibration')
    error('app:SmokeDependencyMissing', ...
        'config/default.json must record operating_point.model and .calibration.');
end
checkpointPath = fullfile(projectRoot, config.operating_point.model);
calibrationPath = fullfile(projectRoot, config.operating_point.calibration);
if isfolder(calibrationPath)
    calibrationPath = fullfile(calibrationPath, 'temperature_fit.mat');
end
for requiredPath = {checkpointPath, calibrationPath}
    if ~isfile(requiredPath{1})
        error('app:SmokeDependencyMissing', ...
            'Smoke dependency does not exist: %s', requiredPath{1});
    end
end

screeningResult = app.runScreeningCase(imagePath, checkpointPath, ...
    calibrationPath, configPath);
reportResult = report.generate(screeningResult, ...
    'ResultsRoot', fullfile(projectRoot, 'results'));

outputs = struct();
outputs.imagePath = string(imagePath);
outputs.qualityResult = screeningResult.qualityResult;
outputs.icdrResult = screeningResult.icdrRuleResult;
outputs.calibratedProbability = screeningResult.calibratedReferableProbability;
outputs.decision = screeningResult.threeWayDecision.decision;
outputs.reportPath = reportResult.reportPath;
outputs.fourPanelPath = reportResult.fourPanelPath;
outputs.overlayPaths = reportResult.overlayPaths;
outputs.sealedDataAccessed = false;

fprintf('image used: %s\n', imagePath);
fprintf('quality result: %s\n', char(screeningResult.qualityResult.class));
if isempty(screeningResult.icdrRuleResult) || ...
        ~isfield(screeningResult.icdrRuleResult, 'level')
    fprintf('ICDR result: not run because the quality gate stopped inference\n');
else
    fprintf('ICDR result: level %d (%s)\n', ...
        screeningResult.icdrRuleResult.level, ...
        screeningResult.icdrRuleResult.firedCriterion);
end
fprintf('calibrated probability: %.6f\n', ...
    screeningResult.calibratedReferableProbability);
fprintf('final decision: %s\n', char(screeningResult.threeWayDecision.decision));
fprintf('report path: %s\n', char(reportResult.reportPath));
fprintf('four-panel path: %s\n', char(reportResult.fourPanelPath));
fprintf('overlay paths: original=%s; processed=%s; gradcam=%s; candidates=%s\n', ...
    reportResult.overlayPaths.original, reportResult.overlayPaths.processed, ...
    reportResult.overlayPaths.gradCAM, reportResult.overlayPaths.candidates);
fprintf('data/sealed/ accessed: no\n');
end
