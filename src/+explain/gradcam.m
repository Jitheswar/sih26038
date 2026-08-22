function result = gradcam(varargin)
%GRADCAM Generate two regional Grad-CAM explanations for one fundus image.
%   RESULT = explain.gradcam(CHECKPOINT, IMAGE, TARGETCLASS) loads a
%   trained baseline checkpoint, preprocesses IMAGE through
%   common.preprocess, and computes Grad-CAM for TARGETCLASS (ICDR 0-4).
%   IMAGE may be a numeric image or an image filename.
%
%   The checkpoint-first form is canonical.  IMAGE-first is also accepted:
%   RESULT = explain.gradcam(IMAGE, CHECKPOINT, TARGETCLASS)
%
%   Name-value options:
%     ResultsRoot  Root directory for the dated explanation result (default
%                  is the repository results directory).
%     FinalLayer   Valid convolutional layer to use as the final map.
%     EarlierLayer Valid earlier convolutional layer.  By default the
%                  nearest earlier layer from a finer-resolution ResNet
%                  stage is selected from the loaded graph.
%
%   The model probability in RESULT is the raw softmax probability.  It is
%   explicitly not a calibrated confidence because temperature scaling is a
%   separate, not-yet-implemented pipeline stage.

rng(42, 'twister');

if nargin < 3
    error('explain:MissingInput', ...
        'A checkpoint path, one fundus image, and a target ICDR class are required.');
end

[checkpointFile, imageInput, targetClass, options] = ...
    localParseInputs(varargin{:});
checkpointFile = localRequireCheckpoint(checkpointFile);
localRejectSealedPath(checkpointFile, 'checkpoint');

checkpoint = localLoadCheckpoint(checkpointFile);
net = checkpoint.net;
config = checkpoint.config;

[originalImage, imagePath] = localLoadImage(imageInput);
localRejectSealedPath(imagePath, 'image');

[processedImage, qualityMetadata, preprocessingMetadata] = ...
    common.preprocess(originalImage, config, 'inference');
if size(processedImage, 3) == 1
    processedImage = repmat(processedImage, 1, 1, 3);
end

selection = resolveLayers(net, options.finalLayer, options.earlierLayer);
executionEnvironment = "cpu";

probabilities = minibatchpredict(net, processedImage, ...
    'MiniBatchSize', 1, ...
    'ExecutionEnvironment', executionEnvironment, ...
    'OutputDataFormats', 'CB');
probabilities = gather(extractdata(probabilities));
probabilities = double(probabilities(:));
if numel(probabilities) ~= 5 || any(~isfinite(probabilities))
    error('explain:InvalidNetworkOutput', ...
        'The checkpoint must produce five finite ICDR class probabilities.');
end

[~, predictedIndex] = max(probabilities, [], 1);
targetIndex = targetClass + 1;

finalMap = localGradCAM(net, processedImage, targetIndex, ...
    selection.finalLayerName, executionEnvironment);
earlierMap = localGradCAM(net, processedImage, targetIndex, ...
    selection.earlierLayerName, executionEnvironment);

originalRows = size(originalImage, 1);
originalColumns = size(originalImage, 2);
final = localMapResult(finalMap, [originalRows, originalColumns], ...
    selection.finalLayerName);
earlier = localMapResult(earlierMap, [originalRows, originalColumns], ...
    selection.earlierLayerName);

originalRgb = localDisplayImage(originalImage);
overlay = localMakeOverlay(originalRgb, final.normalizedHeatmap);

resultsRoot = options.resultsRoot;
if isempty(resultsRoot)
    resultsRoot = fullfile(localProjectRoot(), 'results');
end
resultsDirectory = localCreateDatedDirectory(resultsRoot);
configPath = fullfile(resultsDirectory, 'config.json');
localWriteText(configPath, jsonencode(config));

