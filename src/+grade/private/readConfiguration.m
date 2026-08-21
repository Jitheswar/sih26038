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

if ~isfield(config, 'class_balancing') || ~isstruct(config.class_balancing)
    config.class_balancing = struct();
end
config.class_balancing = localDefault(config.class_balancing, ...
    'method', 'inverse_frequency');
if ~strcmpi(char(config.class_balancing.method), 'inverse_frequency')
    error('grade:UnsupportedClassBalancing', ...
        'The baseline uses inverse-frequency class-weighted loss.');
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
