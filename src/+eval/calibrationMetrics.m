function metrics = calibrationMetrics(labels, rawProbabilities, calibratedProbabilities, varargin)
%CALIBRATIONMETRICS Measure raw and temperature-scaled calibration.
%   METRICS = eval.calibrationMetrics(LABELS, RAW, CALIBRATED) returns
%   multiclass ECE, multiclass Brier score, mean NLL, and reliability data
%   for both probability arrays.  Arrays are classes-by-samples and labels
%   are ICDR grades 0 through 4.

parser = inputParser;
parser.addParameter('NumBins', 10, @(value) isnumeric(value) && isscalar(value) && ...
    isfinite(value) && value >= 2 && value == floor(value));
parser.parse(varargin{:});
numberOfBins = double(parser.Results.NumBins);

labels = double(labels(:));
localValidateLabels(labels);
rawProbabilities = localOrientProbabilities(rawProbabilities, numel(labels), 'raw');
calibratedProbabilities = localOrientProbabilities( ...
    calibratedProbabilities, numel(labels), 'calibrated');
if size(rawProbabilities, 1) ~= size(calibratedProbabilities, 1)
    error('evaluation:ClassCountMismatch', ...
        'Raw and calibrated probabilities must have the same class count.');
end

metrics = struct();
metrics.raw = localOneSet(labels, rawProbabilities, numberOfBins);
metrics.calibrated = localOneSet(labels, calibratedProbabilities, numberOfBins);
metrics.numSamples = numel(labels);
metrics.numClasses = size(rawProbabilities, 1);
metrics.numBins = numberOfBins;
metrics.rawECE = metrics.raw.multiclassECE;
metrics.calibratedECE = metrics.calibrated.multiclassECE;
metrics.rawBrierScore = metrics.raw.multiclassBrierScore;
metrics.calibratedBrierScore = metrics.calibrated.multiclassBrierScore;
metrics.rawMeanNLL = metrics.raw.meanNegativeLogLikelihood;
metrics.calibratedMeanNLL = metrics.calibrated.meanNegativeLogLikelihood;
end

function result = localOneSet(labels, probabilities, numberOfBins)
sampleCount = numel(labels);
classCount = size(probabilities, 1);
predictedLabels = zeros(sampleCount, 1);
confidence = zeros(sampleCount, 1);
for sampleIndex = 1:sampleCount
    [confidence(sampleIndex), predictedIndex] = max(probabilities(:, sampleIndex));
    predictedLabels(sampleIndex) = predictedIndex - 1;
end

