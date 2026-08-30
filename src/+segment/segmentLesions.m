function result = segmentLesions(image, model, varargin)
%SEGMENTLESIONS Run the trained lesion network over a full fundus frame.
%   RESULT = segment.segmentLesions(IMAGE, MODEL) returns per-lesion-type
%   probability maps at the resolution of IMAGE.
%
%   MODEL is either the path to a checkpoint written by
%   segment.trainLesionSegmentation, or a structure holding NET and CONFIG.
%
%   The frame is covered with overlapping native-resolution tiles and never
%   resized.  Resizing the frame to a single network input is the one thing
%   §6.4 rules out: a microaneurysm is a handful of pixels across at
%   2848x4288 and does not survive being scaled down.
%
%   Overlapping tiles are averaged rather than butt-joined because a lesion
%   straddling a tile seam is seen only partially by each tile, and a hard
%   join leaves a visible discontinuity straight through it.

% rng at the top of the entry point (§13.2), then the caller's stream is put
% back on exit.  Tiled inference draws no random numbers, so the seed is a
% convention here rather than a control; the restore matters because
% segment.trainLesionSegmentation calls this function once per validation
% frame, and resetting the global stream inside the epoch loop would hand
% every epoch the identical training image order.
entryStreamState = rng(42, 'twister');
restoreStream = onCleanup(@() rng(entryStreamState));

parser = inputParser();
parser.addParameter('Environment', "auto");
parser.parse(varargin{:});
environment = string(parser.Results.Environment);

[net, config] = localResolveModel(model);
lesion = config.lesion_segmentation;
lesionTypes = lesion.lesion_types;
patchSize = lesion.patch_size;
stride = patchSize - lesion.tile_overlap;

if isempty(image) || ~(isnumeric(image) || islogical(image))
    error('segment:InvalidImage', ...
        'segmentLesions requires a non-empty numeric image.');
end
if size(image, 3) ~= 3
    error('segment:InvalidImage', ...
        'segmentLesions requires a three-channel RGB frame.');
end

if environment == "auto"
    if canUseGPU
        environment = "gpu";
    else
        environment = "cpu";
    end
end
if environment == "gpu"
    net = dlupdate(@gpuArray, net);
end

originalRows = size(image, 1);
originalColumns = size(image, 2);

% Bring the frame to the pixel scale the network trained at, before tiling.
[scaledImage, appliedScale, measuredDiameter] = localNormaliseScale(image, ...
    lesion);

[padded, padRows, padColumns] = localPad(scaledImage, patchSize);
rows = size(padded, 1);
columns = size(padded, 2);

topOrigins = localOrigins(rows, patchSize, stride);
leftOrigins = localOrigins(columns, patchSize, stride);
typeCount = numel(lesionTypes);

accumulator = zeros(rows, columns, typeCount, 'single');
weights = zeros(rows, columns, 'single');

batchSize = lesion.batch_size;
[topGrid, leftGrid] = ndgrid(topOrigins, leftOrigins);
tileOrigins = [topGrid(:), leftGrid(:)];
tileCount = size(tileOrigins, 1);

for firstTile = 1:batchSize:tileCount
    lastTile = min(tileCount, firstTile + batchSize - 1);
    thisBatch = firstTile:lastTile;
    batch = zeros(patchSize, patchSize, 3, numel(thisBatch), 'single');
    for slot = 1:numel(thisBatch)
        top = tileOrigins(thisBatch(slot), 1);
        left = tileOrigins(thisBatch(slot), 2);
        tile = padded(top + (0:patchSize - 1), left + (0:patchSize - 1), :);
        batch(:, :, :, slot) = normaliseLesionPatch(tile);
    end

    input = dlarray(batch, 'SSCB');
    if environment == "gpu"
        input = gpuArray(input);
    end
    logits = predict(net, input);
    probabilities = gather(extractdata(sigmoid(logits)));

    for slot = 1:numel(thisBatch)
        top = tileOrigins(thisBatch(slot), 1);
        left = tileOrigins(thisBatch(slot), 2);
        rowRange = top + (0:patchSize - 1);
        columnRange = left + (0:patchSize - 1);
        accumulator(rowRange, columnRange, :) = ...
            accumulator(rowRange, columnRange, :) + probabilities(:, :, :, slot);
        weights(rowRange, columnRange) = ...
            weights(rowRange, columnRange) + 1;
    end
end

probabilityMaps = accumulator ./ max(weights, 1);
probabilityMaps = probabilityMaps(1:size(scaledImage, 1), ...
    1:size(scaledImage, 2), :);

% Back to the caller's pixel grid, so every coordinate this function returns
% is in the frame the caller passed in.
if appliedScale ~= 1
    probabilityMaps = imresize(probabilityMaps, ...
        [originalRows, originalColumns], 'bilinear');
