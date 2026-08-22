function evidence = buildLesionEvidence(inputImage, detection, varargin)
%BUILDLESIONEVIDENCE Render and describe classical candidate evidence.
%   EVIDENCE = explain.buildLesionEvidence(IMAGE, DETECTION, CNNPREDICTION)
%   creates a candidate overlay, quadrant counts, report-ready evidence
%   text, and structured inputs for a future channel agreement check.
%
%   This milestone intentionally does not implement an ICDR rule engine or
%   a learned segmentation network.  All objects remain candidates.

rng(42, 'twister');

[detection, cnnPrediction] = localArguments(inputImage, detection, varargin{:});
[baseImage, imageSize] = localDisplayImage(inputImage);
[coordinates, scores, quadrants, counts, vesselStatus, frameMethod] = ...
    localDetectionFields(detection, imageSize);

overlay = localOverlay(baseImage, coordinates, scores);

evidence = struct();
evidence.candidateOverlay = overlay;
evidence.overlay = overlay;
evidence.candidateCoordinates = coordinates;
evidence.candidateScores = scores;
evidence.candidateCountsByQuadrant = counts;
evidence.quadrantCounts = counts;
evidence.vesselSuppressionStatus = vesselStatus;
evidence.quadrantCoordinateMethod = frameMethod;
evidence.evidenceText = localEvidenceText(counts, size(coordinates, 1), ...
    vesselStatus, frameMethod, cnnPrediction);
evidence.agreementInputs = localAgreementInputs( ...
    counts, size(coordinates, 1), vesselStatus, frameMethod, cnnPrediction);
evidence.metadata = struct( ...
    'candidateTerminology', 'microaneurysm candidate', ...
    'evidenceType', 'classical candidate evidence', ...
    'clinicalValidationStatus', 'not clinically validated lesion segmentation', ...
    'vesselSuppressionStatus', vesselStatus, ...
    'quadrantCoordinateMethod', frameMethod);
end

function [detection, cnnPrediction] = localArguments(inputImage, detection, varargin)
cnnPrediction = [];
if isstruct(detection) && localIsDetectionResult(detection)
    if ~isempty(varargin)
        cnnPrediction = varargin{1};
    end
    return;
end

% Also accept buildLesionEvidence(IMAGE, CONFIG, CNNPREDICTION), which is
% useful for callers that want this function to own detection invocation.
if ~isempty(varargin)
    cnnPrediction = varargin{1};
end
if isempty(detection)
    detection = segment.detect(inputImage);
else
    detection = segment.detect(inputImage, detection);
end
end

function answer = localIsDetectionResult(value)
answer = isfield(value, 'candidateCoordinates') || ...
    isfield(value, 'candidates') || isfield(value, 'candidateScores') || ...
    (isfield(value, 'centroid') && isfield(value, 'score'));
end

function [image, imageSize] = localDisplayImage(inputImage)
if isempty(inputImage) || ~(isnumeric(inputImage) || islogical(inputImage)) || ...
        ~isreal(inputImage)
    error('explain:InvalidImage', ...
        'The evidence image must be a non-empty real numeric image.');
end
if isinteger(inputImage)
    image = im2double(inputImage);
elseif islogical(inputImage)
    image = double(inputImage);
else
    if any(~isfinite(inputImage(:))) || any(inputImage(:) < 0) || ...
            any(inputImage(:) > 1)
        error('explain:InvalidImage', ...
            'Floating-point evidence images must be finite and lie in [0, 1].');
    end
    image = double(inputImage);
end
if ndims(image) == 2
    imageSize = [size(image, 1), size(image, 2)];
else
    imageSize = [size(image, 1), size(image, 2)];
end
end

function [coordinates, scores, quadrants, counts, vesselStatus, frameMethod] = ...
        localDetectionFields(detection, imageSize)
if isfield(detection, 'candidateCoordinates')
    coordinates = detection.candidateCoordinates;
elseif isfield(detection, 'candidates') && ~isempty(detection.candidates)
    coordinates = reshape([detection.candidates.centroid], 2, []).';
elseif isfield(detection, 'centroid') && ~isempty(detection)
    coordinates = reshape([detection.centroid], 2, []).';
else
    coordinates = zeros(0, 2);
end
if isempty(coordinates)
    coordinates = zeros(0, 2);
end
if ~isnumeric(coordinates) || size(coordinates, 2) ~= 2
    error('explain:InvalidDetection', ...
        'Detection coordinates must be an N-by-2 array.');
end

if isfield(detection, 'candidateScores')
    scores = double(detection.candidateScores(:));
elseif isfield(detection, 'candidates') && ~isempty(detection.candidates)
    scores = double([detection.candidates.score]).';
elseif isfield(detection, 'score') && ~isempty(detection)
    scores = double([detection.score]).';
else
    scores = zeros(size(coordinates, 1), 1);
end
if numel(scores) ~= size(coordinates, 1)
    scores = zeros(size(coordinates, 1), 1);
