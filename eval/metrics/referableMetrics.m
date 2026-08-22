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

[sensitivityCILower, sensitivityCIUpper] = wilsonInterval(truePositives, positiveCount);
[specificityCILower, specificityCIUpper] = wilsonInterval(trueNegatives, negativeCount);

metrics = struct( ...
    'sensitivity', sensitivity, ...
    'specificity', specificity, ...
    'sensitivityCILower', sensitivityCILower, ...
    'sensitivityCIUpper', sensitivityCIUpper, ...
    'specificityCILower', specificityCILower, ...
    'specificityCIUpper', specificityCIUpper, ...
    'truePositives', truePositives, ...
    'falseNegatives', falseNegatives, ...
    'trueNegatives', trueNegatives, ...
    'falsePositives', falsePositives, ...
    'n', sum(matrix, 'all'), ...
    'referableThreshold', referableThreshold);
end

function [lower, upper] = wilsonInterval(successes, total)
%WILSONINTERVAL 95%% Wilson score confidence interval for a binomial rate.

z = 1.96;
if total == 0
    lower = NaN;
    upper = NaN;
    return;
end

phat = successes / total;
zSquared = z^2;
denominator = 1 + zSquared / total;
center = phat + zSquared / (2 * total);
margin = z * sqrt((phat * (1 - phat) / total) + (zSquared / (4 * total^2)));

lower = max(0, (center - margin) / denominator);
upper = min(1, (center + margin) / denominator);
end
