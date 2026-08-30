function result = trainVesselSegmentation(varargin)
%TRAINVESSELSEGMENTATION Train the DRIVE retinal vessel segmentation net.
%   RESULT = segment.trainVesselSegmentation(CONFIG) runs normal training.
%   RESULT = segment.trainVesselSegmentation(CONFIG,'Mode','smoke') runs one
%   short epoch over a handful of frames.
%   RESULT = segment.trainVesselSegmentation(CONFIG,'Mode','inspect') builds
%   the network and reads the splits without training.
%
%   This is §6.3 (R2.2).  §6.3 names three downstream uses and they are the
%   reason it is worth training rather than a box to tick: venous beading
%   assessment for the 4-2-1 rule that defines ICDR Level 3, vessel masking
%   to suppress false haemorrhage detections, since a dark vessel segment
%   and a haemorrhage look alike to the classical channel, and
%   neovascularisation features (§6.6).
%
%   None of those are wired into the screening pipeline by this commit.
%   This trains and measures the network; consuming it is separate work, and
%   claiming the downstream benefit before it is measured would be exactly
%   the kind of unearned claim §11.1 exists to prevent.
%
%   The test split is never trained on and never selects an epoch.  It is
%   three of DRIVE's twenty annotated frames; see data.createVesselSplits
%   for why the split is carved out of DRIVE's training half rather than
%   using DRIVE's own test half.

rng(42, 'twister');

if nargin == 0
    error('segment:MissingConfig', ...
        'A vessel segmentation configuration is required.');
end

[mode, resultsRoot] = localOptions(varargin{2:end});
[config, configText, projectRoot] = vesselConfiguration(varargin{1});

vessel = config.vessel_segmentation;
if ~vessel.enabled
    error('segment:VesselSegmentationDisabled', ...
        ['vessel_segmentation.enabled is false in this configuration. ' ...
        'Training a stage the config switches off would produce a ' ...
        'checkpoint the pipeline never loads.']);
end

if isempty(resultsRoot)
    resultsRoot = fullfile(projectRoot, 'results');
end

trainData = loadVesselSplit(config, projectRoot, 'train');
validationData = loadVesselSplit(config, projectRoot, 'validation');

if mode == "smoke"
    trainData = localTruncateSplit(trainData, vessel.smoke_images);
    validationData = localTruncateSplit(validationData, vessel.smoke_images);
    maxEpochs = vessel.smoke_epochs;
    patchesPerImage = vessel.smoke_patches_per_image;
    batchSize = vessel.smoke_batch_size;
else
    maxEpochs = vessel.max_epochs;
    patchesPerImage = vessel.patches_per_image;
    batchSize = vessel.batch_size;
end

net = buildVesselNetwork(config);

result = struct();
result.config = config;
result.trainImageCount = trainData.imageCount;
result.validationImageCount = validationData.imageCount;
result.mode = mode;
if mode == "inspect"
    result.status = "configured";
    result.net = net;
    return;
end

if ~isfolder(resultsRoot)
    mkdir(resultsRoot);
end
resultsDirectory = localResultsDirectory(resultsRoot);
mkdir(resultsDirectory);
localWriteText(fullfile(resultsDirectory, 'config.json'), configText);

environment = "cpu";
if canUseGPU
    environment = "gpu";
    net = dlupdate(@gpuArray, net);
    device = gpuDevice;
    fprintf('GPU is being used: %s\n', device.Name);
else
    fprintf('GPU is not available; using CPU.\n');
end

fprintf('Vessel segmentation training started.\n');
fprintf(['Dataset: DRIVE | patch: %dx%d | batch: %d | epochs: %d | ' ...
    'CLAHE: %d\n'], vessel.patch_size, vessel.patch_size, batchSize, ...
    maxEpochs, vessel.green_clahe);
fprintf('Train frames: %d | validation frames: %d | patches/frame: %d\n', ...
    trainData.imageCount, validationData.imageCount, patchesPerImage);

lossOptions = struct('diceWeight', vessel.dice_weight);
thresholds = linspace(0, 1, vessel.roc_thresholds);

