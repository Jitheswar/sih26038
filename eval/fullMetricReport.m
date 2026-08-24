function result = fullMetricReport(varargin)
%FULLMETRICREPORT Compute the complete §11.3 metric set for one split.
%   RESULT = fullMetricReport() evaluates the frozen checkpoint at the
%   frozen threshold on the validation split and reports every metric §11.3
%   asks for, rather than the sensitivity/specificity pair alone.
%
%   Name-value options:
%     'Split'       Committed split name (default "validation").
%     'Prevalence'  Screening prevalence for PPV/NPV (default: the observed
%                   referable rate in the split, which is stated in the
%                   output because PPV means nothing without it).
%     'Limit'       Evaluate only the first N images.
%     'ResultsRoot' Root for the dated result directory.
%
%   §11.1 forbids reporting bare accuracy, so no accuracy figure appears
%   here.  Every rate carries a 95% Wilson interval and an explicit n.
%
%   The test split is refused.  It is touched once and has been touched for
%   the frozen internal result; re-running it here would quietly make it a
%   development split.

rng(42, 'twister');

options = localOptions(varargin{:});
projectRoot = localProjectRoot();
config = jsondecode(fileread(fullfile(projectRoot, 'config', 'default.json')));
frozen = config.operating_point;

checkpointPath = fullfile(projectRoot, frozen.model);
if ~isfile(checkpointPath)
    error('eval:MissingCheckpoint', 'Checkpoint does not exist: %s', checkpointPath);
end
checkpoint = load(checkpointPath, 'net', 'config');
checkpoint.checkpointPath = checkpointPath;

split = localReadSplit(projectRoot, options.split, options.limit);
fprintf('Full metric set on the %s split: %d images.\n', options.split, split.n);
fprintf('Frozen threshold %.3f on calibrated P(ICDR>=2), temperature %.4f.\n\n', ...
    frozen.referable_threshold, frozen.temperature);

predictions = localPredict(split, config, checkpoint, frozen);
metrics = localComputeMetrics(predictions, split, frozen, options, ...
    checkpointPath, checkpoint);
localPrintReport(metrics);

resultsDirectory = localDatedDirectory(options.resultsRoot, ...
    sprintf('full_metrics_%s', options.split));
localWriteOutputs(resultsDirectory, metrics, predictions, config, options);

result = struct();
result.status = "completed";
result.metrics = metrics;
result.predictions = predictions;
result.resultsDirectory = string(resultsDirectory);
result.sealedDataAccessed = false;
end

% ---------------------------------------------------------------- options

function options = localOptions(varargin)
parser = inputParser;
parser.addParameter('Split', 'validation');
parser.addParameter('Prevalence', []);
parser.addParameter('Limit', Inf);
parser.addParameter('ResultsRoot', fullfile(localProjectRoot(), 'results'));
parser.parse(varargin{:});

options = struct();
options.split = char(string(parser.Results.Split));
options.prevalence = parser.Results.Prevalence;
options.limit = parser.Results.Limit;
options.resultsRoot = char(string(parser.Results.ResultsRoot));

if strcmpi(options.split, 'test')
    error('eval:TestSplitRefused', ...
        ['The test split is touched once (§11.1) and has already been ' ...
        'touched for the frozen internal result.']);
end
if strcmpi(options.split, 'sealed')
    error('eval:SealedData', 'data/sealed is never read.');
end
end

function split = localReadSplit(projectRoot, splitName, limit)
splitFile = fullfile(projectRoot, 'data', 'splits', [splitName '.csv']);
if ~isfile(splitFile)
    error('eval:MissingSplit', 'Committed split does not exist: %s', splitFile);
end
tableData = readtable(splitFile, 'TextType', 'string');
if any(contains(lower(string(tableData.relative_path)), "sealed"))
    error('eval:SealedData', 'The split references data/sealed.');
end
if isfinite(limit)
    tableData = tableData(1:min(height(tableData), limit), :);
