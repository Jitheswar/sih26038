function result = runScreeningCase(imageInput, checkpointPath, calibrationParameters, projectConfig)
%RUNSCREENINGCASE Run one complete local DR screening case.
%   RESULT = app.runScreeningCase(IMAGE, CHECKPOINT, CALIBRATION, CONFIG)
%   is the testable orchestration seam for the demo application.  IMAGE is
%   an image filename or a numeric/logical image array.  CALIBRATION is a
%   positive temperature, a calibration structure, or a .mat/.json file
%   containing a fitted temperature.
%
%   The quality gate runs before any model or evidence stage.  Classical
%   candidate evidence remains explicitly provisional throughout the result.

rng(42, 'twister');
projectRoot = localProjectRoot();
config = localReadProjectConfig(projectConfig, projectRoot);

if ischar(imageInput) || (isstring(imageInput) && isscalar(imageInput))
    localRejectSealedPath(char(imageInput), 'image');
end
[originalImage, imagePath] = localReadImage(imageInput);
localRejectSealedPath(imagePath, 'image');

% This is intentionally the first pipeline module call for every image.
[qualityResult, qualityProcessedImage] = quality.assess(originalImage, config);
qualityAdvice = qualityResult.recaptureAdvice;

result = localBaseResult(originalImage, qualityProcessedImage, imagePath, ...
    checkpointPath, calibrationParameters, config);
result.qualityResult = qualityResult;
result.qualityAdvice = qualityAdvice;

if strcmpi(char(qualityResult.class), 'ungradable')
    result.status = "stopped_quality_gate";
    result.warnings = { ...
        'The quality gate stopped inference because the image is ungradable.', ...
        'No model, Grad-CAM, or candidate evidence was generated.'};
    result.limitations = localLimitations();
    result.threeWayDecision = grade.decisionPolicy( ...
        struct('quality', qualityResult), localDecisionConfig(config));
    result.agreementStatus = result.threeWayDecision.agreementStatus;
    result.reportMetadata.status = 'quality gate stopped inference';
    return;
end

checkpointPath = localRequirePath(checkpointPath, 'checkpoint', ...
    'app:MissingCheckpoint');
localRejectSealedPath(checkpointPath, 'checkpoint');
[temperature, calibrationMetadata] = localResolveTemperature( ...
    calibrationParameters);

% common.preprocess is the only preprocessing function used by this seam.
% The returned model image is passed into grade.infer through its explicit
% preprocessed-input seam so the model path does not normalize it again.
[modelImage, preprocessingQuality, preprocessingMetadata] = ...
    common.preprocess(originalImage, config, 'inference');
if isempty(qualityResult.fovMask) && isfield(preprocessingQuality, 'fovMask')
    qualityResult = preprocessingQuality;
    result.qualityResult = qualityResult;
    result.qualityAdvice = qualityResult.recaptureAdvice;
end

inference = grade.infer(checkpointPath, modelImage, config, ...
    'ReturnLogits', true, 'Preprocessed', true, ...
    'QualityMetadata', qualityResult, ...
    'PreprocessingMetadata', preprocessingMetadata);
if isempty(inference.logits)
    error('app:MissingLogits', ...
        'The baseline model did not return logits for calibration.');
end

[calibratedClassProbabilities, scaledLogits] = ...
    grade.applyTemperature(inference.logits, temperature);
[~, calibratedPredictedIndex] = max(calibratedClassProbabilities, [], 1);
predictedLevel = double(inference.predictedGrade(1));
calibratedReferableProbability = sum( ...
    calibratedClassProbabilities(3:5, 1));

gradCAMResult = explain.gradcam(checkpointPath, originalImage, predictedLevel, ...
    'ResultsRoot', fullfile(projectRoot, 'results'));

candidateDetection = segment.detect(qualityProcessedImage, config);
cnnEvidenceSummary = struct( ...
    'predictedLevel', predictedLevel, ...
    'calibratedReferableProbability', calibratedReferableProbability);
lesionCandidateEvidence = explain.buildLesionEvidence( ...
    qualityProcessedImage, candidateDetection, cnnEvidenceSummary);

