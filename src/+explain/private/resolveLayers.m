function selection = resolveLayers(net, requestedFinal, requestedEarlier)
%RESOLVELAYERS Find valid convolutional layers in the loaded network graph.

if ~isprop(net, 'Layers')
    error('explain:InvalidNetwork', ...
        'The checkpoint network does not expose a layer graph.');
end
layers = net.Layers;
isConvolution = false(1, numel(layers));
names = strings(1, numel(layers));
for index = 1:numel(layers)
    names(index) = string(layers(index).Name);
    isConvolution(index) = isa(layers(index), ...
        'nnet.cnn.layer.Convolution2DLayer');
end
convolutionIndices = find(isConvolution);
if isempty(convolutionIndices)
    error('explain:NoConvolutionalLayer', ...
        'The loaded network has no valid 2-D convolutional layers.');
end

finalIndex = localSelectRequested(convolutionIndices, names, requestedFinal, ...
    'FinalLayer');
if isempty(finalIndex)
    finalIndex = convolutionIndices(end);
end

earlierIndex = localSelectRequested(convolutionIndices, names, requestedEarlier, ...
    'EarlierLayer');
if isempty(earlierIndex)
    earlierIndex = localSelectEarlier(convolutionIndices, names, finalIndex);
end
if earlierIndex >= finalIndex
    error('explain:InvalidLayer', ...
        'EarlierLayer must occur before the final convolutional layer.');
end

selection = struct();
selection.finalLayerName = char(names(finalIndex));
selection.earlierLayerName = char(names(earlierIndex));
selection.finalLayerIndex = finalIndex;
selection.earlierLayerIndex = earlierIndex;
selection.validConvolutionalLayerNames = names(convolutionIndices);
end

function selectedIndex = localSelectRequested(indices, names, requested, description)
selectedIndex = [];
if isempty(requested)
    return;
end
matches = indices(strcmp(names(indices), string(requested)));
if isempty(matches)
    error('explain:InvalidLayer', ...
        '%s must name an existing convolutional layer in the loaded network: %s', ...
        description, requested);
end
selectedIndex = matches(1);
end

function selectedIndex = localSelectEarlier(indices, names, finalIndex)
% Prefer the nearest earlier ResNet stage, which has a finer spatial map.
finalName = char(names(finalIndex));
finalStage = localResNetStage(finalName);
earlierCandidates = indices(indices < finalIndex);
if isempty(earlierCandidates)
    error('explain:InvalidLayer', ...
        'The loaded network has no convolutional layer earlier than the final layer.');
end

if ~isnan(finalStage)
    candidateStages = nan(size(earlierCandidates));
    for index = 1:numel(earlierCandidates)
        candidateStages(index) = localResNetStage( ...
            char(names(earlierCandidates(index))));
    end
    stageMatches = earlierCandidates(candidateStages < finalStage);
    if ~isempty(stageMatches)
        selectedIndex = stageMatches(end);
        return;
    end
end

% Generic fallback for a valid graph whose layer names do not expose stages.
selectedIndex = earlierCandidates(end);
end

function stage = localResNetStage(name)
tokens = regexp(name, '^res([0-9]+)', 'tokens', 'once');
if isempty(tokens)
    stage = NaN;
else
    stage = str2double(tokens{1});
end
end
