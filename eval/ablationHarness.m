function result = ablationHarness(varargin)
%ABLATIONHARNESS Run the A1-A5 ablation study over one committed split.
%   RESULT = ablationHarness() evaluates config/ablation_A1..A5.json on the
%   validation split, at the frozen operating point, using the frozen
%   checkpoint and the frozen temperature recorded in config/default.json.
%
%   Name-value options:
%     'Configs'     Cell array of configuration filenames.
%     'Split'       Committed split name (default "validation").  The test
%                   split is refused; §11.1 touches it once and it has been
%                   touched.
%     'Limit'       Evaluate only the first N images.  Pilot runs only.
%     'ResultsRoot' Root for the dated result directory.
%
%   This is a separate evaluation path from app.runScreeningCase.  That
%   function is the deployed inference path and produced the frozen
%   operating point, so it is deliberately not modified to carry ablation
%   switches.  TestAblationHarness pins this path against it: for A5 the
%   two must agree case for case.  If that test fails, this file has
%   drifted from the deployed pipeline and its numbers are void.
%
%   Ablation semantics, derived from the §11.6 table.  Each pipeline flag
%   removes one mechanism from the decision, and nothing else:
%
%     quality_gate     off: every image is graded regardless of quality.
%                      on:  an ungradable image is never handled
%                           autonomously; it is routed to a human.
%     enhancement      Handled inside common.preprocess (§5.4).
%     lesion_evidence  off: no candidate detection and no ICDR rule
%                           evidence; the disposition uses the CNN alone.
%     agreement_check  off: Grad-CAM and lesion evidence are never compared
%                           and disagreement never escalates.
%     deferral         off: a forced two-way disposition, refer or clear, at
%                           the frozen threshold.  No case may escalate.
%                      on:  the three-way policy in grade.decisionPolicy.
%
%   grade.decisionPolicy cannot express the ablated policies: its
%   configuration validator refuses to disable the safety flags.  So the
%   reduced policies are composed here, and the full policy A5 is delegated
%   to grade.decisionPolicy unchanged.

rng(42, 'twister');

options = localOptions(varargin{:});
projectRoot = localProjectRoot();
defaultConfig = jsondecode(fileread(fullfile(projectRoot, 'config', 'default.json')));

frozen = localFrozenOperatingPoint(defaultConfig);
checkpointPath = fullfile(projectRoot, frozen.model);
if ~isfile(checkpointPath)
    error('eval:MissingCheckpoint', ...
        'The frozen checkpoint does not exist: %s', checkpointPath);
end

% Loaded once for the whole study. Passing the path instead makes both
% grade.infer and explain.gradcam re-read 84 MB per image, which on a 550
% image split degraded throughput from 3.7 to 12.6 s/image as the run went on.
checkpoint = load(checkpointPath, 'net', 'config');
checkpoint.checkpointPath = checkpointPath;

split = localReadSplit(projectRoot, options.split, options.limit);
fprintf('Ablation study on the %s split: %d images.\n', options.split, split.n);
fprintf('Frozen operating point: threshold %.3f on calibrated P(ICDR>=2), temperature %.4f.\n', ...
    frozen.threshold, frozen.temperature);
fprintf('Frozen checkpoint: %s\n\n', frozen.model);

configs = localReadConfigs(projectRoot, options.configs, defaultConfig);
cache = localExtractFeatures(configs, split, defaultConfig, checkpoint, ...
    frozen, projectRoot, options);

resultsDirectory = localDatedDirectory(options.resultsRoot, 'ablation_A1_A5');
rows = cell(numel(configs), 1);
perConfig = struct([]);
for index = 1:numel(configs)
    entry = configs(index);
    decisions = localComposeDecisions(entry, cache, split, frozen);
    metrics = localMetrics(entry, decisions, split, frozen);
    localPrintConfig(entry, metrics);
    rows{index} = metrics;
    metrics.decisions = decisions;
    if isempty(perConfig)
        perConfig = metrics;
    else
        perConfig(index) = metrics; %#ok<AGROW>
    end
