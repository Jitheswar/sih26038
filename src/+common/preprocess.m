function [processedImage, qualityMetadata, preprocessingMetadata] = ...
        preprocess(inputImage, inputConfig, varargin)
%PREPROCESS Run the single shared training and inference image pipeline.
%   [IMAGE, QUALITY, METADATA] = common.preprocess(INPUT, CONFIG) converts
%   INPUT to the configured numeric type, applies the quality gate and FOV
%   operation, resizes it, and applies training-set channel statistics.
%   CONFIG may be a scalar structure or a JSON configuration filename.
%   An optional third argument records the caller as training or inference;
%   it does not alter the pipeline.

% Seeding is the entry point's responsibility; this helper is deterministic.
if nargin < 2
    inputConfig = [];
end
config = localConfiguration(inputConfig);
mode = localMode(varargin{:});
originalInputClass = class(inputImage);
inputImage = localToExpectedType(inputImage, config.outputType);

% Assess the original capture once, regardless of config.qualityGate, so
% qualityMetadata.class is always populated. The gate is deliberately asked
% not to enhance here so that this function owns the enhancement decision
% and can keep the disabled-enhancement path completely unchanged.
gateConfig = config.quality;
gateConfig.enhancementEnabled = false;
[qualityMetadata, ~] = quality.assess(inputImage, gateConfig);
qualityMetadata.qualityGateApplied = config.qualityGate;

pipelineImage = inputImage;
enhancementApplied = false;
if config.enhancement && ...
        strcmp(qualityMetadata.class, 'borderline')
    enhancementConfig = gateConfig;
    enhancementConfig.enhancementEnabled = true;
    enhancementConfig.claheEnabled = config.claheEnabled;
    pipelineImage = quality.enhanceBorderline( ...
        inputImage, qualityMetadata.fovMask, enhancementConfig);
    enhancementApplied = true;
end
qualityMetadata.isEnhanced = enhancementApplied;
qualityMetadata.enhancementApplied = enhancementApplied;

[pipelineImage, fovApplied, fovBoundingBox] = localApplyFov( ...
    pipelineImage, qualityMetadata.fovMask, config.fovMode);

% quality.enhanceBorderline performs illumination normalisation and CLAHE in
% the same conditional branch above. The metadata names these stages
% separately because they are independently configurable parts of the
% documented enhancement sequence.
illuminationApplied = enhancementApplied;
claheApplied = enhancementApplied && config.claheEnabled;

processedImage = imresize(pipelineImage, config.outputSize, 'bicubic');
processedImage = localApplyChannelNormalization( ...
    processedImage, config.channelMean, config.channelStd);
processedImage = localCastOutput(processedImage, config.outputType);

preprocessingMetadata = struct();
preprocessingMetadata.inputClass = originalInputClass;
preprocessingMetadata.inputSize = size(inputImage);
preprocessingMetadata.outputClass = class(processedImage);
preprocessingMetadata.outputSize = size(processedImage);
preprocessingMetadata.qualityGateEnabled = config.qualityGate;
preprocessingMetadata.fovMode = config.fovMode;
preprocessingMetadata.fovApplied = fovApplied;
preprocessingMetadata.fovBoundingBox = fovBoundingBox;
preprocessingMetadata.enhancementEnabled = config.enhancement;
preprocessingMetadata.enhancementApplied = enhancementApplied;
preprocessingMetadata.illuminationNormalizationApplied = illuminationApplied;
preprocessingMetadata.claheEnabled = config.claheEnabled;
preprocessingMetadata.claheApplied = claheApplied;
preprocessingMetadata.channelMean = config.channelMean;
preprocessingMetadata.channelStd = config.channelStd;
end

function config = localConfiguration(inputConfig)
if nargin == 0 || isempty(inputConfig)
    inputConfig = struct();
elseif ischar(inputConfig) || (isstring(inputConfig) && isscalar(inputConfig))
    configFile = char(inputConfig);
    if ~isfile(configFile)
        error('common:InvalidConfig', ...
            'Configuration file does not exist: %s', configFile);
    end
    try
        inputConfig = jsondecode(fileread(configFile));
    catch exception
        error('common:InvalidConfig', ...
            'Configuration file could not be decoded: %s', exception.message);
    end
end
if ~isstruct(inputConfig) || ~isscalar(inputConfig)
    error('common:InvalidConfig', ...
        'Configuration must be a scalar structure or JSON file.');
end

config = struct();
config.qualityGate = localBoolean(inputConfig, ...
    {{'pipeline', 'quality_gate'}, {'quality_gate'}}, true);
config.enhancement = localBoolean(inputConfig, ...
    {{'pipeline', 'enhancement'}, {'enhancement'}}, true);

sizeValue = localFirst(inputConfig, {{'preprocessing', 'resolution'}, ...
    {'preprocessing', 'input_size'}, {'grading', 'input_size'}, {'input_size'}}, 448);
config.outputSize = localResolution(sizeValue);

