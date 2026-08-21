function loss = weightedLoss(scores, targets, classWeightValues)
%WEIGHTEDLOSS Inverse-frequency weighted five-class cross-entropy.

if isgpuarray(extractdata(scores))
    weights = gpuArray(single(classWeightValues(:)));
else
    weights = single(classWeightValues(:));
end
weights = dlarray(weights, 'C');
loss = indexcrossentropy(scores, targets, weights, ...
    'NormalizationFactor', 'batch-size');
end