% Track B, the learned lesion segmentation, when the config enables it and
% names a checkpoint.  Track A above always runs: §6.4 requires the
% classical detector to remain available so a failure of the learned
% microaneurysm head cannot leave the evidence channel empty.
learnedLesionEvidence = localLearnedLesionEvidence(config, projectRoot, ...
    qualityProcessedImage);
evidenceDetection = localEvidenceDetection(candidateDetection, ...
    learnedLesionEvidence);

icdrEvidence = localICDREvidence(config, candidateDetection, ...
    learnedLesionEvidence);
icdrRuleResult = grade.icdrRule(icdrEvidence);

explanationInput = struct( ...
    'gradCamMetadata', struct( ...
        'available', true, ...
        'layer', gradCAMResult.convolutionalLayerName, ...
        'rawResolution', gradCAMResult.rawHeatmapResolution), ...
    'lesionEvidenceMetadata', struct( ...
        'candidateEvidence', true, ...
        'learnedSegmentation', ~isempty(learnedLesionEvidence), ...
        'evidenceSource', char(icdrEvidence.evidenceSource), ...
        'evidenceKnown', ~icdrRuleResult.caseUnknownEvidence, ...
        'referable', icdrRuleResult.referable), ...
    'gradCamAndLesionEvidenceSpatiallyAgree', ...
        localSpatialAgreement(gradCAMResult, evidenceDetection, ...
        localSpatialConstants(config)), ...
    'lesionEvidenceSupportsCNN', ...
        localEvidenceSupportsCNN(predictedLevel, evidenceDetection, ...
        icdrRuleResult));

decisionInput = struct();
decisionInput.quality = qualityResult;
decisionInput.quality.metadata.postEnhancementQualityClass = ...
    localPostEnhancementQuality(qualityResult);
decisionInput.cnn = struct( ...
    'predictedLevel', predictedLevel, ...
    'calibratedReferableProbability', calibratedReferableProbability, ...
    'classProbabilities', calibratedClassProbabilities(:, 1), ...
    'uncertaintyScore', [], ...
    'uncertaintyThreshold', []);
decisionInput.ruleEngine = icdrRuleResult;
decisionInput.explanation = explanationInput;
threeWayDecision = grade.decisionPolicy(decisionInput, ...
    localDecisionConfig(config));

result.status = "completed";
result.processedImage = qualityProcessedImage;
result.modelInputImage = modelImage;
result.preprocessingMetadata = preprocessingMetadata;
result.predictedICDRLevel = predictedLevel;
result.calibratedReferableProbability = calibratedReferableProbability;
result.classProbabilities = inference.probabilities(:, 1);
result.classProbabilitiesAreCalibrated = false;
result.classProbabilitiesDescription = ...
    'Raw softmax class probabilities; not calibrated confidence.';
result.calibratedClassProbabilities = calibratedClassProbabilities(:, 1);
result.calibratedClassProbabilitiesAreCalibrated = true;
result.temperatureScaledLogits = scaledLogits(:, 1);
result.calibration = calibrationMetadata;
result.gradCAMResult = gradCAMResult;
result.lesionCandidateEvidence = lesionCandidateEvidence;
result.icdrRuleResult = icdrRuleResult;
result.threeWayDecision = threeWayDecision;
result.agreementStatus = threeWayDecision.agreementStatus;
result.reportMetadata = localCompletedReportMetadata(result, config, imagePath);
result.warnings = localWarnings(icdrRuleResult, threeWayDecision);
if isempty(learnedLesionEvidence)
    result.limitations = localLimitations();
else
    result.limitations = localLimitations(icdrEvidence.evidenceSource);
end
end

function result = localBaseResult(originalImage, processedImage, imagePath, ...
        checkpointPath, calibrationParameters, config)
imageIdentifier = localImageIdentifier(imagePath);
result = struct();
result.status = "initializing";
result.originalImage = originalImage;
result.processedImage = processedImage;
result.modelInputImage = [];
result.qualityResult = struct();
result.qualityAdvice = {};
result.predictedICDRLevel = [];
result.calibratedReferableProbability = [];
result.classProbabilities = [];
result.classProbabilitiesAreCalibrated = false;
result.classProbabilitiesDescription = ...
    'Raw softmax class probabilities; not calibrated confidence.';
