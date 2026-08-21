function result = harness(trueLabels, predictedLabels)
%HARNESS Evaluate ICDR predictions and print the required validation metrics.

rng(42);

matrix = confusionMatrix(trueLabels, predictedLabels);
recall = perClassRecall(trueLabels, predictedLabels);
binary = referableMetrics(trueLabels, predictedLabels);

zeroRecallLevels = find(recall == 0) - 1;
hasConstantPredictions = numel(unique(double(predictedLabels(:)))) == 1;
collapseWarning = ~isempty(zeroRecallLevels) || hasConstantPredictions;

fprintf('Full confusion matrix (rows=actual, columns=predicted):\n');
fprintf('       0  1  2  3  4\n');
for level = 0:4
    fprintf('  %d   %d  %d  %d  %d  %d\n', level, matrix(level + 1, :));
end

for level = 0:4
    fprintf('Recall for ICDR level %d: %.6f\n', level, recall(level + 1));
end

fprintf('Binary sensitivity (referable ICDR >= 2): %.6f\n', binary.sensitivity);
fprintf('Binary specificity (referable ICDR >= 2): %.6f\n', binary.specificity);
fprintf('Referable-DR sensitivity (ICDR >= 2): %.6f\n', binary.sensitivity);
fprintf('Referable-DR specificity (ICDR >= 2): %.6f\n', binary.specificity);
fprintf('Number of samples: %d\n', binary.n);

if collapseWarning
    if isempty(zeroRecallLevels)
        fprintf(['WARNING: majority-class collapse detected: all predictions are ' ...
            'one ICDR level.\n']);
    else
        fprintf(['WARNING: majority-class collapse detected: zero recall for ICDR ' ...
            'levels %s.\n'], mat2str(zeroRecallLevels));
    end
end

result = struct( ...
    'confusionMatrix', matrix, ...
    'perClassRecall', recall, ...
    'sensitivity', binary.sensitivity, ...
    'specificity', binary.specificity, ...
    'n', binary.n, ...
    'referableThreshold', binary.referableThreshold, ...
    'zeroRecallLevels', zeroRecallLevels, ...
    'collapseWarning', collapseWarning);
end
