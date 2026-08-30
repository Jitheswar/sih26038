function result = trainLesionSegmentation(varargin)
%TRAINLESIONSEGMENTATION Train the IDRiD multi-label lesion segmentation net.
%   RESULT = segment.trainLesionSegmentation(CONFIG) runs normal training.
%   RESULT = segment.trainLesionSegmentation(CONFIG,'Mode','smoke') runs one
%   short epoch over a handful of images.
%   RESULT = segment.trainLesionSegmentation(CONFIG,'Mode','inspect') builds
%   the network and reads the splits without training.
%
%   This is Track B of §6.4 and §6.5.  It exists because the measured
%   §11.7 result says the classical candidate channel carries no localising
%   information (pointing-game lift 0.96x, which is chance), and the
%   measured §11.6 A3 result says the same channel reaches 0.0000
%   sensitivity because counting microaneurysms can never satisfy an ICDR
%   criterion above Level 1.  Haemorrhages and exudates are what unlock
%   Levels 2 and 3, and per §6.5 they are the easier targets: measured over
%   Set-A they cover 1.00 and 0.81 per cent of the frame against 0.107 per
%   cent for microaneurysms.
%
%   Set-B is never trained on and never selects an epoch.  It is the
%   published IDRiD benchmark split and the set §11.7 already reports
%   explanation quality against.

rng(42, 'twister');

if nargin == 0
    error('segment:MissingConfig', ...
        'A lesion segmentation configuration is required.');
end

[mode, resultsRoot] = localOptions(varargin{2:end});
[config, configText, projectRoot] = lesionConfiguration(varargin{1});
addpath(fullfile(projectRoot, 'eval'));
addpath(fullfile(projectRoot, 'eval', 'metrics'));

lesion = config.lesion_segmentation;
if ~lesion.enabled
    error('segment:LesionSegmentationDisabled', ...
        ['lesion_segmentation.enabled is false in this configuration. ' ...
        'Training a stage the config switches off would produce a ' ...
        'checkpoint the pipeline never loads.']);
end

lesionTypes = lesion.lesion_types;
typeCount = numel(lesionTypes);
if isempty(resultsRoot)
    resultsRoot = fullfile(projectRoot, 'results');
end

trainData = loadLesionSplit(config, projectRoot, 'train');
validationData = loadLesionSplit(config, projectRoot, 'validation');

if mode == "smoke"
    trainData = localTruncateSplit(trainData, lesion.smoke_images);
    validationData = localTruncateSplit(validationData, lesion.smoke_images);
    maxEpochs = lesion.smoke_epochs;
    patchesPerImage = lesion.smoke_patches_per_image;
    batchSize = lesion.smoke_batch_size;
else
    maxEpochs = lesion.max_epochs;
    patchesPerImage = lesion.patches_per_image;
    batchSize = lesion.batch_size;
end

net = buildLesionNetwork(config);

result = struct();
result.config = config;
result.lesionTypes = lesionTypes;
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

