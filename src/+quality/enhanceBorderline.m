function outputImage = enhanceBorderline(inputImage, mask, config)
%ENHANCEBORDERLINE Normalize illumination, apply CLAHE, and denoise safely.
%   Enhancement is deterministic and is intended for borderline captures
%   only.  Pixels outside MASK remain exactly black/background pixels.

if nargin < 3
    config = [];
end
if nargin < 2 || isempty(mask)
    [mask, ~] = quality.fovMask(inputImage, config);
end
config = configuration(config);
[unitImage, originalClass] = toUnitDouble(inputImage);
mask = logical(mask);
if ~isequal(size(mask), size(unitImage(:, :, 1)))
    error('quality:InvalidMask', 'The FOV mask must match the image height and width.');
end

output = unitImage;
if ~any(mask(:))
    outputImage = fromUnitDouble(output, originalClass);
    return;
end

green = localGreen(output);
background = imgaussfilt(green, config.illuminationSigma);
backgroundMean = mean(background(mask));
normalizedGreen = green - background + backgroundMean;
normalizedGreen = min(max(normalizedGreen, 0), 1);

% CLAHE is contrast-limited to avoid turning sensor noise into lesions.
if config.claheEnabled && min(size(normalizedGreen)) >= 8
    enhancedGreen = adapthisteq(normalizedGreen, ...
        'NumTiles', [8, 8], 'ClipLimit', 0.01, 'Distribution', 'rayleigh');
else
    enhancedGreen = normalizedGreen;
end

if size(output, 3) == 1
    output(:, :, 1) = enhancedGreen;
else
    output(:, :, 2) = enhancedGreen;
end

% Non-local means is conservative and deterministic.  The small-image
% fallback keeps the same intent for synthetic unit-test images.
if min(size(output, [1, 2])) >= 10 && exist('imnlmfilt', 'file') == 2
    if size(output, 3) == 1
        output = imnlmfilt(output, 'DegreeOfSmoothing', config.denoiseDegree);
    else
        for channel = 1:size(output, 3)
            output(:, :, channel) = imnlmfilt( ...
                output(:, :, channel), 'DegreeOfSmoothing', config.denoiseDegree);
        end
    end
else
    for channel = 1:size(output, 3)
        output(:, :, channel) = imgaussfilt(output(:, :, channel), 0.35);
    end
end

% Do not manufacture information in the black surround.
outsideMask = ~mask;
for channel = 1:size(output, 3)
    originalChannel = unitImage(:, :, channel);
    enhancedChannel = output(:, :, channel);
    enhancedChannel(outsideMask) = originalChannel(outsideMask);
    output(:, :, channel) = min(max(enhancedChannel, 0), 1);
end
outputImage = fromUnitDouble(output, originalClass);
end

function green = localGreen(image)
if size(image, 3) == 1
    green = image(:, :, 1);
else
    green = image(:, :, 2);
end
end
