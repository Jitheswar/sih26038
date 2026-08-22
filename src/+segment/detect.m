function result = detect(inputImage, varargin)
%DETECT Build classical candidate evidence for one retinal image.
%   RESULT = segment.detect(IMAGE) runs the non-learned microaneurysm
%   candidate detector and assigns each candidate to a quadrant.
%   Optional arguments are a configuration structure or JSON filename,
%   followed by a vessel mask and/or a coordinate-frame structure.
%
%   This function deliberately reports candidates, not confirmed lesions.

rng(42, 'twister');

[config, vesselMask, coordinateFrame] = localArguments(varargin{:});
candidateResult = segment.detectMicroaneurysmCandidates( ...
    inputImage, config, vesselMask);

[quadrants, counts, quadrantMetadata] = segment.assignQuadrants( ...
    candidateResult.candidateCoordinates, coordinateFrame, size(candidateResult.fovMask));

result = candidateResult;
result.candidateQuadrants = quadrants;
result.quadrantLabels = quadrants;
result.quadrantCounts = counts;
result.quadrantMetadata = quadrantMetadata;
result.quadrantCoordinateMethod = quadrantMetadata.coordinateFrameMethod;
result.coordinateFrameMethod = quadrantMetadata.coordinateFrameMethod;
result.metadata = struct( ...
    'coordinateFrameMethod', quadrantMetadata.coordinateFrameMethod, ...
    'coordinateFrameIsApproximate', quadrantMetadata.isApproximate, ...
    'vesselSuppressionStatus', candidateResult.vesselSuppression.status, ...
    'candidateTerminology', 'microaneurysm candidate', ...
    'clinicalValidationStatus', 'not clinically validated');
end

function [config, vesselMask, coordinateFrame] = localArguments(varargin)
config = struct();
vesselMask = [];
coordinateFrame = struct();
for index = 1:numel(varargin)
    argument = varargin{index};
    if isempty(argument)
        continue;
    elseif islogical(argument) || (isnumeric(argument) && ismatrix(argument))
        if isempty(vesselMask)
            vesselMask = argument;
        else
            error('segment:InvalidArguments', ...
                'Only one vessel mask may be supplied.');
        end
    elseif ischar(argument) || (isstring(argument) && isscalar(argument))
        if isempty(fieldnames(config))
            config = char(argument);
        else
            error('segment:InvalidArguments', ...
                'Only one configuration filename may be supplied.');
        end
    elseif isstruct(argument) && isscalar(argument)
        if localLooksLikeCoordinateFrame(argument)
            coordinateFrame = argument;
        elseif isempty(fieldnames(config))
            config = argument;
        elseif isempty(fieldnames(coordinateFrame))
            coordinateFrame = argument;
        else
            error('segment:InvalidArguments', ...
                'Could not distinguish the supplied structures.');
        end
    else
        error('segment:InvalidArguments', ...
            'Optional arguments must be a configuration, vessel mask, or coordinate frame.');
    end
end
end

function answer = localLooksLikeCoordinateFrame(value)
names = fieldnames(value);
answer = any(ismember(names, {'opticDisc', 'opticDiscCenter', ...
    'discCenter', 'fovea', 'foveaCenter', 'origin', 'temporalAxis', ...
    'superiorAxis', 'coordinateFrameMethod'}));
end