fprintf('Lesion segmentation training started.\n');
fprintf(['Dataset: IDRiD Set-A | types: %s | patch: %dx%d | batch: %d | ' ...
    'epochs: %d\n'], strjoin(lesionTypes(:)', ','), lesion.patch_size, ...
    lesion.patch_size, batchSize, maxEpochs);
fprintf('Train frames: %d | validation frames: %d | patches/frame: %d\n', ...
    trainData.imageCount, validationData.imageCount, patchesPerImage);

lossOptions = struct('alpha', lesion.tversky_alpha, ...
    'beta', lesion.tversky_beta, 'gamma', lesion.focal_gamma);
thresholds = linspace(0, 1, lesion.aupr_thresholds);

averageGradient = [];
averageSquaredGradient = [];
iteration = 0;

history = struct();
history.trainingLoss = zeros(maxEpochs, 1);
history.meanAUPR = zeros(maxEpochs, 1);
history.auprPerType = zeros(maxEpochs, typeCount);
history.epochsCompleted = 0;
history.epochCheckpoints = strings(maxEpochs, 1);

bestMeanAUPR = -Inf;
bestEpoch = 0;
epochsWithoutImprovement = 0;
bestCheckpoint = fullfile(resultsDirectory, 'best_lesion_model.mat');

for epoch = 1:maxEpochs
    epochOrder = randperm(trainData.imageCount);
    epochLoss = 0;
    epochBatches = 0;

    groupSize = min(lesion.shuffle_buffer_images, trainData.imageCount);
    for groupStart = 1:groupSize:trainData.imageCount
        groupEnd = min(trainData.imageCount, groupStart + groupSize - 1);
        groupIndices = epochOrder(groupStart:groupEnd);

        [patchPool, maskPool] = localCollectPatches(projectRoot, trainData, ...
            groupIndices, lesionTypes, patchesPerImage, lesion, epoch, true);
        poolCount = size(patchPool, 4);
        if poolCount == 0
            continue;
        end
        poolOrder = randperm(poolCount);

        for firstPatch = 1:batchSize:poolCount
            lastPatch = min(poolCount, firstPatch + batchSize - 1);
            selection = poolOrder(firstPatch:lastPatch);

            batchImages = normaliseLesionPatch(patchPool(:, :, :, selection));
            batchTargets = single(maskPool(:, :, :, selection));
            input = dlarray(batchImages, 'SSCB');
            targets = dlarray(batchTargets, 'SSCB');
            if environment == "gpu"
                input = gpuArray(input);
                targets = gpuArray(targets);
            end

            [loss, gradients, state] = dlfeval(@lesionGradients, net, ...
                input, targets, lossOptions);
            net.State = state;

            iteration = iteration + 1;
            [net, averageGradient, averageSquaredGradient] = adamupdate( ...
                net, gradients, averageGradient, averageSquaredGradient, ...
                iteration, lesion.learning_rate);

            epochLoss = epochLoss + double(gather(extractdata(loss)));
            epochBatches = epochBatches + 1;
        end
    end

    if epochBatches == 0
        error('segment:NoTrainingBatches', ...
            'Epoch %d produced no training batches.', epoch);
    end
    history.trainingLoss(epoch) = epochLoss / epochBatches;
    fprintf('TRAIN epoch %d: Loss: %.6f (%d batches)\n', epoch, ...
        history.trainingLoss(epoch), epochBatches);

    validationMetrics = localValidate(net, config, projectRoot, ...
        validationData, lesionTypes, thresholds, environment);
    localPrintPerType(validationMetrics, lesionTypes, epoch);

    history.meanAUPR(epoch) = mean(validationMetrics.aupr, 'omitnan');
    history.auprPerType(epoch, :) = validationMetrics.aupr(:)';
    history.epochsCompleted = epoch;

    epochCheckpoint = fullfile(resultsDirectory, ...
        sprintf('lesion_epoch_%02d.mat', epoch));
    hostNet = localHostNetwork(net);
    localSaveCheckpoint(epochCheckpoint, hostNet, config, validationMetrics, ...
        epoch);
    history.epochCheckpoints(epoch) = string(epochCheckpoint);

    if history.meanAUPR(epoch) > bestMeanAUPR
        bestMeanAUPR = history.meanAUPR(epoch);
        bestEpoch = epoch;
        epochsWithoutImprovement = 0;
        localSaveCheckpoint(bestCheckpoint, hostNet, config, ...
            validationMetrics, epoch);
        fprintf('Selected lesion checkpoint at epoch %d (mean AUPR %.4f).\n', ...
            epoch, bestMeanAUPR);
    else
        epochsWithoutImprovement = epochsWithoutImprovement + 1;
        if lesion.early_stopping_patience > 0 && ...
                epochsWithoutImprovement >= lesion.early_stopping_patience
            fprintf(['EARLY STOP: mean validation AUPR did not improve for ' ...
                '%d epoch(s).\n'], epochsWithoutImprovement);
            break;
        end
    end
end

history.trainingLoss = history.trainingLoss(1:history.epochsCompleted);
history.meanAUPR = history.meanAUPR(1:history.epochsCompleted);
history.auprPerType = history.auprPerType(1:history.epochsCompleted, :);
history.epochCheckpoints = history.epochCheckpoints(1:history.epochsCompleted);

result.status = "trained";
result.resultsDirectory = string(resultsDirectory);
result.bestCheckpoint = string(bestCheckpoint);
result.bestEpoch = bestEpoch;
result.bestMeanAUPR = bestMeanAUPR;
result.history = history;
result.environment = environment;

localWriteText(fullfile(resultsDirectory, 'history.json'), ...
    jsonencode(history));
fprintf('Best epoch %d with mean validation AUPR %.4f.\n', bestEpoch, ...
    bestMeanAUPR);
fprintf('Results written to %s\n', resultsDirectory);
end

function [mode, resultsRoot] = localOptions(varargin)
parser = inputParser();
parser.addParameter('Mode', "normal");
parser.addParameter('ResultsRoot', '');
parser.parse(varargin{:});
mode = string(parser.Results.Mode);
if ~any(mode == ["normal", "smoke", "inspect"])
    error('segment:InvalidMode', ...
        'Mode must be normal, smoke or inspect.');
end
resultsRoot = parser.Results.ResultsRoot;
end

function splitData = localTruncateSplit(splitData, imageCount)
keep = 1:min(imageCount, splitData.imageCount);
splitData.imageIds = splitData.imageIds(keep);
splitData.imagePaths = splitData.imagePaths(keep);
splitData.setFolders = splitData.setFolders(keep);
splitData.imageCount = numel(keep);
codes = fieldnames(splitData.coverage);
for codeIndex = 1:numel(codes)
    splitData.coverage.(codes{codeIndex}) = ...
        splitData.coverage.(codes{codeIndex})(keep);
end
end

function [patchPool, maskPool] = localCollectPatches(projectRoot, splitData, ...
    imageIndices, lesionTypes, patchesPerImage, lesion, epoch, augment)
%LOCALCOLLECTPATCHES Sample patches from several frames into one pool.
%   Batches are drawn from a pool spanning several frames rather than from
%   one frame at a time.  A batch whose patches all come from a single
%   fundus image shares that image's illumination and camera, and batch
%   normalisation then estimates its statistics from what is effectively one
%   sample, which makes the running statistics oscillate frame to frame.

patchSize = lesion.patch_size;
typeCount = numel(lesionTypes);
imageCount = numel(imageIndices);

patchPool = zeros(patchSize, patchSize, 3, patchesPerImage * imageCount, 'uint8');
maskPool = false(patchSize, patchSize, typeCount, patchesPerImage * imageCount);

cursor = 0;
for position = 1:imageCount
    imageIndex = imageIndices(position);
    [image, masks] = readLesionCase(projectRoot, ...
        splitData.imageIds(imageIndex), splitData.setFolders(imageIndex), ...
        lesionTypes);
    fieldMask = quality.fovMask(imresize(image, 1 / lesion.fov_downsample));

    options = struct( ...
        'patchSize', patchSize, ...
        'patchCount', patchesPerImage, ...
        'lesionFraction', lesion.lesion_patch_fraction, ...
        'augment', augment, ...
        'seed', grade.deterministicBatchSeed(lesion.seed, ...
            epoch * 1000 + imageIndex));
    [patches, patchMasks] = segment.sampleLesionPatches(image, masks, fieldMask, ...
        options);

    slots = cursor + (1:size(patches, 4));
    patchPool(:, :, :, slots) = patches;
    maskPool(:, :, :, slots) = patchMasks;
    cursor = slots(end);
end

patchPool = patchPool(:, :, :, 1:cursor);
maskPool = maskPool(:, :, :, 1:cursor);
end

function metrics = localValidate(net, config, projectRoot, validationData, ...
    lesionTypes, thresholds, environment)
%LOCALVALIDATE Full-frame tiled AUPR over the validation split.
%   Validation runs the same tiled full-frame inference the test evaluation
%   and the deployed pipeline run, not a patch-level approximation.  A
%   patch-level validation score computed over lesion-oversampled crops
%   would sit far above the number the same checkpoint reaches on a whole
%   frame, and epochs would then be selected on a metric the project never
%   reports.

hostNet = localHostNetwork(net);
model = struct('net', hostNet, 'config', config);

totals = struct();
totals.truePositive = 0;
totals.falsePositive = 0;
totals.falseNegative = 0;
totals.positiveCount = zeros(numel(lesionTypes), 1);
totals.pixelCount = 0;

for imageIndex = 1:validationData.imageCount
    [image, masks] = readLesionCase(projectRoot, ...
        validationData.imageIds(imageIndex), ...
        validationData.setFolders(imageIndex), lesionTypes);
    prediction = segment.segmentLesions(image, model, ...
        'Environment', environment);
    counts = lesionThresholdCounts(prediction.probabilityMaps, masks, ...
        thresholds);

    totals.truePositive = totals.truePositive + counts.truePositive;
    totals.falsePositive = totals.falsePositive + counts.falsePositive;
    totals.falseNegative = totals.falseNegative + counts.falseNegative;
    totals.positiveCount = totals.positiveCount + counts.positiveCount;
    totals.pixelCount = totals.pixelCount + counts.pixelCount;
end

metrics = lesionAUPR(totals, thresholds, lesionTypes);
metrics.imageCount = validationData.imageCount;
end

function localPrintPerType(metrics, lesionTypes, epoch)
%LOCALPRINTPERTYPE Per-lesion-type report, every validation epoch.
%   The grading path prints per-class recall and the full confusion matrix
%   every validation epoch because a model that collapses to the majority
%   class raises no error and shows a healthy loss curve (§7.4).  A
%   segmentation head collapsing to all-background is the same failure with
%   the same silence, so the per-type table prints on the same schedule.
%   Recall at the lowest threshold is included because it is the cheapest
%   signal that a head has died: a head that has collapsed cannot reach a
%   positive prediction at any threshold, including zero.

fprintf('VALIDATION epoch %d (n = %d frames)\n', epoch, metrics.imageCount);
fprintf('  %-4s %10s %10s %10s %12s %12s\n', 'type', 'AUPR', 'prevalence', ...
    'AUPR/prev', 'bestF1', 'recall@min');
for typeIndex = 1:numel(lesionTypes)
    recallRow = metrics.recall(typeIndex, :);
    recallAtLowest = recallRow(1);
    fprintf('  %-4s %10.4f %10.5f %10.2f %12.4f %12.4f\n', ...
        lesionTypes{typeIndex}, metrics.aupr(typeIndex), ...
        metrics.prevalence(typeIndex), metrics.auprOverPrevalence(typeIndex), ...
        metrics.bestF1(typeIndex), recallAtLowest);
end
fprintf('  mean AUPR: %.4f\n', mean(metrics.aupr, 'omitnan'));
end

function localSaveCheckpoint(filename, net, config, validation, epoch) %#ok<INUSD>
%LOCALSAVECHECKPOINT Write a checkpoint segment.segmentLesions can read.
%   The network is saved under the name 'net' because that is the field
%   segment.segmentLesions looks for.  Saving it under the caller's local
%   variable name instead produces a checkpoint that loads without error and
%   then fails at the field lookup, which is a slower failure to read.

save(filename, 'net', 'config', 'validation', 'epoch');
end

function hostNet = localHostNetwork(net)
%LOCALHOSTNETWORK Move learnables back to the host before saving.
%   A checkpoint holding gpuArray learnables reloads only on a machine with
%   a GPU, and fails with a CUDA error rather than a clear one.

hostNet = net;
try
    hostNet = dlupdate(@gather, hostNet);
catch
    % Already on the host.
end
end

function directory = localResultsDirectory(resultsRoot)
stamp = datestr(now, 'yyyymmdd_HHMMSS');
directory = fullfile(resultsRoot, sprintf('%s_lesion_segmentation', stamp));
suffix = 1;
while isfolder(directory)
    directory = fullfile(resultsRoot, ...
        sprintf('%s_lesion_segmentation_%02d', stamp, suffix));
    suffix = suffix + 1;
end
end

function localWriteText(filename, text)
fileIdentifier = fopen(filename, 'w');
if fileIdentifier < 0
    error('segment:ResultsNotWritable', ...
        'Could not open %s for writing.', filename);
end
cleanup = onCleanup(@() fclose(fileIdentifier));
fwrite(fileIdentifier, text, 'char');
end
