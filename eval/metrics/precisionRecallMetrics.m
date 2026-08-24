function result = precisionRecallMetrics(actualPositive, scores)
%PRECISIONRECALLMETRICS Precision-recall curve and average precision.
%   RESULT = precisionRecallMetrics(ACTUALPOSITIVE, SCORES) returns the
%   precision-recall curve and the average precision for a binary endpoint
%   (§11.3).  Under class imbalance this is more informative than ROC,
%   because the negative class dominates the false-positive rate and makes
%   ROC look better than the screening experience warrants.
%
%   Average precision is the recall-weighted sum of precisions, which is
%   the interpolation-free summary; a trapezoid over the curve is
%   optimistic where precision jumps.

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
if positiveCount == 0
    result = struct('averagePrecision', NaN, 'precision', [], 'recall', [], ...
        'thresholds', [], 'n', numel(scores), 'positives', 0, ...
        'baselinePrecision', NaN);
    return;
end

[sortedScores, order] = sort(scores, 'descend');
sortedLabels = actualPositive(order);

cumulativeTruePositives = cumsum(sortedLabels);
cumulativePredicted = (1:numel(sortedLabels))';
precision = cumulativeTruePositives ./ cumulativePredicted;
recall = cumulativeTruePositives / positiveCount;

% Collapse ties: a threshold cannot separate equal scores, so only the last
% index of each run of equal scores is a reachable operating point.
isLastOfRun = [diff(sortedScores) ~= 0; true];
precision = precision(isLastOfRun);
recall = recall(isLastOfRun);
thresholds = sortedScores(isLastOfRun);

recallIncrements = diff([0; recall]);
averagePrecision = sum(precision .* recallIncrements);

result = struct( ...
    'averagePrecision', averagePrecision, ...
    'aupr', averagePrecision, ...
    'precision', precision, ...
    'recall', recall, ...
    'thresholds', thresholds, ...
    'n', numel(scores), ...
    'positives', positiveCount, ...
    'baselinePrecision', positiveCount / numel(scores));
end
