function recall = perClassRecall(trueLabels, predictedLabels)
%PERCLASSRECALL Return recall for ICDR levels 0 through 4.

rng(42);
matrix = confusionMatrix(trueLabels, predictedLabels);
support = sum(matrix, 2);
recall = nan(5, 1);
hasSupport = support > 0;
diagonal = diag(matrix);
recall(hasSupport) = diagonal(hasSupport) ./ support(hasSupport);
end
