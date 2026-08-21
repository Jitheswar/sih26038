function features = qualityFeatures(inputImage, mask, config)
%QUALITYFEATURES Compute the §5.2 quality metrics inside the FOV only.
%   The focus, exposure, contrast, entropy, illumination, and FOV-area
%   values are all derived from MASK.  Pixels outside MASK never enter a
%   feature statistic.

rng(42, 'twister');
if nargin < 3
    config = [];
end
if nargin < 2 || isempty(mask)
    [mask, ~] = quality.fovMask(inputImage, config);
end
config = configuration(config);
[unitImage, ~] = toUnitDouble(inputImage);
gray = localGray(unitImage);
green = localGreen(unitImage);

if ~isequal(size(mask), size(gray))
    error('quality:InvalidMask', 'The FOV mask must match the image height and width.');
end
mask = logical(mask);

features = struct();
features.varianceOfLaplacian = NaN;
features.laplacianVariance = NaN;
features.tenengrad = NaN;
features.tenengradScore = NaN;
features.meanIntensity = NaN;
features.darkPixelFraction = NaN;
features.saturatedPixelFraction = NaN;
features.rmsContrast = NaN;
features.entropy = NaN;
features.quadrantIlluminationVariation = NaN;
features.fovAreaRatio = nnz(mask) / numel(mask);
features.quadrantMeans = [NaN, NaN, NaN, NaN];
features.pixelCount = nnz(mask);

if ~any(mask(:))
    return;
end

metricMask = mask;
erodedMask = imerode(mask, strel('disk', 2, 0));
if any(erodedMask(:))
    metricMask = erodedMask;
end

laplacianKernel = [0, 1, 0; 1, -4, 1; 0, 1, 0];
laplacian = imfilter(green, laplacianKernel, 'replicate', 'conv');
laplacianValues = laplacian(metricMask);
features.varianceOfLaplacian = localVariance(laplacianValues);
features.laplacianVariance = features.varianceOfLaplacian;

[gradientX, gradientY] = imgradientxy(green, 'sobel');
tenengradValues = gradientX(metricMask) .^ 2 + gradientY(metricMask) .^ 2;
features.tenengrad = sum(tenengradValues);
features.tenengradScore = features.tenengrad;

values = green(mask);
features.meanIntensity = mean(values);
features.darkPixelFraction = mean(values <= config.darkPixelThreshold);
features.saturatedPixelFraction = mean(values >= config.saturationThreshold);
features.rmsContrast = sqrt(mean((values - features.meanIntensity) .^ 2));
features.entropy = localEntropy(values);

background = imgaussfilt(green, config.illuminationSigma);
height = size(green, 1);
width = size(green, 2);
rowMidpoint = floor(height / 2);
columnMidpoint = floor(width / 2);
quadrantMasks = { ...
    mask & localRectangleMask(height, width, 1, rowMidpoint, 1, columnMidpoint), ...
    mask & localRectangleMask(height, width, 1, rowMidpoint, columnMidpoint + 1, width), ...
    mask & localRectangleMask(height, width, rowMidpoint + 1, height, 1, columnMidpoint), ...
    mask & localRectangleMask(height, width, rowMidpoint + 1, height, columnMidpoint + 1, width)};
for index = 1:4
    quadrantValues = background(quadrantMasks{index});
    if ~isempty(quadrantValues)
        features.quadrantMeans(index) = mean(quadrantValues);
    end
end
validMeans = features.quadrantMeans(isfinite(features.quadrantMeans));
if ~isempty(validMeans)
    features.quadrantIlluminationVariation = std(validMeans, 1) / max(mean(validMeans), eps);
end
end

function gray = localGray(image)
if size(image, 3) == 1
    gray = image(:, :, 1);
else
    gray = im2gray(image);
end
end

function green = localGreen(image)
if size(image, 3) == 1
    green = image(:, :, 1);
else
    green = image(:, :, 2);
end
end

function result = localVariance(values)
if isempty(values)
    result = NaN;
else
    meanValue = mean(values);
    result = mean((values - meanValue) .^ 2);
end
end

function value = localEntropy(values)
counts = histcounts(values, 256, 'BinLimits', [0, 1]);
probabilities = counts / max(sum(counts), 1);
probabilities = probabilities(probabilities > 0);
value = -sum(probabilities .* log2(probabilities));
end

function rectangle = localRectangleMask(height, width, firstRow, lastRow, firstColumn, lastColumn)
rectangle = false(height, width);
if firstRow <= lastRow && firstColumn <= lastColumn
    rectangle(firstRow:lastRow, firstColumn:lastColumn) = true;
end
end