result.calibratedClassProbabilities = [];
result.calibratedClassProbabilitiesAreCalibrated = true;
result.temperatureScaledLogits = [];
result.calibration = struct('temperature', [], 'source', 'not resolved');
result.gradCAMResult = struct();
result.lesionCandidateEvidence = struct();
result.icdrRuleResult = struct();
result.threeWayDecision = struct();
result.agreementStatus = 'not assessed';
result.reportMetadata = struct( ...
    'timestamp', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), ...
    'imageIdentifier', imageIdentifier, ...
    'patientIdentifier', imageIdentifier, ...
    'imagePath', imagePath, ...
    'checkpointPath', char(checkpointPath), ...
    'calibrationSource', localInputDescription(calibrationParameters), ...
    'projectConfiguration', localInputDescription(config), ...
    'sealedDataAccessed', false, ...
    'status', 'not completed');
result.preprocessingMetadata = struct();
result.warnings = {};
result.limitations = localLimitations();
end

function config = localReadProjectConfig(inputConfig, projectRoot)
if nargin < 1 || isempty(inputConfig)
    inputConfig = fullfile(projectRoot, 'config', 'default.json');
end
if ischar(inputConfig) || (isstring(inputConfig) && isscalar(inputConfig))
    configPath = char(inputConfig);
    localRejectSealedPath(configPath, 'project configuration');
    if ~isfile(configPath)
        configPath = fullfile(projectRoot, configPath);
    end
    if ~isfile(configPath)
        error('app:MissingConfig', ...
            'Project configuration does not exist: %s', char(inputConfig));
    end
    try
        config = jsondecode(fileread(configPath));
    catch exception
        error('app:InvalidConfig', ...
            'Project configuration could not be decoded: %s', exception.message);
    end
elseif isstruct(inputConfig) && isscalar(inputConfig)
    config = inputConfig;
else
    error('app:InvalidConfig', ...
        'Project configuration must be a JSON path or scalar structure.');
end
end

function [image, imagePath] = localReadImage(inputImage)
imagePath = '';
if ischar(inputImage) || (isstring(inputImage) && isscalar(inputImage))
    imagePath = char(inputImage);
    if ~isfile(imagePath)
        error('app:MissingImage', 'Image does not exist: %s', imagePath);
    end
    try
        [image, map] = imread(imagePath);
        if ~isempty(map)
            image = ind2rgb(image, map);
        end
    catch exception
        error('app:UnreadableImage', ...
            'Image could not be read: %s', exception.message);
    end
else
    image = inputImage;
end
if isempty(image) || ~(isnumeric(image) || islogical(image)) || ~isreal(image)
    error('app:InvalidImage', ...
        'The image must be a non-empty real numeric or logical array.');
end
end

function checkpointPath = localRequirePath(inputPath, description, errorId)
if ~(ischar(inputPath) || (isstring(inputPath) && isscalar(inputPath)))
    error(errorId, 'The %s must be a file path.', description);
end
checkpointPath = char(inputPath);
if ~isfile(checkpointPath)
    error(errorId, 'The %s does not exist: %s', description, checkpointPath);
end
end

function [temperature, metadata] = localResolveTemperature(input)
metadata = struct('temperature', [], 'source', localInputDescription(input));
if isnumeric(input) && isscalar(input) && isfinite(input) && input > 0
    temperature = double(input);
    metadata.temperature = temperature;
    metadata.source = 'numeric calibration parameter';
    return;
end
if isstruct(input) && isscalar(input)
    temperature = localTemperatureField(input);
    if isempty(temperature)
        error('app:InvalidCalibration', ...
            'Calibration structure does not contain a positive temperature.');
    end
    metadata.temperature = temperature;
    metadata.source = 'calibration structure';
    return;
end
if ~(ischar(input) || (isstring(input) && isscalar(input)))
    error('app:MissingCalibration', ...
        'Calibration parameters must be a temperature, structure, or file path.');
end
calibrationPath = char(input);
localRejectSealedPath(calibrationPath, 'calibration parameters');
if ~isfile(calibrationPath)
    error('app:MissingCalibration', ...
        'Calibration file does not exist: %s', calibrationPath);