fovModeSpecified = localFirst(inputConfig, ...
    {{'preprocessing', 'fov_mode'}, {'fov_mode'}}, []);
fovValue = fovModeSpecified;
if isempty(fovModeSpecified) && isfield(inputConfig, 'preprocessing') && ...
        isstruct(inputConfig.preprocessing) && ...
        isfield(inputConfig.preprocessing, 'crop_fov')
    if ~islogical(inputConfig.preprocessing.crop_fov) && ...
            ~(isnumeric(inputConfig.preprocessing.crop_fov) && ...
            isscalar(inputConfig.preprocessing.crop_fov))
        error('common:InvalidConfig', ...
            'preprocessing.crop_fov must be a logical scalar.');
    end
    if logical(inputConfig.preprocessing.crop_fov)
        fovValue = 'crop';
    else
        fovValue = 'mask';
    end
end
if isempty(fovValue)
    fovValue = 'crop';
end
config.fovMode = localFovMode(fovValue);

config.quality = struct();
if isfield(inputConfig, 'quality')
    config.quality = inputConfig.quality;
elseif isfield(inputConfig, 'qualityConfig')
    config.quality = inputConfig.qualityConfig;
end
if ~isstruct(config.quality) || ~isscalar(config.quality)
    error('common:InvalidConfig', 'The quality configuration must be a scalar structure.');
end
illuminationSigma = localFirst(inputConfig, ...
    {{'preprocessing', 'illumination_sigma'}, {'illumination_sigma'}}, []);
if ~isempty(illuminationSigma)
    config.quality.illuminationSigma = localPositiveScalar( ...
        illuminationSigma, 'illumination sigma');
end

claheDefault = true;
if isfield(config.quality, 'claheEnabled') && ...
        ((islogical(config.quality.claheEnabled) && ...
        isscalar(config.quality.claheEnabled)) || ...
        (isnumeric(config.quality.claheEnabled) && ...
        isscalar(config.quality.claheEnabled)))
    claheDefault = logical(config.quality.claheEnabled);
end
claheValue = localFirst(inputConfig, ...
    {{'preprocessing', 'clahe'}, {'clahe'}}, claheDefault);
if isstruct(claheValue)
    claheValue = localFirst(claheValue, {{'enabled'}}, claheDefault);
end
config.claheEnabled = localBooleanValue(claheValue, 'CLAHE enabled');

config.outputType = localOutputType(localFirst(inputConfig, ...
    {{'preprocessing', 'output_type'}, {'output_type'}}, 'single'));

config.channelMean = localFirst(inputConfig, {{'preprocessing', 'channel_mean'}, ...
    {'preprocessing', 'normalization', 'mean'}, {'normalization', 'mean'}, ...
    {'training_channel_mean'}, {'channel_mean'}}, []);
config.channelStd = localFirst(inputConfig, {{'preprocessing', 'channel_std'}, ...
    {'preprocessing', 'normalization', 'std'}, {'normalization', 'std'}, ...
    {'training_channel_std'}, {'channel_std'}}, []);
if isempty(config.channelMean) && isempty(config.channelStd)
    config.channelMean = 0;
    config.channelStd = 1;
elseif isempty(config.channelMean) || isempty(config.channelStd)
    error('common:InvalidConfig', ...
        'Training channel mean and standard deviation must be provided together.');
end
config.channelMean = localStatistics(config.channelMean, 'mean');
config.channelStd = localStatistics(config.channelStd, 'standard deviation');
if any(config.channelStd <= 0)
    error('common:InvalidConfig', ...
        'Training channel standard deviations must be positive.');
end
end

function mode = localMode(varargin)
mode = 'unspecified';
if nargin == 0 || isempty(varargin{1})
    return;
end
if ~(ischar(varargin{1}) || (isstring(varargin{1}) && isscalar(varargin{1})))
    error('common:InvalidMode', 'The optional preprocessing mode must be text.');
end
mode = lower(char(varargin{1}));
if ~ismember(mode, {'training', 'inference', 'unspecified'})
    error('common:InvalidMode', ...
        'The preprocessing mode must be training or inference.');
end
end

function image = localToExpectedType(inputImage, outputType)
if isempty(inputImage)
    error('common:EmptyImage', 'The input image must not be empty.');
end
if ~(isnumeric(inputImage) || islogical(inputImage)) || ~isreal(inputImage)
    error('common:InvalidImage', ...
        'The input image must be a real numeric or logical image.');
end
if ndims(inputImage) > 3 || (ndims(inputImage) == 3 && ...
        ~ismember(size(inputImage, 3), [1, 3]))
    error('common:InvalidImage', ...
        'The input image must be a 2-D grayscale or 3-D RGB image.');
end

if islogical(inputImage)
    image = single(inputImage);
elseif isinteger(inputImage)
    image = im2single(inputImage);
