function result = lesionSegmentationEvaluation(checkpointPath, varargin)
%LESIONSEGMENTATIONEVALUATION Score the lesion network on IDRiD Set-B.
%   RESULT = lesionSegmentationEvaluation(CHECKPOINTPATH) evaluates a
%   checkpoint written by segment.trainLesionSegmentation over the held-out
%   lesion_test split and reports per-lesion-type AUPR.
%
%   Set-B is IDRiD's own published benchmark split for the lesion
%   sub-challenge.  It is never trained on and never used to select an
%   epoch; the checkpoint handed in here has already been chosen on the
%   validation split (§10.2).
%
%   AUPR at 33 equally spaced thresholds over the pooled pixels of the
%   split, which is the sub-challenge protocol (§6.4).  Every AUPR is
%   reported beside the prevalence of its lesion type, because an AUPR is
%   only interpretable against the precision a detector that answered
%   positive everywhere would reach.
%
%   Note this is not the sealed set.  data/sealed/ holds Messidor-2 and is
%   untouched (§10.4); IDRiD Set-B is an ordinary held-out split.

rng(42, 'twister');

parser = inputParser();
parser.addParameter('ResultsRoot', '');
parser.addParameter('Split', 'test');
parser.addParameter('WritePlots', true);
parser.parse(varargin{:});
splitName = char(parser.Results.Split);

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
addpath(fullfile(projectRoot, 'eval', 'metrics'));
addpath(genpath(fullfile(projectRoot, 'src')));

if ~isfile(char(checkpointPath))
    error('eval:MissingCheckpoint', ...
        'Lesion checkpoint does not exist: %s', char(checkpointPath));
end
loaded = load(char(checkpointPath));
if ~isfield(loaded, 'net') || ~isfield(loaded, 'config')
    error('eval:InvalidCheckpoint', ...
        'Checkpoint %s must contain net and config.', char(checkpointPath));
end
config = loaded.config;
model = struct('net', loaded.net, 'config', config);
if isfield(loaded, 'validation')
    model.validation = loaded.validation;
end

lesion = config.lesion_segmentation;
lesionTypes = lesion.lesion_types;
if ischar(lesionTypes)
    lesionTypes = {lesionTypes};
end
thresholds = linspace(0, 1, lesion.aupr_thresholds);

splitFile = fullfile(projectRoot, 'data', 'splits', ...
    sprintf('lesion_%s.csv', splitName));
if ~isfile(splitFile)
    error('eval:MissingSplit', 'Lesion split file does not exist: %s', ...
        splitFile);
end
splitTable = readtable(splitFile, 'TextType', 'string');

resultsRoot = parser.Results.ResultsRoot;
if isempty(resultsRoot)
    resultsRoot = fullfile(projectRoot, 'results');
end
if ~isfolder(resultsRoot)
    mkdir(resultsRoot);
end
resultsDirectory = fullfile(resultsRoot, sprintf('%s_lesion_%s_evaluation', ...
    datestr(now, 'yyyymmdd_HHMMSS'), splitName));
mkdir(resultsDirectory);
localWriteText(fullfile(resultsDirectory, 'config.json'), jsonencode(config));

fprintf('Evaluating %s\n', char(checkpointPath));
fprintf('Split: lesion_%s (n = %d frames)\n', splitName, height(splitTable));

totals = struct('truePositive', 0, 'falsePositive', 0, ...
    'falseNegative', 0, 'positiveCount', zeros(numel(lesionTypes), 1), ...
    'pixelCount', 0);
perImage = struct('imageId', {}, 'aupr', {});