% Frames are read and prepared once rather than once per epoch.  Fourteen
% DRIVE frames at 584x565 is a few megabytes, and adapthisteq over all of
% them costs more than an epoch of training does.
trainFrames = localPrepareFrames(trainData, vessel);
validationFrames = localPrepareFrames(validationData, vessel);

averageGradient = [];
averageSquaredGradient = [];
iteration = 0;

history = struct();
history.trainingLoss = zeros(maxEpochs, 1);
history.validationAUC = zeros(maxEpochs, 1);
history.validationSensitivity = zeros(maxEpochs, 1);
history.validationSpecificity = zeros(maxEpochs, 1);
history.epochsCompleted = 0;
history.epochCheckpoints = strings(maxEpochs, 1);

bestAUC = -Inf;
bestEpoch = 0;
epochsWithoutImprovement = 0;
bestCheckpoint = fullfile(resultsDirectory, 'best_vessel_model.mat');

for epoch = 1:maxEpochs
    epochOrder = randperm(trainData.imageCount);
    epochLoss = 0;
    epochBatches = 0;

    groupSize = min(vessel.shuffle_buffer_images, trainData.imageCount);
    for groupStart = 1:groupSize:trainData.imageCount
        groupEnd = min(trainData.imageCount, groupStart + groupSize - 1);
        groupIndices = epochOrder(groupStart:groupEnd);

        [patchPool, maskPool] = localCollectPatches(trainFrames, ...
            groupIndices, patchesPerImage, vessel);
        poolCount = size(patchPool, 4);
        if poolCount == 0
            continue;
        end
        poolOrder = randperm(poolCount);

        for firstPatch = 1:batchSize:poolCount
            lastPatch = min(poolCount, firstPatch + batchSize - 1);
            selection = poolOrder(firstPatch:lastPatch);

            input = dlarray(patchPool(:, :, :, selection), 'SSCB');
            targets = dlarray(single(maskPool(:, :, :, selection)), 'SSCB');
            if environment == "gpu"
                input = gpuArray(input);
                targets = gpuArray(targets);
            end

            [loss, gradients, state] = dlfeval(@vesselGradients, net, ...
                input, targets, lossOptions);
            net.State = state;

            iteration = iteration + 1;
            [net, averageGradient, averageSquaredGradient] = adamupdate( ...
                net, gradients, averageGradient, averageSquaredGradient, ...
                iteration, vessel.learning_rate);

            epochLoss = epochLoss + double(gather(extractdata(loss)));
            epochBatches = epochBatches + 1;
        end
    end

    if epochBatches == 0
        error('segment:NoVesselTrainingBatches', ...
            'Epoch %d produced no training batches.', epoch);
    end
    history.trainingLoss(epoch) = epochLoss / epochBatches;
    fprintf('TRAIN epoch %d: Loss: %.6f (%d batches)\n', epoch, ...
        history.trainingLoss(epoch), epochBatches);

    metrics = localValidate(net, config, validationFrames, thresholds, ...
        environment);
    fprintf(['VALIDATION epoch %d: AUC %.4f | sensitivity %.4f | ' ...
        'specificity %.4f | at threshold %.2f\n'], epoch, metrics.auc, ...
        metrics.sensitivity, metrics.specificity, ...
        vessel.operating_threshold);

    history.validationAUC(epoch) = metrics.auc;
    history.validationSensitivity(epoch) = metrics.sensitivity;
    history.validationSpecificity(epoch) = metrics.specificity;
    history.epochsCompleted = epoch;

    epochCheckpoint = fullfile(resultsDirectory, ...
        sprintf('vessel_epoch_%02d.mat', epoch));
    hostNet = localHostNetwork(net);
    localSaveCheckpoint(epochCheckpoint, hostNet, config, metrics, epoch);
    history.epochCheckpoints(epoch) = string(epochCheckpoint);

    if metrics.auc > bestAUC
        bestAUC = metrics.auc;
        bestEpoch = epoch;
        epochsWithoutImprovement = 0;
        localSaveCheckpoint(bestCheckpoint, hostNet, config, metrics, epoch);
        fprintf('Selected vessel checkpoint at epoch %d (AUC %.4f).\n', ...
            epoch, bestAUC);
    else
        epochsWithoutImprovement = epochsWithoutImprovement + 1;
        if vessel.early_stopping_patience > 0 && ...
                epochsWithoutImprovement >= vessel.early_stopping_patience
            fprintf(['EARLY STOP: validation AUC did not improve for ' ...
                '%d epoch(s).\n'], epochsWithoutImprovement);
            break;
        end
    end
