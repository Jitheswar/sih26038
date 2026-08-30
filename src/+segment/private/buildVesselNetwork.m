function net = buildVesselNetwork(config)
%BUILDVESSELNETWORK Build the DRIVE vessel segmentation U-Net.
%   NET = buildVesselNetwork(CONFIG) returns an untrained dlnetwork with a
%   single-channel input and a single-channel output.
%
%   One input channel, not three: §6.3 specifies the green channel, and
%   segment.vesselPreprocess is what reduces a frame to it.
%
%   The head emits logits, not probabilities.  Sigmoid is applied inside the
%   loss in its numerically stable form and once more explicitly at
%   inference, so a saved checkpoint cannot be read as if it were already
%   calibrated.  This mirrors buildLesionNetwork for the same reason.

vessel = config.vessel_segmentation;
patchSize = vessel.patch_size;
depth = vessel.encoder_depth;
baseFilters = vessel.base_filters;

layers = imageInputLayer([patchSize, patchSize, 1], ...
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
        'Stride', 2, 'Name', upName, 'WeightsInitializer', 'he'));
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

graph = addLayers(graph, convolution2dLayer(1, 1, ...
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
    reluLayer('Name', sprintf('%s_relu2', blockName))
    ];

graph = addLayers(graph, block);
graph = connectLayers(graph, inputName, sprintf('%s_conv1', blockName));
end
