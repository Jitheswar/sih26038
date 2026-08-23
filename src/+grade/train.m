function result = train(varargin)
%TRAIN Train the five-class APTOS ResNet-50 grading baseline.
%   RESULT = grade.train(CONFIG) runs the normal training mode.
%   RESULT = grade.train(CONFIG,'Mode','smoke') runs one small smoke epoch.
%   RESULT = grade.train(CONFIG,'Mode','inspect') builds the model and
%   datastores without training.

rng(42, 'twister');

% Preserve the original image-only seam used by the shared preprocessing tests.
if nargin > 0 && localIsImage(varargin{1})
    result = localPreprocessCompatibility(varargin{:});
    return;
end

if nargin == 0
    error('grade:MissingConfig', 'A grading configuration is required.');
end
[mode, resultsRoot, evaluateTest] = localOptions(varargin{2:end});
[config, configText, projectRoot] = readConfiguration(varargin{1});
addpath(fullfile(projectRoot, 'eval'));
addpath(fullfile(projectRoot, 'eval', 'metrics'));

allData = struct();
splitNames = ["train", "validation", "calibration", "test"];
for splitIndex = 1:numel(splitNames)
    splitName = splitNames(splitIndex);
    allData.(char(splitName)) = loadSplitData(config, projectRoot, splitName);
end

selectedData = allData;
selectedData.train = localOversampleMinorities( ...
    selectedData.train, config.class_balancing.oversampling);

% Class weights follow the resampled training counts, so fully balanced
% sampling leaves them near uniform instead of double-correcting.
classWeightValues = classWeights(selectedData.train.classCounts);
if strcmp(mode, "smoke")
    selectedData.train = selectSmokeSubset( ...
        selectedData.train, config.training.smoke_examples_per_class);
    selectedData.validation = selectSmokeSubset( ...
        allData.validation, config.training.smoke_examples_per_class);
    batchSize = config.training.smoke_batch_size;
    maxEpochs = config.training.smoke_epochs;
else
    batchSize = config.grading.batch_size;
    maxEpochs = config.training.max_epochs;
end

stores = struct();
storeNames = fieldnames(selectedData);
for storeIndex = 1:numel(storeNames)
    storeName = storeNames{storeIndex};
    stores.(storeName) = createImageDatastore( ...
        selectedData.(storeName), config);
end

net = buildNetwork(config);
result = localConfiguredResult(config, configText, selectedData, stores, ...
    classWeightValues, net);
if strcmp(mode, "inspect")
    result.status = "configured";
    return;
end

if ~isfolder(resultsRoot)
    mkdir(resultsRoot);
end
resultsDirectory = localResultsDirectory(resultsRoot);
mkdir(resultsDirectory);
localWriteConfiguration(fullfile(resultsDirectory, 'config.json'), configText);

environment = "cpu";
if canUseGPU
    environment = "gpu";
    net = dlupdate(@gpuArray, net);
    device = gpuDevice;
    fprintf('GPU is being used: %s\n', device.Name);
else
    fprintf('GPU is not available; using CPU.\n');
end
fprintf('Training started successfully.\n');
fprintf('Dataset: APTOS | input: %dx%dx3 | batch size: %d | epochs: %d\n', ...
    config.grading.input_size, config.grading.input_size, batchSize, maxEpochs);

trainQueue = createMiniBatchQueue(stores.train, selectedData.train.grades, ...
    batchSize, environment, config.training.dispatch_in_background, ...
    config.training.augmentation, config.grading.seed, config.augmentation);
validationQueue = createMiniBatchQueue(stores.validation, ...
    selectedData.validation.grades, batchSize, environment, ...
    config.training.dispatch_in_background, false, config.grading.seed);

history = struct();
history.validation = repmat(localEmptyMetric(), 0, 1);
history.trainingLoss = zeros(maxEpochs, 1);
history.learningRate = zeros(maxEpochs, 1);
history.backboneFrozen = false(maxEpochs, 1);
history.epochsCompleted = 0;
history.batchSize = batchSize;
history.inputSize = config.modelConfig.inputSize;
history.classWeights = classWeightValues;
history.dropout = config.grading.dropout;
history.weightDecay = config.training.weight_decay;
history.earlyStoppingPatience = config.training.early_stopping_patience;
history.epochCheckpoints = strings(0, 1);

averageGrad = [];
averageSqGrad = [];
iteration = 0;
bestMacroRecall = -Inf;
bestValidationLoss = Inf;
bestEpoch = 0;
bestCheckpoint = fullfile(resultsDirectory, 'best_model.mat');

% Early stopping tracks validation loss separately from checkpoint
% selection, which tracks macro recall. They are different questions:
% "has this stopped improving" and "which epoch do we keep".
lowestValidationLoss = Inf;
epochsWithoutImprovement = 0;
stoppedEarly = false;