end
split = struct();
split.n = height(tableData);
split.imageIds = string(tableData.image_id);
split.grades = double(tableData.grade);
split.files = fullfile(projectRoot, string(tableData.relative_path));
split.name = string(splitName);
end

% ------------------------------------------------------------------ inference

function predictions = localPredict(split, config, checkpoint, frozen)
n = split.n;
predictions = struct();
predictions.rawProbabilities = nan(5, n);
predictions.calibratedProbabilities = nan(5, n);
predictions.referableProbability = nan(n, 1);
predictions.predictedLevel = nan(n, 1);
predictions.qualityClass = strings(n, 1);
predictions.latencySeconds = nan(n, 1);
predictions.failed = false(n, 1);

reportEvery = max(1, floor(n / 10));
timer = tic;
for index = 1:n
    try
        image = imread(char(split.files(index)));
        caseTimer = tic;
        [qualityResult, ~] = quality.assess(image, config);
        [modelImage, ~, preprocessingMetadata] = ...
            common.preprocess(image, config, 'inference');
        inference = grade.infer(checkpoint, modelImage, config, ...
            'ReturnLogits', true, 'Preprocessed', true, ...
            'QualityMetadata', qualityResult, ...
            'PreprocessingMetadata', preprocessingMetadata);
        % Latency is measured over the whole per-case path a deployment
        % actually runs, not the forward pass alone.
        predictions.latencySeconds(index) = toc(caseTimer);

        calibrated = grade.applyTemperature(inference.logits, frozen.temperature);
        predictions.rawProbabilities(:, index) = inference.probabilities(:, 1);
        predictions.calibratedProbabilities(:, index) = calibrated(:, 1);
        predictions.referableProbability(index) = sum(calibrated(3:5, 1));
        predictions.predictedLevel(index) = double(inference.predictedGrade(1));
        predictions.qualityClass(index) = string(qualityResult.class);
    catch exception
        predictions.failed(index) = true;
        fprintf('  image %s failed: %s\n', split.imageIds(index), exception.message);
    end
    if mod(index, reportEvery) == 0 || index == n
        fprintf('  %d/%d (%.0f%%), %.0f s elapsed\n', index, n, ...
            100 * index / n, toc(timer));
    end
end
end

% -------------------------------------------------------------------- metrics

function metrics = localComputeMetrics(predictions, split, frozen, options, ...
        checkpointPath, checkpoint)
keep = ~predictions.failed;
truth = split.grades(keep);
referableProbability = predictions.referableProbability(keep);
predictedLevel = predictions.predictedLevel(keep);
qualityClass = predictions.qualityClass(keep);
truthReferable = truth >= 2;
predictedReferable = referableProbability >= frozen.referable_threshold;

metrics = struct();
metrics.split = split.name;
metrics.n = numel(truth);
metrics.failed = sum(~keep);
metrics.threshold = frozen.referable_threshold;
metrics.temperature = frozen.temperature;
metrics.model = string(frozen.model);
metrics.evaluatedOn = string(datetime('now', 'Format', 'yyyy-MM-dd'));

% Referable endpoint at the frozen threshold. Expressed as pseudo-levels so
% the tested Wilson implementation in referableMetrics is reused.
pseudoLevel = zeros(size(predictedReferable));
pseudoLevel(predictedReferable) = 2;
metrics.referable = referableMetrics(truth, pseudoLevel);

observedPrevalence = mean(truthReferable);
prevalence = options.prevalence;
if isempty(prevalence)
    prevalence = observedPrevalence;
end
metrics.observedPrevalence = observedPrevalence;
metrics.assumedPrevalence = prevalence;
metrics.predictive = predictiveValues(metrics.referable.sensitivity, ...
    metrics.referable.specificity, prevalence);

metrics.roc = rocMetrics(truthReferable, referableProbability);
metrics.precisionRecall = precisionRecallMetrics(truthReferable, referableProbability);
metrics.kappa = quadraticWeightedKappa(truth, predictedLevel);
metrics.confusionMatrix = confusionMatrix(truth, predictedLevel);
metrics.perClassRecall = perClassRecall(truth, predictedLevel);

