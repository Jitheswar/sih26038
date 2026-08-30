function result = explanationQuality(varargin)
%EXPLANATIONQUALITY Measure explanation quality against IDRiD lesion masks.
%   RESULT = explanationQuality() evaluates the §11.7 metric set on the
%   IDRiD segmentation package, which ships pixel-level lesion masks and is
%   the reason IDRiD is in the pipeline at all.
%
%   Name-value options:
%     'Checkpoint'   Frozen checkpoint path (default: config/default.json).
%     'Subset'       "testing" (default) or "training" IDRiD split.
%     'Limit'        Evaluate only the first N images.
%     'TopFraction'  Salient-pixel fraction for the pointing game (0.05).
%     'Steps'        Deletion/insertion steps (default 20).
%     'SanityLimit'  Images used for the randomisation sanity check (5).
%     'ResultsRoot'  Root for the dated result directory.
%
%   Metrics, from the §11.7 table:
%
%     Lesion hit rate (pointing game)
%         Fraction of the top-k% most salient pixels that fall inside a
%         ground-truth lesion mask.  Computed identically for Grad-CAM and
%         for the classical lesion-evidence channel, which is the head-to-
%         head comparison R6.2 asks for, made numeric.  A random-saliency
%         control is reported alongside: a hit rate is only meaningful
%         relative to what chance would score on the same masks.
%
%     Deletion / insertion AUC
%         Progressively remove (or insert) the pixels the explanation calls
%         important and track the target-class probability.  Faithfulness
%         to the model, which is distinct from agreement with clinical
%         ground truth.  An explanation can be faithful to a model that is
%         wrong, so both are reported.
%
%     Sanity check (cascading parameter randomisation)
%         Randomise the trained weights from the top layer down and
%         recompute the map.  If it barely changes, the method is not
%         explaining this model.  Grad-CAM is expected to pass, that is,
%         correlation should fall as randomisation deepens.
%
%   Geometry note.  The masks are compared against the map in the model's
%   own 448x448 frame, not the original frame.  common.preprocess crops to
%   the field of view before resizing, so a map resized straight back to
%   the original dimensions does not line up with the original pixels.
%   Cropping the mask with the recorded fovBoundingBox and resizing it the
%   same way puts both in one frame exactly.
%
%   Domain note.  The grading model is trained on APTOS and IDRiD is a
%   different camera and population, so the predicted grades here carry
%   domain shift.  That does not affect what these metrics measure, which
%   is where the model looks and whether the map is faithful to it, not
%   whether the grade is right.

rng(42, 'twister');

options = localOptions(varargin{:});
projectRoot = localProjectRoot();
config = jsondecode(fileread(fullfile(projectRoot, 'config', 'default.json')));

checkpointPath = options.checkpoint;
if isempty(checkpointPath)
    checkpointPath = fullfile(projectRoot, config.operating_point.model);
end
if ~isfile(checkpointPath)
    error('eval:MissingCheckpoint', 'Checkpoint does not exist: %s', checkpointPath);
end
checkpoint = load(checkpointPath, 'net', 'config');
checkpoint.checkpointPath = checkpointPath;

cases = localFindCases(projectRoot, options.subset, options.limit);
fprintf('Explanation quality on IDRiD %s set: %d images with lesion masks.\n', ...
    options.subset, numel(cases));
fprintf('Top-%.0f%% salient pixels, %d deletion/insertion steps.\n\n', ...
    100 * options.topFraction, options.steps);

perImage = struct([]);
timer = tic;
for index = 1:numel(cases)
    entry = localEvaluateCase(cases(index), checkpoint, config, options);
    if isempty(perImage)
        perImage = entry;
    else
        perImage(index) = entry; %#ok<AGROW>
    end
    fprintf(['  %2d/%2d %-12s grade %d  hit %.3f (cand %.3f, rand %.3f)  ' ...
        'del %.3f ins %.3f  [%.0f s]\n'], index, numel(cases), ...
        entry.imageId, entry.predictedLevel, entry.gradCamHitRate, ...
        entry.candidateHitRate, entry.randomHitRate, ...
        entry.deletionAUC, entry.insertionAUC, toc(timer));
