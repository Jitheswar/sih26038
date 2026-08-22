function result = detectMicroaneurysmCandidates(inputImage, varargin)
%DETECTMICROANEURYSMCANDIDATES Detect classical dark-dot candidates.
%   RESULT = segment.detectMicroaneurysmCandidates(IMAGE, CONFIG, VESSELS)
%   works on the green channel after applying the shared FOV mask.  It uses
%   multi-scale disk top-hat responses and the minimum response from
%   multiple oriented linear top-hats to favour compact responses over
%   elongated vessel-like responses.
%
%   The output is evidence for microaneurysm candidates only.  It is not a
%   clinically validated lesion segmentation and does not make a clinical
%   lesion diagnosis.

rng(42, 'twister');

[configuration, vesselMask, suppliedFovMask] = localArguments(varargin{:});
[image, imageSize] = localUnitImage(inputImage);
configuration = localConfiguration(configuration);

if isempty(suppliedFovMask)
    [fovMask, fovInfo] = quality.fovMask(image, configuration.quality);
    fovMaskSource = 'quality.fovMask';
else
    fovMask = localValidateMask(suppliedFovMask, imageSize, 'FOV mask');
    fovInfo = struct('detected', any(fovMask(:)), 'area', nnz(fovMask), ...
        'areaRatio', nnz(fovMask) / numel(fovMask), 'source', 'supplied');
    fovMaskSource = 'supplied';
end

if isempty(vesselMask)
    vesselMask = [];
    vesselStatus = 'unavailable - no vessel mask supplied';
else
    vesselMask = localValidateMask(vesselMask, imageSize, 'vessel mask');
    vesselStatus = 'available and applied';
end

green = image(:, :, min(2, size(image, 3)));
invertedGreen = 1 - green;
invertedGreen(~fovMask) = 0;

% Morphological filters create artificial bright responses at a sharp FOV
% boundary.  Keep the full shared mask in the output, but use an eroded
% working mask so those boundary responses cannot become candidates.
filterFootprint = max([configuration.topHatRadii, ...
    ceil(configuration.linearLengths / 2)]);
candidateFovMask = imerode(fovMask, strel('disk', filterFootprint, 0));

% A compact bright object remains in the top-hat response for every
% orientation.  An elongated object is likely to be reconstructed by at
% least one matching linear opening and therefore has a low minimum.
diskResponse = zeros(imageSize, 'double');
for radius = configuration.topHatRadii
    element = strel('disk', radius, 0);
    diskResponse = max(diskResponse, imtophat(invertedGreen, element));
end

linearResponse = inf(imageSize);
for lengthValue = configuration.linearLengths
    for angle = configuration.linearAngles
        element = strel('line', lengthValue, angle);
        linearResponse = min(linearResponse, ...
            imtophat(invertedGreen, element));
    end
end
if isempty(configuration.linearLengths) || isempty(configuration.linearAngles)
    linearResponse = diskResponse;
end

response = min(diskResponse, linearResponse);
response(~candidateFovMask) = 0;
response(~isfinite(response)) = 0;

rawCandidateMask = candidateFovMask & response >= configuration.responseThreshold;
rawCandidateMask = bwareaopen(rawCandidateMask, configuration.minimumArea, 8);
rawCandidateMask = localLimitArea(rawCandidateMask, configuration.maximumArea);

if isempty(vesselMask)
    candidateMask = rawCandidateMask;
else
    candidateMask = localSuppressVessels(rawCandidateMask, vesselMask, ...
        configuration.vesselOverlapFraction);
end

[candidateArray, featureVectors] = localFeatures( ...
    candidateMask, response, invertedGreen, fovMask, vesselMask, configuration);

