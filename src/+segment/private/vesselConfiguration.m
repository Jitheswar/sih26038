function [config, configText, projectRoot] = vesselConfiguration(inputConfig)
%VESSELCONFIGURATION Load and validate the vessel segmentation configuration.
%   [CONFIG, CONFIGTEXT, PROJECTROOT] = vesselConfiguration(INPUT) accepts a
%   JSON filename or a scalar structure and fills in every default the
%   vessel segmentation entry points rely on.
%
%   Every knob below is read from config/*.json rather than typed into the
%   code (§11.6, §13.3).

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
        'The vessel configuration must be a JSON filename or scalar structure.');
end

if ~isfield(config, 'vessel_segmentation') || ...
        ~isstruct(config.vessel_segmentation)
    config.vessel_segmentation = struct();
end
vessel = config.vessel_segmentation;

vessel = localDefault(vessel, 'enabled', true);
localRequireLogical(vessel.enabled, 'vessel_segmentation.enabled');

% 128 with four downsampling rounds leaves an 8x8 bridge, and a DRIVE frame
% is 584x565 so a patch is a fifth of it.  Vessels are a connected tree:
% too small a patch shows a caliper of vessel with no branch context and the
% network cannot tell a vessel from any other dark elongated structure.
vessel = localDefault(vessel, 'patch_size', 128);
patchSize = double(vessel.patch_size);
if ~isscalar(patchSize) || ~isfinite(patchSize) || patchSize < 32 || ...
        patchSize ~= floor(patchSize) || mod(patchSize, 16) ~= 0
    error('segment:InvalidVesselPatchSize', ...
        ['vessel_segmentation.patch_size must be an integer multiple of 16 ' ...
        'and at least 32.']);
end
vessel.patch_size = patchSize;

% Fourteen training frames is very few for whole-image training, and §6.3
% records the standard answer: overlapping patches turn them into tens of
% thousands of samples.  200 per frame gives 2800 per epoch.
vessel = localDefault(vessel, 'patches_per_image', 200);
vessel.patches_per_image = localPositiveInteger( ...
    vessel.patches_per_image, 'vessel_segmentation.patches_per_image');

% Fraction of patches whose centre is required to sit on a vessel pixel.
% Vessels cover 12.5 per cent of the field of view, so unlike the lesion
% sampler this does not have to fight a 0.1 per cent prevalence; it is here
% to stop the thinnest capillaries being crowded out by trunk vessels.
vessel = localDefault(vessel, 'vessel_patch_fraction', 0.5);
vesselFraction = double(vessel.vessel_patch_fraction);
if ~isscalar(vesselFraction) || ~isfinite(vesselFraction) || ...
        vesselFraction < 0 || vesselFraction > 1
    error('segment:InvalidVesselFraction', ...
        'vessel_segmentation.vessel_patch_fraction must lie in [0, 1].');
end
vessel.vessel_patch_fraction = vesselFraction;

vessel = localDefault(vessel, 'batch_size', 16);
vessel.batch_size = localPositiveInteger(vessel.batch_size, ...
    'vessel_segmentation.batch_size');

vessel = localDefault(vessel, 'shuffle_buffer_images', 7);
vessel.shuffle_buffer_images = localPositiveInteger( ...
    vessel.shuffle_buffer_images, 'vessel_segmentation.shuffle_buffer_images');

vessel = localDefault(vessel, 'max_epochs', 30);
vessel.max_epochs = localPositiveInteger(vessel.max_epochs, ...
    'vessel_segmentation.max_epochs');

vessel = localDefault(vessel, 'learning_rate', 1e-3);
learningRate = double(vessel.learning_rate);
if ~isscalar(learningRate) || ~isfinite(learningRate) || learningRate <= 0
    error('segment:InvalidVesselLearningRate', ...
        'vessel_segmentation.learning_rate must be a positive scalar.');
end
vessel.learning_rate = learningRate;

vessel = localDefault(vessel, 'base_filters', 32);
vessel.base_filters = localPositiveInteger(vessel.base_filters, ...
    'vessel_segmentation.base_filters');

vessel = localDefault(vessel, 'encoder_depth', 4);
encoderDepth = localPositiveInteger(vessel.encoder_depth, ...
    'vessel_segmentation.encoder_depth');
if encoderDepth > 5
    error('segment:InvalidVesselEncoderDepth', ...
        'vessel_segmentation.encoder_depth above 5 is not supported.');
end
if mod(patchSize, 2 ^ encoderDepth) ~= 0
    error('segment:InvalidVesselEncoderDepth', ...
        ['vessel_segmentation.patch_size (%d) must divide by ' ...
        '2^encoder_depth (%d) so each skip connection matches its ' ...
        'decoder stage.'], patchSize, 2 ^ encoderDepth);
end
vessel.encoder_depth = encoderDepth;

% Dice weight against binary cross-entropy.  The lesion path uses Tversky
% with beta > alpha and refuses to start otherwise, because lesion pixels
% are 0.1 to 1.0 per cent of a frame and a symmetric objective scores well
% by predicting all background (§6.4).  Vessels are not that problem:
% measured over the twenty annotated DRIVE frames they occupy 12.5 per cent
% of the field of view, a hundred times the prevalence, so a symmetric Dice
% term is appropriate and a recall-weighted one would only buy thickened
% vessels and a worse specificity.  This difference is deliberate and is the
% reason the vessel path does not reuse segment.lesionLoss.
vessel = localDefault(vessel, 'dice_weight', 0.5);
diceWeight = double(vessel.dice_weight);
if ~isscalar(diceWeight) || ~isfinite(diceWeight) || diceWeight < 0 || ...
        diceWeight > 1
    error('segment:InvalidDiceWeight', ...
        'vessel_segmentation.dice_weight must lie in [0, 1].');
end
vessel.dice_weight = diceWeight;

vessel = localDefault(vessel, 'early_stopping_patience', 8);
patience = double(vessel.early_stopping_patience);
if ~isscalar(patience) || ~isfinite(patience) || patience < 0 || ...
        patience ~= floor(patience)
    error('segment:InvalidVesselPatience', ...
        ['vessel_segmentation.early_stopping_patience must be a ' ...
        'non-negative integer.']);
end
vessel.early_stopping_patience = patience;

vessel = localDefault(vessel, 'roc_thresholds', 101);
vessel.roc_thresholds = localPositiveInteger(vessel.roc_thresholds, ...
    'vessel_segmentation.roc_thresholds');
if vessel.roc_thresholds < 3
    error('segment:InvalidVesselThresholds', ...
        'vessel_segmentation.roc_thresholds must be at least 3.');
end

% The operating threshold on the sigmoid output.  Selected on validation by
% eval/vesselSegmentationEvaluation.m and written here once, never taken
% from whatever maximised a number on the test split.
vessel = localDefault(vessel, 'operating_threshold', 0.5);
operatingThreshold = double(vessel.operating_threshold);
if ~isscalar(operatingThreshold) || ~isfinite(operatingThreshold) || ...
        operatingThreshold <= 0 || operatingThreshold >= 1
    error('segment:InvalidVesselThreshold', ...
        'vessel_segmentation.operating_threshold must lie in (0, 1).');
end
vessel.operating_threshold = operatingThreshold;

vessel = localDefault(vessel, 'tile_overlap', 32);
tileOverlap = double(vessel.tile_overlap);
if ~isscalar(tileOverlap) || ~isfinite(tileOverlap) || tileOverlap < 0 || ...
        tileOverlap ~= floor(tileOverlap) || tileOverlap >= patchSize / 2
    error('segment:InvalidVesselTileOverlap', ...
        ['vessel_segmentation.tile_overlap must be a non-negative integer ' ...
        'below half the patch size.']);
end
vessel.tile_overlap = tileOverlap;

vessel = localDefault(vessel, 'green_clahe', true);
localRequireLogical(vessel.green_clahe, 'vessel_segmentation.green_clahe');
vessel = localDefault(vessel, 'clahe_clip_limit', 0.01);
clipLimit = double(vessel.clahe_clip_limit);
if ~isscalar(clipLimit) || ~isfinite(clipLimit) || clipLimit <= 0 || ...
        clipLimit >= 1
    error('segment:InvalidClipLimit', ...
        'vessel_segmentation.clahe_clip_limit must lie in (0, 1).');
end
vessel.clahe_clip_limit = clipLimit;
vessel = localDefault(vessel, 'clahe_tiles', 8);
vessel.clahe_tiles = localPositiveInteger(vessel.clahe_tiles, ...
    'vessel_segmentation.clahe_tiles');

vessel = localDefault(vessel, 'checkpoint', '');
vessel.checkpoint = char(vessel.checkpoint);

vessel = localDefault(vessel, 'seed', 42);
if vessel.seed ~= 42
    error('segment:InvalidVesselSeed', ...
        'The vessel segmentation entry point requires rng(42) (§13.2).');
end

vessel = localDefault(vessel, 'smoke_epochs', 1);
vessel.smoke_epochs = localPositiveInteger(vessel.smoke_epochs, ...
    'vessel_segmentation.smoke_epochs');
vessel = localDefault(vessel, 'smoke_images', 2);
vessel.smoke_images = localPositiveInteger(vessel.smoke_images, ...
    'vessel_segmentation.smoke_images');
vessel = localDefault(vessel, 'smoke_patches_per_image', 4);
vessel.smoke_patches_per_image = localPositiveInteger( ...
    vessel.smoke_patches_per_image, ...
    'vessel_segmentation.smoke_patches_per_image');
vessel = localDefault(vessel, 'smoke_batch_size', 2);
vessel.smoke_batch_size = localPositiveInteger(vessel.smoke_batch_size, ...
    'vessel_segmentation.smoke_batch_size');

vessel.split_directory = fullfile(projectRoot, 'data', 'splits');
config.vessel_segmentation = vessel;
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