end

sanity = localSanityCheck(cases, checkpoint, config, options);
summary = localSummarise(perImage, sanity, options);
localPrintSummary(summary);

resultsDirectory = localDatedDirectory(options.resultsRoot, 'explanation_quality');
localWriteOutputs(resultsDirectory, summary, perImage, sanity, options, config);

result = struct();
result.status = "completed";
result.summary = summary;
result.perImage = perImage;
result.sanity = sanity;
result.resultsDirectory = string(resultsDirectory);
result.sealedDataAccessed = false;
end

% ---------------------------------------------------------------- options

function options = localOptions(varargin)
parser = inputParser;
parser.addParameter('Checkpoint', '');
parser.addParameter('Subset', 'testing');
parser.addParameter('Limit', Inf);
parser.addParameter('TopFraction', 0.05);
parser.addParameter('Steps', 20);
parser.addParameter('SanityLimit', 5);
parser.addParameter('ResultsRoot', fullfile(localProjectRoot(), 'results'));
% Optional Track B checkpoint. When supplied, the learned lesion channel is
% scored in the same pointing game as Grad-CAM and the classical channel,
% which is the head-to-head comparison §11.7 exists to make.
parser.addParameter('LesionCheckpoint', '');
parser.parse(varargin{:});

options = struct();
options.checkpoint = char(string(parser.Results.Checkpoint));
options.subset = lower(char(string(parser.Results.Subset)));
options.limit = parser.Results.Limit;
options.topFraction = double(parser.Results.TopFraction);
options.steps = double(parser.Results.Steps);
options.sanityLimit = double(parser.Results.SanityLimit);
options.resultsRoot = char(string(parser.Results.ResultsRoot));
options.lesionCheckpoint = char(string(parser.Results.LesionCheckpoint));
if ~isempty(options.lesionCheckpoint) && ~isfile(options.lesionCheckpoint)
    error('eval:MissingLesionCheckpoint', ...
        'Lesion checkpoint does not exist: %s', options.lesionCheckpoint);
end

if ~ismember(options.subset, {'testing', 'training'})
    error('eval:InvalidSubset', 'Subset must be testing or training.');
end
if options.topFraction <= 0 || options.topFraction >= 1
    error('eval:InvalidTopFraction', 'TopFraction must lie strictly between 0 and 1.');
end
end

function cases = localFindCases(projectRoot, subset, limit)
root = fullfile(projectRoot, 'data', 'raw', 'A. Segmentation');
if ~isfolder(root)
    error('eval:MissingIDRiD', ...
        'The IDRiD segmentation package is not present at %s', root);
end
if strcmp(subset, 'testing')
    imageFolder = fullfile(root, '1. Original Images', 'b. Testing Set');
    maskRoot = fullfile(root, '2. All Segmentation Groundtruths', 'b. Testing Set');
else
    imageFolder = fullfile(root, '1. Original Images', 'a. Training Set');
    maskRoot = fullfile(root, '2. All Segmentation Groundtruths', 'a. Training Set');
end

% The optic disc is deliberately excluded. It is a normal anatomical
% structure, not a lesion, so counting attention on it as a hit would
% reward a map for finding the brightest thing in the image.
lesionFolders = { ...
    fullfile(maskRoot, '1. Microaneurysms'), '_MA'; ...
    fullfile(maskRoot, '2. Haemorrhages'), '_HE'; ...
    fullfile(maskRoot, '3. Hard Exudates'), '_EX'; ...
    fullfile(maskRoot, '4. Soft Exudates'), '_SE'};

listing = dir(fullfile(imageFolder, '*.jpg'));
cases = struct([]);
for index = 1:numel(listing)
    [~, stem] = fileparts(listing(index).name);
    maskFiles = {};
    for folderIndex = 1:size(lesionFolders, 1)
        candidate = fullfile(lesionFolders{folderIndex, 1}, ...
            [stem, lesionFolders{folderIndex, 2}, '.tif']);
        if isfile(candidate)
            maskFiles{end + 1} = candidate; %#ok<AGROW>
        end
    end
    if isempty(maskFiles)
        continue;
    end
    entry = struct('imageId', string(stem), ...
        'imagePath', fullfile(imageFolder, listing(index).name), ...
        'maskFiles', {maskFiles});
    if isempty(cases)
        cases = entry;
    else
        cases(end + 1) = entry; %#ok<AGROW>
    end
