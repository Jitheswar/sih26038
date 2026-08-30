function metrics = lesionAUPR(counts, thresholds, lesionTypes)
%LESIONAUPR Area under the precision-recall curve, per lesion type.
%   METRICS = lesionAUPR(COUNTS, THRESHOLDS, LESIONTYPES) turns pooled
%   confusion counts from lesionThresholdCounts into a per-type AUPR plus
%   the precision and recall points the curve is drawn from.
%
%   AUPR, not ROC-AUC.  §6.4 is explicit about why, and the IDRiD
%   sub-challenge uses AUPR for the same reason: lesion pixels are well
%   under one per cent of a frame, and with a negative class that large a
%   useless detector still posts an impressive ROC-AUC because the false
%   positive rate is divided by an enormous denominator.  Precision is not,
%   so it reports the failure.

thresholds = thresholds(:)';
typeCount = size(counts.truePositive, 1);
if nargin < 3 || isempty(lesionTypes)
    lesionTypes = arrayfun(@(index) sprintf('type%d', index), ...
        1:typeCount, 'UniformOutput', false);
end

truePositive = counts.truePositive;
falsePositive = counts.falsePositive;
falseNegative = counts.falseNegative;

predictedPositive = truePositive + falsePositive;
actualPositive = truePositive + falseNegative;

precision = truePositive ./ max(predictedPositive, 1);
% A threshold so high that nothing is predicted positive has undefined
% precision. Convention for a PR curve is to carry the previous (higher
% threshold) precision, and since the highest threshold is the last column
% the carry runs from the low-threshold end upwards.
precision(predictedPositive == 0) = NaN;
recall = truePositive ./ max(actualPositive, 1);
recall(actualPositive == 0) = NaN;

auprValues = zeros(typeCount, 1);
for typeIndex = 1:typeCount
    typePrecision = precision(typeIndex, :);
    typeRecall = recall(typeIndex, :);
    valid = isfinite(typePrecision) & isfinite(typeRecall);
    if nnz(valid) < 2
        auprValues(typeIndex) = NaN;
        continue;
    end
    validPrecision = typePrecision(valid);
    validRecall = typeRecall(valid);

    % Several thresholds can land on the same recall, and the curve is
    % defined as the upper envelope over them: at a given recall the
    % detector is credited with the best precision it can actually reach
    % there.  Integrating the raw points instead makes a saturating detector
    % score its own worst point - a map that separates lesion from
    % background perfectly puts every threshold at recall 1, and trapezoids
    % across a zero-width recall span collapse the area to the precision of
    % the single most permissive threshold, which is prevalence.  That reads
    % as chance for a detector that is in fact exact.
    [uniqueRecall, ~, group] = unique(validRecall(:));
    envelopePrecision = accumarray(group, validPrecision(:), [], @max);

    % Anchor at recall zero so a type whose curve starts partway along the
    % recall axis is not credited with the area under the missing segment.
    if uniqueRecall(1) > 0
        uniqueRecall = [0; uniqueRecall];
        envelopePrecision = [envelopePrecision(1); envelopePrecision];
    end
    if numel(uniqueRecall) < 2
        % Every threshold reached zero recall: the detector found nothing.
        auprValues(typeIndex) = 0;
        continue;
    end
    auprValues(typeIndex) = trapz(uniqueRecall, envelopePrecision);
end

% The precision a detector that answers positive everywhere would reach.
% Every AUPR below is reported beside it, because for a class occupying
% 0.1 per cent of the frame an AUPR of 0.05 is fifty times chance and an
% AUPR of 0.05 for a class occupying 10 per cent is half of chance.
prevalence = counts.positiveCount ./ ...
    max(counts.pixelCount * ones(typeCount, 1), 1);

f1 = 2 * (precision .* recall) ./ max(precision + recall, eps);
f1(~isfinite(f1)) = 0;
[bestF1, bestIndex] = max(f1, [], 2);

metrics = struct();
metrics.lesionTypes = lesionTypes(:)';
metrics.thresholds = thresholds;
metrics.aupr = auprValues;
metrics.precision = precision;
metrics.recall = recall;
metrics.prevalence = prevalence;
metrics.auprOverPrevalence = auprValues ./ max(prevalence, eps);
metrics.bestF1 = bestF1;
metrics.bestF1Threshold = thresholds(bestIndex)';
metrics.positiveCount = counts.positiveCount;
metrics.pixelCount = counts.pixelCount;
end