warmupEpochs = config.training.warmup_epochs;
gradientThreshold = config.training.gradient_threshold;
weightDecay = config.training.weight_decay;
patience = config.training.early_stopping_patience;
saveEveryEpoch = config.training.save_every_epoch && ~strcmp(mode, "smoke");

for epoch = 1:maxEpochs
    inWarmup = epoch <= warmupEpochs && ~strcmp(mode, "smoke");
    if inWarmup
        epochLearningRate = config.training.warmup_learning_rate;
    else
        epochLearningRate = config.training.learning_rate;
    end
    fprintf('EPOCH %d: lr %.1e | backbone %s\n', epoch, epochLearningRate, ...
        localFrozenLabel(mode, inWarmup));
    shuffle(trainQueue);
    reset(trainQueue);
    freezeBackbone = (strcmp(mode, "smoke") && ...
        config.training.smoke_freeze_backbone) || inWarmup;
    epochLoss = 0;
    epochSamples = 0;
    while hasdata(trainQueue)
        [images, targets] = next(trainQueue);
        iteration = iteration + 1;
        [loss, gradients, state] = dlfeval( ...
            @modelGradients, net, images, targets, classWeightValues);
        % Carry the batch normalization running statistics forward. Without
        % this, forward() trains against mini-batch statistics while
        % predict() scores validation against the untouched ImageNet ones,
        % and the two drift apart every epoch: training loss falls while
        % validation loss rises and predictions collapse onto one class.
        % Backbone freezing acts on gradients only, so warmup epochs still
        % adapt these statistics to the fundus domain, which is what makes
        % epoch-1 validation meaningful.
        net.State = state;
        if freezeBackbone
            gradients = freezeBackboneGradients(gradients);
        end
        if gradientThreshold > 0
            gradients = localClipGradients(gradients, gradientThreshold);
        end
        [net, averageGrad, averageSqGrad] = adamupdate(net, gradients, ...
            averageGrad, averageSqGrad, iteration, ...
            epochLearningRate, ...
            config.training.gradient_decay_factor, ...
            config.training.squared_gradient_decay_factor, ...
            config.training.epsilon);
        if weightDecay > 0
            net = localApplyWeightDecay(net, weightDecay, ...
                epochLearningRate, freezeBackbone);
        end
        batchSamples = size(images, 4);
        epochLoss = epochLoss + double(gather(extractdata(loss))) * batchSamples;
        epochSamples = epochSamples + batchSamples;
    end

    history.trainingLoss(epoch) = epochLoss / max(epochSamples, 1);
    history.learningRate(epoch) = epochLearningRate;
    history.backboneFrozen(epoch) = freezeBackbone;
    fprintf('TRAIN epoch %d: Loss: %.6f\n', epoch, history.trainingLoss(epoch));
    validationMetric = evaluateNetwork(net, validationQueue, classWeightValues, ...
        epoch, "validation");
    history.validation(epoch) = localMetricForHistory(validationMetric);
    history.epochsCompleted = epoch;

    % Every epoch is written before selection runs. The selector optimises
    % five-class macro recall while the reported endpoint is binary
    % referable sensitivity, and in results/20260823_162453 they disagreed:
    % epoch 8 was the best model for the endpoint and was discarded because
    % epoch 7 scored higher on macro recall. Keeping every epoch, with its
    % unstripped metric so the validation probabilities survive, means no
    % operating-point decision is ever foreclosed by the selector.
    if saveEveryEpoch
        epochCheckpoint = fullfile(resultsDirectory, ...
            sprintf('epoch_%02d.mat', epoch));
        validation = validationMetric; %#ok<NASGU>
        save(epochCheckpoint, 'net', 'config', 'validation', 'epoch');
        history.epochCheckpoints(epoch, 1) = string(epochCheckpoint);
    end

    macroRecall = mean(validationMetric.perClassRecall);
    isBetter = macroRecall > bestMacroRecall || ...
        (macroRecall == bestMacroRecall && ...
        validationMetric.loss < bestValidationLoss);
    if isBetter
        bestMacroRecall = macroRecall;
        bestValidationLoss = validationMetric.loss;
        bestEpoch = epoch;
        validation = validationMetric; %#ok<NASGU>
        save(bestCheckpoint, 'net', 'config', 'validation', 'epoch');
        fprintf('Selected validation checkpoint at epoch %d.\n', epoch);
    end

    if validationMetric.loss < lowestValidationLoss
        lowestValidationLoss = validationMetric.loss;
        epochsWithoutImprovement = 0;
    else
        epochsWithoutImprovement = epochsWithoutImprovement + 1;
        fprintf(['Validation loss has not improved for %d epoch(s) ' ...
            '(best %.6f).\n'], epochsWithoutImprovement, lowestValidationLoss);
    end
    if patience > 0 && epochsWithoutImprovement >= patience
        stoppedEarly = true;
        fprintf(['EARLY STOP: validation loss did not improve for %d ' ...
            'consecutive epochs; stopping at epoch %d of %d.\n'], ...
            patience, epoch, maxEpochs);
        break;
    end