end

if isfinite(limit)
    cases = cases(1:min(numel(cases), limit));
end
if isempty(cases)
    error('eval:NoIDRiDCases', 'No IDRiD images with lesion masks were found.');
end
end

% ------------------------------------------------------------ per-image work

function entry = localEvaluateCase(caseEntry, checkpoint, config, options)
image = imread(char(caseEntry.imagePath));
[modelImage, ~, preprocessingMetadata] = ...
    common.preprocess(image, config, 'inference');
modelSize = [size(modelImage, 1), size(modelImage, 2)];

lesionMask = localLoadLesionMask(caseEntry.maskFiles, ...
    [size(image, 1), size(image, 2)]);
alignedMask = localAlignMask(lesionMask, preprocessingMetadata, modelSize);

inference = grade.infer(checkpoint, modelImage, config, ...
    'ReturnLogits', true, 'Preprocessed', true);
predictedLevel = double(inference.predictedGrade(1));

gradCAMResult = explain.gradcam(checkpoint, image, predictedLevel, ...
    'WriteArtifacts', false);
gradCamMap = imresize(double(gradCAMResult.rawHeatmap), modelSize, 'bicubic');
gradCamMap = localNormalise(gradCamMap);

candidateMap = localCandidateSaliency(image, config, ...
    preprocessingMetadata, modelSize);
randomMap = rand(modelSize);

entry = struct();
entry.imageId = caseEntry.imageId;
entry.predictedLevel = predictedLevel;
entry.lesionPixelFraction = mean(alignedMask(:));
entry.maskCount = numel(caseEntry.maskFiles);
entry.gradCamHitRate = localPointingGame(gradCamMap, alignedMask, options.topFraction);
entry.candidateHitRate = localPointingGame(candidateMap, alignedMask, options.topFraction);
entry.randomHitRate = localPointingGame(randomMap, alignedMask, options.topFraction);

% Track B, scored in exactly the same pointing game as the other channels.
if isempty(options.lesionCheckpoint)
    entry.learnedHitRate = NaN;
else
    learnedMap = localLearnedSaliency(image, options.lesionCheckpoint, ...
        preprocessingMetadata, modelSize);
    entry.learnedHitRate = localPointingGame(learnedMap, alignedMask, ...
        options.topFraction);
end

[entry.deletionAUC, entry.deletionCurve] = localPerturbationCurve( ...
    checkpoint, modelImage, gradCamMap, predictedLevel, options.steps, 'deletion');
[entry.insertionAUC, entry.insertionCurve] = localPerturbationCurve( ...
    checkpoint, modelImage, gradCamMap, predictedLevel, options.steps, 'insertion');
end

function mask = localLoadLesionMask(maskFiles, imageSize)
mask = false(imageSize);
for index = 1:numel(maskFiles)
    raw = imread(maskFiles{index});
    if ndims(raw) == 3
        raw = any(raw > 0, 3);
    else
        raw = raw > 0;
    end
    if ~isequal(size(raw), imageSize)
        raw = imresize(raw, imageSize, 'nearest');
    end
    mask = mask | raw;
end
end

function aligned = localAlignMask(mask, preprocessingMetadata, modelSize)
%LOCALALIGNMASK Put the mask in the model's frame using the recorded crop.
boundingBox = preprocessingMetadata.fovBoundingBox;
if isfield(preprocessingMetadata, 'fovApplied') && ...
        preprocessingMetadata.fovApplied && all(isfinite(boundingBox))
    columnStart = max(1, round(boundingBox(1)));
    rowStart = max(1, round(boundingBox(2)));
    columnEnd = min(size(mask, 2), columnStart + round(boundingBox(3)) - 1);
    rowEnd = min(size(mask, 1), rowStart + round(boundingBox(4)) - 1);
    mask = mask(rowStart:rowEnd, columnStart:columnEnd);
