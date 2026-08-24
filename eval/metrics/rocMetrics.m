function result = rocMetrics(actualPositive, scores)
%ROCMETRICS Threshold-independent ROC summary for referable DR.
%   RESULT = rocMetrics(ACTUALPOSITIVE, SCORES) returns the ROC curve and
%   its area for a binary endpoint (§11.3).  ACTUALPOSITIVE is a logical
%   vector, SCORES the calibrated referable probability.
%
%   AUC is computed exactly, as the normalised Mann-Whitney U statistic
%   with ties credited a half, rather than by trapezoid over a sampled
%   curve.  The two agree, but the rank form does not depend on how finely
%   the curve happens to be sampled.
%
%   AUC is threshold-independent and so says nothing about the frozen
%   operating point.  Report it alongside sensitivity and specificity at
%   the frozen threshold, never instead of them (§11.1).

rng(42);

actualPositive = logical(actualPositive(:));
scores = double(scores(:));
if numel(actualPositive) ~= numel(scores)
    error('eval:LengthMismatch', ...
        'Labels and scores must have the same number of elements.');
end
finite = isfinite(scores);
actualPositive = actualPositive(finite);
scores = scores(finite);

positiveCount = sum(actualPositive);
negativeCount = sum(~actualPositive);

if positiveCount == 0 || negativeCount == 0
    result = struct('auc', NaN, 'falsePositiveRate', [], ...
        'truePositiveRate', [], 'thresholds', [], ...
        'n', numel(scores), 'positives', positiveCount, ...
        'negatives', negativeCount, 'youdenThreshold', NaN, ...
        'youdenIndex', NaN);
    return;
end

ranks = tiedrank(scores);
auc = (sum(ranks(actualPositive)) - positiveCount * (positiveCount + 1) / 2) / ...
    (positiveCount * negativeCount);

thresholds = unique([-Inf; sort(scores, 'descend'); Inf]);
thresholds = flipud(thresholds);
truePositiveRate = zeros(numel(thresholds), 1);
falsePositiveRate = zeros(numel(thresholds), 1);
for index = 1:numel(thresholds)
    predicted = scores >= thresholds(index);
    truePositiveRate(index) = sum(predicted & actualPositive) / positiveCount;
    falsePositiveRate(index) = sum(predicted & ~actualPositive) / negativeCount;
end

[youdenIndex, bestIndex] = max(truePositiveRate - falsePositiveRate);

result = struct( ...
    'auc', auc, ...
    'falsePositiveRate', falsePositiveRate, ...
    'truePositiveRate', truePositiveRate, ...
    'thresholds', thresholds, ...
    'n', numel(scores), ...
    'positives', positiveCount, ...
    'negatives', negativeCount, ...
    'youdenThreshold', thresholds(bestIndex), ...
    'youdenIndex', youdenIndex);
end
