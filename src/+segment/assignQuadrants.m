function [quadrantLabels, counts, metadata] = assignQuadrants(coordinates, varargin)
%ASSIGNQUADRANTS Assign candidate coordinates to retinal quadrants.
%   [LABELS, COUNTS, METADATA] = segment.assignQuadrants(COORDINATES,
%   FRAME, IMAGESIZE) prefers an optic-disc/fovea frame when both anatomy
%   coordinates are supplied.  Otherwise it uses an explicitly labelled
%   approximate image-centre frame.
%
%   Coordinates are [x y] pairs, with x increasing rightward and y
%   increasing downward.  Labels are ST, IT, SN, and IN.

rng(42, 'twister');

if nargin < 1 || isempty(coordinates)
    coordinates = zeros(0, 2);
end
if ~isnumeric(coordinates) || ~isreal(coordinates) || size(coordinates, 2) ~= 2 || ...
        any(~isfinite(coordinates(:)))
    error('segment:InvalidCoordinates', ...
        'Candidate coordinates must be a finite N-by-2 [x y] array.');
end

[frame, imageSize] = localArguments(varargin{:});
[origin, temporalAxis, method, isApproximate, description] = ...
    localCoordinateFrame(frame, imageSize);

quadrantLabels = repmat({''}, size(coordinates, 1), 1);
relative = coordinates - origin;
temporalCoordinate = relative * temporalAxis(:);
% Image y increases downward, so rotate the temporal axis toward image-up
% when constructing the superior direction.
superiorAxis = [temporalAxis(2), -temporalAxis(1)];
superiorCoordinate = relative * superiorAxis(:);

for index = 1:size(coordinates, 1)
    if temporalCoordinate(index) >= 0
        if superiorCoordinate(index) >= 0
            quadrantLabels{index} = 'ST';
        else
            quadrantLabels{index} = 'IT';
        end
    elseif superiorCoordinate(index) >= 0
        quadrantLabels{index} = 'SN';
    else
        quadrantLabels{index} = 'IN';
    end
end

counts = struct('ST', sum(strcmp(quadrantLabels, 'ST')), ...
    'IT', sum(strcmp(quadrantLabels, 'IT')), ...
    'SN', sum(strcmp(quadrantLabels, 'SN')), ...
    'IN', sum(strcmp(quadrantLabels, 'IN')), ...
    'superiorTemporal', sum(strcmp(quadrantLabels, 'ST')), ...
    'inferiorTemporal', sum(strcmp(quadrantLabels, 'IT')), ...
    'superiorNasal', sum(strcmp(quadrantLabels, 'SN')), ...
    'inferiorNasal', sum(strcmp(quadrantLabels, 'IN')));

metadata = struct();
metadata.coordinateFrameMethod = method;
metadata.method = method;
metadata.isApproximate = isApproximate;
metadata.description = description;
metadata.origin = origin;
metadata.temporalAxis = temporalAxis;
metadata.superiorAxis = superiorAxis;
metadata.imageSize = imageSize;
metadata.labels = {'ST', 'IT', 'SN', 'IN'};
metadata.clinicalValidationStatus = 'coordinate partition only - not clinically validated';
end

function [frame, imageSize] = localArguments(varargin)
frame = struct();
imageSize = [];
for index = 1:numel(varargin)
    value = varargin{index};
    if isempty(value)
        continue;
    elseif isstruct(value) && isscalar(value)
        frame = value;
        if isfield(value, 'imageSize')
            imageSize = value.imageSize;
        end
    elseif isnumeric(value) && isvector(value) && numel(value) == 2
        imageSize = double(value(:)).';
    else
        error('segment:InvalidCoordinateFrame', ...
            'Coordinate frame must be a structure and image size must be [rows columns].');
    end
end
if isempty(imageSize)
    imageSize = [1, 1];
end
if ~isnumeric(imageSize) || numel(imageSize) ~= 2 || ...
        any(~isfinite(imageSize(:))) || any(imageSize <= 0)
    error('segment:InvalidCoordinateFrame', ...
        'Image size must contain two positive finite values.');
end
imageSize = double(imageSize(:)).';
end

function [origin, temporalAxis, method, isApproximate, description] = ...
        localCoordinateFrame(frame, imageSize)
opticDisc = localCoordinate(frame, ...
    {'opticDiscCenter', 'opticDisc', 'discCenter'});
fovea = localCoordinate(frame, {'foveaCenter', 'fovea'});

if ~isempty(opticDisc) && ~isempty(fovea)
    origin = opticDisc;
    axis = fovea - opticDisc;
    if norm(axis) <= eps
        error('segment:InvalidCoordinateFrame', ...
            'Optic-disc and fovea coordinates must not be identical.');
    end
    temporalAxis = axis / norm(axis);
    method = 'optic-disc-fovea';
    isApproximate = false;
    description = 'Optic-disc/fovea coordinate frame supplied.';
    return;
end

if isfield(frame, 'origin') && isfield(frame, 'temporalAxis')
    origin = localPair(frame.origin, 'coordinate-frame origin');
    temporalAxis = localPair(frame.temporalAxis, 'temporal axis');
    if norm(temporalAxis) <= eps
        error('segment:InvalidCoordinateFrame', 'Temporal axis must be non-zero.');
    end
    temporalAxis = temporalAxis / norm(temporalAxis);
    method = 'supplied-coordinate-frame';
    isApproximate = false;
    description = 'Explicit coordinate frame supplied by the caller.';
    return;
end

origin = [(imageSize(2) + 1) / 2, (imageSize(1) + 1) / 2];
temporalAxis = [1, 0];
method = 'approximate-image-centre';
isApproximate = true;
description = ['Approximate image-centre coordinate frame; clinical ', ...
    'optic-disc/fovea coordinates were unavailable.'];
end

function value = localCoordinate(frame, names)
value = [];
for index = 1:numel(names)
    if isfield(frame, names{index}) && ~isempty(frame.(names{index}))
        value = localPair(frame.(names{index}), names{index});
        return;
    end
end
end

function value = localPair(value, description)
if ~isnumeric(value) || numel(value) ~= 2 || ~isreal(value) || ...
        any(~isfinite(value(:)))
    error('segment:InvalidCoordinateFrame', ...
        '%s must be a finite two-element coordinate.', description);
end
value = double(value(:)).';
end