end
aligned = imresize(mask, modelSize, 'nearest');
end

function map = localLearnedSaliency(image, lesionCheckpoint, ...
    preprocessingMetadata, modelSize)
%LOCALLEARNEDSALIENCY Dense saliency from the trained lesion network.
%   The learned channel already produces a dense map per lesion type, so
%   unlike the classical channel it needs no disc rendering.  The channels
%   are reduced by taking the strongest lesion response at each pixel: the
%   pointing game asks whether the explanation points at a lesion, not at
%   which kind, and the ground-truth mask it is scored against is likewise
%   the union over lesion types.
%
%   The map is put through the same crop-and-resize as the ground-truth
%   mask, so a hit means the two agree in the model's own frame rather than
%   in two frames that happen to be the same size.

map = zeros(modelSize);
try
    prediction = segment.segmentLesions(image, lesionCheckpoint);
catch exception
    warning('eval:LearnedSaliencyFailed', ...
        'Learned lesion saliency failed: %s', exception.message);
    return;
end

combined = max(prediction.probabilityMaps, [], 3);
map = localAlignMask(combined, preprocessingMetadata, modelSize);
map = localNormalise(double(map));
end

function map = localCandidateSaliency(image, config, preprocessingMetadata, modelSize)
%LOCALCANDIDATESALIENCY Turn classical candidates into a comparable map.
%   The lesion-evidence channel reports points, not a dense map, so each
%   candidate is rendered as a small disc and the result is smoothed. The
%   pointing game then applies to both channels identically.
map = zeros(modelSize);
try
    detection = segment.detect(image, config);
catch
    return;
end
if detection.candidateCount == 0
    return;
end

coordinates = detection.candidateCoordinates;
scale = [size(image, 2), size(image, 1)];
boundingBox = preprocessingMetadata.fovBoundingBox;
if isfield(preprocessingMetadata, 'fovApplied') && ...
        preprocessingMetadata.fovApplied && all(isfinite(boundingBox))
    coordinates(:, 1) = coordinates(:, 1) - round(boundingBox(1)) + 1;
    coordinates(:, 2) = coordinates(:, 2) - round(boundingBox(2)) + 1;
    scale = [round(boundingBox(3)), round(boundingBox(4))];
end

columns = round(coordinates(:, 1) * modelSize(2) / max(scale(1), 1));
rows = round(coordinates(:, 2) * modelSize(1) / max(scale(2), 1));
valid = columns >= 1 & columns <= modelSize(2) & rows >= 1 & rows <= modelSize(1);
if ~any(valid)
    return;
end
linear = sub2ind(modelSize, rows(valid), columns(valid));
map(linear) = 1;
map = imgaussfilt(map, 4);
map = localNormalise(map);
end

% -------------------------------------------------------------------- metrics

function hitRate = localPointingGame(saliency, lesionMask, topFraction)
if ~any(lesionMask(:))
    hitRate = NaN;
    return;
end
values = saliency(:);
count = max(1, round(topFraction * numel(values)));
[~, order] = sort(values, 'descend');
topIndices = order(1:count);
hitRate = mean(lesionMask(topIndices));
end

function [auc, curve] = localPerturbationCurve(checkpoint, modelImage, ...
        saliency, targetLevel, steps, mode)
%LOCALPERTURBATIONCURVE Deletion or insertion curve for one image.
%   Deletion replaces the most salient pixels with a heavily blurred copy
%   rather than with zeros: zeroing introduces a hard edge that the network
%   itself responds to, which would be measured as a probability drop that
%   the explanation did not earn.

targetIndex = targetLevel + 1;
baseline = imgaussfilt(modelImage, 16);

values = saliency(:);
[~, order] = sort(values, 'descend');
totalPixels = numel(values);
fractions = linspace(0, 1, steps + 1);

probabilities = zeros(steps + 1, 1);
for stepIndex = 1:numel(fractions)
    count = round(fractions(stepIndex) * totalPixels);
    perturbed = localPerturb(modelImage, baseline, order, count, mode);
    scores = minibatchpredict(checkpoint.net, perturbed, 'MiniBatchSize', 1, ...
        'ExecutionEnvironment', 'auto');
    probabilities(stepIndex) = double(scores(targetIndex));