end
[~, ~, extension] = fileparts(calibrationPath);
try
    if strcmpi(extension, '.json')
        loaded = jsondecode(fileread(calibrationPath));
    else
        loaded = load(calibrationPath);
    end
catch exception
    error('app:InvalidCalibration', ...
        'Calibration file could not be loaded: %s', exception.message);
end
temperature = localTemperatureField(loaded);
if isempty(temperature)
    error('app:InvalidCalibration', ...
        'Calibration file does not contain a positive temperature.');
end
metadata.temperature = temperature;
metadata.source = calibrationPath;
if isstruct(loaded) && isfield(loaded, 'temperatureFit')
    metadata.fit = loaded.temperatureFit;
elseif isstruct(loaded) && isfield(loaded, 'calibrationResult')
    metadata.fit = loaded.calibrationResult;
end
end

function temperature = localTemperatureField(value)
temperature = [];
if isnumeric(value) && isscalar(value) && isfinite(value) && value > 0
    temperature = double(value);
    return;
end
if ~isstruct(value) || ~isscalar(value)
    return;
end
names = {'temperature', 'temperatureFit', 'calibrationResult'};
for index = 1:numel(names)
    if isfield(value, names{index})
        temperature = localTemperatureField(value.(names{index}));
        if ~isempty(temperature)
            return;
        end
    end
end
end

function evidence = localICDREvidence(config, detection, learnedLesionEvidence)
if isfield(config, 'app') && isstruct(config.app) && ...
        isfield(config.app, 'icdrEvidence')
    evidence = config.app.icdrEvidence;
    if ~isstruct(evidence) || ~isscalar(evidence)
        error('app:InvalidICDREvidence', ...
            'app.icdrEvidence must be a scalar evidence structure.');
    end
    return;
end
if nargin >= 3 && ~isempty(learnedLesionEvidence)
    evidence = grade.icdrEvidenceFromLesionSegmentation( ...
        learnedLesionEvidence, detection, localEvidenceHeads(config));
    return;
end
evidence = grade.icdrEvidenceFromDetection(detection);
end

function learnedLesionEvidence = localLearnedLesionEvidence(config, ...
    projectRoot, image)
%LOCALLEARNEDLESIONEVIDENCE Run Track B when the config switches it on.
%   Returns empty when the stage is disabled or no checkpoint is configured,
%   which leaves the pipeline on the classical Track A evidence it has
%   always used.  The stage is switched from config rather than by editing
%   this function (§11.6, §13.3), so the ablation that measures what the
%   learned channel contributes is a config file rather than a code branch.

learnedLesionEvidence = [];
if ~isfield(config, 'pipeline') || ~isstruct(config.pipeline) || ...
        ~isfield(config.pipeline, 'learned_lesion_evidence') || ...
        ~config.pipeline.learned_lesion_evidence
    return;
end
if ~isfield(config, 'lesion_segmentation') || ...
        ~isstruct(config.lesion_segmentation) || ...
        ~isfield(config.lesion_segmentation, 'checkpoint') || ...
        isempty(config.lesion_segmentation.checkpoint)
    return;
end

checkpointPath = char(config.lesion_segmentation.checkpoint);
if ~isfile(checkpointPath)
    checkpointPath = fullfile(projectRoot, checkpointPath);
end
if ~isfile(checkpointPath)
    error('app:MissingLesionCheckpoint', ...
        ['pipeline.learned_lesion_evidence is enabled but the checkpoint ' ...
        '%s does not exist. Silently falling back to the classical ' ...
        'channel would report a pipeline the config does not describe.'], ...
        char(config.lesion_segmentation.checkpoint));
end

learnedLesionEvidence = segment.lesionEvidence(image, checkpointPath, ...
    'Thresholds', localEvidenceThresholds(config));
end


function thresholds = localEvidenceThresholds(config)
%LOCALEVIDENCETHRESHOLDS Per-head operating thresholds named by the config.
%   Empty falls back to the checkpoint's own thresholds, which maximise
%   pixel F1 on IDRiD.  §11.7 measured that those do not transfer to APTOS,
%   so a deployed configuration is expected to name its own, re-selected on
%   the calibration split.
thresholds = [];
if ~isfield(config, 'lesion_segmentation')
    return;
