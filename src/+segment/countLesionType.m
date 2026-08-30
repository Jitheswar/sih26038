function [count, centroids, areas, mask] = countLesionType(probabilityMap, ...
    threshold, minimumArea)
%COUNTLESIONTYPE Threshold one lesion probability map and count what remains.
%   [COUNT, CENTROIDS, AREAS, MASK] = segment.countLesionType(PROBABILITYMAP,
%   THRESHOLD, MINIMUMAREA) applies THRESHOLD to a single lesion type's
%   probability map, discards connected components smaller than MINIMUMAREA,
%   and returns the number of surviving components, their centroids as an
%   N-by-2 [x y] array, their areas, and the binary mask.
%
%   This is the one place a probability map becomes a count.  It exists as
%   its own function because two callers need exactly this step and must not
%   drift apart: segment.lesionEvidence runs it once per type at the
%   operating thresholds, and the threshold-transfer sweep
%   (eval/lesionThresholdTransfer.m) runs it many times per type over a grid
%   of candidate thresholds, reusing a single expensive inference pass.
%
%   The minimum-area filter is not cosmetic.  Without it a single stray
%   pixel counts as one haemorrhage, and the ICDR Level 3 criterion is a
%   threshold on haemorrhage COUNT (the 4-2-1 rule, §3.3), so noise at the
%   pixel level converts directly into a severity level.

if ~isnumeric(probabilityMap) || ~isreal(probabilityMap) || ...
        ~ismatrix(probabilityMap)
    error('segment:InvalidProbabilityMap', ...
        'The probability map must be a real numeric matrix.');
end
if ~isnumeric(threshold) || ~isscalar(threshold) || ~isfinite(threshold)
    error('segment:InvalidThreshold', ...
        'The threshold must be a finite numeric scalar.');
end
if ~isnumeric(minimumArea) || ~isscalar(minimumArea) || ...
        ~isfinite(minimumArea) || minimumArea < 0
    error('segment:InvalidMinimumArea', ...
        'The minimum area must be a finite non-negative numeric scalar.');
end

mask = probabilityMap >= threshold;

if minimumArea > 1
    mask = bwareaopen(mask, minimumArea);
end

components = bwconncomp(mask);
properties = regionprops(components, 'Centroid', 'Area');
if isempty(properties)
    centroids = zeros(0, 2);
    areas = zeros(0, 1);
else
    centroids = reshape([properties.Centroid], 2, []).';
    areas = [properties.Area].';
end

count = components.NumObjects;
end
