function result = externalValidation(varargin)
%EXTERNALVALIDATION Run the frozen pipeline over the sealed external set once.
%   RESULT = externalValidation('ConfirmUnseal', true) opens the sealed
%   Messidor-2 set and evaluates the frozen operating point against the
%   Krause et al. adjudicated ICDR grades.  This is the §10.4 protocol step
%   and it is designed to happen exactly once.
%
%   Name-value options:
%     'ConfirmUnseal'  Must be true.  Nothing runs without it.
%     'Operator'       Name of the key holder authorising the unseal.
%     'Force'          Run even though a previous unseal is on record.
%                      Whatever comes out is no longer a first-run external
%                      validation result and is labelled as such.
%     'Prevalence'     Screening prevalence for PPV/NPV.
%     'Limit'          Evaluate only the first N images.  Any limited run is
%                      recorded as a partial run.
%     'ResultsRoot'    Root for the dated result directory.
%
%   Before it will run, this function requires:
%     - operating_point.referable_threshold, temperature, model and
%       frozen_on to be populated in config/default.json, and
%     - frozen_on to be a date no later than today.
%   An operating point chosen with knowledge of this set is not an external
%   validation result, so the freeze must precede the run.
%
%   What is recorded, so that §10.4's "if any change is made to the pipeline
%   after opening the seal" is checkable rather than a promise: a SHA-256
%   digest of every pipeline source file that determines the endpoint is
%   written into the unseal record.  Re-running localPipelineDigest later
%   and comparing tells you whether the pipeline that produced an external
%   number is the pipeline you have now.
%
%   The endpoint evaluated here is the frozen one from §11.2: the
%   temperature-calibrated P(ICDR >= 2) thresholded at the frozen value.
%   The three-way decision policy is deliberately not part of it, because
%   the frozen operating point is defined on the calibrated probability.
%
%   Whatever comes out is reported (§10.5, §11.4).  A low external number
%   that is reported and analysed is the stronger submission; a number
%   obtained after adjusting anything is not an external result at all.

rng(42, 'twister');

options = localOptions(varargin{:});
projectRoot = localProjectRoot();

if ~options.confirmUnseal
    error('eval:SealNotConfirmed', ...
        ['The sealed set stays sealed unless ConfirmUnseal is true. ' ...
        'Opening it is a one-time, irreversible step under §10.4.']);
end

config = jsondecode(fileread(fullfile(projectRoot, 'config', 'default.json')));
frozen = localRequireFrozenOperatingPoint(config);

recordPath = fullfile(projectRoot, 'data', 'sealed', 'UNSEAL_RECORD.json');
priorRecord = localReadPriorRecord(recordPath);
if ~isempty(priorRecord) && ~options.force
    error('eval:SealAlreadyOpened', ...
        ['The seal was already opened on %s by %s (results: %s). §10.4 ' ...
        'allows exactly one run. Pass Force true only if you accept that ' ...
        'the result is no longer a first-run external validation.'], ...
        priorRecord.openedOn, priorRecord.operator, priorRecord.resultsDirectory);
end

sealed = localLoadSealedSet(projectRoot, options.limit);
digest = localPipelineDigest(projectRoot);

fprintf('=== §10.4 SEALED EXTERNAL SET: OPENING ===\n');
fprintf('Operator            %s\n', options.operator);
fprintf('Frozen on           %s (today %s)\n', frozen.frozenOn, ...
    char(datetime('now', 'Format', 'yyyy-MM-dd')));
fprintf('Frozen threshold    %.3f on calibrated P(ICDR>=2)\n', frozen.threshold);
fprintf('Frozen temperature  %.4f\n', frozen.temperature);
fprintf('Frozen model        %s\n', frozen.model);
fprintf('Pipeline digest     %s\n', digest.combined);
fprintf('Gradable images     %d of %d adjudicated\n', sealed.n, sealed.total);
if isfinite(options.limit)
    fprintf('PARTIAL RUN: limited to %d images.\n', options.limit);
end
fprintf('\n');

checkpointPath = fullfile(projectRoot, frozen.model);
checkpoint = load(checkpointPath, 'net', 'config');
checkpoint.checkpointPath = checkpointPath;

predictions = localPredict(sealed, config, checkpoint, frozen);
metrics = localComputeMetrics(predictions, sealed, frozen, options);
localPrintReport(metrics, frozen, options);

resultsDirectory = localDatedDirectory(options.resultsRoot, 'external_messidor2');
localWriteOutputs(resultsDirectory, metrics, predictions, sealed, config, options, digest);
localWriteUnsealRecord(recordPath, options, frozen, digest, resultsDirectory, ...
    metrics, priorRecord);

