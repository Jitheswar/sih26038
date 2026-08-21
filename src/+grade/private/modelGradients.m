function [loss, gradients] = modelGradients(net, images, targets, classWeights)
%MODELGRADIENTS Forward pass and differentiable weighted loss.

scores = forward(net, images);
loss = weightedLoss(scores, targets, classWeights);
gradients = dlgradient(loss, net.Learnables);
end