end

localWriteOutputs(resultsDirectory, perConfig, configs, split, frozen, options);
localPrintTable(rows);

result = struct();
result.status = "completed";
result.split = string(options.split);
result.n = split.n;
result.frozen = frozen;
result.configs = configs;
result.metrics = perConfig;
result.resultsDirectory = string(resultsDirectory);
result.sealedDataAccessed = false;
end

% ---------------------------------------------------------------- options

function options = localOptions(varargin)
parser = inputParser;
parser.addParameter('Configs', {'ablation_A1.json', 'ablation_A2.json', ...
    'ablation_A3.json', 'ablation_A4.json', 'ablation_A5.json'});
parser.addParameter('Split', 'validation');
parser.addParameter('Limit', Inf);
parser.addParameter('ResultsRoot', fullfile(localProjectRoot(), 'results'));
parser.parse(varargin{:});

options = struct();
options.configs = cellstr(string(parser.Results.Configs));
options.split = char(string(parser.Results.Split));
options.limit = parser.Results.Limit;
options.resultsRoot = char(string(parser.Results.ResultsRoot));

if strcmpi(options.split, 'test')
    error('eval:TestSplitRefused', ...
        ['The test split is touched once (§11.1) and has already been ' ...
        'touched for the frozen internal result. Run ablations on ' ...
        'validation or calibration.']);
end
if strcmpi(options.split, 'sealed')
    error('eval:SealedData', 'data/sealed is never read.');
end
end

function frozen = localFrozenOperatingPoint(config)
if ~isfield(config, 'operating_point') || ~isstruct(config.operating_point)
    error('eval:MissingOperatingPoint', ...
        'config/default.json does not carry an operating_point block.');
end
point = config.operating_point;
required = {'referable_threshold', 'temperature', 'model', 'frozen_on'};
for index = 1:numel(required)
    if ~isfield(point, required{index}) || isempty(point.(required{index}))
        error('eval:UnfrozenOperatingPoint', ...
            ['operating_point.%s is empty. The ablation study compares ' ...
            'configurations at one frozen threshold (§11.6); it cannot ' ...
            'run before the operating point is frozen.'], required{index});
    end
end
frozen = struct( ...
    'threshold', double(point.referable_threshold), ...
    'temperature', double(point.temperature), ...
    'model', char(point.model), ...
    'frozenOn', char(point.frozen_on));
end

function split = localReadSplit(projectRoot, splitName, limit)
splitFile = fullfile(projectRoot, 'data', 'splits', [splitName '.csv']);
if ~isfile(splitFile)
    error('eval:MissingSplit', 'Committed split does not exist: %s', splitFile);
end
tableData = readtable(splitFile, 'TextType', 'string');
relativePaths = string(tableData.relative_path);
if any(contains(lower(relativePaths), "sealed"))
    error('eval:SealedData', 'The split references data/sealed.');
end
if isfinite(limit)
    keep = 1:min(height(tableData), limit);
    tableData = tableData(keep, :);
    relativePaths = relativePaths(keep);
end
split = struct();
split.n = height(tableData);
split.imageIds = string(tableData.image_id);
split.grades = double(tableData.grade);
split.files = fullfile(projectRoot, relativePaths);
split.name = string(splitName);
end

