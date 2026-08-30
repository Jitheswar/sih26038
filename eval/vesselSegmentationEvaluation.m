function result = vesselSegmentationEvaluation(varargin)
%VESSELSEGMENTATIONEVALUATION Score a vessel checkpoint on a held-out split.
%   RESULT = vesselSegmentationEvaluation(CHECKPOINT) scores CHECKPOINT on
%   the DRIVE test split and reports the §6.3 metric set: sensitivity,
%   specificity and ROC AUC against the expert annotations.
%
%   Name-value options:
%     'Split'        Committed split name (default "test").
%     'Threshold'    Operating threshold; default is the checkpoint's.
%     'ResultsRoot'  Root for the dated result directory.
%
%   Every pixel scored lies inside the field-of-view mask.  A DRIVE frame is
%   31 per cent black corner outside the camera aperture and every one of
%   those pixels is a true negative, so scoring the whole frame adds a third
%   of a frame of free specificity and makes the number incomparable to the
%   published DRIVE results §6.3 wants to compare against.
%
%   What this number is and is not.  It is a held-out result: the three
%   frames were never trained on and never selected an epoch.  It is not
%   the DRIVE benchmark.  DRIVE's own test half ships without annotations in
%   the archive this project holds, so there is no local ground truth for
%   it; see data.createVesselSplits.  Three frames is a small denominator
%   and the intervals below are correspondingly wide, which is why they are
%   reported rather than a single decimal.

rng(42, 'twister');

options = localOptions(varargin{:});
projectRoot = localProjectRoot();

checkpointPath = options.checkpoint;
if isempty(checkpointPath)
    config = jsondecode(fileread(fullfile(projectRoot, 'config', ...
        'default.json')));
    if ~isfield(config, 'vessel_segmentation') || ...
            isempty(config.vessel_segmentation.checkpoint)
        error('eval:MissingVesselCheckpoint', ...
            ['No checkpoint given and vessel_segmentation.checkpoint is ' ...
            'empty in config/default.json.']);
    end
    checkpointPath = fullfile(projectRoot, ...
        config.vessel_segmentation.checkpoint);
end
if ~isfile(checkpointPath)
    error('eval:MissingVesselCheckpoint', ...
        'Vessel checkpoint does not exist: %s', checkpointPath);
end

model = load(checkpointPath, 'net', 'config', 'epoch');
vessel = model.config.vessel_segmentation;
threshold = options.threshold;
if isnan(threshold)
    threshold = vessel.operating_threshold;
end

splitFile = fullfile(projectRoot, 'data', 'splits', ...
    sprintf('vessel_%s.csv', options.split));
if ~isfile(splitFile)
    error('eval:MissingVesselSplit', ...
        'Vessel split file does not exist: %s', splitFile);
end
splitTable = readtable(splitFile, 'TextType', 'string', ...
    'Delimiter', ',', 'ReadVariableNames', true);

fprintf('Vessel segmentation evaluation on the DRIVE %s split: %d frames.\n', ...
    options.split, height(splitTable));
fprintf('Checkpoint: %s (epoch %d)\n', checkpointPath, model.epoch);
fprintf('Operating threshold: %.3f\n\n', threshold);

environment = "cpu";
if canUseGPU
    environment = "gpu";
end

thresholds = linspace(0, 1, vessel.roc_thresholds);
allScores = [];
allLabels = [];
perFrame = struct('imageId', {}, 'sensitivity', {}, 'specificity', {}, ...
    'auc', {}, 'vesselFraction', {});

for index = 1:height(splitTable)
    imagePath = fullfile(projectRoot, char(splitTable.relative_path(index)));
    manualPath = fullfile(projectRoot, char(splitTable.manual_path(index)));
    maskPath = fullfile(projectRoot, char(splitTable.mask_path(index)));

    image = imread(imagePath);
    vessels = imread(manualPath) > 0;
    fieldOfView = imread(maskPath) > 0;

    segmentation = segment.segmentVessels(image, model, ...
        'Environment', environment, 'FieldOfView', fieldOfView);

    scores = double(segmentation.probabilityMap(fieldOfView));
    labels = double(vessels(fieldOfView));
    allScores = [allScores; scores]; %#ok<AGROW>
    allLabels = [allLabels; labels]; %#ok<AGROW>

    frameMetrics = localMetrics(scores, labels, thresholds, threshold);
    perFrame(index).imageId = splitTable.image_id(index); %#ok<AGROW>
    perFrame(index).sensitivity = frameMetrics.sensitivity; %#ok<AGROW>
    perFrame(index).specificity = frameMetrics.specificity; %#ok<AGROW>
    perFrame(index).auc = frameMetrics.auc; %#ok<AGROW>
    perFrame(index).vesselFraction = mean(labels); %#ok<AGROW>

    fprintf('  %-10s sensitivity %.4f | specificity %.4f | AUC %.4f | vessels %.4f\n', ...
        splitTable.image_id(index), frameMetrics.sensitivity, ...
        frameMetrics.specificity, frameMetrics.auc, mean(labels));
end

pooled = localMetrics(allScores, allLabels, thresholds, threshold);

% Wilson intervals over pooled pixels.  These are pixel-level intervals and
% they are narrow because a frame holds hundreds of thousands of pixels;
% they describe sampling error over pixels, not over patients or frames, and
% the frame-to-frame spread printed above is the honest measure of how much
% this varies from eye to eye.  Both are reported for that reason.
sensitivityInterval = localWilson(pooled.truePositives, pooled.positiveCount);
specificityInterval = localWilson(pooled.trueNegatives, pooled.negativeCount);

