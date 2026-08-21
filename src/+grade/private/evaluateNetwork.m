function metrics = evaluateNetwork(net, queue, classWeights, epoch, splitName)
%EVALUATENETWORK Evaluate one split through the project harness.

reset(queue);
actualLabels = zeros(0, 1);
predictedLabels = zeros(0, 1);
probabilities = zeros(5, 0, 'single');
lossTotal = 0;
sampleTotal = 0;

while hasdata(queue)
    [images, targets] = next(queue);
    scores = predict(net, images);
    batchScores = gather(extractdata(scores));
    batchTargets = gather(extractdata(targets));
    batchScores = reshape(batchScores, 5, []);
    batchTargets = reshape(batchTargets, 1, []);
    batchCount = numel(batchTargets);
    batchPredictions = reshape(gather(extractdata( ...
        scores2label(scores, string(0:4)))), 1, []);
    if iscategorical(batchPredictions)
        batchPredictions = double(string(batchPredictions));
    end
    batchPredictions = double(batchPredictions(:)) - 0;
    batchTargets = double(batchTargets(:)) - 1;

    batchLoss = gather(extractdata(dlfeval( ...
        @weightedLoss, scores, targets, classWeights)));
    lossTotal = lossTotal + double(batchLoss) * batchCount;
    sampleTotal = sampleTotal + batchCount;
    actualLabels = [actualLabels; batchTargets]; %#ok<AGROW>
    predictedLabels = [predictedLabels; batchPredictions]; %#ok<AGROW>
    probabilities = [probabilities, single(batchScores)]; %#ok<AGROW>
end

if sampleTotal == 0
    error('grade:EmptyEvaluation', 'The %s datastore produced no samples.', splitName);
end

fprintf('%s epoch %d: Loss: %.6f\n', ...
    upper(char(splitName)), epoch, lossTotal / sampleTotal);
harnessResult = harness(actualLabels, predictedLabels);
metrics = harnessResult;
metrics.loss = lossTotal / sampleTotal;
metrics.epoch = epoch;
metrics.split = string(splitName);
metrics.actualLabels = actualLabels;
metrics.predictedLabels = predictedLabels;
metrics.probabilities = probabilities;
end