end

if bestEpoch == 0
    error('grade:NoCheckpoint', 'No validation checkpoint was selected.');
end

checkpoint = load(bestCheckpoint, 'net');
net = checkpoint.net;

% Early stopping leaves the preallocated per-epoch vectors padded with
% zeros past the last epoch that actually ran. Trim them so a reader cannot
% mistake padding for a measured epoch of zero loss.
history.trainingLoss = history.trainingLoss(1:history.epochsCompleted);
history.learningRate = history.learningRate(1:history.epochsCompleted);
history.backboneFrozen = history.backboneFrozen(1:history.epochsCompleted);

history.bestEpoch = bestEpoch;
history.bestValidationMacroRecall = bestMacroRecall;
history.bestValidationLoss = bestValidationLoss;
history.stoppedEarly = stoppedEarly;
history.lowestValidationLoss = lowestValidationLoss;
history.maxEpochsConfigured = maxEpochs;
save(fullfile(resultsDirectory, 'training_history.mat'), ...
    'history', 'config', '-v7.3');

testMetric = [];
testEvaluated = strcmp(mode, "normal") && evaluateTest;
if testEvaluated
    testQueue = createMiniBatchQueue(stores.test, selectedData.test.grades, ...
        batchSize, environment, config.training.dispatch_in_background, false, ...
        config.grading.seed);
    testMetric = evaluateNetwork(net, testQueue, classWeightValues, ...
        bestEpoch, "test");
    testMetric = localMetricForHistory(testMetric);
    save(fullfile(resultsDirectory, 'test_metrics.mat'), 'testMetric');
end

result.status = "completed";
result.mode = mode;
result.network = net;
result.history = history;
result.resultsDirectory = string(resultsDirectory);
result.bestCheckpoint = string(bestCheckpoint);
result.testMetrics = testMetric;
result.gpuUsed = environment == "gpu";
result.checkpointSelection.testUsed = testEvaluated;
result.checkpointSelection.bestEpoch = bestEpoch;
result.stoppedEarly = stoppedEarly;
result.epochCheckpoints = history.epochCheckpoints;
end

function net = localApplyWeightDecay(net, weightDecay, learningRate, freezeBackbone)
%LOCALAPPLYWEIGHTDECAY Decoupled (AdamW-style) decay on weight tensors.
%   Applied after adamupdate rather than folded into the gradient, so the
%   decay is not rescaled by Adam's per-parameter second-moment estimate.
%
%   Two exclusions matter. Biases and batch normalization Scale/Offset are
%   left alone: shrinking them does not reduce model capacity and pulling a
%   normalization scale toward zero suppresses the channel outright.
%   Frozen layers are also left alone - during warmup only fc1000 receives
%   gradients, and decaying the backbone there would shrink pretrained
%   ImageNet features that have no gradient to push back, degrading the
%   representation before fine-tuning ever starts.

learnables = net.Learnables;
factor = 1 - learningRate * weightDecay;
for index = 1:height(learnables)
    if learnables.Parameter(index) ~= "Weights"
        continue;
    end
    if freezeBackbone && string(learnables.Layer(index)) ~= "fc1000"
        continue;
    end
    learnables.Value{index} = learnables.Value{index} * factor;
end
net.Learnables = learnables;
end

function data = localOversampleMinorities(data, enabled)
%LOCALOVERSAMPLEMINORITIES Duplicate training rows so every grade appears
%   equally often per epoch (design doc §7.4 remedy two). Duplicates stay
%   inside the training split; validation, calibration and test keep the
%   true deployment distribution. Selection is deterministic: rows of each
%   minority class are repeated in file order until the class reaches the
%   majority count.

if ~enabled
    return;
end
counts = data.classCounts(:);
target = max(counts);
extraRows = zeros(0, 1);
for level = 0:4
    need = target - counts(level + 1);
    if need <= 0
        continue;
    end
    candidates = find(data.grades == level);
    repetitions = repmat(candidates, ceil(need / numel(candidates)), 1);
    extraRows = [extraRows; repetitions(1:need)]; %#ok<AGROW>