metrics.calibration = eval.calibrationMetrics(truth, ...
    predictions.rawProbabilities(:, keep), ...
    predictions.calibratedProbabilities(:, keep));

% Confidence for the risk-coverage curve is distance from the decision
% threshold: a case sitting on the threshold is the one to hand to a human.
correct = predictedReferable == truthReferable;
confidence = abs(referableProbability - frozen.referable_threshold);
metrics.riskCoverage = riskCoverage(correct, confidence);

metrics.qualityStrata = localStratify(qualityClass, truth, pseudoLevel);
metrics.latency = localLatency(predictions.latencySeconds(keep));
metrics.modelSize = localModelSize(checkpointPath, checkpoint);

% §11.3 also asks for stratification by dataset and camera. The development
% splits are APTOS only, so there is nothing to stratify on here; that
% comparison is what the sealed external set exists for (§11.4).
metrics.datasetStrata = "single dataset (APTOS); external comparison is §11.4";
end

function strata = localStratify(qualityClass, truth, pseudoLevel)
classes = unique(qualityClass, 'stable');
strata = struct('qualityClass', {}, 'n', {}, 'sensitivity', {}, ...
    'specificity', {}, 'sensitivityCILower', {}, 'specificityCILower', {});
for index = 1:numel(classes)
    selected = qualityClass == classes(index);
    if ~any(selected)
        continue;
    end
    subset = referableMetrics(truth(selected), pseudoLevel(selected));
    strata(end + 1) = struct( ...
        'qualityClass', classes(index), ...
        'n', sum(selected), ...
        'sensitivity', subset.sensitivity, ...
        'specificity', subset.specificity, ...
        'sensitivityCILower', subset.sensitivityCILower, ...
        'specificityCILower', subset.specificityCILower); %#ok<AGROW>
end
end

function latency = localLatency(seconds)
seconds = seconds(isfinite(seconds));
if isempty(seconds)
    latency = struct('meanSeconds', NaN, 'medianSeconds', NaN, ...
        'p95Seconds', NaN, 'maxSeconds', NaN, 'n', 0);
    return;
end
latency = struct( ...
    'meanSeconds', mean(seconds), ...
    'medianSeconds', median(seconds), ...
    'p95Seconds', prctile(seconds, 95), ...
    'maxSeconds', max(seconds), ...
    'n', numel(seconds));
end

function modelSize = localModelSize(checkpointPath, checkpoint)
info = dir(checkpointPath);
parameterCount = 0;
try
    learnables = checkpoint.net.Learnables;
    for index = 1:height(learnables)
        parameterCount = parameterCount + numel(extractdata(learnables.Value{index}));
    end
catch
    parameterCount = NaN;
end
modelSize = struct( ...
    'checkpointBytes', info.bytes, ...
    'checkpointMegabytes', info.bytes / 1048576, ...
    'learnableParameters', parameterCount);
end

% ------------------------------------------------------------------ reporting

function localPrintReport(m)
fprintf('\n===== §11.3 full metric set: %s split =====\n', m.split);
fprintf('n = %d (failed %d), frozen threshold %.3f, temperature %.4f\n\n', ...
    m.n, m.failed, m.threshold, m.temperature);

fprintf('Referable DR at the frozen operating point\n');
fprintf('  Sensitivity  %.4f  (95%% Wilson CI %.4f-%.4f, %d/%d)\n', ...
    m.referable.sensitivity, m.referable.sensitivityCILower, ...
    m.referable.sensitivityCIUpper, m.referable.truePositives, ...
    m.referable.truePositives + m.referable.falseNegatives);
fprintf('  Specificity  %.4f  (95%% Wilson CI %.4f-%.4f, %d/%d)\n', ...
    m.referable.specificity, m.referable.specificityCILower, ...
    m.referable.specificityCIUpper, m.referable.trueNegatives, ...
    m.referable.trueNegatives + m.referable.falsePositives);