result = struct();
result.status = "completed";
result.metrics = metrics;
result.predictions = predictions;
result.digest = digest;
result.resultsDirectory = string(resultsDirectory);
result.sealedDataAccessed = true;
result.isFirstRun = isempty(priorRecord);
result.isPartialRun = isfinite(options.limit);
end

% ---------------------------------------------------------------- options

function options = localOptions(varargin)
parser = inputParser;
parser.addParameter('ConfirmUnseal', false);
parser.addParameter('Operator', '');
parser.addParameter('Force', false);
parser.addParameter('Prevalence', []);
parser.addParameter('Limit', Inf);
parser.addParameter('ResultsRoot', fullfile(localProjectRoot(), 'results'));
parser.parse(varargin{:});

options = struct();
options.confirmUnseal = logical(parser.Results.ConfirmUnseal);
options.operator = char(string(parser.Results.Operator));
options.force = logical(parser.Results.Force);
options.prevalence = parser.Results.Prevalence;
options.limit = parser.Results.Limit;
options.resultsRoot = char(string(parser.Results.ResultsRoot));

if options.confirmUnseal && isempty(options.operator)
    error('eval:MissingOperator', ...
        ['§10.4 names one key holder. Pass Operator so the unseal record ' ...
        'says who authorised it.']);
end
end

function frozen = localRequireFrozenOperatingPoint(config)
if ~isfield(config, 'operating_point') || ~isstruct(config.operating_point)
    error('eval:UnfrozenOperatingPoint', ...
        'config/default.json carries no operating_point block.');
end
point = config.operating_point;
required = {'referable_threshold', 'temperature', 'model', 'frozen_on'};
for index = 1:numel(required)
    if ~isfield(point, required{index}) || isempty(point.(required{index}))
        error('eval:UnfrozenOperatingPoint', ...
            ['operating_point.%s is empty. The sealed set may only be ' ...
            'opened after the operating point is frozen and dated (§10.4).'], ...
            required{index});
    end
end

frozenOn = datetime(char(point.frozen_on), 'InputFormat', 'yyyy-MM-dd');
if frozenOn > datetime('now')
    error('eval:FreezeDateInFuture', ...
        'operating_point.frozen_on is in the future; the freeze must precede the run.');
end

frozen = struct( ...
    'threshold', double(point.referable_threshold), ...
    'temperature', double(point.temperature), ...
    'model', char(point.model), ...
    'frozenOn', char(point.frozen_on));
end

% ------------------------------------------------------------- sealed loading

function sealed = localLoadSealedSet(projectRoot, limit)
sealedRoot = fullfile(projectRoot, 'data', 'sealed');
gradeFile = fullfile(sealedRoot, 'messidor2_grades', 'messidor_data.csv');
imageFolder = fullfile(sealedRoot, 'IMAGES');

if ~isfile(gradeFile)
    error('eval:MissingSealedGrades', ...
        'Adjudicated grade file not found: %s', gradeFile);
end
if ~isfolder(imageFolder)
    error('eval:MissingSealedImages', ...
        'Sealed image folder not found: %s', imageFolder);
end

grades = readtable(gradeFile, 'TextType', 'string');
total = height(grades);

% adjudicated_gradable = 0 means no DR grade was assigned at all, so those
% images carry no reference standard and cannot contribute to a
% sensitivity or specificity. They are counted and reported, not silently
% dropped: §11.1 forbids metrics on a filtered "clean" subset presented
% without the exclusion.
gradable = grades.adjudicated_gradable == 1 & ~ismissing(grades.adjudicated_dr_grade);
grades = grades(gradable, :);

files = fullfile(imageFolder, string(grades.image_id));
present = arrayfun(@(f) isfile(f), files);
missingCount = sum(~present);
grades = grades(present, :);
files = files(present);

if isfinite(limit)
    keep = 1:min(height(grades), limit);
    grades = grades(keep, :);
    files = files(keep);
end

sealed = struct();
sealed.n = height(grades);
sealed.total = total;
sealed.ungradableExcluded = total - sum(gradable);
sealed.missingImages = missingCount;
sealed.imageIds = string(grades.image_id);
sealed.grades = double(grades.adjudicated_dr_grade);
sealed.files = files;
sealed.name = "messidor2_sealed";
end

function digest = localPipelineDigest(projectRoot)
%LOCALPIPELINEDIGEST Hash the source that determines the frozen endpoint.
files = { ...
    fullfile('src', '+common', 'preprocess.m'), ...
    fullfile('src', '+grade', 'infer.m'), ...
    fullfile('src', '+grade', 'applyTemperature.m'), ...
    fullfile('src', '+quality', 'assess.m'), ...
    fullfile('config', 'default.json')};

entries = struct('file', {}, 'sha256', {});
combined = '';
for index = 1:numel(files)
    path = fullfile(projectRoot, files{index});
    if ~isfile(path)
        continue;
    end
    hash = localSha256(path);
    entries(end + 1) = struct('file', files{index}, 'sha256', hash); %#ok<AGROW>
    combined = [combined, hash]; %#ok<AGROW>
