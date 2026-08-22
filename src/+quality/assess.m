function [qualityResult, processedImage] = assess(image, config)
%ASSESS Assess one fundus image and optionally enhance a borderline capture.
%   [QUALITYRESULT, PROCESSEDIMAGE] = quality.assess(IMAGE, CONFIG) is the
%   only public quality-gate entry point used by downstream inference.

% Seeding is the entry point's responsibility; this helper is deterministic.
if nargin < 2
    config = [];
end
config = configuration(config);

[mask, fovInfo] = quality.fovMask(image, config);
fovInfo.mask = mask;
features = quality.qualityFeatures(image, mask, config);
[qualityClass, classifierDiagnostics] = quality.classifyQuality( ...
    features, config, fovInfo);

processedImage = image;
isEnhanced = false;
if strcmp(qualityClass, 'borderline') && config.enhancementEnabled
    processedImage = quality.enhanceBorderline(image, mask, config);
    isEnhanced = true;
end

if strcmp(qualityClass, 'gradable')
    advice = {};
    adviceDetails = struct('dominantFailure', '', ...
        'boundaryBrightFraction', fovInfo.boundaryBrightFraction, 'reasons', {{}});
else
    [advice, adviceDetails] = quality.recaptureAdvice( ...
        image, features, fovInfo, config);
end

qualityResult = struct();
qualityResult.class = qualityClass;
qualityResult.qualityClass = qualityClass;
qualityResult.fovMask = mask;
qualityResult.fovInfo = fovInfo;
qualityResult.features = features;
qualityResult.advice = advice;
qualityResult.recaptureAdvice = advice;
qualityResult.adviceDetails = adviceDetails;
qualityResult.classifierDiagnostics = classifierDiagnostics;
qualityResult.isEnhanced = isEnhanced;
end