result = struct();
result.candidates = candidateArray;
result.candidateCount = numel(candidateArray);
result.candidateCoordinates = featureVectors.coordinates;
result.candidateAreas = featureVectors.areas;
result.candidateEccentricities = featureVectors.eccentricities;
result.candidateEquivalentDiameters = featureVectors.equivalentDiameters;
result.candidateLocalContrasts = featureVectors.localContrasts;
result.candidateResponseStrengths = featureVectors.responseStrengths;
result.candidateDistancesToNearestVessel = featureVectors.vesselDistances;
result.candidateScores = featureVectors.scores;
result.candidateClassLabels = featureVectors.classLabels;
result.candidateLabels = featureVectors.classLabels;
result.candidateMask = candidateMask;
result.rawCandidateMask = rawCandidateMask;
result.fovMask = fovMask;
result.candidateFovMask = candidateFovMask;
result.fovInfo = fovInfo;
result.greenChannel = green;
result.invertedGreenChannel = invertedGreen;
result.intermediateResponseMap = single(response);
result.responseMap = single(response);
result.vesselMask = vesselMask;
result.vesselSuppression = struct( ...
    'available', ~isempty(vesselMask), ...
    'applied', ~isempty(vesselMask), ...
    'status', vesselStatus, ...
    'overlapFractionThreshold', configuration.vesselOverlapFraction);
result.fovMaskSource = fovMaskSource;
result.configuration = configuration.public;
result.diagnostic = struct( ...
    'fovMaskSource', fovMaskSource, ...
    'fovDetected', any(fovMask(:)), ...
    'fovArea', nnz(fovMask), ...
    'rawCandidateCount', bwconncomp(rawCandidateMask, 8).NumObjects, ...
    'candidateCount', result.candidateCount, ...
    'vesselSuppressionStatus', vesselStatus, ...
    'responseThreshold', configuration.responseThreshold, ...
    'minimumArea', configuration.minimumArea, ...
    'maximumArea', configuration.maximumArea, ...
    'topHatRadii', configuration.topHatRadii, ...
    'linearLengths', configuration.linearLengths, ...
    'linearAngles', configuration.linearAngles, ...
    'candidateTerminology', 'microaneurysm candidate', ...
    'clinicalValidationStatus', 'not clinically validated');
end

function [configuration, vesselMask, fovMask] = localArguments(varargin)
configuration = struct();
vesselMask = [];
fovMask = [];
for index = 1:numel(varargin)
    argument = varargin{index};
    if isempty(argument)
        continue;
    elseif ischar(argument) || (isstring(argument) && isscalar(argument))
        configuration = char(argument);
    elseif islogical(argument) || (isnumeric(argument) && ismatrix(argument))
        if isempty(vesselMask)
            vesselMask = argument;
        else
            fovMask = argument;
        end
    elseif isstruct(argument) && isscalar(argument)
        if isfield(argument, 'fovMask') && ~isempty(argument.fovMask)
            fovMask = argument.fovMask;
        end
        if isfield(argument, 'vesselMask') && ~isempty(argument.vesselMask)
            vesselMask = argument.vesselMask;
        end
        if isempty(fieldnames(configuration))
            configuration = argument;
        else
            configuration = localMerge(configuration, argument);
        end
    else
        error('segment:InvalidArguments', ...
            'Configuration must be a scalar structure or JSON filename.');
    end
end
end

function merged = localMerge(first, second)
merged = first;
names = fieldnames(second);
for index = 1:numel(names)
    merged.(names{index}) = second.(names{index});
end
end

function [image, imageSize] = localUnitImage(inputImage)
if isempty(inputImage)
    error('segment:InvalidImage', ...
        'The input retinal image must be non-empty.');
end
if ~(isnumeric(inputImage) || islogical(inputImage)) || ~isreal(inputImage)
    error('segment:InvalidImage', ...
        'The input retinal image must be a real numeric or logical image.');
end
if ndims(inputImage) > 3 || (ndims(inputImage) == 3 && ...
        ~ismember(size(inputImage, 3), [1, 3]))
    error('segment:InvalidImage', ...
        'The input retinal image must be 2-D grayscale or 3-D RGB.');
end
if islogical(inputImage)
    image = double(inputImage);
elseif isinteger(inputImage)
    image = im2double(inputImage);
else
    if any(~isfinite(inputImage(:))) || any(inputImage(:) < 0) || ...
            any(inputImage(:) > 1)
        error('segment:InvalidImage', ...
            'Floating-point retinal image values must be finite and lie in [0, 1].');
    end
    image = double(inputImage);
end
if ndims(image) == 2
    image = reshape(image, size(image, 1), size(image, 2), 1);
end
imageSize = [size(image, 1), size(image, 2)];
end

function mask = localValidateMask(mask, imageSize, description)
if ~(islogical(mask) || isnumeric(mask)) || ~isreal(mask) || ...
        ~isequal(size(mask), imageSize)
    error('segment:InvalidMask', '%s must match the image rows and columns.', description);
