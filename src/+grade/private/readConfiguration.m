function [config, configText, projectRoot] = readConfiguration(inputConfig)
%READCONFIGURATION Load and validate the baseline grading configuration.

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(fileparts(fileparts(thisFile))));

if ischar(inputConfig) || (isstring(inputConfig) && isscalar(inputConfig))
    configFile = char(inputConfig);
    if ~isfile(configFile)
        error('grade:MissingConfig', 'Configuration file does not exist: %s', configFile);
    end
    configText = fileread(configFile);
    try
        config = jsondecode(configText);
    catch exception
        error('grade:InvalidConfig', ...
            'Configuration file could not be decoded: %s', exception.message);
    end
elseif isstruct(inputConfig) && isscalar(inputConfig)
    config = inputConfig;
    configText = jsonencode(config);
else
    error('grade:InvalidConfig', ...
        'The grading configuration must be a JSON filename or scalar structure.');
end

if ~isfield(config, 'grading') || ~isstruct(config.grading)
    config.grading = struct();
end
if ~isfield(config.grading, 'backbone')
    config.grading.backbone = 'resnet50';
end
if ~strcmpi(char(config.grading.backbone), 'resnet50')
    error('grade:UnsupportedBackbone', ...
        'The baseline requires imagePretrainedNetwork(''resnet50'').');
end
if ~isfield(config.grading, 'head')
    config.grading.head = 'softmax';
end
if ~strcmpi(char(config.grading.head), 'softmax')
    error('grade:UnsupportedHead', ...
        'The first baseline milestone requires a five-class softmax head.');
end
if ~isfield(config.grading, 'num_classes')
    config.grading.num_classes = 5;
end
if config.grading.num_classes ~= 5
    error('grade:InvalidClassCount', 'The baseline must have exactly five classes.');
end
if ~isfield(config.grading, 'input_size')
    config.grading.input_size = 448;
end
inputSize = double(config.grading.input_size);
if ~isscalar(inputSize) || ~isfinite(inputSize) || inputSize < 448 || ...
        inputSize ~= floor(inputSize)
    error('grade:InvalidInputSize', ...
        'The baseline input size must be an integer of at least 448.');
end
config.grading.input_size = inputSize;
if ~isfield(config.grading, 'batch_size')
    config.grading.batch_size = 16;
end
batchSize = double(config.grading.batch_size);
if ~isscalar(batchSize) || ~isfinite(batchSize) || batchSize < 1 || ...
        batchSize ~= floor(batchSize)
    error('grade:InvalidBatchSize', 'The batch size must be a positive integer.');
end
config.grading.batch_size = batchSize;
if ~isfield(config.grading, 'seed')
    config.grading.seed = 42;
end
if config.grading.seed ~= 42
    error('grade:InvalidSeed', 'The baseline entry point requires rng(42).');
end
% Dropout in front of the classification head. ResNet-50 ships without any,
% and 2564 unique training images against 25M parameters overfits by the
% fifth epoch (results/20260823_162453). Zero disables the layer entirely,
% which keeps the pre-dropout architecture reachable from config alone.
config.grading = localDefault(config.grading, 'dropout', 0.5);
dropout = double(config.grading.dropout);
if ~isscalar(dropout) || ~isfinite(dropout) || dropout < 0 || dropout >= 1
    error('grade:InvalidDropout', ...
        'grading.dropout must be a scalar in [0, 1).');
end
config.grading.dropout = dropout;

if ~isfield(config, 'training') || ~isstruct(config.training)
    config.training = struct();
end
config.training = localDefault(config.training, 'max_epochs', 10);
config.training = localDefault(config.training, 'learning_rate', 1e-4);
config.training = localDefault(config.training, 'gradient_decay_factor', 0.9);
config.training = localDefault(config.training, 'squared_gradient_decay_factor', 0.999);
config.training = localDefault(config.training, 'epsilon', 1e-8);
config.training = localDefault(config.training, 'smoke_epochs', 1);
config.training = localDefault(config.training, 'smoke_examples_per_class', 2);
config.training = localDefault(config.training, 'smoke_batch_size', 2);
config.training = localDefault(config.training, 'smoke_freeze_backbone', true);

config.training = localDefault(config.training, 'warmup_epochs', 2);
warmupEpochs = double(config.training.warmup_epochs);
if ~isscalar(warmupEpochs) || ~isfinite(warmupEpochs) || ...
        warmupEpochs < 0 || warmupEpochs ~= floor(warmupEpochs)
    error('grade:InvalidWarmupEpochs', ...
        'training.warmup_epochs must be a non-negative integer.');
