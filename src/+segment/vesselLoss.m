function [loss, diceScore] = vesselLoss(logits, targets, lossOptions)
%VESSELLOSS Combined Dice and binary cross-entropy loss for vessel maps.
%   [LOSS, DICESCORE] = segment.vesselLoss(LOGITS, TARGETS, LOSSOPTIONS)
%   returns the training objective and the Dice score the Dice term is
%   built from, for logging.
%
%   Why this is not segment.lesionLoss.  The lesion path uses Tversky with
%   beta > alpha and refuses to start with a symmetric objective, because
%   lesion pixels are 0.1 to 1.0 per cent of a frame and an all-background
%   prediction scores excellently against a symmetric loss (§6.4).  Vessels
%   are the opposite regime: measured over the twenty annotated DRIVE
%   frames they cover 12.5 per cent of the field of view, a hundred times
%   the prevalence.  A recall-weighted objective there buys thickened
%   vessels and a worse specificity for no sensitivity that matters, and
%   §6.3 reports specificity as a headline number.  So the Dice term is
%   symmetric, and the cross-entropy term carries the per-pixel calibration
%   the Dice term alone does not.
%
%   LOSSOPTIONS.diceWeight mixes the two in [0, 1]: 1 is Dice alone, 0 is
%   cross-entropy alone.

if nargin < 3
    lossOptions = struct();
end
if ~isfield(lossOptions, 'diceWeight')
    lossOptions.diceWeight = 0.5;
end
diceWeight = lossOptions.diceWeight;

% Sigmoid in its numerically stable form.  The network head emits logits so
% that a saved checkpoint cannot be mistaken for calibrated probabilities.
probabilities = sigmoid(logits);

% Binary cross-entropy computed from the logits directly rather than from
% the probabilities, so a saturated logit does not become log(0).
%   max(z, 0) - z * y + log(1 + exp(-|z|))
crossEntropy = max(logits, 0) - logits .* targets + ...
    log(1 + exp(-abs(logits)));
crossEntropy = mean(crossEntropy, 'all');

% Dice over the whole batch rather than per patch.  A patch that happens to
% contain no vessel pixel has an undefined per-patch Dice, and averaging
% those makes the loss depend on how the sampler happened to draw.
smoothing = 1;
intersection = sum(probabilities .* targets, 'all');
total = sum(probabilities, 'all') + sum(targets, 'all');
diceScore = (2 * intersection + smoothing) / (total + smoothing);

loss = diceWeight * (1 - diceScore) + (1 - diceWeight) * crossEntropy;
end