result = struct();
result.status = "completed";
result.checkpointPath = string(checkpointFile);
result.imagePath = string(imagePath);
result.originalImageSize = size(originalImage);
result.targetClass = targetClass;
result.predictedClass = predictedIndex - 1;
result.classNames = string(0:4).';
result.modelProbability = probabilities(targetIndex);
result.predictedClassProbability = probabilities(predictedIndex);
result.probabilities = probabilities;
result.probabilitiesAreCalibrated = false;
result.probabilityDescription = ...
    "Raw softmax model probability; not a temperature-calibrated confidence.";
result.convolutionalLayerName = string(selection.finalLayerName);
result.earlierConvolutionalLayerName = string(selection.earlierLayerName);
result.rawHeatmap = final.rawHeatmap;
result.resizedHeatmap = final.resizedHeatmap;
result.normalizedHeatmap = final.normalizedHeatmap;
result.overlay = overlay;
result.overlayAlpha = single(0.55 * final.normalizedHeatmap);
result.transparentOverlayDescription = ...
    "RGB composite with the normalized Grad-CAM map alpha-blended over the fundus image.";
result.rawHeatmapHeight = final.rawHeatmapHeight;
result.rawHeatmapWidth = final.rawHeatmapWidth;
result.rawHeatmapResolution = string(final.rawHeatmapResolution);
result.layers = struct('final', final, 'earlier', earlier);
% The quality gate carries a full-resolution FOV mask.  Keep the scalar
% quality metadata in the returned result but omit that mask from persisted
% explanation artifacts so a single case does not become unnecessarily huge.
if isfield(qualityMetadata, 'fovMask')
    qualityMetadata.fovMask = [];
end
if isfield(qualityMetadata, 'fovInfo') && ...
        isfield(qualityMetadata.fovInfo, 'mask')
    qualityMetadata.fovInfo.mask = [];
end
result.qualityMetadata = qualityMetadata;
result.preprocessingMetadata = preprocessingMetadata;
result.executionEnvironment = executionEnvironment;
result.clinicalLimitation = ...
    "Grad-CAM shows regional model attention, not precise microaneurysm localisation.";
result.resultsDirectory = string(resultsDirectory);
result.configPath = string(configPath);

overlayPath = fullfile(resultsDirectory, 'gradcam_overlay.png');
reportPath = fullfile(resultsDirectory, 'gradcam_report.png');
reportTextPath = fullfile(resultsDirectory, 'gradcam_report.txt');
localExportOverlay(overlay, overlayPath);
localExportReport(originalRgb, final, earlier, overlay, result, reportPath);
localWriteText(reportTextPath, localReportText(result));

result.overlayPath = string(overlayPath);
result.reportPath = string(reportPath);
result.reportTextPath = string(reportTextPath);
result.matPath = string(fullfile(resultsDirectory, 'explanation.mat'));
% The returned result keeps every map for interactive use.  Persist one copy
% of the final maps at top level and the earlier raw map, rather than storing
% duplicate full-resolution maps inside both layer structs.
resultForSave = result;
resultForSave.layers.final.rawHeatmap = [];
resultForSave.layers.final.resizedHeatmap = [];
resultForSave.layers.final.normalizedHeatmap = [];
resultForSave.layers.earlier.resizedHeatmap = [];
resultForSave.layers.earlier.normalizedHeatmap = [];
fullResult = result;
result = resultForSave;
save(char(result.matPath), 'result');
result = fullResult;
end

function [checkpointFile, imageInput, targetClass, options] = ...
        localParseInputs(varargin)
if localIsText(varargin{1})
    checkpointFile = char(varargin{1});
    imageInput = varargin{2};
elseif localIsText(varargin{2})
    imageInput = varargin{1};
    checkpointFile = char(varargin{2});
else
    error('explain:InvalidCheckpoint', ...
        'One of the first two inputs must be the checkpoint filename.');
end

