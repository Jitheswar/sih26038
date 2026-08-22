function result = infer(varargin)
%INFER Run the shared preprocessing and five-class baseline inference.
%   RESULT = grade.infer(IMAGE, CONFIG) preserves the preprocessing seam.
%   RESULT = grade.infer(CHECKPOINT, IMAGE, CONFIG) predicts one image.
%   RESULT = grade.infer(IMAGE, CHECKPOINT, CONFIG) is also accepted.

rng(42, 'twister');
if nargin == 0
    error('grade:MissingInferenceInput', 'An image is required.');
end

if localIsImage(varargin{1})
    image = varargin{1};
    if nargin >= 2 && localIsCheckpoint(varargin{2})
        checkpointInput = varargin{2};
        [configInput, optionArguments] = localConfigAndOptions(varargin(3:end));
    else
        [configInput, optionArguments] = localConfigAndOptions(varargin(2:end));
        result = localPreprocessOnly(image, configInput);
        if ~isempty(optionArguments)
            error('grade:InvalidInferenceOptions', ...
                'Inference options require a checkpoint and an image.');
        end
        return;
    end
else
    checkpointInput = varargin{1};
    if ~localIsCheckpointReference(checkpointInput)
        error('grade:MissingInferenceCheckpoint', ...
            'The first argument must be a checkpoint filename or loaded checkpoint.');
    end
    if nargin < 2 || ~localIsImage(varargin{2})
        error('grade:MissingInferenceImage', ...
            'A numeric image must follow the checkpoint filename.');
    end
    image = varargin{2};
    [configInput, optionArguments] = localConfigAndOptions(varargin(3:end));
end

parser = inputParser;
parser.addParameter('ReturnLogits', false, @(value) islogical(value) || ...
    (isnumeric(value) && isscalar(value)));
parser.parse(optionArguments{:});
returnLogits = logical(parser.Results.ReturnLogits);

if isstruct(checkpointInput)
    checkpoint = checkpointInput;
else
    checkpointFile = char(checkpointInput);
    if ~isfile(checkpointFile)
        error('grade:MissingCheckpoint', 'Checkpoint does not exist: %s', checkpointFile);
    end
    checkpoint = load(checkpointFile, 'net', 'config');
end
if isempty(configInput)
    configInput = checkpoint.config;
end
[config, ~, projectRoot] = readConfiguration(configInput);
addpath(fullfile(projectRoot, 'eval'));
addpath(fullfile(projectRoot, 'eval', 'metrics'));
[processedImage, qualityMetadata, preprocessingMetadata] = ...
    localPrepareImages(image, config);

net = checkpoint.net;
executionEnvironment = "cpu";
if canUseGPU
    executionEnvironment = "gpu";
    if ~localNetworkUsesGPU(net)
        net = dlupdate(@gpuArray, net);
    end
end
logitsData = minibatchpredict(net, processedImage, ...
    'MiniBatchSize', min(size(processedImage, 4), 16), ...
    'ExecutionEnvironment', executionEnvironment, ...
    'OutputDataFormats', 'CB', ...
    'Outputs', 'fc1000');
logits = gather(extractdata(logitsData));
logits = reshape(double(logits), 5, []);
probabilities = localSoftmax(logits);
[~, predictedIndex] = max(probabilities, [], 1);

result = struct();
result.status = "inferred";
result.predictedGrade = predictedIndex - 1;
result.classNames = string(0:4).';
result.probabilities = probabilities;
result.rawProbabilities = probabilities;
result.referableProbability = sum(probabilities(3:5));
result.referableThreshold = 2;
result.probabilitiesAreCalibrated = false;
result.rawProbabilitiesAreCalibrated = false;
result.logits = [];
if returnLogits
    result.logits = logits;
end
result.qualityMetadata = qualityMetadata;
result.preprocessingMetadata = preprocessingMetadata;
result.preprocessedImage = processedImage;
result.gpuUsed = executionEnvironment == "gpu";
end

function result = localPreprocessOnly(image, configInput)
result = struct('status', 'preprocessed');
[result.preprocessedImage, result.qualityMetadata, ...
    result.preprocessingMetadata] = localPrepareImages(image, configInput);
end

function [processedImages, qualityMetadata, preprocessingMetadata] = ...
        localPrepareImages(images, config)
if iscell(images)
    sampleCount = numel(images);
    if sampleCount == 0
        error('grade:MissingInferenceImage', 'At least one image is required.');
    end
    processedImages = [];
    qualityMetadata = cell(sampleCount, 1);
    preprocessingMetadata = cell(sampleCount, 1);
    for index = 1:sampleCount
        [processedImage, qualityMetadata{index}, preprocessingMetadata{index}] = ...
            common.preprocess(images{index}, config, 'inference');
        if size(processedImage, 3) == 1
            processedImage = repmat(processedImage, 1, 1, 3);
        end
        if isempty(processedImages)
            processedImages = zeros([size(processedImage), sampleCount], ...
                'like', processedImage);
        end
        processedImages(:, :, :, index) = processedImage;
    end
else
    [processedImages, qualityMetadata, preprocessingMetadata] = ...
        common.preprocess(images, config, 'inference');
    if size(processedImages, 3) == 1
        processedImages = repmat(processedImages, 1, 1, 3);
    end
end
end

function [configInput, optionArguments] = localConfigAndOptions(arguments)
configInput = [];
optionArguments = arguments;
if isempty(arguments)
    return;
end

firstArgument = arguments{1};
isOptionName = (ischar(firstArgument) || ...
    (isstring(firstArgument) && isscalar(firstArgument))) && ...
    ismember(lower(string(firstArgument)), "returnlogits");
if ~isOptionName
    configInput = firstArgument;
    optionArguments = arguments(2:end);
end
end

function probabilities = localSoftmax(logits)
shifted = logits - max(logits, [], 1);
unnormalized = exp(shifted);
probabilities = unnormalized ./ sum(unnormalized, 1);
end

function result = localIsImage(value)
result = ((isnumeric(value) || islogical(value)) && ~isempty(value)) || ...
    (iscell(value) && ~isempty(value));
end

function result = localIsCheckpoint(value)
result = (ischar(value) || (isstring(value) && isscalar(value))) && ...
    isfile(char(value));
end

function result = localIsCheckpointReference(value)
result = localIsCheckpoint(value) || (isstruct(value) && ...
    isfield(value, 'net') && isfield(value, 'config'));
end

function result = localNetworkUsesGPU(net)
try
    result = isgpuarray(extractdata(net.Learnables.Value{1}));
catch
    result = false;
end
end