function configs = localReadConfigs(projectRoot, names, defaultConfig)
configs = struct([]);
for index = 1:numel(names)
    path = names{index};
    if ~isfile(path)
        path = fullfile(projectRoot, 'config', names{index});
    end
    if ~isfile(path)
        error('eval:MissingConfig', 'Ablation config does not exist: %s', names{index});
    end
    raw = jsondecode(fileread(path));
    if ~isfield(raw, 'pipeline') || ~isfield(raw, 'ablation')
        error('eval:InvalidAblationConfig', ...
            '%s needs an ablation block and a pipeline block.', names{index});
    end

    entry = struct();
    entry.id = char(raw.ablation.id);
    entry.label = char(raw.ablation.configuration);
    entry.usesCNN = logical(raw.ablation.uses_cnn);
    entry.path = path;
    entry.config = raw;
    entry.qualityGate = logical(raw.pipeline.quality_gate);
    entry.enhancement = logical(raw.pipeline.enhancement);
    entry.lesionEvidence = logical(raw.pipeline.lesion_evidence);
    entry.agreementCheck = logical(raw.pipeline.agreement_check);
    entry.deferral = logical(raw.pipeline.deferral);
    entry.cacheKey = localCacheKey(entry.qualityGate, entry.enhancement);

    % The frozen model and threshold are not the ablated variable. Every
    % configuration inherits them so the comparison is like for like.
    entry.config.operating_point = defaultConfig.operating_point;
    entry.config.preprocessing = defaultConfig.preprocessing;
    entry.config.grading = defaultConfig.grading;

    if isempty(configs)
        configs = entry;
    else
        configs(index) = entry; %#ok<AGROW>
    end
end
end

function key = localCacheKey(qualityGate, enhancement)
key = sprintf('qg%d_enh%d', qualityGate, enhancement);
end

% ------------------------------------------------------- feature extraction

function cache = localExtractFeatures(configs, split, defaultConfig, ...
        checkpoint, frozen, projectRoot, options)
%LOCALEXTRACTFEATURES Run each distinct preprocessing setting exactly once.
%   Four configurations share two preprocessing settings, and the CNN
%   forward pass, candidate detection and Grad-CAM do not depend on which
%   decision mechanisms are switched on. Extracting once per setting and
%   composing decisions afterwards keeps the run to three passes.

keys = unique({configs.cacheKey}, 'stable');
cache = struct();
for keyIndex = 1:numel(keys)
    key = keys{keyIndex};
    members = configs(strcmp({configs.cacheKey}, key));
    needCNN = any([members.usesCNN]);
    needDetection = any([members.lesionEvidence] | [members.agreementCheck]);
    needGradCAM = any([members.agreementCheck]);

    config = defaultConfig;
    config.pipeline = members(1).config.pipeline;

    fprintf(['Feature pass %d of %d [%s]: cnn=%d detection=%d gradcam=%d ' ...
        '(serves %s)\n'], keyIndex, numel(keys), key, needCNN, ...
        needDetection, needGradCAM, strjoin({members.id}, ' '));

    cache.(key) = localFeaturePass(split, config, checkpoint, frozen, ...
        needCNN, needDetection, needGradCAM, projectRoot, options);
end
end

function features = localFeaturePass(split, config, checkpoint, frozen, ...
        needCNN, needDetection, needGradCAM, projectRoot, options)
n = split.n;
features = struct();
features.qualityClass = strings(n, 1);
features.enhancementApplied = false(n, 1);
features.clearlyGradableAfterEnhancement = false(n, 1);
features.predictedLevel = nan(n, 1);
features.referableProbability = nan(n, 1);
features.classProbabilities = nan(5, n);
features.candidateCount = nan(n, 1);
features.ruleLevel = nan(n, 1);
features.ruleReferable = false(n, 1);
features.ruleUncertain = true(n, 1);
% Tracked separately from ruleUncertain: uncertain is true whenever any
% evidence field is unknown, which includes the seven that have no detector
% in this build and are therefore unknown on every image.  Only a case-level
% unknown says anything about this image, and it is that distinction the
% decision policy acts on.  Mirrors app.runScreeningCase.
features.ruleCaseUnknown = true(n, 1);
features.ruleResults = cell(n, 1);
features.qualityResults = cell(n, 1);
features.spatiallyAgree = false(n, 1);
features.gradCamAvailable = false(n, 1);
features.evidenceSupportsCNN = false(n, 1);
features.failed = false(n, 1);