fprintf('  PPV %.4f, NPV %.4f at prevalence %.4f (observed %.4f)\n\n', ...
    m.predictive.ppv, m.predictive.npv, m.assumedPrevalence, m.observedPrevalence);

fprintf('Threshold-independent\n');
fprintf('  ROC AUC             %.4f\n', m.roc.auc);
fprintf('  Average precision   %.4f  (baseline %.4f)\n', ...
    m.precisionRecall.averagePrecision, m.precisionRecall.baselinePrecision);
fprintf('  Quadratic weighted kappa %.4f\n\n', m.kappa.kappa);

fprintf('Five-class confusion (rows actual, columns predicted)\n');
fprintf('       0    1    2    3    4\n');
for level = 0:4
    fprintf('  %d  %4d %4d %4d %4d %4d\n', level, m.confusionMatrix(level + 1, :));
end
fprintf('  Per-class recall: %s\n\n', mat2str(round(m.perClassRecall', 4)));

fprintf('Calibration\n');
fprintf('  ECE   raw %.4f -> calibrated %.4f\n', ...
    m.calibration.rawECE, m.calibration.calibratedECE);
fprintf('  Brier raw %.4f -> calibrated %.4f\n', ...
    m.calibration.rawBrierScore, m.calibration.calibratedBrierScore);
fprintf('  NLL   raw %.4f -> calibrated %.4f\n\n', ...
    m.calibration.rawMeanNLL, m.calibration.calibratedMeanNLL);

fprintf('Deferral\n');
fprintf('  AURC %.4f (base risk %.4f)\n\n', ...
    m.riskCoverage.aurc, m.riskCoverage.baseRisk);

fprintf('Stratified by quality tier\n');
for index = 1:numel(m.qualityStrata)
    s = m.qualityStrata(index);
    fprintf('  %-12s n=%4d  sens %.4f (CI lower %.4f)  spec %.4f (CI lower %.4f)\n', ...
        s.qualityClass, s.n, s.sensitivity, s.sensitivityCILower, ...
        s.specificity, s.specificityCILower);
end

fprintf('\nDeployment\n');
fprintf('  Latency mean %.3f s, median %.3f s, p95 %.3f s (n=%d)\n', ...
    m.latency.meanSeconds, m.latency.medianSeconds, m.latency.p95Seconds, ...
    m.latency.n);
fprintf('  Checkpoint %.1f MB, %d learnable parameters\n', ...
    m.modelSize.checkpointMegabytes, m.modelSize.learnableParameters);
end

function localWriteOutputs(resultsDirectory, metrics, predictions, config, options)
localWriteText(fullfile(resultsDirectory, 'full_metrics.json'), ...
    jsonencode(metrics, 'PrettyPrint', true));
localWriteText(fullfile(resultsDirectory, 'config.json'), ...
    jsonencode(config, 'PrettyPrint', true));
localWriteText(fullfile(resultsDirectory, 'run_options.json'), ...
    jsonencode(options, 'PrettyPrint', true));
save(fullfile(resultsDirectory, 'full_metrics.mat'), 'metrics', 'predictions', '-v7.3');
fprintf('\nResults written to %s\n', resultsDirectory);
end

% -------------------------------------------------------------------- helpers

function directory = localDatedDirectory(resultsRoot, suffix)
if ~isfolder(resultsRoot)
    mkdir(resultsRoot);
end
stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
directory = fullfile(resultsRoot, [stamp '_' suffix]);
counter = 0;
while isfolder(directory)
    counter = counter + 1;
    directory = fullfile(resultsRoot, sprintf('%s_%s_%d', stamp, suffix, counter));
end
mkdir(directory);
end

function localWriteText(filename, text)
fileId = fopen(filename, 'w');
if fileId == -1
    error('eval:UnwritableFile', 'Could not write %s', filename);
end
cleanup = onCleanup(@() fclose(fileId));
fwrite(fileId, text, 'char');
end

function root = localProjectRoot()
root = fileparts(fileparts(mfilename('fullpath')));
end