targetClass = localTargetClass(varargin{3});
options = struct('resultsRoot', '', 'finalLayer', '', 'earlierLayer', '');
if numel(varargin) > 3
    if mod(numel(varargin) - 3, 2) ~= 0
        error('explain:InvalidOptions', ...
            'Name-value options must be supplied as pairs.');
    end
    for index = 4:2:numel(varargin)
        name = varargin{index};
        if ~localIsText(name)
            error('explain:InvalidOptions', 'Option names must be text.');
        end
        name = lower(char(name));
        value = varargin{index + 1};
        switch name
            case 'resultsroot'
                if ~localIsText(value)
                    error('explain:InvalidOptions', ...
                        'ResultsRoot must be a directory name.');
                end
                options.resultsRoot = char(value);
            case 'finallayer'
                if ~localIsText(value)
                    error('explain:InvalidOptions', ...
                        'FinalLayer must be a layer name.');
                end
                options.finalLayer = char(value);
            case 'earlierlayer'
                if ~localIsText(value)
                    error('explain:InvalidOptions', ...
                        'EarlierLayer must be a layer name.');
                end
                options.earlierLayer = char(value);
            otherwise
                error('explain:InvalidOptions', 'Unknown option: %s.', name);
        end
    end
end

if ~(isnumeric(imageInput) || islogical(imageInput) || localIsText(imageInput))
    error('explain:InvalidImage', ...
        'The image must be a numeric array, logical array, or image filename.');
end
end

function targetClass = localTargetClass(value)
if iscategorical(value) && isscalar(value)
    value = string(value);
end
if localIsText(value)
    text = strtrim(char(value));
    parsed = str2double(text);
    if isfinite(parsed) && parsed == floor(parsed)
        value = parsed;
    end
end
if ~(isnumeric(value) && isscalar(value) && isreal(value) && ...
        isfinite(value) && value == floor(value) && value >= 0 && value <= 4)
    error('explain:InvalidTargetClass', ...
        'Target ICDR class must be an integer from 0 through 4.');
end
targetClass = double(value);
end

function checkpointFile = localRequireCheckpoint(checkpointFile)
if ~isfile(checkpointFile)
    error('explain:MissingCheckpoint', ...
        'Checkpoint does not exist: %s', checkpointFile);
end
checkpointFile = char(java.io.File(checkpointFile).getCanonicalPath());
end

function checkpoint = localLoadCheckpoint(checkpointFile)
try
    checkpoint = load(checkpointFile);
catch exception
    error('explain:InvalidCheckpoint', ...
        'Checkpoint could not be loaded: %s', exception.message);
end
if ~isfield(checkpoint, 'net') || ~isa(checkpoint.net, 'dlnetwork')
    error('explain:InvalidCheckpoint', ...
        'Checkpoint must contain a trained dlnetwork named net.');
end
if ~isfield(checkpoint, 'config') || ~isstruct(checkpoint.config) || ...
        ~isscalar(checkpoint.config)
    error('explain:InvalidCheckpoint', ...
        'Checkpoint must contain the training configuration named config.');
end
end

function [image, imagePath] = localLoadImage(imageInput)
imagePath = '';
if localIsText(imageInput)
    imagePath = char(imageInput);
    if ~isfile(imagePath)
        error('explain:MissingImage', 'Image does not exist: %s', imagePath);
    end
    try
        [image, map] = imread(imagePath);
        if ~isempty(map)
            image = ind2rgb(image, map);
        end
    catch exception
        error('explain:InvalidImage', ...
            'Image could not be read: %s', exception.message);
    end
else
    image = imageInput;
end
end

function scoreMap = localGradCAM(net, image, targetIndex, layerName, executionEnvironment)
try
    scoreMap = gradCAM(net, image, targetIndex, ...
        'FeatureLayer', layerName, ...
        'OutputUpsampling', 'none', ...
        'InputDataFormats', 'SSCB', ...
        'ExecutionEnvironment', executionEnvironment);
catch exception
    error('explain:GradCAMFailed', ...
        'Grad-CAM failed for valid layer %s: %s', layerName, exception.message);
end
scoreMap = gather(scoreMap);
if isa(scoreMap, 'dlarray')
    scoreMap = extractdata(scoreMap);
