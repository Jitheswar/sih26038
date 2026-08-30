function counts = lesionThresholdCounts(probabilityMaps, targetMasks, thresholds)
%LESIONTHRESHOLDCOUNTS Accumulate pixel confusion counts at fixed thresholds.
%   COUNTS = lesionThresholdCounts(PROBABILITYMAPS, TARGETMASKS, THRESHOLDS)
%   returns T-by-numel(THRESHOLDS) matrices of true positives, false
%   positives and false negatives, one row per lesion type.
%
%   Counts rather than stored maps, because the caller sums them over a
%   whole split.  Retaining the probability maps for 27 frames of 2848x4288
%   pixels and four lesion types to score them at the end would need about
%   five gigabytes; the counts need a few hundred bytes and are exactly
%   additive across images, which is what the IDRiD protocol asks for
%   (§6.4): one precision-recall curve over the pooled pixels of the set,
%   not the average of per-image curves.

if ndims(probabilityMaps) ~= ndims(targetMasks) || ...
        any(size(probabilityMaps) ~= size(targetMasks))
    error('eval:lesionThresholdCounts:SizeMismatch', ...
        'Probability maps and target masks must have identical size.');
end

thresholds = thresholds(:)';
thresholdCount = numel(thresholds);
typeCount = size(probabilityMaps, 3);

counts = struct();
counts.truePositive = zeros(typeCount, thresholdCount);
counts.falsePositive = zeros(typeCount, thresholdCount);
counts.falseNegative = zeros(typeCount, thresholdCount);
counts.positiveCount = zeros(typeCount, 1);
counts.pixelCount = size(probabilityMaps, 1) * size(probabilityMaps, 2);

for typeIndex = 1:typeCount
    scores = probabilityMaps(:, :, typeIndex);
    target = targetMasks(:, :, typeIndex);
    positive = target(:);
    scoresPositive = scores(positive);
    scoresNegative = scores(~positive);
    counts.positiveCount(typeIndex) = numel(scoresPositive);

    for thresholdIndex = 1:thresholdCount
        threshold = thresholds(thresholdIndex);
        truePositive = sum(scoresPositive >= threshold);
        counts.truePositive(typeIndex, thresholdIndex) = truePositive;
        counts.falseNegative(typeIndex, thresholdIndex) = ...
            numel(scoresPositive) - truePositive;
        counts.falsePositive(typeIndex, thresholdIndex) = ...
            sum(scoresNegative >= threshold);
    end
end
end