fprintf('\n===== §6.3 vessel segmentation, DRIVE %s split =====\n', ...
    options.split);
fprintf('n = %d frames, %d pixels inside the field of view\n', ...
    height(splitTable), numel(allLabels));
fprintf('Vessel prevalence inside the field of view: %.4f\n\n', ...
    mean(allLabels));
fprintf('Sensitivity  %.4f  (95%% Wilson %.4f-%.4f, %d/%d pixels)\n', ...
    pooled.sensitivity, sensitivityInterval(1), sensitivityInterval(2), ...
    pooled.truePositives, pooled.positiveCount);
fprintf('Specificity  %.4f  (95%% Wilson %.4f-%.4f, %d/%d pixels)\n', ...
    pooled.specificity, specificityInterval(1), specificityInterval(2), ...
    pooled.trueNegatives, pooled.negativeCount);
fprintf('ROC AUC      %.4f\n', pooled.auc);
fprintf('\nPer frame, sensitivity %.4f-%.4f and specificity %.4f-%.4f.\n', ...
    min([perFrame.sensitivity]), max([perFrame.sensitivity]), ...
    min([perFrame.specificity]), max([perFrame.specificity]));

resultsRoot = options.resultsRoot;
if isempty(resultsRoot)
    resultsRoot = fullfile(projectRoot, 'results');
end
resultsDirectory = fullfile(resultsRoot, sprintf('%s_vessel_%s_evaluation', ...
    char(datetime('now', 'Format', 'yyyyMMdd_HHmmss')), options.split));
mkdir(resultsDirectory);

result = struct();
result.split = string(options.split);
result.checkpoint = string(checkpointPath);
result.epoch = model.epoch;
result.threshold = threshold;
result.frameCount = height(splitTable);
result.pixelCount = numel(allLabels);
result.prevalence = mean(allLabels);
result.sensitivity = pooled.sensitivity;
result.sensitivityInterval = sensitivityInterval;
result.specificity = pooled.specificity;
result.specificityInterval = specificityInterval;
result.auc = pooled.auc;
result.perFrame = perFrame;
result.resultsDirectory = string(resultsDirectory);

save(fullfile(resultsDirectory, 'vessel_evaluation.mat'), 'result', '-v7.3');
localWriteText(fullfile(resultsDirectory, 'summary.json'), ...
    jsonencode(rmfield(result, 'perFrame'), 'PrettyPrint', true));
fprintf('\nResults written to %s\n', resultsDirectory);
end

function metrics = localMetrics(scores, labels, thresholds, operatingThreshold)
positive = labels > 0;
negative = ~positive;
positiveCount = sum(positive);
negativeCount = sum(negative);

sensitivityCurve = zeros(numel(thresholds), 1);
specificityCurve = zeros(numel(thresholds), 1);
for index = 1:numel(thresholds)
    predicted = scores >= thresholds(index);
    sensitivityCurve(index) = sum(predicted & positive) / max(1, positiveCount);
    specificityCurve(index) = sum(~predicted & negative) / max(1, negativeCount);
end

falsePositiveRate = 1 - specificityCurve;
[falsePositiveRate, order] = sort(falsePositiveRate);
truePositiveRate = sensitivityCurve(order);

predicted = scores >= operatingThreshold;
metrics = struct();
metrics.auc = trapz(falsePositiveRate, truePositiveRate);
metrics.truePositives = sum(predicted & positive);
metrics.trueNegatives = sum(~predicted & negative);
metrics.positiveCount = positiveCount;
metrics.negativeCount = negativeCount;
metrics.sensitivity = metrics.truePositives / max(1, positiveCount);
metrics.specificity = metrics.trueNegatives / max(1, negativeCount);
end

function interval = localWilson(successes, total)
%LOCALWILSON 95 per cent Wilson score interval.
if total == 0
    interval = [NaN, NaN];
    return;
end
z = 1.959963984540054;
proportion = successes / total;
denominator = 1 + z ^ 2 / total;
centre = (proportion + z ^ 2 / (2 * total)) / denominator;
margin = z * sqrt(proportion * (1 - proportion) / total + ...
    z ^ 2 / (4 * total ^ 2)) / denominator;
interval = [max(0, centre - margin), min(1, centre + margin)];
end

function localWriteText(path, text)
fileId = fopen(path, 'w');
if fileId == -1
    error('eval:CannotWrite', 'Could not open %s for writing.', path);
end
cleanup = onCleanup(@() fclose(fileId)); %#ok<NASGU>
fwrite(fileId, char(text), 'char');
end

function options = localOptions(varargin)
parser = inputParser();
parser.addOptional('Checkpoint', '');
parser.addParameter('Split', 'test');
parser.addParameter('Threshold', NaN);
parser.addParameter('ResultsRoot', '');
parser.parse(varargin{:});

options = struct();
options.checkpoint = char(parser.Results.Checkpoint);
options.split = char(parser.Results.Split);
options.threshold = double(parser.Results.Threshold);
options.resultsRoot = char(parser.Results.ResultsRoot);

if strcmp(options.split, 'sealed')
    error('eval:SealedData', ...
        'The sealed set is not evaluated during development (§10.4).');
end
end

function projectRoot = localProjectRoot()
thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
end