end

result = struct();
result.probabilityMaps = probabilityMaps;
result.lesionTypes = lesionTypes;
result.imageSize = [originalRows, originalColumns];
result.tileCount = tileCount;
result.padding = [padRows, padColumns];
result.environment = environment;
result.appliedScale = appliedScale;
result.measuredFovDiameter = measuredDiameter;
result.metadata = struct( ...
    'evidenceType', 'learned lesion segmentation', ...
    'scaleNormalisationApplied', appliedScale ~= 1, ...
    'appliedScale', appliedScale, ...
    'referenceFovDiameter', lesion.reference_fov_diameter, ...
    'measuredFovDiameter', measuredDiameter, ...
    'clinicalValidationStatus', ...
    'not clinically validated lesion segmentation');
end

function [scaledImage, appliedScale, measuredDiameter] = ...
    localNormaliseScale(image, lesion)
%LOCALNORMALISESCALE Resample a frame to the training field-of-view scale.
%   The illuminated field is measured with quality.fovMask - the same field
%   definition the rest of the pipeline uses - on a downsampled copy, and
%   summarised as the diameter of a circle of equal area.  Area rather than
%   a bounding box because a frame cropped flat at the top and bottom, which
%   both APTOS and IDRiD contain, has a bounding box far taller than its
%   actual field.

appliedScale = 1;
measuredDiameter = NaN;
scaledImage = image;
if ~lesion.scale_normalisation
    return;
end

downsample = lesion.fov_downsample;
small = imresize(image, 1 / downsample);
fieldMask = quality.fovMask(small);
fieldArea = nnz(fieldMask);
if fieldArea == 0
    % No measurable field. Leaving the frame alone is the honest response:
    % a guessed scale would silently change every lesion count downstream.
    return;
end

measuredDiameter = 2 * sqrt(fieldArea / pi) * downsample;
requestedScale = lesion.reference_fov_diameter / measuredDiameter;
appliedScale = min(max(requestedScale, lesion.scale_limits(1)), ...
    lesion.scale_limits(2));

if abs(appliedScale - 1) < 0.02
    appliedScale = 1;
    return;
end
scaledImage = imresize(image, appliedScale);
end

function [net, config] = localResolveModel(model)
if ischar(model) || (isstring(model) && isscalar(model))
    checkpointPath = char(model);
    if ~isfile(checkpointPath)
        error('segment:MissingCheckpoint', ...
            'Lesion segmentation checkpoint does not exist: %s', checkpointPath);
    end
    loaded = load(checkpointPath);
    if ~isfield(loaded, 'net') || ~isfield(loaded, 'config')
        error('segment:InvalidCheckpoint', ...
            'Checkpoint %s must contain net and config.', checkpointPath);
    end
    net = loaded.net;
    config = loaded.config;
elseif isstruct(model) && isscalar(model) && isfield(model, 'net') && ...
        isfield(model, 'config')
    net = model.net;
    config = model.config;
else
    error('segment:InvalidModel', ...
        ['segmentLesions requires a checkpoint path or a structure with ' ...
        'net and config fields.']);
end

if ~isfield(config, 'lesion_segmentation')
    error('segment:InvalidCheckpoint', ...
        'Checkpoint configuration has no lesion_segmentation block.');
end

% Re-run the configuration defaults over whatever the checkpoint carries.
% A checkpoint written before a setting existed has no field for it, and
% reading that field directly would fail on exactly the older checkpoints
% this function most needs to stay able to load.  lesionConfiguration is
% the single place those defaults are defined, so filling them here cannot
% drift from how training filled them.  It also normalises lesion_types,
% which jsondecode collapses to a char row when the list has one entry.
config = lesionConfiguration(config);
end

function origins = localOrigins(extent, patchSize, stride)
%LOCALORIGINS Tile origins covering EXTENT, with the last tile flush to the end.
%   Without the flush the final stride can leave a strip narrower than one
%   tile uncovered, which would read as zero probability rather than as
%   unexamined.

origins = 1:stride:(extent - patchSize + 1);
if isempty(origins)
    origins = 1;
end
if origins(end) ~= extent - patchSize + 1
    origins(end + 1) = extent - patchSize + 1;
end
origins = unique(origins(:));
end

function [padded, padRows, padColumns] = localPad(image, patchSize)
%LOCALPAD Grow a frame smaller than one tile by reflection.
%   Reflection rather than zeros: a black border invents an edge the network
%   never saw in training, and edges are what the exudate head keys on.

rows = size(image, 1);
columns = size(image, 2);
padRows = max(0, patchSize - rows);
padColumns = max(0, patchSize - columns);
if padRows == 0 && padColumns == 0
    padded = image;
    return;
end
padded = padarray(image, [padRows, padColumns], 'symmetric', 'post');
end
