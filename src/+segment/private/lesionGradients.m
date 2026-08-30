function [loss, gradients, state, tverskyPerType] = lesionGradients(net, ...
    input, targets, lossOptions)
%LESIONGRADIENTS One forward and backward pass over a lesion patch batch.
%   [LOSS, GRADIENTS, STATE, TVERSKYPERTYPE] = lesionGradients(NET, INPUT,
%   TARGETS, LOSSOPTIONS) is the dlfeval entry point for training.
%
%   STATE is returned and must be written back to NET.State by the caller.
%   Dropping it leaves the batch normalisation running statistics at their
%   initial values, so the network trains normally under forward(...) and
%   then collapses under predict(...) at inference, with nothing in the
%   training log to indicate it.  This repository has already paid for that
%   lesson once, in commit 08a9b9a on the grading path.

[logits, state] = forward(net, input);
[loss, tverskyPerType] = segment.lesionLoss(logits, targets, lossOptions);
gradients = dlgradient(loss, net.Learnables);
end
