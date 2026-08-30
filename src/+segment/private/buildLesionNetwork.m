function net = buildLesionNetwork(config)
%BUILDLESIONNETWORK Build the multi-label lesion segmentation U-Net.
%   NET = buildLesionNetwork(CONFIG) returns an untrained dlnetwork with one
%   output channel per configured lesion type.
%
%   The head emits logits, not probabilities.  Sigmoid is applied inside the
%   loss in its numerically stable form and once more explicitly at
%   inference, so a saved checkpoint cannot be read as if it were already
%   calibrated.
%
%   The channels are independent sigmoids rather than a softmax over lesion
%   classes.  Softmax would assert the lesion types are mutually exclusive
%   at every pixel, and IDRiD graders do mark overlapping hard- and
%   soft-exudate regions; more importantly the reported metric is a
%   per-lesion-type AUPR (§6.4), which needs a per-type score that does not
%   move when a different type's score changes.

lesion = config.lesion_segmentation;
patchSize = lesion.patch_size;
depth = lesion.encoder_depth;
baseFilters = lesion.base_filters;
typeCount = numel(lesion.lesion_types);

layers = imageInputLayer([patchSize, patchSize, 3], ...
    'Name', 'input', 'Normalization', 'none');
graph = layerGraph(layers);

skipNames = strings(depth, 1);
previousName = 'input';
for level = 1:depth
    filters = baseFilters * 2 ^ (level - 1);
    blockName = sprintf('enc%d', level);
    graph = localAddConvBlock(graph, blockName, previousName, filters);
    skipNames(level) = string(sprintf('%s_relu2', blockName));

    poolName = sprintf('pool%d', level);
    graph = addLayers(graph, maxPooling2dLayer(2, 'Stride', 2, ...
        'Name', poolName));
    graph = connectLayers(graph, char(skipNames(level)), poolName);
    previousName = poolName;
end

bridgeFilters = baseFilters * 2 ^ depth;
graph = localAddConvBlock(graph, 'bridge', previousName, bridgeFilters);
previousName = 'bridge_relu2';

for level = depth:-1:1
    filters = baseFilters * 2 ^ (level - 1);
    upName = sprintf('up%d', level);
    graph = addLayers(graph, transposedConv2dLayer(2, filters, ...
        'Stride', 2, 'Name', upName, ...
        'WeightsInitializer', 'he'));
    graph = connectLayers(graph, previousName, upName);

    concatName = sprintf('concat%d', level);
    graph = addLayers(graph, concatenationLayer(3, 2, 'Name', concatName));
    graph = connectLayers(graph, upName, sprintf('%s/in1', concatName));
    graph = connectLayers(graph, char(skipNames(level)), ...
        sprintf('%s/in2', concatName));

    blockName = sprintf('dec%d', level);
    graph = localAddConvBlock(graph, blockName, concatName, filters);
    previousName = sprintf('%s_relu2', blockName);
end

graph = addLayers(graph, convolution2dLayer(1, typeCount, ...
    'Name', 'logits', 'Padding', 'same', 'WeightsInitializer', 'he'));
graph = connectLayers(graph, previousName, 'logits');

net = dlnetwork(graph);
end

function graph = localAddConvBlock(graph, blockName, inputName, filters)
%LOCALADDCONVBLOCK Two padded 3x3 convolutions with batch normalisation.
%   Padding is 'same' throughout so a skip connection always matches its
%   decoder stage exactly and no cropping is needed.

block = [
    convolution2dLayer(3, filters, 'Padding', 'same', ...
        'Name', sprintf('%s_conv1', blockName), 'WeightsInitializer', 'he')
    batchNormalizationLayer('Name', sprintf('%s_bn1', blockName))
    reluLayer('Name', sprintf('%s_relu1', blockName))
    convolution2dLayer(3, filters, 'Padding', 'same', ...
        'Name', sprintf('%s_conv2', blockName), 'WeightsInitializer', 'he')
    batchNormalizationLayer('Name', sprintf('%s_bn2', blockName))
    reluLayer('Name', sprintf('%s_relu2', blockName))];
graph = addLayers(graph, block);
graph = connectLayers(graph, inputName, sprintf('%s_conv1', blockName));
end
