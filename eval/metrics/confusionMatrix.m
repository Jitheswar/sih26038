function matrix = confusionMatrix(trueLabels, predictedLabels)
%CONFUSIONMATRIX Return a fixed 5-by-5 ICDR confusion matrix.
% Rows are true ICDR levels and columns are predicted ICDR levels.

rng(42);
validateInputs(trueLabels, predictedLabels);

trueLabels = double(trueLabels(:));
predictedLabels = double(predictedLabels(:));
matrix = zeros(5, 5);

for sample = 1:numel(trueLabels)
    trueLevel = trueLabels(sample) + 1;
    predictedLevel = predictedLabels(sample) + 1;
    matrix(trueLevel, predictedLevel) = matrix(trueLevel, predictedLevel) + 1;
end
end

function validateInputs(trueLabels, predictedLabels)
validateLabels(trueLabels, 'trueLabels');
validateLabels(predictedLabels, 'predictedLabels');

if numel(trueLabels) ~= numel(predictedLabels)
    error('evaluation:LabelLengthMismatch', ...
        'True labels and predicted labels must have the same number of elements.');
end
end

function validateLabels(labels, labelName)
if isempty(labels)
    error('evaluation:EmptyInput', ...
        '%s must be a non-empty vector.', labelName);
end

if ~(isnumeric(labels) || islogical(labels)) || ~isvector(labels) || ...
        ~isreal(labels)
    error('evaluation:InvalidLabels', ...
        '%s must be a real numeric vector of integer ICDR levels 0 through 4.', ...
        labelName);
end

numericLabels = double(labels);
if any(~isfinite(numericLabels)) || any(numericLabels ~= fix(numericLabels)) || ...
        any(numericLabels < 0) || any(numericLabels > 4)
    error('evaluation:InvalidLabels', ...
        '%s must contain only integer ICDR levels 0 through 4.', labelName);
end
end
