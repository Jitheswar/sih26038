function images = augmentBatch(images)
%AUGMENTBATCH Train-only dihedral and photometric jitter for one batch.
%   Applies, independently per sample: a random 90-degree rotation, then
%   horizontal and vertical flips, then modest brightness and contrast
%   jitter. Random values come from the caller's seeded global stream, so
%   runs stay reproducible under the entry-point rng discipline. No blur or
%   noise is added: the design doc forbids augmentations that destroy the
%   microaneurysm-level evidence the model exists to find.

sampleCount = size(images, 4);
for sample = 1:sampleCount
    quarterTurns = randi([0, 3]);
    if quarterTurns > 0
        images(:, :, :, sample) = rot90(images(:, :, :, sample), quarterTurns);
    end
    if rand() < 0.5
        images(:, :, :, sample) = flip(images(:, :, :, sample), 2);
    end
    if rand() < 0.5
        images(:, :, :, sample) = flip(images(:, :, :, sample), 1);
    end
    gain = 0.9 + 0.2 * rand();
    bias = -10 + 20 * rand();
    images(:, :, :, sample) = images(:, :, :, sample) * gain + bias;
end
end