end

curve = struct('fraction', fractions(:), 'probability', probabilities);
auc = trapz(fractions(:), probabilities) / (fractions(end) - fractions(1));
end

function perturbed = localPerturb(modelImage, baseline, order, count, mode)
perturbed = modelImage;
if count <= 0
    if strcmp(mode, 'insertion')
        perturbed = baseline;
    end
    return;
end
selected = order(1:min(count, numel(order)));
[rows, columns] = ind2sub([size(modelImage, 1), size(modelImage, 2)], selected);
channels = size(modelImage, 3);
if strcmp(mode, 'insertion')
    perturbed = baseline;
    source = modelImage;
else
    source = baseline;
end
for channel = 1:channels
    linear = sub2ind(size(modelImage), rows, columns, ...
        repmat(channel, numel(rows), 1));
    perturbed(linear) = source(linear);
end
end

% --------------------------------------------------------------- sanity check

function sanity = localSanityCheck(cases, checkpoint, config, options)
%LOCALSANITYCHECK Cascading randomisation of the trained weights.
%   Adebayo et al. (NeurIPS 2018) show that some popular saliency methods
%   are invariant to the model's parameters, meaning they behave largely as
%   edge detectors.  Grad-CAM is on the passing side and should show
%   correlation falling as randomisation reaches deeper layers.  Running it
%   on our own maps is what turns that citation into a measurement.

limit = min(options.sanityLimit, numel(cases));
fprintf('\nSanity check: cascading randomisation on %d image(s).\n', limit);

learnables = checkpoint.net.Learnables;
layerNames = unique(string(learnables.Layer), 'stable');
% Randomise from the output end backwards, in blocks, so the curve shows
% how deep the randomisation must go before the map stops tracking.
blockCount = 4;
edges = round(linspace(0, numel(layerNames), blockCount + 1));

sanity = struct('imageId', strings(0, 1), 'fractionRandomised', [], ...
    'spearman', [], 'layersRandomised', []);
records = struct([]);

for caseIndex = 1:limit
    image = imread(char(cases(caseIndex).imagePath));
    [modelImage, ~, preprocessingMetadata] = ...
        common.preprocess(image, config, 'inference'); %#ok<ASGLU>
    modelSize = [size(modelImage, 1), size(modelImage, 2)];

    reference = explain.gradcam(checkpoint, image, 0, 'WriteArtifacts', false);
    referenceMap = imresize(double(reference.rawHeatmap), modelSize, 'bicubic');

    for blockIndex = 1:blockCount
        randomisedLayers = layerNames(numel(layerNames) - edges(blockIndex + 1) + 1:end);
        perturbedCheckpoint = localRandomiseLayers(checkpoint, randomisedLayers);
        try
            perturbed = explain.gradcam(perturbedCheckpoint, image, 0, ...
                'WriteArtifacts', false);
        catch
            continue;
        end
        perturbedMap = imresize(double(perturbed.rawHeatmap), modelSize, 'bicubic');
        rho = localSpearman(referenceMap(:), perturbedMap(:));

        record = struct('imageId', cases(caseIndex).imageId, ...
            'fractionRandomised', edges(blockIndex + 1) / numel(layerNames), ...
            'layersRandomised', numel(randomisedLayers), 'spearman', rho);
        if isempty(records)
            records = record;
        else
            records(end + 1) = record; %#ok<AGROW>
        end
        fprintf('  %-12s %3.0f%% of layers randomised: Spearman %+.3f\n', ...
            cases(caseIndex).imageId, ...
            100 * record.fractionRandomised, rho);
    end
end

if ~isempty(records)
    sanity = records;
end
end