reportEvery = max(1, floor(n / 20));
passTimer = tic;
for index = 1:n
    detection = [];
    try
        image = imread(char(split.files(index)));
        [qualityResult, processedImage] = quality.assess(image, config);
        features.qualityClass(index) = string(qualityResult.class);
        features.qualityResults{index} = localSlimQualityResult(qualityResult);
        features.enhancementApplied(index) = localEnhancementApplied(qualityResult);
        features.clearlyGradableAfterEnhancement(index) = ...
            ~strcmpi(char(qualityResult.class), 'ungradable');

        if needCNN
            [modelImage, ~, preprocessingMetadata] = ...
                common.preprocess(image, config, 'inference');
            inference = grade.infer(checkpoint, modelImage, config, ...
                'ReturnLogits', true, 'Preprocessed', true, ...
                'QualityMetadata', qualityResult, ...
                'PreprocessingMetadata', preprocessingMetadata);
            calibrated = grade.applyTemperature(inference.logits, frozen.temperature);
            features.classProbabilities(:, index) = calibrated(:, 1);
            features.predictedLevel(index) = double(inference.predictedGrade(1));
            features.referableProbability(index) = sum(calibrated(3:5, 1));
        end

        if needDetection
            detection = segment.detect(processedImage, config);
            features.candidateCount(index) = detection.candidateCount;
            ruleResult = grade.icdrRule(localICDREvidence(config, detection));
            features.ruleResults{index} = ruleResult;
            features.ruleLevel(index) = ruleResult.level;
            features.ruleReferable(index) = ruleResult.referable;
            features.ruleUncertain(index) = ruleResult.uncertain;
            features.ruleCaseUnknown(index) = ruleResult.caseUnknownEvidence;
            if needCNN
                features.evidenceSupportsCNN(index) = localEvidenceSupportsCNN( ...
                    features.predictedLevel(index), detection, ruleResult);
            end
        end

        if needGradCAM && needCNN
            % WriteArtifacts false: only the returned maps are read, and
            % persisting 550 explanations costs about 24 GB.
            gradCAMResult = explain.gradcam(checkpoint, image, ...
                features.predictedLevel(index), 'WriteArtifacts', false);
            features.gradCamAvailable(index) = true;
            features.spatiallyAgree(index) = localSpatialAgreement( ...
                gradCAMResult, detection);
        end
    catch exception
        features.failed(index) = true;
        fprintf('  image %s failed: %s\n', split.imageIds(index), exception.message);
    end

    if mod(index, reportEvery) == 0 || index == n
        elapsed = toc(passTimer);
        fprintf('  %d/%d (%.0f%%), %.1f s elapsed, %.1f s/image\n', ...
            index, n, 100 * index / n, elapsed, elapsed / index);
    end
end

failedCount = sum(features.failed);
if failedCount > 0
    fprintf('  %d image(s) failed in this pass and are excluded.\n', failedCount);
end
end

% ------------------------------------------------------ decision composition

function decisions = localComposeDecisions(entry, cache, split, frozen)
features = cache.(entry.cacheKey);
n = split.n;

decisions = struct();
decisions.decision = strings(n, 1);
decisions.autonomous = false(n, 1);
decisions.predictedReferable = false(n, 1);
decisions.predictedLevel = nan(n, 1);
decisions.reason = strings(n, 1);

