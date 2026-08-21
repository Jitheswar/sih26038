function [qualityClass, diagnostics] = classifyQuality(features, config, fovInfo)
%CLASSIFYQUALITY Apply the documented first-version rule-based quality gate.
%   Thresholds are deliberately explicit until hand-labelled quality data
%   exists.  Severe focus, exposure, illumination, contrast, or FOV failures
%   are ungradable.  Lesser failures are borderline and are enhanced once.

rng(42, 'twister');
if nargin < 2
    config = [];
end
if nargin < 3
    fovInfo = struct();
end
config = configuration(config);
if ~isstruct(features) || ~isscalar(features)
    error('quality:InvalidFeatures', 'Features must be a scalar feature struct.');
end

hardFailures = {};
borderlineFailures = {};

if ~isfield(features, 'fovAreaRatio') || ~isfinite(features.fovAreaRatio)
    hardFailures{end + 1} = 'field of view not detected'; %#ok<AGROW>
elseif features.fovAreaRatio < config.minimumFovAreaRatio
    hardFailures{end + 1} = 'field of view is too small'; %#ok<AGROW>
elseif features.fovAreaRatio < config.fovAreaBorderline
    borderlineFailures{end + 1} = 'field of view is small'; %#ok<AGROW>
end

laplacian = localValue(features, 'varianceOfLaplacian', NaN);
tenengrad = localValue(features, 'tenengrad', NaN);
meanIntensity = localValue(features, 'meanIntensity', NaN);
focusScale = max(meanIntensity ^ 2, 0.01);
normalizedLaplacian = laplacian / focusScale;
normalizedTenengrad = tenengrad / focusScale;
focusUsable = isfinite(meanIntensity) && meanIntensity >= config.meanDarkBorderline;
if ~isfinite(laplacian) || ~isfinite(tenengrad) || ~isfinite(meanIntensity)
    hardFailures{end + 1} = 'focus is severely low'; %#ok<AGROW>
elseif focusUsable && (normalizedLaplacian < config.laplacianUngradable || ...
        normalizedTenengrad < config.tenengradUngradable)
    hardFailures{end + 1} = 'focus is severely low'; %#ok<AGROW>
elseif focusUsable && (normalizedLaplacian < config.laplacianBorderline || ...
        normalizedTenengrad < config.tenengradBorderline)
    borderlineFailures{end + 1} = 'focus is low'; %#ok<AGROW>
end

darkFraction = localValue(features, 'darkPixelFraction', NaN);
if ~isfinite(meanIntensity) || ~isfinite(darkFraction) || ...
        meanIntensity < config.meanDarkUngradable || darkFraction >= config.darkFractionUngradable
    hardFailures{end + 1} = 'exposure is severely dark'; %#ok<AGROW>
elseif meanIntensity < config.meanDarkBorderline || darkFraction >= config.darkFractionBorderline
    borderlineFailures{end + 1} = 'exposure is dark'; %#ok<AGROW>
end

saturatedFraction = localValue(features, 'saturatedPixelFraction', NaN);
if ~isfinite(saturatedFraction) || saturatedFraction >= config.saturatedFractionUngradable
    hardFailures{end + 1} = 'exposure is severely saturated'; %#ok<AGROW>
elseif saturatedFraction >= config.saturatedFractionBorderline
    borderlineFailures{end + 1} = 'exposure is saturated'; %#ok<AGROW>
end

rmsContrast = localValue(features, 'rmsContrast', NaN);
entropyValue = localValue(features, 'entropy', NaN);
if ~isfinite(rmsContrast) || ~isfinite(entropyValue) || ...
        (rmsContrast < config.rmsContrastUngradable && entropyValue < config.entropyUngradable)
    hardFailures{end + 1} = 'contrast and entropy are severely low'; %#ok<AGROW>
elseif rmsContrast < config.rmsContrastBorderline || entropyValue < config.entropyBorderline
    borderlineFailures{end + 1} = 'contrast or entropy is low'; %#ok<AGROW>
end

illumination = localValue(features, 'quadrantIlluminationVariation', NaN);
if ~isfinite(illumination) || illumination >= config.illuminationCvUngradable
    hardFailures{end + 1} = 'illumination is highly uneven'; %#ok<AGROW>
elseif illumination >= config.illuminationCvBorderline
    borderlineFailures{end + 1} = 'illumination is uneven'; %#ok<AGROW>
end

if isfield(fovInfo, 'centerOffset') && isfinite(fovInfo.centerOffset) && ...
        fovInfo.centerOffset > config.centerOffsetLimit
    borderlineFailures{end + 1} = 'field of view is off-centre'; %#ok<AGROW>
end

if ~isempty(hardFailures)
    qualityClass = 'ungradable';
elseif ~isempty(borderlineFailures)
    qualityClass = 'borderline';
else
    qualityClass = 'gradable';
end

diagnostics = struct();
diagnostics.hardFailures = hardFailures;
diagnostics.borderlineFailures = borderlineFailures;
diagnostics.normalizedLaplacian = normalizedLaplacian;
diagnostics.normalizedTenengrad = normalizedTenengrad;
diagnostics.thresholds = config;
end

function value = localValue(features, name, fallback)
if isfield(features, name)
    value = double(features.(name));
else
    value = fallback;
end
end
