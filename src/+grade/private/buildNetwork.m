function net = buildNetwork(config)
%BUILDNETWORK Load ImageNet ResNet-50 with the five-class output head.

net = imagePretrainedNetwork('resnet50', NumClasses=5, Weights='pretrained');
% ResNet-50 accepts variable spatial dimensions in dlnetwork forward passes.
% Keep the pretrained input layer intact so its ImageNet zero-center remains
% coupled to the ImageNet weights while common.preprocess owns resizing.
if config.modelConfig.inputSize(1) < 448
    error('grade:InvalidInputSize', 'The baseline input size must be at least 448.');
end

% ResNet-50 ships with no dropout anywhere. Against 2564 unique training
% images the run in results/20260823_162453 reached 0.065 training loss and
% 0.644 validation loss by epoch 10 - it was memorising, not learning.
% Dropout sits between the pooled features and the head so it regularises
% the classifier without disturbing the pretrained convolutional stack.
% fc1000 stays the last learnable layer, which is what
% freezeBackboneGradients keys on during warmup.
dropoutProbability = config.grading.dropout;
if dropoutProbability > 0
    net = addLayers(net, dropoutLayer(dropoutProbability, Name='head_dropout'));
    net = disconnectLayers(net, 'avg_pool', 'fc1000');
    net = connectLayers(net, 'avg_pool', 'head_dropout');
    net = connectLayers(net, 'head_dropout', 'fc1000');
    net = initialize(net);
end
end