end
data.table = data.table([(1:numel(data.grades)).'; extraRows], :);
data.files = [data.files; data.files(extraRows)];
data.grades = [data.grades; data.grades(extraRows)];
data.classCounts = arrayfun(@(level) sum(data.grades == level), 0:4).';
data.count = numel(data.grades);
data.oversampled = true;
end

function gradients = localClipGradients(gradients, threshold)
%LOCALCLIPGRADIENTS Rescale gradients so their global L2 norm is at most
%   the configured threshold. Gradients mirror net.Learnables: a table with
%   a Value column of dlarrays.

normSquared = 0;
for index = 1:numel(gradients.Value)
    normSquared = normSquared + sum(extractdata(gradients.Value{index}).^2, 'all');
end
globalNorm = sqrt(double(normSquared));
if globalNorm <= threshold || ~isfinite(globalNorm)
    return;
end
scale = single(threshold / globalNorm);
gradients = dlupdate(@(g) g * scale, gradients);
end

function label = localFrozenLabel(mode, inWarmup)
if strcmp(mode, "smoke")
    label = "frozen (smoke)";
elseif inWarmup
    label = "frozen (warmup)";
else
    label = "trainable";
end
end

function result = localConfiguredResult(config, configText, data, stores, weights, net)
result = struct();
result.status = "configured";
result.config = config;
result.configText = configText;
result.modelConfig = config.modelConfig;
result.network = net;
result.classWeights = weights;
result.datastores = stores;
result.data = data;
result.checkpointSelection = struct( ...
    'split', "validation", ...
    'metric', "validationMacroRecallThenLoss", ...
    'testUsed', false);
end

function metric = localEmptyMetric()
metric = struct( ...
    'loss', NaN, ...
    'epoch', 0, ...
    'split', "", ...
    'confusionMatrix', zeros(5, 5), ...
    'perClassRecall', NaN(5, 1), ...
    'sensitivity', NaN, ...
    'specificity', NaN, ...
    'sensitivityCILower', NaN, ...
    'sensitivityCIUpper', NaN, ...
    'specificityCILower', NaN, ...
    'specificityCIUpper', NaN, ...
    'n', 0, ...
    'referableThreshold', 2, ...
    'zeroRecallLevels', zeros(0, 1), ...
    'collapseWarning', false);
end

function metric = localMetricForHistory(metric)
metric = rmfield(metric, {'actualLabels', 'predictedLabels', 'probabilities'});
end

function [mode, resultsRoot, evaluateTest] = localOptions(varargin)
parser = inputParser;
parser.addParameter('Mode', 'normal');
parser.addParameter('ResultsRoot', '');
parser.addParameter('EvaluateTest', false);
parser.parse(varargin{:});
mode = lower(string(parser.Results.Mode));
if ~ismember(mode, ["normal", "smoke", "inspect"])
    error('grade:InvalidMode', 'Mode must be normal, smoke, or inspect.');
end
resultsRoot = string(parser.Results.ResultsRoot);
if strlength(resultsRoot) == 0
    thisFile = mfilename('fullpath');
    projectRoot = fileparts(fileparts(fileparts(thisFile)));
    resultsRoot = string(fullfile(projectRoot, 'results'));
end
resultsRoot = char(resultsRoot);
rawEvaluateTest = parser.Results.EvaluateTest;
isValidEvaluateTest = (islogical(rawEvaluateTest) || isnumeric(rawEvaluateTest)) ...
    && isscalar(rawEvaluateTest);
if ~isValidEvaluateTest
    error('grade:InvalidEvaluateTest', 'EvaluateTest must be a logical scalar.');
end
evaluateTest = logical(rawEvaluateTest);
if evaluateTest && mode ~= "normal"
    error('grade:InvalidEvaluateTest', ...
        'EvaluateTest is only valid in normal mode.');
end
end

function directory = localResultsDirectory(resultsRoot)
stamp = datestr(now, 'yyyymmdd_HHMMSS');
directory = fullfile(resultsRoot, stamp);
suffix = 1;
while isfolder(directory)
    directory = fullfile(resultsRoot, sprintf('%s_%02d', stamp, suffix));
    suffix = suffix + 1;
end
end

function localWriteConfiguration(filename, configText)
fileIdentifier = fopen(filename, 'w');
if fileIdentifier < 0
    error('grade:ResultsWriteFailed', 'Could not write configuration: %s', filename);
end
cleanup = onCleanup(@() fclose(fileIdentifier)); %#ok<NASGU>
fwrite(fileIdentifier, configText, 'char');
end

function result = localPreprocessCompatibility(varargin)
config = [];
if nargin >= 2
    config = varargin{2};
end
result = struct('status', 'preprocessed');
[result.preprocessedImage, result.qualityMetadata, ...
    result.preprocessingMetadata] = common.preprocess( ...
    varargin{1}, config, 'training');
end

function result = localIsImage(value)
result = (isnumeric(value) || islogical(value)) && ~isempty(value);
end