end
scoreMap = double(squeeze(scoreMap));
if ndims(scoreMap) ~= 2 || isempty(scoreMap) || any(~isfinite(scoreMap(:)))
    error('explain:InvalidHeatmap', ...
        'Grad-CAM returned a non-finite or empty map for layer %s.', layerName);
end
end

function layerResult = localMapResult(rawHeatmap, originalSize, layerName)
resizedHeatmap = imresize(rawHeatmap, originalSize, 'bicubic');
if any(~isfinite(resizedHeatmap(:)))
    error('explain:InvalidHeatmap', ...
        'The resized Grad-CAM map for layer %s is non-finite.', layerName);
end
normalizedHeatmap = localNormalize(resizedHeatmap);

layerResult = struct();
layerResult.name = string(layerName);
layerResult.rawHeatmap = single(rawHeatmap);
layerResult.resizedHeatmap = single(resizedHeatmap);
layerResult.normalizedHeatmap = single(normalizedHeatmap);
layerResult.rawHeatmapHeight = size(rawHeatmap, 1);
layerResult.rawHeatmapWidth = size(rawHeatmap, 2);
layerResult.rawHeatmapResolution = sprintf('%dx%d', ...
    layerResult.rawHeatmapHeight, layerResult.rawHeatmapWidth);
end

function normalized = localNormalize(map)
map = double(map);
minimum = min(map(:));
maximum = max(map(:));
if maximum > minimum
    normalized = (map - minimum) / (maximum - minimum);
else
    normalized = zeros(size(map));
end
normalized = min(max(normalized, 0), 1);
end

function overlay = localMakeOverlay(originalRgb, normalizedHeatmap)
base = min(max(im2double(originalRgb), 0), 1);
colorMap = parula(256);
indices = 1 + floor(255 * normalizedHeatmap);
heatmapRgb = ind2rgb(indices, colorMap);
alpha = 0.55 * normalizedHeatmap;
alpha = repmat(alpha, 1, 1, 3);
overlay = single((1 - alpha) .* base + alpha .* heatmapRgb);
end

function image = localDisplayImage(image)
if ndims(image) == 2
    image = repmat(image, 1, 1, 3);
end
if size(image, 3) ~= 3
    error('explain:InvalidImage', 'The fundus image must be grayscale or RGB.');
end
if isinteger(image) || islogical(image)
    image = im2double(image);
else
    image = double(image);
end
image = min(max(image, 0), 1);
end

function localExportOverlay(overlay, outputPath)
figureHandle = figure('Visible', 'off', 'Color', 'none');
cleanup = onCleanup(@() close(figureHandle)); %#ok<NASGU>
axesHandle = axes(figureHandle);
imshow(overlay, 'Parent', axesHandle);
axis(axesHandle, 'image', 'off');
try
    exportgraphics(axesHandle, outputPath, 'Resolution', 150);
catch exception
    error('explain:ExportFailed', ...
        'Overlay export failed: %s', exception.message);
end
end

function localExportReport(original, final, earlier, overlay, result, outputPath)
figureHandle = figure('Visible', 'off', 'Color', 'white', ...
    'Position', [100, 100, 1200, 900]);
cleanup = onCleanup(@() close(figureHandle)); %#ok<NASGU>
layout = tiledlayout(figureHandle, 2, 2, 'TileSpacing', 'compact', ...
    'Padding', 'compact');

nexttile(layout);
imshow(original);
title('Original fundus', 'Color', [0.05, 0.05, 0.05]);

nexttile(layout);
imagesc(final.normalizedHeatmap);
axis image off;
colorbarHandle = colorbar;
colorbarHandle.Color = [0.05, 0.05, 0.05];
titleHandle = title(sprintf('Final layer: %s (%s raw)', final.name, ...
    final.rawHeatmapResolution), 'Interpreter', 'none');
titleHandle.Color = [0.05, 0.05, 0.05];