end
digest = struct();
digest.files = entries;
digest.combined = localSha256Text(combined);
end

function hash = localSha256(path)
digestBuilder = java.security.MessageDigest.getInstance('SHA-256');
bytes = fileread(path);
raw = digestBuilder.digest(uint8(bytes));
hash = lower(reshape(dec2hex(typecast(raw, 'uint8')).', 1, []));
end

function hash = localSha256Text(text)
digestBuilder = java.security.MessageDigest.getInstance('SHA-256');
raw = digestBuilder.digest(uint8(text));
hash = lower(reshape(dec2hex(typecast(raw, 'uint8')).', 1, []));
end

% ------------------------------------------------------------------ inference

function predictions = localPredict(sealed, config, checkpoint, frozen)
n = sealed.n;
predictions = struct();
predictions.rawProbabilities = nan(5, n);
predictions.calibratedProbabilities = nan(5, n);
predictions.referableProbability = nan(n, 1);
predictions.predictedLevel = nan(n, 1);
predictions.qualityClass = strings(n, 1);
predictions.latencySeconds = nan(n, 1);
predictions.failed = false(n, 1);

reportEvery = max(1, floor(n / 20));
timer = tic;
for index = 1:n
    try
        image = imread(char(sealed.files(index)));
        caseTimer = tic;
        [qualityResult, ~] = quality.assess(image, config);
        [modelImage, ~, preprocessingMetadata] = ...
            common.preprocess(image, config, 'inference');
        inference = grade.infer(checkpoint, modelImage, config, ...
            'ReturnLogits', true, 'Preprocessed', true, ...
            'QualityMetadata', qualityResult, ...
            'PreprocessingMetadata', preprocessingMetadata);
        predictions.latencySeconds(index) = toc(caseTimer);

        calibrated = grade.applyTemperature(inference.logits, frozen.temperature);
        predictions.rawProbabilities(:, index) = inference.probabilities(:, 1);
        predictions.calibratedProbabilities(:, index) = calibrated(:, 1);
        predictions.referableProbability(index) = sum(calibrated(3:5, 1));
        predictions.predictedLevel(index) = double(inference.predictedGrade(1));
        predictions.qualityClass(index) = string(qualityResult.class);
    catch exception
        predictions.failed(index) = true;
        fprintf('  image %s failed: %s\n', sealed.imageIds(index), exception.message);
    end
    if mod(index, reportEvery) == 0 || index == n
        fprintf('  %d/%d (%.0f%%), %.0f s elapsed\n', index, n, ...
            100 * index / n, toc(timer));
    end
end
end

% -------------------------------------------------------------------- metrics

function metrics = localComputeMetrics(predictions, sealed, frozen, options)
keep = ~predictions.failed;
truth = sealed.grades(keep);
referableProbability = predictions.referableProbability(keep);
predictedLevel = predictions.predictedLevel(keep);
qualityClass = predictions.qualityClass(keep);
truthReferable = truth >= 2;
predictedReferable = referableProbability >= frozen.threshold;

pseudoLevel = zeros(size(predictedReferable));
pseudoLevel(predictedReferable) = 2;

metrics = struct();
metrics.dataset = "Messidor-2 (sealed external)";
metrics.referenceStandard = "Krause et al. 2018 adjudicated ICDR grades";
metrics.n = numel(truth);
metrics.failed = sum(~keep);
metrics.ungradableExcluded = sealed.ungradableExcluded;
metrics.missingImages = sealed.missingImages;
metrics.threshold = frozen.threshold;
metrics.temperature = frozen.temperature;
metrics.model = string(frozen.model);
metrics.frozenOn = string(frozen.frozenOn);
metrics.evaluatedOn = string(datetime('now', 'Format', 'yyyy-MM-dd'));

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

correct = predictedReferable == truthReferable;
confidence = abs(referableProbability - frozen.threshold);
metrics.riskCoverage = riskCoverage(correct, confidence);
metrics.qualityStrata = localStratify(qualityClass, truth, pseudoLevel);
end

function strata = localStratify(qualityClass, truth, pseudoLevel)
classes = unique(qualityClass, 'stable');
strata = struct('qualityClass', {}, 'n', {}, 'sensitivity', {}, 'specificity', {});
for index = 1:numel(classes)
    selected = qualityClass == classes(index);
    subset = referableMetrics(truth(selected), pseudoLevel(selected));
    strata(end + 1) = struct('qualityClass', classes(index), ...
        'n', sum(selected), 'sensitivity', subset.sensitivity, ...
        'specificity', subset.specificity); %#ok<AGROW>
end
end

% ------------------------------------------------------------------ reporting

function localPrintReport(m, frozen, options)
fprintf('\n===== EXTERNAL VALIDATION: %s =====\n', m.dataset);
fprintf('Reference standard: %s\n', m.referenceStandard);
fprintf('n = %d gradable images (%d ungradable excluded, %d failed, %d images missing)\n', ...
    m.n, m.ungradableExcluded, m.failed, m.missingImages);
fprintf('Operating point frozen %s, evaluated %s, threshold %.3f\n\n', ...
    m.frozenOn, m.evaluatedOn, m.threshold);

fprintf('Referable DR (ICDR >= 2) at the frozen operating point\n');
fprintf('  Sensitivity  %.4f  (95%% Wilson CI %.4f-%.4f, %d/%d)\n', ...
    m.referable.sensitivity, m.referable.sensitivityCILower, ...
    m.referable.sensitivityCIUpper, m.referable.truePositives, ...
    m.referable.truePositives + m.referable.falseNegatives);
fprintf('  Specificity  %.4f  (95%% Wilson CI %.4f-%.4f, %d/%d)\n', ...
    m.referable.specificity, m.referable.specificityCILower, ...
    m.referable.specificityCIUpper, m.referable.trueNegatives, ...
    m.referable.trueNegatives + m.referable.falsePositives);
fprintf('  PPV %.4f, NPV %.4f at prevalence %.4f\n', ...
    m.predictive.ppv, m.predictive.npv, m.assumedPrevalence);
fprintf('  ROC AUC %.4f, average precision %.4f, QWK %.4f\n\n', ...
    m.roc.auc, m.precisionRecall.averagePrecision, m.kappa.kappa);

fprintf('Five-class confusion (rows actual, columns predicted)\n');
fprintf('       0    1    2    3    4\n');
for level = 0:4
    fprintf('  %d  %4d %4d %4d %4d %4d\n', level, m.confusionMatrix(level + 1, :));
end
fprintf('  Per-class recall: %s\n\n', mat2str(round(m.perClassRecall', 4)));

if isfinite(options.limit)
    fprintf(['NOTE: partial run over %d images. This is not the §10.4 ' ...
        'single full external evaluation.\n'], options.limit);
end
fprintf(['This number is reported as measured (§10.5, §11.4). If the ' ...
    'pipeline is changed\nafter this run, any later figure is no longer ' ...
    'an external validation result.\n']);
end

function localWriteOutputs(resultsDirectory, metrics, predictions, sealed, ...
        config, options, digest)
payload = struct();
payload.metrics = metrics;
payload.pipelineDigest = digest;
payload.options = options;
payload.sealedDataAccessed = true;
localWriteText(fullfile(resultsDirectory, 'external_metrics.json'), ...
    jsonencode(payload, 'PrettyPrint', true));
localWriteText(fullfile(resultsDirectory, 'config.json'), ...
    jsonencode(config, 'PrettyPrint', true));

lines = {'image_id,adjudicated_grade,predicted_level,referable_probability,quality_class'};
for index = 1:sealed.n
    lines{end + 1} = sprintf('%s,%d,%d,%.6f,%s', sealed.imageIds(index), ...
        sealed.grades(index), predictions.predictedLevel(index), ...
        predictions.referableProbability(index), ...
        predictions.qualityClass(index)); %#ok<AGROW>
end
localWriteText(fullfile(resultsDirectory, 'per_image.csv'), strjoin(lines, newline));
save(fullfile(resultsDirectory, 'external_validation.mat'), ...
    'metrics', 'predictions', '-v7.3');
fprintf('\nResults written to %s\n', resultsDirectory);
end

function localWriteUnsealRecord(recordPath, options, frozen, digest, ...
        resultsDirectory, metrics, priorRecord)
record = struct();
record.openedOn = char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
record.operator = options.operator;
record.frozenOn = frozen.frozenOn;
record.threshold = frozen.threshold;
record.model = frozen.model;
record.pipelineDigest = digest;
record.resultsDirectory = resultsDirectory;
record.n = metrics.n;
record.sensitivity = metrics.referable.sensitivity;
record.specificity = metrics.referable.specificity;
record.isFirstRun = isempty(priorRecord);
record.wasPartialRun = isfinite(options.limit);
record.note = ['Recorded under §10.4. Any pipeline change after this ' ...
    'timestamp means later figures are not external validation results. ' ...
    'Compare localPipelineDigest against pipelineDigest to check.'];
localWriteText(recordPath, jsonencode(record, 'PrettyPrint', true));
fprintf('Unseal recorded in %s\n', recordPath);
end

function record = localReadPriorRecord(recordPath)
record = [];
if ~isfile(recordPath)
    return;
end
try
    record = jsondecode(fileread(recordPath));
catch
    record = [];
end
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
