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

checkpointPath = fullfile(projectRoot, 'results', '20260822_030539', ...
    'best_model.mat');
calibrationPath = fullfile(projectRoot, 'results', '20260822_091625', ...
    'temperature_fit.mat');
configPath = fullfile(projectRoot, 'config', 'default.json');
for requiredPath = {checkpointPath, calibrationPath, configPath}
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