targets = zeros(classCount, sampleCount);
targetIndices = sub2ind([classCount, sampleCount], labels + 1, (1:sampleCount).');
targets(targetIndices) = 1;
multiclassBrierScore = mean(sum((probabilities - targets).^2, 1));
targetProbabilities = probabilities(targetIndices);
meanNegativeLogLikelihood = -mean(log(max(targetProbabilities, realmin('double'))));

multiclassReliability = localReliability(confidence, ...
    double(predictedLabels == labels), numberOfBins);
multiclassECE = sum(multiclassReliability.count .* ...
    multiclassReliability.absoluteGap) / sampleCount;

referableLabels = double(labels >= 2);
referableProbabilities = sum(probabilities(3:5, :), 1).';
referableReliability = localReliability(referableProbabilities, ...
    referableLabels, numberOfBins);
referableECE = sum(referableReliability.count .* ...
    referableReliability.absoluteGap) / sampleCount;
referableBrierScore = mean((referableProbabilities - referableLabels).^2);
referableNLL = -mean(log(max( ...
    referableLabels .* referableProbabilities + ...
    (1 - referableLabels) .* (1 - referableProbabilities), ...
    realmin('double'))));

result = struct();
result.multiclassECE = multiclassECE;
result.ece = multiclassECE;
result.multiclassBrierScore = multiclassBrierScore;
result.brierScore = multiclassBrierScore;
result.meanNegativeLogLikelihood = meanNegativeLogLikelihood;
result.meanNLL = meanNegativeLogLikelihood;
result.reliabilityDiagram = multiclassReliability;
result.predictedLabels = predictedLabels;
result.confidence = confidence;
result.referableDR = struct( ...
    'labels', referableLabels, ...
    'probabilities', referableProbabilities, ...
    'binaryECE', referableECE, ...
    'ece', referableECE, ...
    'binaryBrierScore', referableBrierScore, ...
    'brierScore', referableBrierScore, ...
    'meanNegativeLogLikelihood', referableNLL, ...
    'reliabilityDiagram', referableReliability);
result.referableProbability = referableProbabilities;
result.referableLabels = referableLabels;
result.binaryECE = referableECE;
result.binaryBrierScore = referableBrierScore;
result.referableReliabilityDiagram = referableReliability;
end

function diagram = localReliability(confidence, correctness, numberOfBins)
sampleCount = numel(confidence);
binEdges = linspace(0, 1, numberOfBins + 1).';
binIndex = floor(confidence * numberOfBins) + 1;
binIndex(confidence >= 1) = numberOfBins;
binIndex = max(1, min(numberOfBins, binIndex));

count = zeros(numberOfBins, 1);
meanConfidence = zeros(numberOfBins, 1);
observedFrequency = zeros(numberOfBins, 1);
absoluteGap = zeros(numberOfBins, 1);
occupied = false(numberOfBins, 1);
for bin = 1:numberOfBins
    selected = binIndex == bin;
    count(bin) = sum(selected);
    if count(bin) > 0
        occupied(bin) = true;
        meanConfidence(bin) = mean(confidence(selected));
        observedFrequency(bin) = mean(correctness(selected));
        absoluteGap(bin) = abs(meanConfidence(bin) - observedFrequency(bin));
    end
end

diagram = struct( ...
    'binEdges', binEdges, ...
    'binLowerEdges', binEdges(1:end-1), ...
    'binUpperEdges', binEdges(2:end), ...
    'count', count, ...
    'meanConfidence', meanConfidence, ...
    'accuracy', observedFrequency, ...
    'observedFrequency', observedFrequency, ...
    'absoluteGap', absoluteGap, ...
    'occupied', occupied, ...
    'sampleCount', sampleCount);
end

function probabilities = localOrientProbabilities(probabilities, sampleCount, name)
if ~isnumeric(probabilities) || isempty(probabilities) || ndims(probabilities) ~= 2
    error('evaluation:InvalidProbabilities', ...
        '%s probabilities must be a non-empty numeric two-dimensional array.', name);
end
if size(probabilities, 2) == sampleCount
    % The project convention is classes-by-samples.
elseif size(probabilities, 1) == sampleCount
    probabilities = probabilities.';
else
    error('evaluation:ProbabilityLengthMismatch', ...
        '%s probabilities do not contain one column per label.', name);
end
if size(probabilities, 1) < 5
    error('evaluation:InvalidClassCount', ...
        'Calibration probabilities must contain five ICDR classes.');
end
if any(~isfinite(probabilities(:))) || any(probabilities(:) < 0)
    error('evaluation:InvalidProbabilities', ...
        '%s probabilities must be finite and non-negative.', name);
end
columnSums = sum(probabilities, 1);
if any(abs(columnSums - 1) > 1e-8)
    error('evaluation:UnnormalizedProbabilities', ...
        '%s probabilities must sum to one in every sample.', name);
end
probabilities = double(probabilities ./ columnSums);
end

function localValidateLabels(labels)
if isempty(labels) || any(~isfinite(labels)) || any(labels ~= floor(labels)) || ...
        any(~ismember(labels, 0:4))
    error('evaluation:InvalidLabels', ...
        'Calibration labels must be non-empty integer ICDR grades from 0 through 4.');
end
end