for index = 1:n
    if features.failed(index)
        decisions.decision(index) = "failed";
        decisions.reason(index) = "feature extraction failed";
        continue;
    end

    isUngradable = strcmpi(features.qualityClass(index), 'ungradable');
    if entry.qualityGate && isUngradable
        decisions.decision(index) = "human-review";
        decisions.reason(index) = "quality gate stopped inference";
        continue;
    end

    if ~entry.usesCNN
        % A3: the fully interpretable baseline. The ICDR rule engine is the
        % only decision maker; there is no model probability to threshold.
        rule = features.ruleResults{index};
        if isempty(rule)
            decisions.decision(index) = "failed";
            decisions.reason(index) = "no rule evidence";
            continue;
        end
        decisions.predictedLevel(index) = rule.level;
        decisions.predictedReferable(index) = rule.referable;
        decisions.decision(index) = localTwoWay(rule.referable);
        decisions.autonomous(index) = true;
        decisions.reason(index) = "icdr rule engine";
        continue;
    end

    decisions.predictedLevel(index) = features.predictedLevel(index);

    if ~entry.deferral
        % Deferral off is a forced binary disposition at the frozen
        % threshold. No case may be sent to a human on uncertainty.
        referable = features.referableProbability(index) >= frozen.threshold;
        decisions.predictedReferable(index) = referable;
        decisions.decision(index) = localTwoWay(referable);
        decisions.autonomous(index) = true;
        decisions.reason(index) = "threshold on calibrated probability";
        continue;
    end

    if ~entry.lesionEvidence
        % A4: deferral with the lesion channel switched off.  This is a
        % reduced policy and must be composed here, like the others.
        % grade.decisionPolicy requires rule evidence for auto-clear as a
        % locked safety invariant, so handing it a configuration that has
        % removed the evidence channel raises missing-rule-evidence on
        % every image and escalates all of them.  That measures the
        % contradiction between the flag and the invariant, not deferral.
        % The disposition uses the CNN alone, exactly as the semantics at
        % the top of this file state: clear below the auto-clear threshold,
        % refer at or above the referral threshold, and defer the band
        % between them, which is the whole of what deferral adds over A2.
        [decision, reason] = localCnnOnlyThreeWay( ...
            features.predictedLevel(index), ...
            features.referableProbability(index), entry.config);
        decisions.decision(index) = decision;
        decisions.reason(index) = reason;
        decisions.autonomous(index) = ~strcmp(decision, "escalate");
        decisions.predictedReferable(index) = strcmp(decision, "refer");
        continue;
    end

    policyResult = grade.decisionPolicy( ...
        localDecisionInput(entry, features, index), entry.config);
    decisions.decision(index) = string(policyResult.decision);
    decisions.reason(index) = string(strjoin(policyResult.reasonCodes, ','));
    decisions.autonomous(index) = ~strcmp(policyResult.decision, 'escalate');
    decisions.predictedReferable(index) = strcmp(policyResult.decision, 'refer');
end
end

function [decision, reason] = localCnnOnlyThreeWay(predictedLevel, ...
        probability, config)
%LOCALCNNONLYTHREEWAY The three-way disposition without the lesion channel.
%   Used where the ablation switches lesion evidence off but leaves deferral
%   on.  Deferral's contribution is the band between the two thresholds:
%   below the auto-clear threshold the patient goes home, at or above the
%   referral threshold they are referred, and in between a human decides.
policy = config.decision_policy;
if isfinite(predictedLevel) && predictedLevel == 4
    % Every predicted Level 4 reaches a human whatever the confidence.  That
    % is the declared mitigation for the neovascularisation data gap and it
    % does not depend on the lesion evidence channel.
    decision = "escalate";
    reason = "cnn-level-4";
elseif probability >= policy.referableThreshold
    decision = "refer";
    reason = "calibrated probability at or above the referral threshold";
elseif probability < policy.autoClearThreshold
    decision = "auto-clear";
    reason = "calibrated probability below the auto-clear threshold";
else
    decision = "escalate";
    reason = "calibrated probability in the deferral band";
end
end

function decision = localTwoWay(referable)
if referable
    decision = "refer";
else
    decision = "auto-clear";
end
end

function input = localDecisionInput(entry, features, index)
%LOCALDECISIONINPUT Build the grade.decisionPolicy input for one case.
%   Mirrors app.runScreeningCase. TestAblationHarness pins the two together
%   for A5; any change here must keep that test passing.

qualityResult = features.qualityResults{index};
qualityResult.metadata.postEnhancementQualityClass = ...
    localPostEnhancementQuality(qualityResult);

input = struct();
input.quality = qualityResult;
input.cnn = struct( ...
    'predictedLevel', features.predictedLevel(index), ...
    'calibratedReferableProbability', features.referableProbability(index), ...
    'classProbabilities', features.classProbabilities(:, index), ...
    'uncertaintyScore', [], ...
    'uncertaintyThreshold', []);

if entry.lesionEvidence
    input.ruleEngine = features.ruleResults{index};
