function net = buildNetwork(config)
%BUILDNETWORK Load ImageNet ResNet-50 with the five-class output head.

net = imagePretrainedNetwork('resnet50', NumClasses=5, Weights='pretrained');
% ResNet-50 accepts variable spatial dimensions in dlnetwork forward passes.
% Keep the pretrained input layer intact so its ImageNet zero-center remains
% coupled to the ImageNet weights while common.preprocess owns resizing.
if config.modelConfig.inputSize(1) < 448
    error('grade:InvalidInputSize', 'The baseline input size must be at least 448.');
end
end
