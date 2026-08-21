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
        checkpointFile = char(varargin{2});
        configInput = [];
        if nargin >= 3
            configInput = varargin{3};
        end
    else
        configInput = [];
        if nargin >= 2
            configInput = varargin{2};
        end
        result = localPreprocessOnly(image, configInput);
        return;
    end
else
    checkpointFile = char(varargin{1});
    if nargin < 2 || ~localIsImage(varargin{2})
        error('grade:MissingInferenceImage', ...
            'A numeric image must follow the checkpoint filename.');
    end
    image = varargin{2};
    configInput = [];
    if nargin >= 3
        configInput = varargin{3};
    end
end

if ~isfile(checkpointFile)
    error('grade:MissingCheckpoint', 'Checkpoint does not exist: %s', checkpointFile);
end
checkpoint = load(checkpointFile, 'net', 'config');
if isempty(configInput)
    configInput = checkpoint.config;
end
[config, ~, projectRoot] = readConfiguration(configInput);
addpath(fullfile(projectRoot, 'eval'));
addpath(fullfile(projectRoot, 'eval', 'metrics'));
[processedImage, qualityMetadata, preprocessingMetadata] = ...
    common.preprocess(image, config, 'inference');
if size(processedImage, 3) == 1
    processedImage = repmat(processedImage, 1, 1, 3);
end

net = checkpoint.net;
executionEnvironment = "cpu";
if canUseGPU
    executionEnvironment = "gpu";
    net = dlupdate(@gpuArray, net);
end
scores = minibatchpredict(net, processedImage, ...
    'MiniBatchSize', 1, ...
    'ExecutionEnvironment', executionEnvironment, ...
    'OutputDataFormats', 'CB');
probabilities = gather(extractdata(scores));
probabilities = reshape(double(probabilities), 5, 1);
[~, predictedIndex] = max(probabilities, [], 1);

result = struct();
result.status = "inferred";
result.predictedGrade = predictedIndex - 1;
result.classNames = string(0:4).';
result.probabilities = probabilities;
result.referableProbability = sum(probabilities(3:5));
result.referableThreshold = 2;
result.probabilitiesAreCalibrated = false;
result.qualityMetadata = qualityMetadata;
result.preprocessingMetadata = preprocessingMetadata;
result.preprocessedImage = processedImage;
result.gpuUsed = executionEnvironment == "gpu";
end

function result = localPreprocessOnly(image, configInput)
result = struct('status', 'preprocessed');
[result.preprocessedImage, result.qualityMetadata, ...
    result.preprocessingMetadata] = common.preprocess( ...
    image, configInput, 'inference');
end

function result = localIsImage(value)
result = (isnumeric(value) || islogical(value)) && ~isempty(value);
end

function result = localIsCheckpoint(value)
result = (ischar(value) || (isstring(value) && isscalar(value))) && ...
    isfile(char(value));
end
