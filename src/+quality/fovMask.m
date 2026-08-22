function [mask, info] = fovMask(inputImage, config)
%FOVMASK Detect the illuminated retinal field and discard the black surround.
%   [MASK, INFO] = quality.fovMask(IMAGE, CONFIG) thresholds the image,
%   keeps the largest filled component, and returns diagnostics for the
%   detected field.  The returned MASK is reused by every quality metric.

if nargin < 2
    config = [];
end
config = configuration(config);
[unitImage, ~] = toUnitDouble(inputImage);
gray = localGray(unitImage);

threshold = config.fovThreshold;
foreground = gray > threshold;
% A very dark but non-black retinal capture can be below the default
% camera threshold.  Use a relative fallback while retaining black as the
% background when the image contains any signal.
if ~any(foreground(:)) && max(gray(:)) > 0
    threshold = min(threshold, 0.5 * max(gray(:)));
    foreground = gray > threshold;
end

mask = false(size(gray));
if any(foreground(:))
    foreground = imfill(foreground, 'holes');
    mask = bwareafilt(foreground, 1);
end
mask = logical(mask);

info = struct();
info.detected = any(mask(:));
info.threshold = threshold;
info.imageSize = size(gray);
info.area = nnz(mask);
info.areaRatio = info.area / numel(mask);
info.centroid = [NaN, NaN];
info.boundingBox = [NaN, NaN, NaN, NaN];
info.equivalentDiameter = NaN;
info.radius = NaN;
info.centerOffset = Inf;
info.centered = false;
info.boundaryBrightFraction = NaN;

if info.detected
    stats = regionprops(mask, 'Centroid', 'EquivDiameter', 'BoundingBox');
    info.centroid = stats.Centroid;
    info.boundingBox = stats.BoundingBox;
    info.equivalentDiameter = stats.EquivDiameter;
    info.radius = stats.EquivDiameter / 2;

    imageCenter = [(size(gray, 2) + 1) / 2, (size(gray, 1) + 1) / 2];
    info.centerOffset = norm(info.centroid - imageCenter) / norm(size(gray, [2, 1]));
    info.centered = info.centerOffset <= config.centerOffsetLimit;

    boundary = mask & ~imerode(mask, strel('disk', 1, 0));
    info.boundaryBrightFraction = mean(gray(boundary) >= 0.92);
end
end

function gray = localGray(image)
if size(image, 3) == 1
    gray = image(:, :, 1);
else
    gray = im2gray(image);
end
end