end

fields = {'trainingLoss', 'validationAUC', 'validationSensitivity', ...
    'validationSpecificity', 'epochCheckpoints'};
for fieldIndex = 1:numel(fields)
    history.(fields{fieldIndex}) = ...
        history.(fields{fieldIndex})(1:history.epochsCompleted);
end

result.status = "trained";
result.resultsDirectory = string(resultsDirectory);
result.bestCheckpoint = string(bestCheckpoint);
result.bestEpoch = bestEpoch;
result.bestAUC = bestAUC;
result.history = history;
result.environment = environment;

localWriteText(fullfile(resultsDirectory, 'history.json'), ...
    jsonencode(history));
fprintf('Best epoch %d with validation AUC %.4f.\n', bestEpoch, bestAUC);
fprintf('Results written to %s\n', resultsDirectory);
end

function [mode, resultsRoot] = localOptions(varargin)
parser = inputParser();
parser.addParameter('Mode', "normal");
parser.addParameter('ResultsRoot', '');
parser.parse(varargin{:});
mode = string(parser.Results.Mode);
if ~any(mode == ["normal", "smoke", "inspect"])
    error('segment:InvalidMode', 'Mode must be normal, smoke or inspect.');
end
resultsRoot = parser.Results.ResultsRoot;
end

function splitData = localTruncateSplit(splitData, imageCount)
keep = 1:min(imageCount, splitData.imageCount);
splitData.imageIds = splitData.imageIds(keep);
splitData.imagePaths = splitData.imagePaths(keep);
splitData.manualPaths = splitData.manualPaths(keep);
splitData.maskPaths = splitData.maskPaths(keep);
splitData.vesselFraction = splitData.vesselFraction(keep);
splitData.imageCount = numel(keep);
end

function frames = localPrepareFrames(splitData, vessel)
%LOCALPREPAREFRAMES Read and prepare every frame in a split once.
% The raw frame is kept alongside the prepared one.  Validation scores
% whole frames through segment.segmentVessels, which prepares its own
% input, and handing it an already-prepared frame would apply CLAHE twice.
frames = struct('imageId', {}, 'image', {}, 'prepared', {}, 'vessels', {}, ...
    'fieldOfView', {});
for index = 1:splitData.imageCount
    image = imread(char(splitData.imagePaths(index)));
    vessels = imread(char(splitData.manualPaths(index))) > 0;
    fieldOfView = imread(char(splitData.maskPaths(index))) > 0;

    if ~isequal(size(vessels), size(fieldOfView)) || ...
            ~isequal(size(vessels), [size(image, 1), size(image, 2)])
        error('segment:VesselSizeMismatch', ...
            'Image, annotation and field-of-view mask differ in size for %s.', ...
            splitData.imageIds(index));
    end

    frames(index).imageId = splitData.imageIds(index); %#ok<AGROW>
    frames(index).image = image; %#ok<AGROW>
    frames(index).prepared = segment.vesselPreprocess(image, vessel); %#ok<AGROW>
    frames(index).vessels = vessels; %#ok<AGROW>
    frames(index).fieldOfView = fieldOfView; %#ok<AGROW>
end
end

function [patchPool, maskPool] = localCollectPatches(frames, imageIndices, ...
    patchesPerImage, vessel)
%LOCALCOLLECTPATCHES Sample patches from several frames into one pool.
%   Batches are drawn from a pool spanning several frames rather than from
%   one frame at a time.  A batch whose patches all come from one frame
%   shares that frame's illumination, which batch normalisation would read
%   as the statistics of the whole distribution.