end
scores(~isfinite(scores) | scores < 0) = 0;

if isfield(detection, 'candidateQuadrants')
    quadrants = detection.candidateQuadrants;
else
    [quadrants, counts, quadrantMetadata] = segment.assignQuadrants( ...
        coordinates, struct(), imageSize);
    frameMethod = quadrantMetadata.coordinateFrameMethod;
end
if ~exist('counts', 'var')
    if isfield(detection, 'quadrantCounts')
        counts = detection.quadrantCounts;
    else
        [~, counts] = segment.assignQuadrants(coordinates, struct(), imageSize);
    end
end
if ~exist('frameMethod', 'var')
    if isfield(detection, 'quadrantCoordinateMethod')
        frameMethod = char(detection.quadrantCoordinateMethod);
    else
        frameMethod = 'unspecified-coordinate-frame';
    end
end
if isfield(detection, 'vesselSuppression') && ...
        isfield(detection.vesselSuppression, 'status')
    vesselStatus = detection.vesselSuppression.status;
else
    vesselStatus = 'unavailable - no vessel mask supplied';
end
end

function overlay = localOverlay(image, coordinates, scores)
if ndims(image) == 2
    overlay = image;
    numberOfChannels = 1;
else
    overlay = image;
    numberOfChannels = size(image, 3);
end
rows = size(image, 1);
columns = size(image, 2);
for index = 1:size(coordinates, 1)
    x = round(coordinates(index, 1));
    y = round(coordinates(index, 2));
    if x < 1 || x > columns || y < 1 || y > rows
        continue;
    end
    radius = 3;
    xRange = max(1, x - radius - 1):min(columns, x + radius + 1);
    yRange = max(1, y - radius - 1):min(rows, y + radius + 1);
    [xx, yy] = meshgrid(xRange, yRange);
    ring = abs(hypot(xx - x, yy - y) - radius) <= 1.0;
    if numberOfChannels == 1
        patch = overlay(yRange, xRange);
        patch(ring) = max(patch(ring), min(1, 0.75 + scores(index)));
        overlay(yRange, xRange) = patch;
    else
        red = overlay(:, :, 1);
        green = overlay(:, :, 2);
        blue = overlay(:, :, 3);
        redPatch = red(yRange, xRange);
        greenPatch = green(yRange, xRange);
        bluePatch = blue(yRange, xRange);
        redPatch(ring) = 1;
        greenPatch(ring) = 0.1 * greenPatch(ring);
        bluePatch(ring) = 0.1 * bluePatch(ring);
        red(yRange, xRange) = redPatch;
        green(yRange, xRange) = greenPatch;
        blue(yRange, xRange) = bluePatch;
        overlay(:, :, 1) = red;
        overlay(:, :, 2) = green;
        overlay(:, :, 3) = blue;
    end
end
end

function text = localEvidenceText(counts, total, vesselStatus, frameMethod, cnnPrediction)
cnnText = localPredictionText(cnnPrediction);
text = sprintf(['Classical candidate evidence - not clinically validated lesion segmentation.\n', ...
    'MICROANEURYSM CANDIDATE EVIDENCE\n', ...
    'Candidate count: %d\n', ...
    'Quadrant counts (ST, IT, SN, IN): %d, %d, %d, %d\n', ...
    'Vessel suppression: %s\n', ...
    'Quadrant coordinate frame: %s\n', ...
    'CNN comparison input: %s\n', ...
    'Clinical confirmation remains required.'], total, counts.ST, counts.IT, ...
    counts.SN, counts.IN, char(vesselStatus), char(frameMethod), cnnText);
end

function inputs = localAgreementInputs(counts, total, vesselStatus, frameMethod, cnnPrediction)
inputs = struct();
inputs.candidateCountsByQuadrant = counts;
inputs.totalCandidateCount = total;
inputs.classicalCandidateEvidenceAvailable = total > 0;
inputs.vesselSuppressionStatus = vesselStatus;
inputs.quadrantCoordinateMethod = frameMethod;
inputs.cnnPrediction = cnnPrediction;
inputs.comparisonReady = ~isempty(cnnPrediction);
inputs.agreementState = 'not assessed - ICDR rule engine is out of scope for this milestone';
inputs.clinicalValidationRequired = true;
end

function text = localPredictionText(prediction)
if isempty(prediction)
    text = 'not supplied';
elseif ischar(prediction) || (isstring(prediction) && isscalar(prediction))
    text = char(prediction);
elseif isnumeric(prediction) && isscalar(prediction)
    text = sprintf('grade/prediction %g', prediction);
elseif isstruct(prediction)
    if isfield(prediction, 'predictedClass')
        text = sprintf('predicted class %s', mat2str(prediction.predictedClass));
    elseif isfield(prediction, 'grade')
        text = sprintf('grade %s', mat2str(prediction.grade));
    else
        text = 'structured prediction supplied';
    end
else
    text = 'prediction supplied';
end
end