end
lesion = config.lesion_segmentation;
if ~isfield(lesion, 'evidence_thresholds') || isempty(lesion.evidence_thresholds)
    return;
end
lesionTypes = lesion.lesion_types;
if ischar(lesionTypes)
    lesionTypes = {lesionTypes};
end
requested = lesion.evidence_thresholds;
thresholds = zeros(numel(lesionTypes), 1);
for index = 1:numel(lesionTypes)
    lesionType = lesionTypes{index};
    if ~isfield(requested, lesionType)
        error('app:MissingEvidenceThreshold', ...
            ['lesion_segmentation.evidence_thresholds names no threshold ' ...
            'for head %s. Refusing to fall back to a default for one head ' ...
            'while honouring the configuration for the others.'], lesionType);
    end
    thresholds(index) = double(requested.(lesionType));
end
end


function heads = localEvidenceHeads(config)
%LOCALEVIDENCEHEADS Which lesion heads the configuration trusts as evidence.
%   Empty means every trained head.  §11.7 measured why this is not the
%   same question as which heads the network was trained for.
heads = {};
if ~isfield(config, 'lesion_segmentation')
    return;
end
lesion = config.lesion_segmentation;
if ~isfield(lesion, 'evidence_heads') || isempty(lesion.evidence_heads)
    return;
end
heads = lesion.evidence_heads;
if ischar(heads)
    heads = {heads};
end
heads = cellstr(heads);
end

function detection = localEvidenceDetection(candidateDetection, ...
    learnedLesionEvidence)
%LOCALEVIDENCEDETECTION Present the active evidence channel in one shape.
%   The Grad-CAM agreement check and the under-detection check both read a
%   lesion count and a list of lesion coordinates.  Adapting the learned
%   evidence into that shape keeps a single implementation of each check,
%   rather than a second copy that could drift from the first.

if isempty(learnedLesionEvidence)
    detection = candidateDetection;
    return;
end

lesionTypes = learnedLesionEvidence.lesionTypes;
coordinates = zeros(0, 2);
for typeIndex = 1:numel(lesionTypes)
    coordinates = [coordinates; ...
        learnedLesionEvidence.centroids.(lesionTypes{typeIndex})]; %#ok<AGROW>
end

detection = struct( ...
    'candidateCount', size(coordinates, 1), ...
    'candidateCoordinates', coordinates, ...
    'candidateScores', ones(size(coordinates, 1), 1), ...
    'evidenceSource', 'learned lesion segmentation');
end

function value = localPostEnhancementQuality(qualityResult)
if strcmpi(char(qualityResult.class), 'borderline')
    value = 'borderline';
else
    value = char(qualityResult.class);
end
end

function constants = localSpatialConstants(projectConfig)
%LOCALSPATIALCONSTANTS The §8.6 spatial test's two constants, from config.
%   Read through localDecisionConfig so a configuration that omits the
%   decision policy gets the same frozen fallback the policy itself gets,
%   rather than a second set of defaults living here.
policy = localDecisionConfig(projectConfig).decision_policy;
constants = struct();
for name = ["spatialAttentionCut", "spatial_attention_cut", ...
        "spatialAgreementFraction", "spatial_agreement_fraction"]
    if isfield(policy, name)
        constants.(name) = policy.(name);
    end
end
end

function [answer, evidence] = localSpatialAgreement(gradCAMResult, detection, configuration)
%LOCALSPATIALAGREEMENT Delegate to the shared §8.6 spatial test.
%   Shared with eval/ablationHarness.m through grade.spatialAgreement so
%   the ablation cannot drift from the deployed pipeline.
[answer, evidence] = grade.spatialAgreement(gradCAMResult, detection, ...
    configuration);
end

function answer = localEvidenceSupportsCNN(predictedLevel, detection, rule)
answer = grade.evidenceSupportsCNN(predictedLevel, detection, rule);
end