else
    input.ruleEngine = struct();
end

if entry.agreementCheck
    input.explanation = struct( ...
        'gradCamMetadata', struct( ...
            'available', features.gradCamAvailable(index), ...
            'layer', '', ...
            'rawResolution', []), ...
        'lesionEvidenceMetadata', struct( ...
            'candidateEvidence', true, ...
            'evidenceKnown', ~features.ruleCaseUnknown(index), ...
            'referable', features.ruleReferable(index)), ...
        'gradCamAndLesionEvidenceSpatiallyAgree', features.spatiallyAgree(index), ...
        'lesionEvidenceSupportsCNN', features.evidenceSupportsCNN(index));
else
    input.explanation = struct();
end
end

% -------------------------------------------------------------------- metrics

function metrics = localMetrics(entry, decisions, split, frozen)
evaluated = ~strcmp(decisions.decision, "failed");
truth = split.grades(evaluated);
autonomous = decisions.autonomous(evaluated);
predictedReferable = decisions.predictedReferable(evaluated);
truthReferable = truth >= 2;

% referableMetrics derives the binary endpoint from ICDR levels, so the
% thresholded disposition is expressed as a pseudo-level: 2 for refer, 0
% for clear. That reuses the tested Wilson interval rather than repeating
% the arithmetic here.
pseudoLevel = zeros(size(predictedReferable));
pseudoLevel(predictedReferable) = 2;
allCases = referableMetrics(truth, pseudoLevel);

if any(autonomous)
    autoMetrics = referableMetrics(truth(autonomous), pseudoLevel(autonomous));
    autonomousAccuracy = mean(predictedReferable(autonomous) == truthReferable(autonomous));
else
    autoMetrics = referableMetrics([0; 2], [0; 2]);
    autoMetrics.sensitivity = NaN;
    autoMetrics.specificity = NaN;
    autonomousAccuracy = NaN;
end

metrics = struct();
metrics.id = string(entry.id);
metrics.label = string(entry.label);
metrics.n = numel(truth);
metrics.failed = sum(~evaluated);
metrics.coverage = mean(autonomous);
metrics.autonomousCount = sum(autonomous);
metrics.humanReviewCount = sum(~autonomous);
metrics.allCases = allCases;
metrics.autonomousSubset = autoMetrics;
metrics.autonomousAccuracy = autonomousAccuracy;
metrics.missedReferable = sum(truthReferable & ~predictedReferable & autonomous);
metrics.threshold = frozen.threshold;
metrics.decisionCounts = struct( ...
    'autoClear', sum(strcmp(decisions.decision, "auto-clear")), ...
    'refer', sum(strcmp(decisions.decision, "refer")), ...
    'escalate', sum(strcmp(decisions.decision, "escalate")), ...
    'humanReview', sum(strcmp(decisions.decision, "human-review")), ...
    'failed', sum(strcmp(decisions.decision, "failed")));

levels = decisions.predictedLevel(evaluated);
known = ~isnan(levels);
if any(known)
    metrics.confusionMatrix = confusionMatrix(truth(known), levels(known));
    metrics.perClassRecall = perClassRecall(truth(known), levels(known));
else
    metrics.confusionMatrix = zeros(5, 5);
    metrics.perClassRecall = nan(5, 1);
end
end

% ------------------------------------------------------------------ reporting

function localPrintConfig(entry, metrics)
fprintf('\n===== %s: %s =====\n', entry.id, entry.label);
fprintf('  n %d (failed %d)\n', metrics.n, metrics.failed);
fprintf('  Referable sensitivity (all cases): %.4f (95%% Wilson CI %.4f-%.4f, %d/%d)\n', ...
    metrics.allCases.sensitivity, metrics.allCases.sensitivityCILower, ...
    metrics.allCases.sensitivityCIUpper, metrics.allCases.truePositives, ...
    metrics.allCases.truePositives + metrics.allCases.falseNegatives);