function perturbedCheckpoint = localRandomiseLayers(checkpoint, layerNames)
perturbedCheckpoint = checkpoint;
net = checkpoint.net;
learnables = net.Learnables;
for index = 1:height(learnables)
    if ~ismember(string(learnables.Layer(index)), layerNames)
        continue;
    end
    value = learnables.Value{index};
    data = extractdata(value);
    % Match the scale of what is being replaced so the network does not
    % simply saturate, which would make any map look uncorrelated for the
    % wrong reason.
    scale = std(double(data(:)));
    if ~isfinite(scale) || scale == 0
        scale = 1e-2;
    end
    replacement = cast(scale * randn(size(data), 'like', double(data)), 'like', data);
    learnables.Value{index} = dlarray(replacement);
end
net.Learnables = learnables;
perturbedCheckpoint.net = net;
end

function rho = localSpearman(a, b)
rho = corr(tiedrank(a), tiedrank(b));
end

% ------------------------------------------------------------------ reporting

function summary = localSummarise(perImage, sanity, options)
summary = struct();
summary.n = numel(perImage);
summary.topFraction = options.topFraction;
summary.steps = options.steps;
summary.subset = string(options.subset);

summary.gradCamHitRate = localStat([perImage.gradCamHitRate]);
summary.candidateHitRate = localStat([perImage.candidateHitRate]);
summary.learnedHitRate = localStat([perImage.learnedHitRate]);
summary.randomHitRate = localStat([perImage.randomHitRate]);
summary.deletionAUC = localStat([perImage.deletionAUC]);
summary.insertionAUC = localStat([perImage.insertionAUC]);
summary.lesionPixelFraction = localStat([perImage.lesionPixelFraction]);

% The lift over a random map is the number that matters. A hit rate of 0.10
% sounds poor until you see that lesions occupy 1% of the pixels.
summary.gradCamLiftOverRandom = summary.gradCamHitRate.mean / ...
    max(summary.randomHitRate.mean, eps);
summary.candidateLiftOverRandom = summary.candidateHitRate.mean / ...
    max(summary.randomHitRate.mean, eps);
summary.learnedLiftOverRandom = summary.learnedHitRate.mean / ...
    max(summary.randomHitRate.mean, eps);
summary.lesionCheckpoint = string(options.lesionCheckpoint);
summary.insertionMinusDeletion = summary.insertionAUC.mean - summary.deletionAUC.mean;

if isstruct(sanity) && ~isempty(sanity) && isfield(sanity, 'spearman')
    fractions = unique([sanity.fractionRandomised]);
    curve = struct('fractionRandomised', [], 'meanSpearman', []);
    for index = 1:numel(fractions)
        selected = [sanity.fractionRandomised] == fractions(index);
        curve(index).fractionRandomised = fractions(index); %#ok<AGROW>
        curve(index).meanSpearman = mean([sanity(selected).spearman], 'omitnan'); %#ok<AGROW>
    end
    summary.sanityCurve = curve;
else
    summary.sanityCurve = struct('fractionRandomised', {}, 'meanSpearman', {});
end
end

function stat = localStat(values)
values = double(values(:));
values = values(isfinite(values));
if isempty(values)
    stat = struct('mean', NaN, 'median', NaN, 'std', NaN, 'min', NaN, ...
        'max', NaN, 'n', 0);
    return;
end
stat = struct('mean', mean(values), 'median', median(values), ...
    'std', std(values), 'min', min(values), 'max', max(values), ...
    'n', numel(values));
end

function localPrintSummary(summary)
fprintf('\n===== §11.7 explanation quality =====\n');
fprintf('n = %d IDRiD %s images, top-%.0f%% salient pixels\n', ...
    summary.n, summary.subset, 100 * summary.topFraction);
fprintf('Lesion pixels occupy %.4f of the frame on average.\n\n', ...
    summary.lesionPixelFraction.mean);
fprintf('%-26s %-9s %-9s %-9s\n', 'Pointing game', 'mean', 'median', 'lift');
fprintf('%-26s %-9.4f %-9.4f %-9.2fx\n', '  Grad-CAM', ...
    summary.gradCamHitRate.mean, summary.gradCamHitRate.median, ...
    summary.gradCamLiftOverRandom);
fprintf('%-26s %-9.4f %-9.4f %-9.2fx\n', '  Lesion channel (classical)', ...
    summary.candidateHitRate.mean, summary.candidateHitRate.median, ...
    summary.candidateLiftOverRandom);
