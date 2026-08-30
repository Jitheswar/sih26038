function prepared = vesselPreprocess(image, vessel)
%VESSELPREPROCESS Turn a fundus frame into the vessel network's input.
%   PREPARED = segment.vesselPreprocess(IMAGE, VESSEL) returns a single
%   channel in [0, 1] on the same pixel grid as IMAGE.
%
%   Both segment.trainVesselSegmentation and segment.segmentVessels call
%   this, and nothing else may prepare a vessel input.  §5.4's hard rule is
%   that exactly one preprocessing function serves training and inference,
%   because enhancement applied at inference but not at training is
%   self-inflicted domain shift and no metric names it.  This is the vessel
%   path's instance of that rule; extend this function, a second one is the
%   bug.
%
%   Green channel, per §6.3.  Retinal vessels absorb most strongly in green:
%   the red channel is saturated by choroidal background and the blue
%   channel carries almost no signal and most of the sensor noise.  Feeding
%   all three would hand the network two channels of nuisance variation
%   across the twenty frames it has to learn from.
%
%   CLAHE, when vessel.green_clahe is true.  DRIVE frames are unevenly
%   illuminated, brighter at the centre and falling off towards the field
%   edge, and a network trained on raw green learns that gradient as much as
%   it learns vessels.  Contrast-limited equalisation on small tiles
%   normalises local contrast without amplifying noise the way plain
%   histogram equalisation does.  The clip limit is configuration, not a
%   constant typed in here (§13.3).

if nargin < 2
    vessel = struct();
end
if ~isfield(vessel, 'green_clahe')
    vessel.green_clahe = true;
end
if ~isfield(vessel, 'clahe_clip_limit')
    vessel.clahe_clip_limit = 0.01;
end
if ~isfield(vessel, 'clahe_tiles')
    vessel.clahe_tiles = 8;
end

if ndims(image) == 3 && size(image, 3) >= 3
    green = image(:, :, 2);
elseif ismatrix(image)
    green = image;
else
    error('segment:InvalidVesselImage', ...
        'A vessel input must be an RGB frame or a single channel.');
end

if isinteger(green)
    green = single(green) / single(intmax(class(green)));
else
    green = single(green);
end
green = max(0, min(1, green));

if vessel.green_clahe
    % adapthisteq needs double in [0, 1] and returns the same class.
    green = single(adapthisteq(double(green), ...
        'ClipLimit', vessel.clahe_clip_limit, ...
        'NumTiles', [vessel.clahe_tiles, vessel.clahe_tiles], ...
        'Distribution', 'uniform'));
end

prepared = max(0, min(1, single(green)));
end
