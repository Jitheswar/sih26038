function [loss, tverskyPerType] = lesionLoss(logits, targets, options)
%LESIONLOSS Recall-weighted Tversky plus focal cross-entropy, per lesion type.
%   [LOSS, TVERSKYPERTYPE] = lesionLoss(LOGITS, TARGETS, OPTIONS) scores an
%   SSCB batch of logits against logical targets of the same shape.
%
%   Two terms, for two different failure modes:
%
%   The Tversky term is a set-overlap score with false negatives weighted
%   above false positives (beta > alpha).  §6.4 requires it: lesion pixels
%   are 0.1 to 1.0 per cent of a frame, and a symmetric objective reaches an
%   excellent value by predicting all background.  It is aggregated over the
%   whole batch per channel rather than per sample, because a background
%   patch contains no positives of any type and its per-sample Tversky index
%   would be a constant zero that carries no gradient direction.
%
%   The focal cross-entropy term supplies the per-pixel gradient the Tversky
%   term lacks while its overlap is still near zero, and its (1 - p_t)^gamma
%   factor stops the enormous easy background from drowning the lesion
%   pixels.
%
%   Both are computed from logits in numerically stable form.  Taking
%   log(sigmoid(z)) directly underflows to -Inf for the strongly negative
%   logits that a 99-per-cent-background problem produces within a few
%   hundred iterations.

alpha = options.alpha;
beta = options.beta;
gamma = options.gamma;
smooth = 1;

targets = single(targets);
probabilities = sigmoid(logits);

% Sum over spatial and batch dimensions, leaving one value per lesion type.
truePositive = sum(probabilities .* targets, [1, 2, 4]);
falsePositive = sum(probabilities .* (1 - targets), [1, 2, 4]);
falseNegative = sum((1 - probabilities) .* targets, [1, 2, 4]);

tverskyPerType = (truePositive + smooth) ./ ...
    (truePositive + alpha * falsePositive + beta * falseNegative + smooth);
tverskyLoss = mean(1 - tverskyPerType);

% Stable binary cross-entropy from logits:
%   max(z, 0) - z * g + log(1 + exp(-|z|))
crossEntropy = max(logits, 0) - logits .* targets + ...
    log(1 + exp(-abs(logits)));
probabilityOfTarget = probabilities .* targets + ...
    (1 - probabilities) .* (1 - targets);
focalWeight = (1 - probabilityOfTarget) .^ gamma;
focalLoss = mean(focalWeight .* crossEntropy, 'all');

loss = tverskyLoss + focalLoss;
end