end
config.training.warmup_epochs = warmupEpochs;
if warmupEpochs >= config.training.max_epochs
    error('grade:InvalidWarmupEpochs', ...
        'training.warmup_epochs must leave at least one full-finetune epoch.');
end
config.training = localDefault(config.training, 'warmup_learning_rate', 1e-3);
warmupLearningRate = double(config.training.warmup_learning_rate);
if ~isscalar(warmupLearningRate) || ~isfinite(warmupLearningRate) || ...
        warmupLearningRate <= 0
    error('grade:InvalidLearningRate', ...
        'training.warmup_learning_rate must be a positive scalar.');
end
config.training.warmup_learning_rate = warmupLearningRate;
learningRate = double(config.training.learning_rate);
if ~isscalar(learningRate) || ~isfinite(learningRate) || learningRate <= 0
    error('grade:InvalidLearningRate', ...
        'training.learning_rate must be a positive scalar.');
end
config.training.learning_rate = learningRate;
config.training = localDefault(config.training, 'gradient_threshold', 10);
gradientThreshold = double(config.training.gradient_threshold);
if ~isscalar(gradientThreshold) || ~isfinite(gradientThreshold) || ...
        gradientThreshold < 0
    error('grade:InvalidGradientThreshold', ...
        'training.gradient_threshold must be a non-negative scalar (0 disables clipping).');
end
config.training.gradient_threshold = gradientThreshold;
% Default false: DispatchInBackground fans batches across the whole
% parallel pool, and which batch lands in which delivery position from
% next() is not guaranteed independent of pool size (verified: two pool
% sizes returned the same two batches in swapped order), so a run is not
% reproducible across machines with different worker counts (design doc
% §13.2). collateData seeds augmentation from (seed, batch identity), so
% turning this back on for throughput no longer produces different pixel
% content per batch - it can still reorder batches across pool sizes.
config.training = localDefault(config.training, 'dispatch_in_background', false);
if ~(islogical(config.training.dispatch_in_background) && ...
        isscalar(config.training.dispatch_in_background))
    error('grade:InvalidDispatchOption', ...
        'training.dispatch_in_background must be a logical scalar.');
end
config.training = localDefault(config.training, 'augmentation', true);
if ~(islogical(config.training.augmentation) && ...
        isscalar(config.training.augmentation))
    error('grade:InvalidAugmentationFlag', ...
        'training.augmentation must be a logical scalar.');
end

% Decoupled (AdamW-style) weight decay, applied after adamupdate to weight
% tensors only, and only where gradients flow. Applying it to a frozen
% backbone would shrink pretrained features that receive no gradient to
% balance them, so localApplyWeightDecay skips frozen layers during warmup.
config.training = localDefault(config.training, 'weight_decay', 0.1);
weightDecay = double(config.training.weight_decay);
if ~isscalar(weightDecay) || ~isfinite(weightDecay) || weightDecay < 0
    error('grade:InvalidWeightDecay', ...
        'training.weight_decay must be a non-negative scalar (0 disables decay).');
end
config.training.weight_decay = weightDecay;

% Stop once validation loss has failed to improve for this many consecutive
% epochs. Validation loss is the early-stopping signal rather than macro
% recall because it is the metric that penalises overconfidence, and the
% previous run kept its accuracy while its probabilities degraded.
% Zero disables early stopping and runs the full epoch budget.
config.training = localDefault(config.training, 'early_stopping_patience', 4);
patience = double(config.training.early_stopping_patience);
if ~isscalar(patience) || ~isfinite(patience) || patience < 0 || ...
        patience ~= floor(patience)
    error('grade:InvalidEarlyStoppingPatience', ...
        'training.early_stopping_patience must be a non-negative integer.');
end
config.training.early_stopping_patience = patience;

% Write a checkpoint for every epoch, not just the selected one. The
% selector optimises five-class macro recall while the primary endpoint is
% binary referable sensitivity; in results/20260823_162453 those disagreed
% and the best endpoint epoch was discarded unrecoverably.
config.training = localDefault(config.training, 'save_every_epoch', true);
if ~(islogical(config.training.save_every_epoch) && ...
        isscalar(config.training.save_every_epoch))
    error('grade:InvalidSaveEveryEpoch', ...
        'training.save_every_epoch must be a logical scalar.');
