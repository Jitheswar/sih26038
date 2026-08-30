function evidence = lesionEvidence(image, model, varargin)
%LESIONEVIDENCE Measure lesion quantities from the trained segmentation net.
%   EVIDENCE = segment.lesionEvidence(IMAGE, MODEL) runs the lesion network
%   over IMAGE and reduces its probability maps to the countable quantities
%   the ICDR rules are written in: how many discrete lesions of each type,
%   and for haemorrhages, how many fall in each retinal quadrant.
%
%   This function measures.  It deliberately does not decide an ICDR level
%   or name a referral: grade.icdrEvidenceFromLesionSegmentation turns these
%   measurements into evidence fields and grade.icdrRule applies the rules,
%   so the rule engine stays the single place a severity level is decided.
%
%   Per-type thresholds come from the checkpoint's validation metrics, at
%   the point that maximised validation F1 for that lesion type.  They are
%   selected on the validation split and never on Set-B (§10.2).

parser = inputParser();
parser.addParameter('Thresholds', []);
parser.addParameter('MinimumArea', 'auto');
parser.addParameter('Frame', struct());
parser.addParameter('Environment', "auto");
parser.parse(varargin{:});

% Resolve the operating thresholds before running inference, not after.
% Tiled inference over a full frame is the expensive step here, and a
% configuration that cannot supply a threshold fails just as surely
% afterwards - only slower, and after occupying the GPU.
lesionTypes = localModelLesionTypes(model);
typeCount = numel(lesionTypes);
thresholds = localResolveThresholds(parser.Results.Thresholds, model, ...
    lesionTypes);
minimumArea = localResolveMinimumArea(parser.Results.MinimumArea, lesionTypes);

prediction = segment.segmentLesions(image, model, ...
    'Environment', parser.Results.Environment);
imageSize = prediction.imageSize;

counts = struct();
centroids = struct();
binaryMasks = false([imageSize, typeCount]);
areas = struct();

for typeIndex = 1:typeCount
    lesionType = lesionTypes{typeIndex};
    % Thresholding, the minimum-area filter and the component count live in
    % segment.countLesionType, because the threshold-transfer sweep needs
    % exactly this step over a grid of candidate thresholds and must not
    % reimplement it.  One code path, two callers.
    [componentCount, centroidList, areaList, mask] = ...
        segment.countLesionType( ...
            prediction.probabilityMaps(:, :, typeIndex), ...
            thresholds(typeIndex), minimumArea(typeIndex));

    binaryMasks(:, :, typeIndex) = mask;
    counts.(lesionType) = componentCount;
    centroids.(lesionType) = centroidList;
    areas.(lesionType) = areaList;
end

evidence = struct();
evidence.lesionTypes = lesionTypes;
evidence.counts = counts;
evidence.centroids = centroids;
evidence.areas = areas;
evidence.binaryMasks = binaryMasks;
evidence.probabilityMaps = prediction.probabilityMaps;
evidence.thresholds = thresholds;
evidence.minimumArea = minimumArea;
evidence.imageSize = imageSize;

% Quadrant counts are produced for haemorrhages because ICDR Level 3 is
% written as a per-quadrant haemorrhage criterion (the 4-2-1 rule, §3.3).
% The other types have no per-quadrant criterion, so counting them by
% quadrant would produce a number no rule reads.
if any(strcmp('HE', lesionTypes))
    [quadrantLabels, quadrantCounts, quadrantMetadata] = ...
        segment.assignQuadrants(centroids.HE, parser.Results.Frame, imageSize);
    evidence.haemorrhageQuadrantLabels = quadrantLabels;
    evidence.haemorrhageQuadrantCounts = quadrantCounts;
    evidence.quadrantCoordinateMethod = quadrantMetadata.coordinateFrameMethod;
    evidence.quadrantIsApproximate = quadrantMetadata.isApproximate;
end

evidence.metadata = struct( ...
    'evidenceType', 'learned lesion segmentation', ...
    'evidenceSource', 'IDRiD-trained multi-label lesion U-Net', ...
    'resizedBeforeInference', false, ...
    'thresholdSelection', 'validation-split best-F1 per lesion type', ...
    'clinicalValidationStatus', ...
    'not clinically validated lesion segmentation');
end

function lesionTypes = localModelLesionTypes(model)
%LOCALMODELLESIONTYPES Read the lesion types a model was trained for.
if isstruct(model) && isfield(model, 'config')
    config = model.config;
elseif (ischar(model) || (isstring(model) && isscalar(model))) && ...
        isfile(char(model))
    loaded = load(char(model), 'config');
    config = loaded.config;
else
    error('segment:InvalidModel', ...
        ['lesionEvidence requires a checkpoint path or a structure with ' ...
        'net and config fields.']);
end
lesionTypes = config.lesion_segmentation.lesion_types;
if ischar(lesionTypes)
    lesionTypes = {lesionTypes};
end
end

function thresholds = localResolveThresholds(requested, model, lesionTypes)
%LOCALRESOLVETHRESHOLDS Per-type operating thresholds, validation-selected.

typeCount = numel(lesionTypes);
if ~isempty(requested)
    thresholds = double(requested(:));
    if numel(thresholds) == 1
        thresholds = repmat(thresholds, typeCount, 1);
    end
    if numel(thresholds) ~= typeCount
        error('segment:InvalidThresholds', ...
            'Thresholds must be scalar or have one entry per lesion type.');
    end
    return;
end

validation = localCheckpointValidation(model);
if ~isempty(validation) && isfield(validation, 'bestF1Threshold') && ...
        numel(validation.bestF1Threshold) == typeCount
    thresholds = double(validation.bestF1Threshold(:));
    return;
end

error('segment:MissingThresholds', ...
    ['No per-type thresholds were supplied and the checkpoint carries no ' ...
    'validation bestF1Threshold. Refusing to fall back to 0.5: an ' ...
    'arbitrary threshold on a class occupying under one per cent of the ' ...
    'frame changes the lesion count by orders of magnitude, and the count ' ...
    'is what the ICDR rules read.']);
end

function validation = localCheckpointValidation(model)
validation = [];
if isstruct(model) && isfield(model, 'validation')
    validation = model.validation;
    return;
end
if ischar(model) || (isstring(model) && isscalar(model))
    if isfile(char(model))
        loaded = load(char(model));
        if isfield(loaded, 'validation')
            validation = loaded.validation;
        end
    end
end
end

function minimumArea = localResolveMinimumArea(requested, lesionTypes)
%LOCALRESOLVEMINIMUMAREA Smallest component size kept, per lesion type.
%   An explicit request wins; otherwise the per-type defaults come from
%   segment.defaultLesionMinimumArea, which carries the rationale and is
%   shared with the threshold-transfer sweep.

typeCount = numel(lesionTypes);
if isnumeric(requested)
    minimumArea = double(requested(:));
    if numel(minimumArea) == 1
        minimumArea = repmat(minimumArea, typeCount, 1);
    end
    if numel(minimumArea) ~= typeCount
        error('segment:InvalidMinimumArea', ...
            'MinimumArea must be scalar or have one entry per lesion type.');
    end
    return;
end

minimumArea = segment.defaultLesionMinimumArea(lesionTypes);
end
