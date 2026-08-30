function [config, configText, projectRoot] = lesionConfiguration(inputConfig)
%LESIONCONFIGURATION Load and validate the lesion segmentation configuration.
%   [CONFIG, CONFIGTEXT, PROJECTROOT] = lesionConfiguration(INPUT) accepts a
%   JSON filename or a scalar structure and fills in every default the
%   lesion segmentation entry points rely on.
%
%   Every knob below is read from config/*.json rather than typed into the
%   code, because the ablation study switches stages on and off from config
%   alone (§11.6, §13.3).

thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(fileparts(fileparts(thisFile))));

if ischar(inputConfig) || (isstring(inputConfig) && isscalar(inputConfig))
    configFile = char(inputConfig);
    if ~isfile(configFile)
        error('segment:MissingConfig', ...
            'Configuration file does not exist: %s', configFile);
    end
    configText = fileread(configFile);
    try
        config = jsondecode(configText);
    catch exception
        error('segment:InvalidConfig', ...
            'Configuration file could not be decoded: %s', exception.message);
    end
elseif isstruct(inputConfig) && isscalar(inputConfig)
    config = inputConfig;
    configText = jsonencode(config);
else
    error('segment:InvalidConfig', ...
        'The lesion configuration must be a JSON filename or scalar structure.');
end

if ~isfield(config, 'lesion_segmentation') || ...
        ~isstruct(config.lesion_segmentation)
    config.lesion_segmentation = struct();
end
lesion = config.lesion_segmentation;

lesion = localDefault(lesion, 'enabled', true);
localRequireLogical(lesion.enabled, 'lesion_segmentation.enabled');

% MA is kept in the trained set even though §6.4 predicts it will be the
% weakest head. Dropping it would leave the classical Track A detector as
% the only microaneurysm source and remove the head-to-head comparison that
% §11.7 measures.
lesion = localDefault(lesion, 'lesion_types', {'MA'; 'HE'; 'EX'; 'SE'});
lesionTypes = localNormaliseTypes(lesion.lesion_types);
lesion.lesion_types = lesionTypes;

% Native-resolution crops. §6.4 makes this non-negotiable: the IDRiD frame
% is 2848x4288 and downsampling it to fit a whole image on the GPU removes
% the microaneurysms the patch is supposed to teach.
lesion = localDefault(lesion, 'patch_size', 512);
patchSize = double(lesion.patch_size);
if ~isscalar(patchSize) || ~isfinite(patchSize) || patchSize < 64 || ...
        patchSize ~= floor(patchSize) || mod(patchSize, 16) ~= 0
    error('segment:InvalidPatchSize', ...
        ['lesion_segmentation.patch_size must be an integer multiple of 16 ' ...
        'and at least 64, so four rounds of downsampling stay exact.']);
end
lesion.patch_size = patchSize;

lesion = localDefault(lesion, 'patches_per_image', 24);
lesion.patches_per_image = localPositiveInteger( ...
    lesion.patches_per_image, 'lesion_segmentation.patches_per_image');

% Random 512x512 crops from a fundus frame are almost all lesion-free
% (§6.4), so a uniform sampler trains almost entirely on background.
lesion = localDefault(lesion, 'lesion_patch_fraction', 0.75);
lesionFraction = double(lesion.lesion_patch_fraction);
if ~isscalar(lesionFraction) || ~isfinite(lesionFraction) || ...
        lesionFraction < 0 || lesionFraction > 1
    error('segment:InvalidLesionFraction', ...
        'lesion_segmentation.lesion_patch_fraction must lie in [0, 1].');
end
lesion.lesion_patch_fraction = lesionFraction;

% Under VRAM pressure reduce this, never patch_size (§7.1 applied to
% patches): a smaller patch destroys the evidence, a smaller batch does not.
lesion = localDefault(lesion, 'batch_size', 4);
lesion.batch_size = localPositiveInteger(lesion.batch_size, ...
    'lesion_segmentation.batch_size');

% Patches are pooled across this many frames before batches are drawn, so a
% batch mixes frames instead of holding one frame's illumination and camera
% throughout, which batch normalisation would otherwise read as the
% statistics of the whole distribution.
lesion = localDefault(lesion, 'shuffle_buffer_images', 8);
lesion.shuffle_buffer_images = localPositiveInteger( ...
    lesion.shuffle_buffer_images, 'lesion_segmentation.shuffle_buffer_images');

% The field-of-view mask only decides whether a candidate patch centre sits
% inside the camera aperture, which is a decision at millimetre scale, so it
% is computed on a downsampled frame.  quality.fovMask runs imfill and
% bwareafilt, and at the full 2848x4288 that costs about a second per frame,
% which at 43 frames an epoch would exceed the time spent training on them.
lesion = localDefault(lesion, 'fov_downsample', 8);
lesion.fov_downsample = localPositiveInteger(lesion.fov_downsample, ...
    'lesion_segmentation.fov_downsample');

lesion = localDefault(lesion, 'max_epochs', 40);
lesion.max_epochs = localPositiveInteger(lesion.max_epochs, ...
    'lesion_segmentation.max_epochs');

lesion = localDefault(lesion, 'learning_rate', 1e-3);
learningRate = double(lesion.learning_rate);
if ~isscalar(learningRate) || ~isfinite(learningRate) || learningRate <= 0
    error('segment:InvalidLearningRate', ...
        'lesion_segmentation.learning_rate must be a positive scalar.');
end
lesion.learning_rate = learningRate;

lesion = localDefault(lesion, 'base_filters', 32);
lesion.base_filters = localPositiveInteger(lesion.base_filters, ...
    'lesion_segmentation.base_filters');

lesion = localDefault(lesion, 'encoder_depth', 4);
encoderDepth = localPositiveInteger(lesion.encoder_depth, ...
    'lesion_segmentation.encoder_depth');
if encoderDepth > 5
    error('segment:InvalidEncoderDepth', ...
        'lesion_segmentation.encoder_depth above 5 is not supported.');
end
if mod(patchSize, 2 ^ encoderDepth) ~= 0
    error('segment:InvalidEncoderDepth', ...
        ['lesion_segmentation.patch_size (%d) must divide by 2^encoder_depth ' ...
        '(%d) so each skip connection matches its decoder stage.'], ...
        patchSize, 2 ^ encoderDepth);
end
lesion.encoder_depth = encoderDepth;

% Tversky with beta > alpha weights false negatives above false positives.
% §6.4 requires this: with lesion pixels at 0.1-1.0 per cent of the frame,
% a symmetric loss reaches an excellent value by predicting all background.
lesion = localDefault(lesion, 'tversky_alpha', 0.3);
lesion = localDefault(lesion, 'tversky_beta', 0.7);
alpha = double(lesion.tversky_alpha);
beta = double(lesion.tversky_beta);
if ~isscalar(alpha) || ~isfinite(alpha) || alpha < 0 || ...
        ~isscalar(beta) || ~isfinite(beta) || beta < 0 || (alpha + beta) == 0
    error('segment:InvalidTversky', ...
        ['lesion_segmentation.tversky_alpha and tversky_beta must be ' ...
        'non-negative and not both zero.']);
end
if beta < alpha
    error('segment:InvalidTversky', ...
        ['lesion_segmentation.tversky_beta must be at least tversky_alpha; ' ...
        'the design requires a recall-weighted loss (§6.4).']);
end
lesion.tversky_alpha = alpha;
lesion.tversky_beta = beta;

lesion = localDefault(lesion, 'focal_gamma', 1.0);
focalGamma = double(lesion.focal_gamma);
if ~isscalar(focalGamma) || ~isfinite(focalGamma) || focalGamma <= 0
    error('segment:InvalidFocalGamma', ...
        'lesion_segmentation.focal_gamma must be a positive scalar.');
end
lesion.focal_gamma = focalGamma;

lesion = localDefault(lesion, 'early_stopping_patience', 8);
patience = double(lesion.early_stopping_patience);
if ~isscalar(patience) || ~isfinite(patience) || patience < 0 || ...
        patience ~= floor(patience)
    error('segment:InvalidPatience', ...
        ['lesion_segmentation.early_stopping_patience must be a ' ...
        'non-negative integer.']);
end
lesion.early_stopping_patience = patience;

% 33 equally spaced levels is the IDRiD sub-challenge 1 protocol (§6.4).
% Changing it makes the AUPR incomparable to the published benchmark.
lesion = localDefault(lesion, 'aupr_thresholds', 33);
lesion.aupr_thresholds = localPositiveInteger(lesion.aupr_thresholds, ...
    'lesion_segmentation.aupr_thresholds');
if lesion.aupr_thresholds < 2
    error('segment:InvalidThresholds', ...
        'lesion_segmentation.aupr_thresholds must be at least 2.');
end

lesion = localDefault(lesion, 'tile_overlap', 64);
tileOverlap = double(lesion.tile_overlap);
if ~isscalar(tileOverlap) || ~isfinite(tileOverlap) || tileOverlap < 0 || ...
        tileOverlap ~= floor(tileOverlap) || tileOverlap >= patchSize / 2
    error('segment:InvalidTileOverlap', ...
        ['lesion_segmentation.tile_overlap must be a non-negative integer ' ...
        'below half the patch size.']);
end
lesion.tile_overlap = tileOverlap;

% Scale normalisation.  The network learns lesions at the pixel scale of the
% frames it trained on, and IDRiD is one camera at one protocol: measured
% over Set-A the illuminated field is 3279 pixels across, varying by three
% pixels across the whole set.  APTOS is not one camera - measured over a
% sample its field ranges from 1055 to 2555 pixels - so the same lesion
% covers between a third and four fifths as many pixels there.  Presenting
% that to the network unchanged asks it to find objects at a scale it never
% saw.  Each frame is therefore resampled so its field diameter matches the
% training reference before tiling, and the maps are mapped back afterwards.
%
% For IDRiD frames the factor is 1.00 and this is a no-op, so the Set-B
% benchmark number is unaffected by it.
lesion = localDefault(lesion, 'scale_normalisation', true);
localRequireLogical(lesion.scale_normalisation, ...
    'lesion_segmentation.scale_normalisation');
lesion = localDefault(lesion, 'reference_fov_diameter', 3279);
referenceDiameter = double(lesion.reference_fov_diameter);
if ~isscalar(referenceDiameter) || ~isfinite(referenceDiameter) || ...
        referenceDiameter <= 0
    error('segment:InvalidReferenceDiameter', ...
        'lesion_segmentation.reference_fov_diameter must be positive.');
end
lesion.reference_fov_diameter = referenceDiameter;

% Clamp the resampling factor. A frame whose field cannot be measured (a
% blank or grossly over-exposed capture) would otherwise produce an
% arbitrary factor and a resize to an absurd size.
lesion = localDefault(lesion, 'scale_limits', [0.25, 4]);
scaleLimits = double(lesion.scale_limits(:))';
if numel(scaleLimits) ~= 2 || any(~isfinite(scaleLimits)) || ...
        scaleLimits(1) <= 0 || scaleLimits(1) > scaleLimits(2)
    error('segment:InvalidScaleLimits', ...
        'lesion_segmentation.scale_limits must be [low high] with 0 < low <= high.');
end
lesion.scale_limits = scaleLimits;

lesion = localDefault(lesion, 'seed', 42);
if lesion.seed ~= 42
    error('segment:InvalidSeed', ...
        'The lesion segmentation entry point requires rng(42) (§13.2).');
end

lesion = localDefault(lesion, 'smoke_epochs', 1);
lesion.smoke_epochs = localPositiveInteger(lesion.smoke_epochs, ...
    'lesion_segmentation.smoke_epochs');
lesion = localDefault(lesion, 'smoke_images', 2);
lesion.smoke_images = localPositiveInteger(lesion.smoke_images, ...
    'lesion_segmentation.smoke_images');
lesion = localDefault(lesion, 'smoke_patches_per_image', 2);
lesion.smoke_patches_per_image = localPositiveInteger( ...
    lesion.smoke_patches_per_image, ...
    'lesion_segmentation.smoke_patches_per_image');
lesion = localDefault(lesion, 'smoke_batch_size', 2);
lesion.smoke_batch_size = localPositiveInteger(lesion.smoke_batch_size, ...
    'lesion_segmentation.smoke_batch_size');

lesion.split_directory = fullfile(projectRoot, 'data', 'splits');
config.lesion_segmentation = lesion;
configText = jsonencode(config);
end

function inputStruct = localDefault(inputStruct, fieldName, value)
if ~isfield(inputStruct, fieldName)
    inputStruct.(fieldName) = value;
end
end

function localRequireLogical(value, name)
if ~(islogical(value) && isscalar(value))
    error('segment:InvalidConfig', '%s must be a logical scalar.', name);
end
end

function value = localPositiveInteger(value, name)
value = double(value);
if ~isscalar(value) || ~isfinite(value) || value < 1 || value ~= floor(value)
    error('segment:InvalidConfig', '%s must be a positive integer.', name);
end
end

function types = localNormaliseTypes(rawTypes)
%LOCALNORMALISETYPES Accept a cell array, string array or char row.
%   jsondecode turns a JSON array of strings into a cell array of char, but
%   turns a single-element array into a plain char row, so both shapes have
%   to survive here.

if ischar(rawTypes)
    rawTypes = {rawTypes};
end
if isstring(rawTypes)
    rawTypes = cellstr(rawTypes);
end
if ~iscell(rawTypes) || isempty(rawTypes)
    error('segment:InvalidLesionTypes', ...
        'lesion_segmentation.lesion_types must be a non-empty list.');
end

types = cell(numel(rawTypes), 1);
supported = {'MA', 'HE', 'EX', 'SE'};
for typeIndex = 1:numel(rawTypes)
    candidate = upper(strtrim(char(rawTypes{typeIndex})));
    if ~any(strcmp(candidate, supported))
        error('segment:InvalidLesionTypes', ...
            ['lesion_segmentation.lesion_types entries must be MA, HE, EX ' ...
            'or SE, not %s. The optic disc mask is a suppression input ' ...
            '(§6.5), not a lesion class.'], candidate);
    end
    types{typeIndex} = candidate;
end
if numel(unique(types)) ~= numel(types)
    error('segment:InvalidLesionTypes', ...
        'lesion_segmentation.lesion_types must not repeat a lesion code.');
end
end
