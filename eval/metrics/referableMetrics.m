function metrics = referableMetrics(trueLabels, predictedLabels)
%REFERABLEMETRICS Calculate binary metrics for ICDR level 2 or higher.

rng(42);
matrix = confusionMatrix(trueLabels, predictedLabels);

trueLabels = double(trueLabels(:));
predictedLabels = double(predictedLabels(:));
referableThreshold = 2;
actualReferable = trueLabels >= referableThreshold;
predictedReferable = predictedLabels >= referableThreshold;

truePositives = sum(actualReferable & predictedReferable);
falseNegatives = sum(actualReferable & ~predictedReferable);
trueNegatives = sum(~actualReferable & ~predictedReferable);
falsePositives = sum(~actualReferable & predictedReferable);

positiveCount = truePositives + falseNegatives;
negativeCount = trueNegatives + falsePositives;
sensitivity = truePositives / positiveCount;
specificity = trueNegatives / negativeCount;

if positiveCount == 0
    sensitivity = NaN;
end
if negativeCount == 0
    specificity = NaN;
end

metrics = struct( ...
    'sensitivity', sensitivity, ...
    'specificity', specificity, ...
    'truePositives', truePositives, ...
    'falseNegatives', falseNegatives, ...
    'trueNegatives', trueNegatives, ...
    'falsePositives', falsePositives, ...
    'n', sum(matrix, 'all'), ...
    'referableThreshold', referableThreshold);
end
