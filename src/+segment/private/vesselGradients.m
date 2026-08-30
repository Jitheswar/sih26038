function [loss, gradients, state, diceScore] = vesselGradients(net, ...
    input, targets, lossOptions)
%VESSELGRADIENTS One forward and backward pass over a vessel patch batch.
%   [LOSS, GRADIENTS, STATE, DICESCORE] = vesselGradients(NET, INPUT,
%   TARGETS, LOSSOPTIONS) is the dlfeval entry point for training.
%
%   STATE is returned and must be written back to NET.State by the caller.
%   Dropping it leaves the batch normalisation running statistics at their
%   initial values, so the network trains normally under forward(...) and
%   then collapses under predict(...) at inference, with nothing in the
%   training log to indicate it.  This repository has already paid for that
%   lesson twice, in commit 08a9b9a on the grading path and again on the
%   lesion path.

[logits, state] = forward(net, input);
[loss, diceScore] = segment.vesselLoss(logits, targets, lossOptions);
gradients = dlgradient(loss, net.Learnables);
end