end
if any(~isfinite(double(mask(:))))
    error('segment:InvalidMask', '%s must contain finite values.', description);
end
mask = logical(mask);
end

function configuration = localConfiguration(inputConfiguration)
defaults = struct( ...
    'responseThreshold', 0.045, ...
    'minimumArea', 1, ...
    'maximumArea', 250, ...
    'topHatRadii', [2, 3, 5], ...
    'linearLengths', [7, 11, 15], ...
    'linearAngles', 0:30:150, ...
    'vesselOverlapFraction', 0, ...
    'localContrastRadius', 3);

raw = inputConfiguration;
if nargin == 0 || isempty(raw)
    raw = struct();
elseif ischar(raw) || (isstring(raw) && isscalar(raw))
    if ~isfile(char(raw))
        error('segment:InvalidConfig', ...
            'Configuration file does not exist: %s', char(raw));
    end
    try
        raw = jsondecode(fileread(char(raw)));
    catch exception
        error('segment:InvalidConfig', ...
            'Configuration file could not be decoded: %s', exception.message);
    end
end
if ~isstruct(raw) || ~isscalar(raw)
    error('segment:InvalidConfig', ...
        'Configuration must be a scalar structure or JSON filename.');
end

for name = {'lesionEvidence', 'lesion_evidence', 'segmentation', 'microaneurysm'}
    if isfield(raw, name{1}) && isstruct(raw.(name{1}))
        raw = localMerge(raw, raw.(name{1}));
    end
end

configuration = defaults;
configuration.quality = struct();
configuration.responseThreshold = localValue(raw, ...
    {'responseThreshold', 'response_threshold', 'threshold', 'candidateThreshold'}, ...
    defaults.responseThreshold);
configuration.minimumArea = localValue(raw, ...
    {'minimumArea', 'minimum_area', 'minArea'}, defaults.minimumArea);
configuration.maximumArea = localValue(raw, ...
    {'maximumArea', 'maximum_area', 'maxArea'}, defaults.maximumArea);
configuration.topHatRadii = localVector(raw, ...
    {'topHatRadii', 'top_hat_radii', 'scales'}, defaults.topHatRadii);
configuration.linearLengths = localVector(raw, ...
    {'linearLengths', 'linear_lengths', 'lineLengths'}, defaults.linearLengths);
configuration.linearAngles = localVector(raw, ...
    {'linearAngles', 'linear_angles', 'lineAngles'}, defaults.linearAngles);
configuration.vesselOverlapFraction = localValue(raw, ...
    {'vesselOverlapFraction', 'vessel_overlap_fraction'}, ...
    defaults.vesselOverlapFraction);
configuration.localContrastRadius = localValue(raw, ...
    {'localContrastRadius', 'local_contrast_radius'}, ...
    defaults.localContrastRadius);

if configuration.responseThreshold < 0 || configuration.minimumArea < 1 || ...
        configuration.maximumArea < configuration.minimumArea || ...
        configuration.vesselOverlapFraction < 0 || ...
        configuration.vesselOverlapFraction > 1 || ...
        configuration.localContrastRadius < 1 || ...
        any(configuration.topHatRadii < 1) || ...
        any(configuration.linearLengths < 2) || ...
        any(~isfinite([configuration.responseThreshold, ...
        configuration.minimumArea, configuration.maximumArea, ...
        configuration.vesselOverlapFraction, configuration.localContrastRadius]))
    error('segment:InvalidConfig', ...
        'Candidate thresholds, areas, radii, and suppression values are invalid.');
end
configuration.minimumArea = floor(configuration.minimumArea);
configuration.maximumArea = floor(configuration.maximumArea);
configuration.topHatRadii = unique(floor(configuration.topHatRadii));
configuration.linearLengths = unique(floor(configuration.linearLengths));
configuration.linearAngles = unique(configuration.linearAngles);
configuration.localContrastRadius = floor(configuration.localContrastRadius);
configuration.public = configuration;
end

function value = localValue(raw, names, defaultValue)
value = defaultValue;
for index = 1:numel(names)
    if isfield(raw, names{index})
        value = raw.(names{index});
        break;
    end