else
    if any(~isfinite(inputImage(:))) || any(inputImage(:) < 0) || ...
            any(inputImage(:) > 1)
        error('common:InvalidImage', ...
            'Floating-point image values must be finite and lie in [0, 1].');
    end
    image = single(inputImage);
end
if strcmp(outputType, 'double')
    image = double(image);
end
end

function [image, applied, boundingBox] = localApplyFov(image, mask, mode)
boundingBox = [NaN, NaN, NaN, NaN];
applied = false;
if strcmp(mode, 'none') || ~any(mask(:))
    return;
end
[rows, columns] = find(mask);
rowStart = min(rows);
rowEnd = max(rows);
columnStart = min(columns);
columnEnd = max(columns);
boundingBox = [columnStart, rowStart, columnEnd - columnStart + 1, ...
    rowEnd - rowStart + 1];
if strcmp(mode, 'crop')
    image = image(rowStart:rowEnd, columnStart:columnEnd, :);
else
    for channel = 1:size(image, 3)
        channelImage = image(:, :, channel);
        channelImage(~mask) = 0;
        image(:, :, channel) = channelImage;
    end
end
applied = true;
end

function image = localApplyChannelNormalization(image, channelMean, channelStd)
numberOfChannels = size(image, 3);
if numberOfChannels == 1
    if numel(channelMean) ~= 1 || numel(channelStd) ~= 1
        error('common:InvalidConfig', ...
            'Grayscale images require one channel mean and standard deviation.');
    end
else
    if numel(channelMean) == 1
        channelMean = repmat(channelMean, 1, numberOfChannels);
    end
    if numel(channelStd) == 1
        channelStd = repmat(channelStd, 1, numberOfChannels);
    end
    if numel(channelMean) ~= numberOfChannels || ...
            numel(channelStd) ~= numberOfChannels
        error('common:InvalidConfig', ...
            'RGB images require one channel mean and standard deviation per channel.');
    end
end

if ~isfloat(image)
    image = single(image);
end
for channel = 1:numberOfChannels
    image(:, :, channel) = (image(:, :, channel) - cast(channelMean(channel), 'like', image)) ...
        ./ cast(channelStd(channel), 'like', image);
end
end

function image = localCastOutput(image, outputType)
if strcmp(outputType, 'single')
    image = single(image);
else
    image = double(image);
end
end

function value = localFirst(inputStruct, paths, defaultValue)
value = defaultValue;
for index = 1:numel(paths)
    candidate = inputStruct;
    path = paths{index};
    found = true;
    for component = 1:numel(path)
        if ~isstruct(candidate) || ~isscalar(candidate) || ...
                ~isfield(candidate, path{component})
            found = false;
            break;
        end
        candidate = candidate.(path{component});
    end
    if found
        value = candidate;
        return;
    end
end
end

function value = localBoolean(inputStruct, paths, defaultValue)
value = localBooleanValue(localFirst(inputStruct, paths, defaultValue), ...
    'configuration flag');
end

function value = localBooleanValue(value, description)
if islogical(value) && isscalar(value)
    value = logical(value);
elseif isnumeric(value) && isscalar(value) && isfinite(value) && ...
        ismember(value, [0, 1])
    value = logical(value);
else
    error('common:InvalidConfig', '%s must be a logical scalar.', description);
end
end

function outputSize = localResolution(value)
if ~isnumeric(value) || ~isreal(value) || isempty(value) || ...
        ~ismember(numel(value), [1, 2]) || any(~isfinite(value(:))) || ...
        any(value(:) <= 0) || any(value(:) ~= floor(value(:)))
    error('common:InvalidConfig', ...
        'The configured resolution must contain one or two positive integers.');
end
value = double(value(:).');
if numel(value) == 1
    outputSize = [value, value];
else
    outputSize = value;
end
end

function mode = localFovMode(value)
if isstring(value) && isscalar(value)
    value = char(value);
end
if ~(ischar(value) && isrow(value))
    error('common:InvalidConfig', 'FOV mode must be crop, mask, or none.');
end
mode = lower(value);
if ~ismember(mode, {'crop', 'mask', 'none'})
    error('common:InvalidConfig', 'FOV mode must be crop, mask, or none.');
end
end

function outputType = localOutputType(value)
if isstring(value) && isscalar(value)
    value = char(value);
end
if ~(ischar(value) && isrow(value))
    error('common:InvalidConfig', 'Output type must be single or double.');
end
outputType = lower(value);
if ~ismember(outputType, {'single', 'double'})
    error('common:InvalidConfig', 'Output type must be single or double.');
end
end

function values = localStatistics(values, description)
if ~isnumeric(values) || ~isreal(values) || isempty(values) || ...
        ~isvector(values) || any(~isfinite(values(:)))
    error('common:InvalidConfig', ...
        'Training channel %s must be a finite numeric vector.', description);
end
values = double(values(:).');
end

function value = localPositiveScalar(value, description)
if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || value <= 0
    error('common:InvalidConfig', '%s must be a positive scalar.', description);
end
value = double(value);
end
