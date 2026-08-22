function [advice, details] = recaptureAdvice(varargin)
%RECAPTUREADVICE Map quality failures to actionable operator feedback.
%   Supported forms are RECAPTUREADVICE(FEATURES) and
%   RECAPTUREADVICE(IMAGE, FEATURES, FOVINFO, CONFIG).  Advice is a cell
%   array of messages so multiple independent capture problems are visible.

[image, features, fovInfo, config] = localArguments(varargin{:});

advice = {};
details = struct('dominantFailure', '', 'boundaryBrightFraction', NaN, 'reasons', {{}});

if ~isstruct(features)
    error('quality:InvalidFeatures', 'Features must be a scalar feature struct.');
end

meanIntensity = localValue(features, 'meanIntensity', NaN);
focusScale = max(meanIntensity ^ 2, 0.01);
normalizedLaplacian = localValue(features, 'varianceOfLaplacian', Inf) / focusScale;
normalizedTenengrad = localValue(features, 'tenengrad', Inf) / focusScale;
if isfinite(meanIntensity) && meanIntensity >= config.meanDarkBorderline && ...
        (normalizedLaplacian < config.laplacianBorderline || ...
        normalizedTenengrad < config.tenengradBorderline)
    advice{end + 1} = 'Image out of focus'; %#ok<AGROW>
    details.reasons{end + 1} = 'focus'; %#ok<AGROW>
end
if localValue(features, 'meanIntensity', Inf) < config.meanDarkBorderline || ...
        localValue(features, 'darkPixelFraction', 0) >= config.darkFractionBorderline
    advice{end + 1} = 'Image too dark'; %#ok<AGROW>
    details.reasons{end + 1} = 'dark exposure'; %#ok<AGROW>
end
if localValue(features, 'saturatedPixelFraction', 0) >= config.saturatedFractionBorderline
    advice{end + 1} = 'Image over-exposed'; %#ok<AGROW>
    details.reasons{end + 1} = 'saturated exposure'; %#ok<AGROW>
end
if localValue(features, 'quadrantIlluminationVariation', 0) >= config.illuminationCvBorderline
    advice{end + 1} = 'Uneven lighting'; %#ok<AGROW>
    details.reasons{end + 1} = 'quadrant illumination'; %#ok<AGROW>
end

offCentre = false;
if isfield(fovInfo, 'centerOffset') && isfinite(fovInfo.centerOffset)
    offCentre = fovInfo.centerOffset > config.centerOffsetLimit;
elseif localValue(features, 'fovAreaRatio', 0) < config.fovAreaBorderline
    offCentre = true;
end
if offCentre
    advice{end + 1} = 'Field of view not centred'; %#ok<AGROW>
    details.reasons{end + 1} = 'FOV position'; %#ok<AGROW>
end

if ~isempty(image) && isfield(fovInfo, 'mask')
    unitImage = toUnitDouble(image);
    gray = localGray(unitImage);
    ring = fovInfo.mask & ~imerode(fovInfo.mask, strel('disk', 1, 0));
    if any(ring(:))
        details.boundaryBrightFraction = mean(gray(ring) >= 0.92);
        if details.boundaryBrightFraction >= 0.25 && ...
                localValue(features, 'saturatedPixelFraction', 0) < 0.5
            advice{end + 1} = 'Lens flare or eyelash artifact'; %#ok<AGROW>
            details.reasons{end + 1} = 'bright boundary artifact'; %#ok<AGROW>
        end
    end
end

if ~isempty(advice)
    details.dominantFailure = advice{1};
end
end

function [image, features, fovInfo, config] = localArguments(varargin)
image = [];
features = [];
fovInfo = struct();
config = configuration();
if nargin == 1
    features = varargin{1};
elseif nargin >= 2
    image = varargin{1};
    features = varargin{2};
    if nargin >= 3 && ~isempty(varargin{3})
        fovInfo = varargin{3};
    end
    if nargin >= 4
        config = configuration(varargin{4});
    end
else
    error('quality:InvalidAdviceArguments', 'Features are required.');
end
end

function value = localValue(features, name, fallback)
if isfield(features, name) && isscalar(features.(name))
    value = double(features.(name));
else
    value = fallback;
end
end

function gray = localGray(image)
if size(image, 3) == 1
    gray = image(:, :, 1);
else
    gray = im2gray(image);
end
end