if summary.learnedHitRate.n > 0
    fprintf('%-26s %-9.4f %-9.4f %-9.2fx\n', '  Lesion channel (learned)', ...
        summary.learnedHitRate.mean, summary.learnedHitRate.median, ...
        summary.learnedLiftOverRandom);
else
    fprintf('%-26s %-9s %-9s %-9s\n', '  Lesion channel (learned)', ...
        'n/a', 'n/a', 'n/a');
end
fprintf('%-26s %-9.4f %-9.4f %-9s\n', '  Random control', ...
    summary.randomHitRate.mean, summary.randomHitRate.median, '1.00x');
fprintf('\nFaithfulness (Grad-CAM)\n');
fprintf('  Deletion AUC  %.4f  (lower is better)\n', summary.deletionAUC.mean);
fprintf('  Insertion AUC %.4f  (higher is better)\n', summary.insertionAUC.mean);
fprintf('  Insertion - deletion %+.4f\n', summary.insertionMinusDeletion);
if ~isempty(summary.sanityCurve)
    fprintf('\nSanity check (cascading randomisation)\n');
    for index = 1:numel(summary.sanityCurve)
        fprintf('  %3.0f%% of layers randomised: mean Spearman %+.3f\n', ...
            100 * summary.sanityCurve(index).fractionRandomised, ...
            summary.sanityCurve(index).meanSpearman);
    end
end
end

function localWriteOutputs(resultsDirectory, summary, perImage, sanity, options, config)
payload = struct();
payload.summary = summary;
payload.options = options;
payload.evaluatedOn = char(datetime('now', 'Format', 'yyyy-MM-dd'));
payload.sealedDataAccessed = false;
payload.dataset = 'IDRiD segmentation package';
localWriteText(fullfile(resultsDirectory, 'explanation_quality.json'), ...
    jsonencode(payload, 'PrettyPrint', true));
localWriteText(fullfile(resultsDirectory, 'config.json'), ...
    jsonencode(config, 'PrettyPrint', true));

lines = {'image_id,predicted_level,lesion_pixel_fraction,gradcam_hit_rate,candidate_hit_rate,random_hit_rate,deletion_auc,insertion_auc'};
for index = 1:numel(perImage)
    e = perImage(index);
    lines{end + 1} = sprintf('%s,%d,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f', ...
        e.imageId, e.predictedLevel, e.lesionPixelFraction, ...
        e.gradCamHitRate, e.candidateHitRate, e.randomHitRate, ...
        e.deletionAUC, e.insertionAUC); %#ok<AGROW>
end
localWriteText(fullfile(resultsDirectory, 'per_image.csv'), strjoin(lines, newline));
save(fullfile(resultsDirectory, 'explanation_quality.mat'), ...
    'summary', 'perImage', 'sanity', '-v7.3');
fprintf('\nResults written to %s\n', resultsDirectory);
end

% -------------------------------------------------------------------- helpers

function map = localNormalise(map)
map = double(map);
lowest = min(map(:));
highest = max(map(:));
if ~isfinite(lowest) || ~isfinite(highest) || highest <= lowest
    map = zeros(size(map));
    return;
end
map = (map - lowest) / (highest - lowest);
end

function directory = localDatedDirectory(resultsRoot, suffix)
if ~isfolder(resultsRoot)
    mkdir(resultsRoot);
end
stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
directory = fullfile(resultsRoot, [stamp '_' suffix]);
counter = 0;
while isfolder(directory)
    counter = counter + 1;
    directory = fullfile(resultsRoot, sprintf('%s_%s_%d', stamp, suffix, counter));
end
mkdir(directory);
end

function localWriteText(filename, text)
fileId = fopen(filename, 'w');
if fileId == -1
    error('eval:UnwritableFile', 'Could not write %s', filename);
end
cleanup = onCleanup(@() fclose(fileId));
fwrite(fileId, text, 'char');
end

function root = localProjectRoot()
root = fileparts(fileparts(mfilename('fullpath')));
end
