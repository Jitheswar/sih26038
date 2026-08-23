function [loss, gradients, state] = modelGradients(net, images, targets, classWeights)
%MODELGRADIENTS Forward pass, differentiable weighted loss, updated state.
%   The third output carries the batch normalization running statistics
%   that FORWARD recomputes from this mini-batch. ResNet-50 has 53 batch
%   normalization layers, so NET.STATE holds 106 running mean/variance
%   entries. FORWARD uses mini-batch statistics; PREDICT, which
%   evaluateNetwork uses to score validation, uses NET.STATE instead.
%   The caller must assign this output back to NET.STATE - otherwise the
%   running statistics stay at their ImageNet values while the weights
%   fine-tune away from them, and validation is scored against statistics
%   that no longer describe the network's own activations.

[scores, state] = forward(net, images);
loss = weightedLoss(scores, targets, classWeights);
gradients = dlgradient(loss, net.Learnables);
end