end

config = localAugmentationConfiguration(config);

if ~isfield(config, 'class_balancing') || ~isstruct(config.class_balancing)
    config.class_balancing = struct();
end
config.class_balancing = localDefault(config.class_balancing, ...
    'method', 'inverse_frequency');
if ~strcmpi(char(config.class_balancing.method), 'inverse_frequency')
    error('grade:UnsupportedClassBalancing', ...
        'The baseline uses inverse-frequency class-weighted loss.');
end
config.class_balancing = localDefault(config.class_balancing, ...
    'oversampling', true);
if ~(islogical(config.class_balancing.oversampling) && ...
        isscalar(config.class_balancing.oversampling))
    error('grade:InvalidOversamplingFlag', ...
        'class_balancing.oversampling must be a logical scalar.');
end

if ~isfield(config, 'data') || ~isstruct(config.data)
    config.data = struct();
end
config.data = localDefault(config.data, 'dataset', 'APTOS');
if ~strcmpi(char(config.data.dataset), 'APTOS')
    error('grade:UnsupportedDataset', 'The baseline uses APTOS only.');
end
config.data.split_directory = fullfile(projectRoot, 'data', 'splits');

config.modelConfig = struct( ...
    'backbone', 'resnet50', ...
    'head', 'five_class_softmax', ...
    'numClasses', 5, ...
    'inputSize', [config.grading.input_size, config.grading.input_size, 3], ...
    'pretrainedWeights', 'ImageNet', ...
    'batchSize', config.grading.batch_size, ...
    'classBalancing', char(config.class_balancing.method));
configText = jsonencode(config);
end

function inputStruct = localDefault(inputStruct, fieldName, value)
if ~isfield(inputStruct, fieldName)
    inputStruct.(fieldName) = value;
end
end

function config = localAugmentationConfiguration(config)
%LOCALAUGMENTATIONCONFIGURATION Validate the train-only augmentation block.
%   training.augmentation is the on/off switch; this block says how. The
%   design doc forbids augmentations that destroy microaneurysm evidence,
%   so there is deliberately no blur, no noise and no elastic warp here -
%   only rigid transforms and modest photometric jitter.

if ~isfield(config, 'augmentation') || ~isstruct(config.augmentation)
    config.augmentation = struct();
end
augmentation = config.augmentation;

augmentation = localDefault(augmentation, 'rotation', true);
if ~(islogical(augmentation.rotation) && isscalar(augmentation.rotation))
    error('grade:InvalidAugmentation', ...
        'augmentation.rotation must be a logical scalar.');
end
augmentation = localDefault(augmentation, 'flips', true);
if ~(islogical(augmentation.flips) && isscalar(augmentation.flips))
    error('grade:InvalidAugmentation', ...
        'augmentation.flips must be a logical scalar.');
end

augmentation = localDefault(augmentation, 'scale_jitter', [0.85, 1.0]);
scaleJitter = double(augmentation.scale_jitter(:)).';
if numel(scaleJitter) ~= 2 || any(~isfinite(scaleJitter)) || ...
        scaleJitter(1) <= 0 || scaleJitter(1) > scaleJitter(2) || ...
        scaleJitter(2) > 1
    error('grade:InvalidAugmentation', ...
        ['augmentation.scale_jitter must be [low high] with ' ...
        '0 < low <= high <= 1; values above 1 would need padding, ' ...
        'which invents evidence outside the field of view.']);
end
augmentation.scale_jitter = scaleJitter;

augmentation = localDefault(augmentation, 'brightness_shift', 10);
brightnessShift = double(augmentation.brightness_shift);
if ~isscalar(brightnessShift) || ~isfinite(brightnessShift) || brightnessShift < 0
    error('grade:InvalidAugmentation', ...
        'augmentation.brightness_shift must be a non-negative scalar.');
end
augmentation.brightness_shift = brightnessShift;

augmentation = localDefault(augmentation, 'contrast_gain', [0.9, 1.1]);
contrastGain = double(augmentation.contrast_gain(:)).';
if numel(contrastGain) ~= 2 || any(~isfinite(contrastGain)) || ...
        contrastGain(1) <= 0 || contrastGain(1) > contrastGain(2)
    error('grade:InvalidAugmentation', ...
        'augmentation.contrast_gain must be [low high] with 0 < low <= high.');
end
augmentation.contrast_gain = contrastGain;

config.augmentation = augmentation;
end