patchSize = vessel.patch_size;
totalPatches = numel(imageIndices) * patchesPerImage;
patchPool = zeros(patchSize, patchSize, 1, totalPatches, 'single');
maskPool = false(patchSize, patchSize, 1, totalPatches);

cursor = 0;
for index = imageIndices
    frame = frames(index);
    [patches, masks] = segment.sampleVesselPatches(frame.prepared, ...
        frame.vessels, frame.fieldOfView, patchesPerImage, vessel, true);
    span = cursor + (1:size(patches, 4));
    patchPool(:, :, :, span) = patches;
    maskPool(:, :, :, span) = masks;
    cursor = span(end);
end

patchPool = patchPool(:, :, :, 1:cursor);
maskPool = maskPool(:, :, :, 1:cursor);
end

function metrics = localValidate(net, config, frames, thresholds, environment)
%LOCALVALIDATE Score whole validation frames inside the field of view.
%   Whole frames, not patches: the reported metric has to describe what the
%   network does when it is used, and it is used a frame at a time.
%
%   Pixels outside the field of view are excluded.  They are 31 per cent of
%   a DRIVE frame and they are all true negatives, so including them adds a
%   third of a frame of free specificity to every number and makes the
%   result incomparable to the published DRIVE results §6.3 wants to compare
%   against.

model = struct('net', net, 'config', config);

scores = [];
labels = [];
for index = 1:numel(frames)
    frame = frames(index);
    result = segment.segmentVessels(frame.image, model, ...
        'Environment', environment, 'FieldOfView', frame.fieldOfView);

    inside = frame.fieldOfView;
    scores = [scores; double(result.probabilityMap(inside))]; %#ok<AGROW>
    labels = [labels; double(frame.vessels(inside))]; %#ok<AGROW>
end

metrics = eval_vesselMetrics(scores, labels, thresholds, ...
    config.vessel_segmentation.operating_threshold);
end

function metrics = eval_vesselMetrics(scores, labels, thresholds, ...
    operatingThreshold)
%EVAL_VESSELMETRICS Sensitivity, specificity and trapezoidal ROC AUC.

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

% AUC by the trapezoidal rule over the ROC curve, ordered by increasing
% false-positive rate.
falsePositiveRate = 1 - specificityCurve;
[falsePositiveRate, order] = sort(falsePositiveRate);
truePositiveRate = sensitivityCurve(order);
metrics = struct();
metrics.auc = trapz(falsePositiveRate, truePositiveRate);

predicted = scores >= operatingThreshold;
metrics.sensitivity = sum(predicted & positive) / max(1, positiveCount);
metrics.specificity = sum(~predicted & negative) / max(1, negativeCount);
metrics.thresholds = thresholds(:);
metrics.sensitivityCurve = sensitivityCurve;
metrics.specificityCurve = specificityCurve;
metrics.positiveCount = positiveCount;
metrics.negativeCount = negativeCount;
end

function directory = localResultsDirectory(resultsRoot)
stamp = datetime('now', 'Format', 'yyyyMMdd_HHmmss');
directory = fullfile(resultsRoot, ...
    sprintf('%s_vessel_segmentation', char(stamp)));
suffix = 0;
while isfolder(directory)
    suffix = suffix + 1;
    directory = fullfile(resultsRoot, ...
        sprintf('%s_vessel_segmentation_%02d', char(stamp), suffix));
end
end

function net = localHostNetwork(net)
if canUseGPU
    net = dlupdate(@gather, net);
end
end

function localSaveCheckpoint(path, net, config, metrics, epoch) %#ok<INUSD>
save(path, 'net', 'config', 'metrics', 'epoch', '-v7.3');
end

function localWriteText(path, text)
fileId = fopen(path, 'w');
if fileId == -1
    error('segment:CannotWrite', 'Could not open %s for writing.', path);
end
cleanup = onCleanup(@() fclose(fileId));
fwrite(fileId, text, 'char');
end