fprintf('  Referable specificity (all cases): %.4f (95%% Wilson CI %.4f-%.4f, %d/%d)\n', ...
    metrics.allCases.specificity, metrics.allCases.specificityCILower, ...
    metrics.allCases.specificityCIUpper, metrics.allCases.trueNegatives, ...
    metrics.allCases.trueNegatives + metrics.allCases.falsePositives);
fprintf('  Coverage (handled autonomously): %.4f (%d of %d)\n', ...
    metrics.coverage, metrics.autonomousCount, metrics.n);
fprintf('  Accuracy on the autonomous subset: %.4f\n', metrics.autonomousAccuracy);
fprintf('  Referable cases missed autonomously: %d\n', metrics.missedReferable);
fprintf('  Decisions: auto-clear %d, refer %d, escalate %d, human-review %d\n', ...
    metrics.decisionCounts.autoClear, metrics.decisionCounts.refer, ...
    metrics.decisionCounts.escalate, metrics.decisionCounts.humanReview);
fprintf('  Per-class recall: %s\n', mat2str(round(metrics.perClassRecall', 4)));
end

function localPrintTable(rows)
fprintf('\n===== §11.6 ablation table =====\n');
fprintf('%-4s %-9s %-9s %-9s %-9s %-8s\n', ...
    'Cfg', 'Sens', 'Spec', 'Coverage', 'AutoAcc', 'Missed');
for index = 1:numel(rows)
    m = rows{index};
    fprintf('%-4s %-9.4f %-9.4f %-9.4f %-9.4f %-8d\n', m.id, ...
        m.allCases.sensitivity, m.allCases.specificity, m.coverage, ...
        m.autonomousAccuracy, m.missedReferable);
end
fprintf(['\nSens and spec are over all cases at the frozen threshold. ' ...
    'AutoAcc is\naccuracy on the subset handled without a human, which is ' ...
    'where deferral\nearns its keep (§11.6). Compare A5 with A1 at equal ' ...
    'coverage.\n']);
end

function localWriteOutputs(resultsDirectory, perConfig, configs, split, frozen, options)
summary = struct();
summary.split = char(split.name);
summary.n = split.n;
summary.evaluatedOn = char(datetime('now', 'Format', 'yyyy-MM-dd'));
summary.frozenOperatingPoint = frozen;
summary.sealedDataAccessed = false;
summary.configurations = struct([]);

lines = {'config,label,n,sensitivity,sensitivity_ci_lower,sensitivity_ci_upper,specificity,specificity_ci_lower,specificity_ci_upper,coverage,autonomous_accuracy,missed_referable,auto_clear,refer,escalate,human_review'};
for index = 1:numel(perConfig)
    m = perConfig(index);
    entry = struct( ...
        'id', char(m.id), 'label', char(m.label), 'n', m.n, ...
        'coverage', m.coverage, 'autonomousAccuracy', m.autonomousAccuracy, ...
        'missedReferable', m.missedReferable, ...
        'allCases', m.allCases, 'autonomousSubset', m.autonomousSubset, ...
        'confusionMatrix', m.confusionMatrix, ...
        'perClassRecall', m.perClassRecall, ...
        'decisionCounts', m.decisionCounts, ...
        'pipeline', configs(index).config.pipeline);
    if isempty(summary.configurations)
        summary.configurations = entry;
    else
        summary.configurations(index) = entry;
    end
    lines{end + 1} = sprintf('%s,"%s",%d,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%d,%d,%d,%d,%d', ...
        char(m.id), char(m.label), m.n, ...
        m.allCases.sensitivity, m.allCases.sensitivityCILower, m.allCases.sensitivityCIUpper, ...
        m.allCases.specificity, m.allCases.specificityCILower, m.allCases.specificityCIUpper, ...
        m.coverage, m.autonomousAccuracy, m.missedReferable, ...
        m.decisionCounts.autoClear, m.decisionCounts.refer, ...
        m.decisionCounts.escalate, m.decisionCounts.humanReview); %#ok<AGROW>
end

localWriteText(fullfile(resultsDirectory, 'ablation_table.csv'), strjoin(lines, newline));
localWriteText(fullfile(resultsDirectory, 'ablation_summary.json'), ...
    jsonencode(summary, 'PrettyPrint', true));
save(fullfile(resultsDirectory, 'ablation_results.mat'), 'perConfig', '-v7.3');
for index = 1:numel(configs)
    localWriteText(fullfile(resultsDirectory, sprintf('config_%s.json', configs(index).id)), ...
        jsonencode(configs(index).config, 'PrettyPrint', true));
end
localWriteText(fullfile(resultsDirectory, 'run_options.json'), ...
    jsonencode(options, 'PrettyPrint', true));
fprintf('\nResults written to %s\n', resultsDirectory);
end

% -------------------------------------------------------------------- helpers
% localSpatialAgreement and localPostEnhancementQuality reproduce
% app.runScreeningCase exactly.  TestAblationHarness fails if they stop
% matching.  Evidence construction and the evidence-support check are no
% longer reproduced here: both callers delegate to grade.icdrEvidence-
% FromDetection and grade.evidenceSupportsCNN, because two copies of the
% evidence schema is precisely how this path drifts from the deployed one
% while still passing its own tests.

function evidence = localICDREvidence(config, detection)
if isfield(config, 'app') && isstruct(config.app) && isfield(config.app, 'icdrEvidence')
    evidence = config.app.icdrEvidence;
    return;
end
evidence = grade.icdrEvidenceFromDetection(detection);
end

function answer = localSpatialAgreement(gradCAMResult, detection)
answer = false;
if isempty(detection) || ~isfield(gradCAMResult, 'normalizedHeatmap') || ...
        isempty(gradCAMResult.normalizedHeatmap)
    return;
end
if detection.candidateCount == 0
    answer = true;
    return;
end
heatmap = double(gradCAMResult.normalizedHeatmap);
coordinates = detection.candidateCoordinates;
valid = coordinates(:, 1) >= 1 & coordinates(:, 1) <= size(heatmap, 2) & ...
    coordinates(:, 2) >= 1 & coordinates(:, 2) <= size(heatmap, 1);
coordinates = round(coordinates(valid, :));
if isempty(coordinates)
    return;
end
linear = sub2ind(size(heatmap), coordinates(:, 2), coordinates(:, 1));
answer = mean(heatmap(linear) >= 0.35) >= 0.25;
end

function answer = localEvidenceSupportsCNN(predictedLevel, detection, rule)
answer = grade.evidenceSupportsCNN(predictedLevel, detection, rule);
end

function value = localPostEnhancementQuality(qualityResult)
if strcmpi(char(qualityResult.class), 'borderline')
    value = 'borderline';
else
    value = char(qualityResult.class);
end
end

function applied = localEnhancementApplied(qualityResult)
applied = false;
if isfield(qualityResult, 'enhancementApplied')
    applied = logical(qualityResult.enhancementApplied);
elseif isfield(qualityResult, 'isEnhanced')
    applied = logical(qualityResult.isEnhanced);
end
end

function slim = localSlimQualityResult(qualityResult)
%LOCALSLIMQUALITYRESULT Keep only what grade.decisionPolicy reads.
%   The full result carries a full-resolution logical FOV mask, about 6 MB
%   per image. Caching 550 of those exhausted a 16 GB machine part way
%   through the second feature pass. normalizeDecisionInput reads class,
%   metadata and enhancementApplied and nothing else.
slim = struct();
slim.class = qualityResult.class;
slim.qualityClass = qualityResult.qualityClass;
if isfield(qualityResult, 'metadata') && isstruct(qualityResult.metadata)
    slim.metadata = qualityResult.metadata;
else
    slim.metadata = struct();
end
if isfield(qualityResult, 'enhancementApplied')
    slim.enhancementApplied = qualityResult.enhancementApplied;
elseif isfield(qualityResult, 'isEnhanced')
    slim.enhancementApplied = qualityResult.isEnhanced;
end
if isfield(qualityResult, 'isEnhanced')
    slim.isEnhanced = qualityResult.isEnhanced;
end
end

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