function config = localDecisionConfig(projectConfig)
config = projectConfig;
if ~isfield(config, 'decision_policy') || ~isstruct(config.decision_policy)
    % Matches the operating point frozen on 23 August 2026.  A fallback that
    % still carried the pre-freeze 0.20 would silently screen at a different
    % threshold than every reported number whenever a config omitted the
    % section.
    config.decision_policy = struct( ...
        'referableThreshold', 0.70, ...
        'autoClearThreshold', 0.40, ...
        'uncertaintyThreshold', 0.50, ...
        'requireEvidenceForAutoClear', true, ...
        'alwaysEscalateLevel4', true, ...
        'escalateOnUnknownEvidence', true, ...
        'escalateOnExplanationDisagreement', true, ...
        'escalateOnCapabilityGap', false);
end
end

function result = localCompletedReportMetadata(result, config, imagePath)
result = struct( ...
    'timestamp', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')), ...
    'imageIdentifier', localImageIdentifier(imagePath), ...
    'patientIdentifier', localImageIdentifier(imagePath), ...
    'imagePath', imagePath, ...
    'checkpointPath', char(result.reportMetadata.checkpointPath), ...
    'calibrationSource', char(result.calibration.source), ...
    'temperature', result.calibration.temperature, ...
    'projectConfiguration', localInputDescription(config), ...
    'sealedDataAccessed', false, ...
    'status', 'completed', ...
    'footer', 'Screening aid. Not a diagnosis. Requires clinician confirmation.');
end

function warnings = localWarnings(rule, decision)
warnings = { ...
    'Classical candidate evidence is provisional and not clinically validated lesion segmentation.', ...
    'Raw softmax class probabilities are displayed only as raw model output, never as calibrated confidence.', ...
    'Grad-CAM is regional model attention, not precise lesion localisation.', ...
    'This screening aid is a research prototype and requires clinician confirmation.'};
if rule.uncertain
    warnings{end + 1} = rule.uncertaintyWarning;
end
if strcmp(decision.decision, 'escalate')
    warnings{end + 1} = decision.decisionReason;
end
end

function limitations = localLimitations(learnedSegmentationSource)
%LOCALLIMITATIONS Limitations text for the report.
%   LEARNEDSEGMENTATIONSOURCE is the evidence source description when the
%   learned lesion segmentation contributed to this case, and is omitted or
%   empty when it did not.
%
%   The first entry has to follow what actually ran. Stating that no learned
%   lesion segmentation is used, on a case whose rule trace in the same report
%   reads "Received evidence source: learned lesion segmentation (EX)", is a
%   contradiction a reader is entitled to trust the wrong half of. The entry
%   was written before the learned channel existed and stopped being true once
%   the config could enable it.
if nargin < 1 || isempty(learnedSegmentationSource)
    segmentationLimitation = 'No learned lesion segmentation is used.';
else
    segmentationLimitation = sprintf( ...
        ['Lesion evidence came from %s, which is not clinically ', ...
        'validated lesion segmentation.'], char(learnedSegmentationSource));
end
limitations = { ...
    segmentationLimitation, ...
    'No MC dropout or final clinical validation is implemented.', ...
    'Classical candidate evidence is provisional and not clinically validated lesion segmentation.', ...
    'This prototype has no CDSCO clearance and must not be used for clinical decision-making.', ...
    'Messidor-2 and data/sealed/ are not read, loaded, evaluated, or modified.'};
end

function identifier = localImageIdentifier(imagePath)
if isempty(imagePath)
    identifier = 'array-input';
else
    [~, name, extension] = fileparts(imagePath);
    identifier = [name, extension];
end
end

function text = localInputDescription(value)
if ischar(value)
    text = value;
elseif isstring(value) && isscalar(value)
    text = char(value);
elseif isstruct(value)
    text = 'scalar configuration or calibration structure';
elseif isempty(value)
    text = 'not supplied';
else
    text = class(value);
end
end

function localRejectSealedPath(path, description)
if isempty(path)
    return;
end
normalizedPath = lower(strrep(char(path), '\\', '/'));
if contains(normalizedPath, '/data/sealed/') || ...
        endsWith(normalizedPath, '/data/sealed')
    error('app:SealedData', ...
        'The %s is inside data/sealed and cannot be used.', description);
end
end

function root = localProjectRoot()
thisFile = mfilename('fullpath');
root = fileparts(fileparts(fileparts(thisFile)));
end
