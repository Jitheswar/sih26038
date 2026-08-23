function images = augmentBatch(images, stream, options)
%AUGMENTBATCH Train-only rigid and photometric jitter for one batch.
%   Applies, independently per sample: a random rotation, a random zoom-in
%   crop, horizontal and vertical flips, then modest brightness and
%   contrast jitter. IMAGES = AUGMENTBATCH(IMAGES) draws from the caller's
%   seeded global stream with the default envelope. IMAGES =
%   AUGMENTBATCH(IMAGES, STREAM) draws from STREAM instead, which lets
%   collateData hand in a stream seeded deterministically from (run seed,
%   batch identity), so a background worker's own unseeded global stream
%   never enters the result (design doc §13.2). IMAGES =
%   AUGMENTBATCH(IMAGES, STREAM, OPTIONS) takes the envelope from the
%   config.augmentation block instead of the defaults.
%
%   No blur, no noise, no elastic warp: the design doc forbids
%   augmentations that destroy the microaneurysm-level evidence the model
%   exists to find, and all three do exactly that. Every transform here is
%   rigid or per-pixel affine, so a one-pixel lesion stays a one-pixel
%   lesion.
%
%   Rotation is by an arbitrary angle rather than the previous quarter
%   turns. common.preprocess crops to the field-of-view bounding box and
%   resizes, so the retina arrives as a disc inscribed in a square frame
%   whose corners are already black; rotating about the centre moves only
%   those corners. That turns 8 reachable orientations into a continuum,
%   which matters most for ICDR level 3 - 135 unique training images seen
%   about nine times per epoch, and the only class that never learned in
%   results/20260823_162453.

if nargin < 2 || isempty(stream)
    stream = RandStream.getGlobalStream();
end
if nargin < 3 || isempty(options)
    options = struct();
end
options = localOptions(options);

sampleCount = size(images, 4);
for sample = 1:sampleCount
    frame = images(:, :, :, sample);

    if options.rotation
        angle = 360 * rand(stream);
        frame = imrotate(frame, angle, 'bilinear', 'crop');
    end

    if options.scaleJitter(1) < 1
        frame = localZoomCrop(frame, stream, options.scaleJitter);
    end

    if options.flips
        if rand(stream) < 0.5
            frame = flip(frame, 2);
        end
        if rand(stream) < 0.5
            frame = flip(frame, 1);
        end
    end

    gainRange = options.contrastGain;
    gain = gainRange(1) + (gainRange(2) - gainRange(1)) * rand(stream);
    bias = -options.brightnessShift + 2 * options.brightnessShift * rand(stream);
    images(:, :, :, sample) = frame * gain + bias;
end
end

function frame = localZoomCrop(frame, stream, scaleJitter)
%LOCALZOOMCROP Take a random sub-window and resize it back to full size.
%   The scale is capped at 1 upstream, so this only ever zooms in. Zooming
%   out would need padding, and padded borders are evidence the camera
%   never captured.

[height, width, ~] = size(frame);
scale = scaleJitter(1) + (scaleJitter(2) - scaleJitter(1)) * rand(stream);
cropHeight = max(1, round(scale * height));
cropWidth = max(1, round(scale * width));
rowStart = 1 + floor((height - cropHeight + 1) * rand(stream));
columnStart = 1 + floor((width - cropWidth + 1) * rand(stream));
rowStart = min(rowStart, height - cropHeight + 1);
columnStart = min(columnStart, width - cropWidth + 1);

frame = frame(rowStart:rowStart + cropHeight - 1, ...
    columnStart:columnStart + cropWidth - 1, :);
frame = imresize(frame, [height, width], 'bilinear');
end

function options = localOptions(options)
options = localDefault(options, 'rotation', true);
options = localDefault(options, 'flips', true);
options = localDefault(options, 'scale_jitter', [0.85, 1.0]);
options = localDefault(options, 'brightness_shift', 10);
options = localDefault(options, 'contrast_gain', [0.9, 1.1]);

options.rotation = logical(options.rotation);
options.flips = logical(options.flips);
options.scaleJitter = double(options.scale_jitter(:)).';
options.brightnessShift = double(options.brightness_shift);
options.contrastGain = double(options.contrast_gain(:)).';

if numel(options.scaleJitter) ~= 2 || options.scaleJitter(2) > 1
    error('grade:InvalidAugmentation', ...
        'scale_jitter must be [low high] with high no greater than 1.');
end
if numel(options.contrastGain) ~= 2
    error('grade:InvalidAugmentation', ...
        'contrast_gain must be [low high].');
end
end

function options = localDefault(options, fieldName, value)
if ~isfield(options, fieldName) || isempty(options.(fieldName))
    options.(fieldName) = value;
end
end
