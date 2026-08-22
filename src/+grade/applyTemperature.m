function [probabilities, scaledLogits] = applyTemperature(logits, temperature)
%APPLYTEMPERATURE Convert logits to probabilities with temperature scaling.
%   PROBABILITIES = grade.applyTemperature(LOGITS, T) divides each sample's
%   logits by the positive scalar T and applies a numerically stable softmax.
%   LOGITS are arranged as classes-by-samples.

if ~isnumeric(logits) || isempty(logits) || ndims(logits) ~= 2
    error('grade:InvalidLogits', ...
        'Logits must be a non-empty numeric two-dimensional array.');
end
if any(~isfinite(logits(:)))
    error('grade:InvalidLogits', 'Logits must contain only finite values.');
end
if ~isnumeric(temperature) || ~isscalar(temperature) || ...
        ~isfinite(temperature) || temperature <= 0
    error('grade:InvalidTemperature', ...
        'Temperature must be a finite positive scalar.');
end
if size(logits, 1) < 2
    error('grade:InvalidLogits', ...
        'Logits must contain at least two output classes.');
end

if temperature == 1
    scaledLogits = logits;
else
    scaledLogits = logits ./ temperature;
end
shiftedLogits = scaledLogits - max(scaledLogits, [], 1);
unnormalized = exp(shiftedLogits);
probabilities = unnormalized ./ sum(unnormalized, 1);
end