for rowIndex = 1:height(splitTable)
    imageId = char(splitTable.image_id(rowIndex));
    setFolder = localSetFolder(char(splitTable.relative_path(rowIndex)));
    [image, masks] = localReadCase(projectRoot, imageId, setFolder, ...
        lesionTypes);

    prediction = segment.segmentLesions(image, model);
    counts = lesionThresholdCounts(prediction.probabilityMaps, masks, ...
        thresholds);

    totals.truePositive = totals.truePositive + counts.truePositive;
    totals.falsePositive = totals.falsePositive + counts.falsePositive;
    totals.falseNegative = totals.falseNegative + counts.falseNegative;
    totals.positiveCount = totals.positiveCount + counts.positiveCount;
    totals.pixelCount = totals.pixelCount + counts.pixelCount;

    imageMetrics = lesionAUPR(counts, thresholds, lesionTypes);
    perImage(end + 1) = struct('imageId', imageId, ...
        'aupr', imageMetrics.aupr(:)'); %#ok<AGROW>
    fprintf('  %-12s done (%d of %d)\n', imageId, rowIndex, height(splitTable));
end

metrics = lesionAUPR(totals, thresholds, lesionTypes);
metrics.imageCount = height(splitTable);
metrics.split = string(splitName);

localPrintTable(metrics, lesionTypes, splitName);

if parser.Results.WritePlots
    localWritePrecisionRecallPlot(metrics, lesionTypes, ...
        fullfile(resultsDirectory, 'precision_recall.png'));
end

summary = struct();
summary.checkpoint = string(checkpointPath);
summary.split = string(splitName);
summary.imageCount = metrics.imageCount;
summary.lesionTypes = lesionTypes(:)';
summary.aupr = metrics.aupr(:)';
summary.prevalence = metrics.prevalence(:)';
summary.auprOverPrevalence = metrics.auprOverPrevalence(:)';
summary.bestF1 = metrics.bestF1(:)';
summary.bestF1Threshold = metrics.bestF1Threshold(:)';
localWriteText(fullfile(resultsDirectory, 'metrics.json'), ...
    jsonencode(summary));
save(fullfile(resultsDirectory, 'metrics.mat'), 'metrics', 'perImage', ...
    'summary');

result = summary;
result.metrics = metrics;
result.perImage = perImage;
result.resultsDirectory = string(resultsDirectory);
fprintf('Results written to %s\n', resultsDirectory);
end

function [image, masks] = localReadCase(projectRoot, imageId, setFolder, ...
    lesionTypes)
imagePath = fullfile(projectRoot, 'data', 'raw', 'A. Segmentation', ...
    '1. Original Images', setFolder, sprintf('%s.jpg', imageId));
image = imread(imagePath);
masks = false(size(image, 1), size(image, 2), numel(lesionTypes));
for typeIndex = 1:numel(lesionTypes)
    maskPath = common.lesionMaskPath(projectRoot, setFolder, imageId, ...
        lesionTypes{typeIndex});
    if ~isfile(maskPath)
        continue;
    end
    raw = imread(maskPath);
    if ndims(raw) == 3
        raw = raw(:, :, 1);
    end
    masks(:, :, typeIndex) = raw > 0;
end
end

function setFolder = localSetFolder(relativePath)
if contains(relativePath, 'a. Training Set')
    setFolder = 'a. Training Set';
else
    setFolder = 'b. Testing Set';
end
end

function localPrintTable(metrics, lesionTypes, splitName)
fprintf('\nLesion segmentation, split %s, n = %d frames\n', splitName, ...
    metrics.imageCount);
fprintf('%-4s %10s %12s %12s %10s %12s\n', 'type', 'AUPR', 'prevalence', ...
    'AUPR/prev', 'bestF1', 'threshold');
for typeIndex = 1:numel(lesionTypes)
    fprintf('%-4s %10.4f %12.5f %12.2f %10.4f %12.4f\n', ...
        lesionTypes{typeIndex}, metrics.aupr(typeIndex), ...
        metrics.prevalence(typeIndex), ...
        metrics.auprOverPrevalence(typeIndex), ...
        metrics.bestF1(typeIndex), metrics.bestF1Threshold(typeIndex));
end
fprintf('mean AUPR: %.4f\n\n', mean(metrics.aupr, 'omitnan'));
end

function localWritePrecisionRecallPlot(metrics, lesionTypes, filename)
%LOCALWRITEPRECISIONRECALLPLOT Draw the per-type PR curves.
%   exportgraphics rather than Report Generator, which is outside the
%   declared toolbox set (§4.4, §8.7).

figureHandle = figure('Visible', 'off', 'Position', [100, 100, 800, 600]);
cleanup = onCleanup(@() close(figureHandle));
axesHandle = axes(figureHandle); %#ok<LAXES>
hold(axesHandle, 'on');

for typeIndex = 1:numel(lesionTypes)
    recall = metrics.recall(typeIndex, :);
    precision = metrics.precision(typeIndex, :);
    valid = isfinite(recall) & isfinite(precision);
    [sortedRecall, order] = sort(recall(valid));
    sortedPrecision = precision(valid);
    sortedPrecision = sortedPrecision(order);
    plot(axesHandle, sortedRecall, sortedPrecision, '-o', ...
        'LineWidth', 1.5, 'MarkerSize', 3, ...
        'DisplayName', sprintf('%s (AUPR %.4f)', lesionTypes{typeIndex}, ...
        metrics.aupr(typeIndex)));
    yline(axesHandle, metrics.prevalence(typeIndex), ':', ...
        'HandleVisibility', 'off');
end

xlabel(axesHandle, 'Recall');
ylabel(axesHandle, 'Precision');
title(axesHandle, sprintf(['Lesion segmentation precision-recall, ' ...
    'IDRiD split %s (n = %d)'], metrics.split, metrics.imageCount));
legend(axesHandle, 'Location', 'northeast');
grid(axesHandle, 'on');
xlim(axesHandle, [0, 1]);
exportgraphics(figureHandle, filename, 'Resolution', 150);
end

function localWriteText(filename, text)
fileIdentifier = fopen(filename, 'w');
if fileIdentifier < 0
    error('eval:ResultsNotWritable', ...
        'Could not open %s for writing.', filename);
end
cleanup = onCleanup(@() fclose(fileIdentifier));
fwrite(fileIdentifier, text, 'char');
end
