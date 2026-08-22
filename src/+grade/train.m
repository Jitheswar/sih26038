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

classWeightValues = classWeights(allData.train.classCounts);
if strcmp(mode, "smoke")
    selectedData = allData;
    selectedData.train = selectSmokeSubset( ...
        allData.train, config.training.smoke_examples_per_class);
    selectedData.validation = selectSmokeSubset( ...
        allData.validation, config.training.smoke_examples_per_class);
    batchSize = config.training.smoke_batch_size;
    maxEpochs = config.training.smoke_epochs;
else
    selectedData = allData;
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
    batchSize, environment);
validationQueue = createMiniBatchQueue(stores.validation, ...
    selectedData.validation.grades, batchSize, environment);

history = struct();
history.validation = repmat(localEmptyMetric(), 0, 1);
history.trainingLoss = zeros(maxEpochs, 1);
history.epochsCompleted = 0;
history.batchSize = batchSize;
history.inputSize = config.modelConfig.inputSize;
history.classWeights = classWeightValues;

averageGrad = [];
averageSqGrad = [];
iteration = 0;
bestMacroRecall = -Inf;
bestValidationLoss = Inf;
bestEpoch = 0;
bestCheckpoint = fullfile(resultsDirectory, 'best_model.mat');

for epoch = 1:maxEpochs
    shuffle(trainQueue);
    reset(trainQueue);
    epochLoss = 0;
    epochSamples = 0;
    while hasdata(trainQueue)
        [images, targets] = next(trainQueue);
        iteration = iteration + 1;
        [loss, gradients] = dlfeval( ...
            @modelGradients, net, images, targets, classWeightValues);
        if strcmp(mode, "smoke") && config.training.smoke_freeze_backbone
            gradients = freezeBackboneGradients(gradients);
        end
        [net, averageGrad, averageSqGrad] = adamupdate(net, gradients, ...
            averageGrad, averageSqGrad, iteration, ...
            config.training.learning_rate, ...
            config.training.gradient_decay_factor, ...
            config.training.squared_gradient_decay_factor, ...
            config.training.epsilon);
        batchSamples = size(images, 4);
        epochLoss = epochLoss + double(gather(extractdata(loss))) * batchSamples;
        epochSamples = epochSamples + batchSamples;
    end

    history.trainingLoss(epoch) = epochLoss / max(epochSamples, 1);
    validationMetric = evaluateNetwork(net, validationQueue, classWeightValues, ...
        epoch, "validation");
    history.validation(epoch) = localMetricForHistory(validationMetric);
    history.epochsCompleted = epoch;

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
end

if bestEpoch == 0
    error('grade:NoCheckpoint', 'No validation checkpoint was selected.');
end

history.bestEpoch = bestEpoch;
history.bestValidationMacroRecall = bestMacroRecall;
history.bestValidationLoss = bestValidationLoss;
save(fullfile(resultsDirectory, 'training_history.mat'), ...
    'history', 'config', '-v7.3');

testMetric = [];
testEvaluated = strcmp(mode, "normal") && evaluateTest;
if testEvaluated
    checkpoint = load(bestCheckpoint, 'net');
    net = checkpoint.net;
    testQueue = createMiniBatchQueue(stores.test, selectedData.test.grades, ...
        batchSize, environment);
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
evaluateTest = logical(parser.Results.EvaluateTest);
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