nexttile(layout);
imshow(overlay);
title('Transparent regional attention overlay', ...
    'Color', [0.05, 0.05, 0.05]);

nexttile(layout);
axis off;
reportLines = { ...
    sprintf('Target ICDR class: %d', result.targetClass), ...
    sprintf('Predicted ICDR class: %d', result.predictedClass), ...
    sprintf('Raw softmax target probability: %.6f', result.modelProbability), ...
    'Probability is not temperature-calibrated confidence.', ...
    sprintf('Final layer: %s | raw map: %s', final.name, ...
        final.rawHeatmapResolution), ...
    sprintf('Earlier layer: %s | raw map: %s', earlier.name, ...
        earlier.rawHeatmapResolution), ...
    'Grad-CAM is regional model attention.', ...
    'It is not precise microaneurysm localisation.', ...
    'Screening aid. Not a diagnosis. Requires clinician confirmation.'};
text(0.02, 0.98, reportLines, 'Units', 'normalized', ...
    'VerticalAlignment', 'top', 'Interpreter', 'none', 'FontSize', 11, ...
    'Color', [0.05, 0.05, 0.05]);

try
    exportgraphics(figureHandle, outputPath, 'Resolution', 150);
catch exception
    error('explain:ExportFailed', ...
        'Annotated report export failed: %s', exception.message);
end
end

function text = localReportText(result)
text = sprintf([ ...
    'Grad-CAM explanation report\n', ...
    'Checkpoint: %s\n', ...
    'Image: %s\n', ...
    'Target ICDR class: %d\n', ...
    'Predicted ICDR class: %d\n', ...
    'Raw softmax target probability: %.6f\n', ...
    'Probability is not a temperature-calibrated confidence.\n', ...
    'Final convolutional layer: %s\n', ...
    'Final raw heatmap resolution: %s\n', ...
    'Earlier convolutional layer: %s\n', ...
    'Earlier raw heatmap resolution: %s\n', ...
    'Clinical limitation: %s\n', ...
    'Sealed test set used: no\n'], ...
    result.checkpointPath, result.imagePath, result.targetClass, ...
    result.predictedClass, result.modelProbability, ...
    result.layers.final.name, result.layers.final.rawHeatmapResolution, ...
    result.layers.earlier.name, result.layers.earlier.rawHeatmapResolution, ...
    result.clinicalLimitation);
end

function directory = localCreateDatedDirectory(resultsRoot)
if ~isfolder(resultsRoot)
    try
        mkdir(resultsRoot);
    catch exception
        error('explain:ResultsDirectory', ...
            'Results root could not be created: %s', exception.message);
    end
end
stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
for suffix = 0:999
    if suffix == 0
        name = stamp;
    else
        name = sprintf('%s_%02d', stamp, suffix);
    end
    directory = fullfile(resultsRoot, name);
    if ~isfolder(directory)
        mkdir(directory);
        return;
    end
end
error('explain:ResultsDirectory', ...
    'Could not allocate a unique dated explanation directory.');
end

function localWriteText(filename, text)
fileIdentifier = fopen(filename, 'w', 'n', 'UTF-8');
if fileIdentifier < 0
    error('explain:ResultsDirectory', 'Could not write %s.', filename);
end
cleanup = onCleanup(@() fclose(fileIdentifier)); %#ok<NASGU>
fwrite(fileIdentifier, text, 'char');
end

function localRejectSealedPath(path, description)
if isempty(path)
    return;
end
normalizedPath = lower(strrep(char(path), '\\', '/'));
if contains(normalizedPath, '/data/sealed/') || ...
        endsWith(normalizedPath, '/data/sealed')
    error('explain:SealedData', ...
        'The %s is inside data/sealed and cannot be used.', description);
end
end

function result = localIsText(value)
result = ischar(value) || (isstring(value) && isscalar(value));
end

function root = localProjectRoot()
thisFile = mfilename('fullpath');
root = fileparts(fileparts(fileparts(thisFile)));
end