end
if ~isnumeric(value) || ~isscalar(value) || ~isreal(value) || ~isfinite(value)
    error('segment:InvalidConfig', 'Configuration value must be a finite scalar.');
end
value = double(value);
end

function value = localVector(raw, names, defaultValue)
value = defaultValue;
for index = 1:numel(names)
    if isfield(raw, names{index})
        value = raw.(names{index});
        break;
    end
end
if ~isnumeric(value) || isempty(value) || ~isreal(value) || ...
        any(~isfinite(value(:)))
    error('segment:InvalidConfig', 'Configuration vector must be finite and non-empty.');
end
value = double(value(:)).';
end

function mask = localLimitArea(mask, maximumArea)
components = bwconncomp(mask, 8);
mask = false(size(mask));
for index = 1:components.NumObjects
    if numel(components.PixelIdxList{index}) <= maximumArea
        mask(components.PixelIdxList{index}) = true;
    end
end
end

function mask = localSuppressVessels(mask, vessels, maximumOverlap)
components = bwconncomp(mask, 8);
for index = 1:components.NumObjects
    pixels = components.PixelIdxList{index};
    overlap = mean(vessels(pixels));
    if overlap > maximumOverlap
        mask(pixels) = false;
    end
end
end

function [candidates, vectors] = localFeatures(mask, response, invertedGreen, fovMask, vessels, configuration)
components = bwconncomp(mask, 8);
count = components.NumObjects;
vectors.coordinates = zeros(count, 2);
vectors.areas = zeros(count, 1);
vectors.eccentricities = zeros(count, 1);
vectors.equivalentDiameters = zeros(count, 1);
vectors.localContrasts = zeros(count, 1);
vectors.responseStrengths = zeros(count, 1);
vectors.vesselDistances = NaN(count, 1);
vectors.scores = zeros(count, 1);
vectors.classLabels = repmat({'microaneurysm candidate'}, count, 1);

if ~isempty(vessels)
    distanceMap = bwdist(vessels);
else
    distanceMap = [];
end

template = struct('coordinate', [0, 0], 'centroid', [0, 0], ...
    'area', 0, 'eccentricity', 0, 'equivalentDiameter', 0, ...
    'localContrast', 0, 'responseStrength', 0, ...
    'distanceToNearestVessel', NaN, 'score', 0, ...
    'classLabel', 'microaneurysm candidate', ...
    'class', 'microaneurysm candidate');
candidates = repmat(template, count, 1);

for index = 1:count
    pixels = components.PixelIdxList{index};
    componentMask = false(size(mask));
    componentMask(pixels) = true;
    properties = regionprops(componentMask, 'Area', 'Centroid', ...
        'Eccentricity', 'EquivDiameter');
    centroid = properties.Centroid;
    ring = imdilate(componentMask, strel('disk', ...
        configuration.localContrastRadius, 0)) & ~componentMask & fovMask;
    if any(ring(:))
        contrast = max(0, mean(invertedGreen(componentMask)) - ...
            mean(invertedGreen(ring)));
    else
        contrast = 0;
    end
    responseStrength = max(0, max(response(pixels)));
    if isempty(distanceMap)
        vesselDistance = NaN;
    else
        vesselDistance = max(0, distanceMap(round(centroid(2)), round(centroid(1))));
    end
    circularityFactor = max(0, 1 - properties.Eccentricity);
    score = max(0, responseStrength * circularityFactor * ...
        (0.5 + 0.5 * min(1, contrast / max(configuration.responseThreshold, eps))));

    vectors.coordinates(index, :) = centroid;
    vectors.areas(index) = properties.Area;
    vectors.eccentricities(index) = properties.Eccentricity;
    vectors.equivalentDiameters(index) = properties.EquivDiameter;
    vectors.localContrasts(index) = contrast;
    vectors.responseStrengths(index) = responseStrength;
    vectors.vesselDistances(index) = vesselDistance;
    vectors.scores(index) = score;

    candidates(index).coordinate = centroid;
    candidates(index).centroid = centroid;
    candidates(index).area = properties.Area;
    candidates(index).eccentricity = properties.Eccentricity;
    candidates(index).equivalentDiameter = properties.EquivDiameter;
    candidates(index).localContrast = contrast;
    candidates(index).responseStrength = responseStrength;
    candidates(index).distanceToNearestVessel = vesselDistance;
    candidates(index).score = score;
end
end
