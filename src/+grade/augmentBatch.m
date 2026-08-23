function images = augmentBatch(images, stream)
%AUGMENTBATCH Train-only dihedral and photometric jitter for one batch.
%   Applies, independently per sample: a random 90-degree rotation, then
%   horizontal and vertical flips, then modest brightness and contrast
%   jitter. IMAGES = AUGMENTBATCH(IMAGES) draws from the caller's seeded
%   global stream. IMAGES = AUGMENTBATCH(IMAGES, STREAM) draws from STREAM
%   instead, which lets collateData hand in a stream seeded
%   deterministically from (run seed, batch identity), so a background
%   worker's own unseeded global stream never enters the result (design
%   doc §13.2). No blur or noise is added: the design doc forbids
%   augmentations that destroy the microaneurysm-level evidence the model
%   exists to find.

if nargin < 2 || isempty(stream)
    stream = RandStream.getGlobalStream();
end

sampleCount = size(images, 4);
for sample = 1:sampleCount
    quarterTurns = randi(stream, [0, 3]);
    if quarterTurns > 0
        images(:, :, :, sample) = rot90(images(:, :, :, sample), quarterTurns);
    end
    if rand(stream) < 0.5
        images(:, :, :, sample) = flip(images(:, :, :, sample), 2);
    end
    if rand(stream) < 0.5
        images(:, :, :, sample) = flip(images(:, :, :, sample), 1);
    end
    gain = 0.9 + 0.2 * rand(stream);
    bias = -10 + 20 * rand(stream);
    images(:, :, :, sample) = images(:, :, :, sample) * gain + bias;
end
end
