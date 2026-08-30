function result = segmentVessels(image, model, varargin)
%SEGMENTVESSELS Run the trained vessel network over a whole fundus frame.
%   RESULT = segment.segmentVessels(IMAGE, MODEL) returns a struct with
%   the vessel probability map on IMAGE's own pixel grid.
%
%   MODEL is either a checkpoint path or a loaded struct carrying `net` and
%   `config`.
%
%   Name-value options:
%     'Environment'  "auto" (default), "gpu" or "cpu".
%     'FieldOfView'  Logical mask; computed with quality.fovMask if absent.
%
%   The frame is tiled rather than resized.  A DRIVE frame is 584x565 and
%   would fit whole on most GPUs, but the network is trained on 128x128
%   crops and its batch-normalisation statistics are those of a crop.
%   Feeding a whole frame changes the input statistics without changing the
%   weights, which shifts the output for reasons that have nothing to do
%   with the retina.  Tiles overlap by vessel.tile_overlap and the overlap
%   is averaged, because a vessel crossing a tile seam is otherwise cut by
%   whichever tile saw less of it.
%
%   Unlike the lesion path there is no scale normalisation here.  That
%   exists because IDRiD and APTOS differ in field-of-view diameter by up to
%   3x and a lesion is an absolute size (§6.4).  This network is trained and
%   evaluated on DRIVE alone, so there is no cross-camera factor to correct
%   and inventing one would be untested code on the inference path.  Running
%   it on a non-DRIVE camera would need that work first.

options = localOptions(varargin{:});

model = localLoadModel(model);
net = model.net;
vessel = model.config.vessel_segmentation;

originalSize = [size(image, 1), size(image, 2)];
prepared = segment.vesselPreprocess(image, vessel);

if isempty(options.fieldOfView)
    fieldOfView = quality.fovMask(image);
else
    fieldOfView = logical(options.fieldOfView);
    if ~isequal(size(fieldOfView), originalSize)
        error('segment:VesselFieldOfViewMismatch', ...
            'FieldOfView must match the image on its first two dimensions.');
    end
end

environment = options.environment;
if environment == "auto"
    environment = "cpu";
    if canUseGPU
        environment = "gpu";
    end
end
if environment == "gpu"
    net = dlupdate(@gpuArray, net);
end

probabilityMap = localTiledPredict(net, prepared, vessel, environment);

% Outside the camera aperture there is no retina, so there is no vessel.
% Leaving the network's answer there would put probability mass on the black
% corners, where it would count towards a specificity that §6.3 reports
% inside the field of view only.
probabilityMap(~fieldOfView) = 0;

result = struct();
result.probabilityMap = probabilityMap;
result.vesselMask = probabilityMap >= vessel.operating_threshold;
result.operatingThreshold = vessel.operating_threshold;
result.fieldOfView = fieldOfView;
result.imageSize = originalSize;
result.environment = environment;
end

function map = localTiledPredict(net, prepared, vessel, environment)
%LOCALTILEDPREDICT Average the network over overlapping tiles.

patchSize = vessel.patch_size;
stride = patchSize - vessel.tile_overlap;
[height, width] = size(prepared);

% Pad so the last tile in each direction is whole.  Symmetric padding
% mirrors the retina outward rather than inventing a black border, which the
% network would read as the field-of-view edge and answer accordingly.
padRows = max(0, ceil(max(0, height - patchSize) / stride) * stride + ...
    patchSize - height);
padColumns = max(0, ceil(max(0, width - patchSize) / stride) * stride + ...
    patchSize - width);
padded = padarray(prepared, [padRows, padColumns], 'symmetric', 'post');
[paddedHeight, paddedWidth] = size(padded);

accumulator = zeros(paddedHeight, paddedWidth, 'single');
counts = zeros(paddedHeight, paddedWidth, 'single');

rowStarts = 1:stride:(paddedHeight - patchSize + 1);
columnStarts = 1:stride:(paddedWidth - patchSize + 1);

for rowStart = rowStarts
    for columnStart = columnStarts
        rows = rowStart:rowStart + patchSize - 1;
        columns = columnStart:columnStart + patchSize - 1;

        tile = padded(rows, columns);
        input = dlarray(reshape(tile, patchSize, patchSize, 1, 1), 'SSCB');
        if environment == "gpu"
            input = gpuArray(input);
        end

        logits = predict(net, input);
        probabilities = extractdata(gather(sigmoid(logits)));

        accumulator(rows, columns) = accumulator(rows, columns) + ...
            single(probabilities(:, :, 1, 1));
        counts(rows, columns) = counts(rows, columns) + 1;
    end
end

if any(counts(:) == 0)
    error('segment:VesselTilingGap', ...
        'Tiling left pixels unwritten; check patch_size against tile_overlap.');
end

map = accumulator ./ counts;
map = map(1:height, 1:width);
end

function model = localLoadModel(model)
if ischar(model) || (isstring(model) && isscalar(model))
    checkpointPath = char(model);
    if ~isfile(checkpointPath)
        error('segment:MissingVesselCheckpoint', ...
            'Vessel checkpoint does not exist: %s', checkpointPath);
    end
    model = load(checkpointPath, 'net', 'config');
end
if ~isstruct(model) || ~isfield(model, 'net') || ~isfield(model, 'config')
    error('segment:InvalidVesselModel', ...
        'A vessel model must carry both net and config.');
end
if ~isfield(model.config, 'vessel_segmentation')
    error('segment:InvalidVesselModel', ...
        'The vessel checkpoint config has no vessel_segmentation block.');
end
end

function options = localOptions(varargin)
parser = inputParser();
parser.addParameter('Environment', "auto");
parser.addParameter('FieldOfView', []);
parser.parse(varargin{:});

options = struct();
options.environment = string(parser.Results.Environment);
if ~any(options.environment == ["auto", "gpu", "cpu"])
    error('segment:InvalidEnvironment', ...
        'Environment must be auto, gpu or cpu.');
end
options.fieldOfView = parser.Results.FieldOfView;
end
