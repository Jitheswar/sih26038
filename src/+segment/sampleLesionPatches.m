function [patches, patchMasks] = sampleLesionPatches(image, masks, ...
    fieldMask, options)
%SAMPLELESIONPATCHES Draw native-resolution training patches from one frame.
%   [PATCHES, PATCHMASKS] = sampleLesionPatches(IMAGE, MASKS, FIELDMASK,
%   OPTIONS) returns PATCHSIZE-by-PATCHSIZE-by-3-by-N uint8 patches and the
%   matching PATCHSIZE-by-PATCHSIZE-by-T logical mask stack.
%
%   OPTIONS carries patchSize, patchCount, lesionFraction, augment and seed.
%   The seed makes the draw reproducible for a given (run seed, epoch,
%   image) triple, so a rerun of the same configuration sees the same
%   patches (§13.2).
%
%   Sampling picks a lesion TYPE uniformly first and only then a pixel
%   within that type.  Picking a pixel uniformly across the union instead
%   would allocate patches in proportion to lesion area, and since
%   haemorrhages cover roughly ten times the area of microaneurysms
%   (measured over Set-A: 1.00 per cent against 0.107 per cent), the
%   microaneurysm head would see almost no positive pixels.

patchSize = options.patchSize;
patchCount = options.patchCount;
typeCount = size(masks, 3);
rows = size(image, 1);
columns = size(image, 2);

if rows < patchSize || columns < patchSize
    error('segment:FrameTooSmall', ...
        'A %dx%d frame cannot yield %dx%d patches.', rows, columns, ...
        patchSize, patchSize);
end

stream = RandStream('threefry4x64_20', 'Seed', options.seed);

lesionCount = round(options.lesionFraction * patchCount);
lesionCount = min(patchCount, max(0, lesionCount));

% Types that are actually present on this frame. Asking for a lesion-centred
% patch of a type with no pixels is unsatisfiable, and silently falling back
% to background would quietly lower the true lesion fraction.
presentTypes = find(squeeze(any(any(masks, 1), 2)))';
if isempty(presentTypes)
    lesionCount = 0;
end

topLeft = zeros(patchCount, 2);
for patchIndex = 1:patchCount
    if patchIndex <= lesionCount
        typeIndex = presentTypes(randi(stream, numel(presentTypes)));
        linearIndices = find(masks(:, :, typeIndex));
        chosen = linearIndices(randi(stream, numel(linearIndices)));
        [centreRow, centreColumn] = ind2sub([rows, columns], chosen);
        % Jitter the centre so the lesion does not always sit at the exact
        % middle of the patch, which would let the network learn position
        % rather than appearance.
        centreRow = centreRow + randi(stream, [-1, 1] * floor(patchSize / 4));
        centreColumn = centreColumn + ...
            randi(stream, [-1, 1] * floor(patchSize / 4));
        top = centreRow - floor(patchSize / 2);
        left = centreColumn - floor(patchSize / 2);
    else
        [top, left] = localBackgroundOrigin(stream, fieldMask, patchSize, ...
            rows, columns);
    end
    topLeft(patchIndex, :) = [ ...
        min(max(top, 1), rows - patchSize + 1), ...
        min(max(left, 1), columns - patchSize + 1)];
end

patches = zeros(patchSize, patchSize, 3, patchCount, 'uint8');
patchMasks = false(patchSize, patchSize, typeCount, patchCount);
for patchIndex = 1:patchCount
    rowRange = topLeft(patchIndex, 1) + (0:patchSize - 1);
    columnRange = topLeft(patchIndex, 2) + (0:patchSize - 1);
    patch = image(rowRange, columnRange, :);
    patchMask = masks(rowRange, columnRange, :);
    if options.augment
        [patch, patchMask] = localAugment(stream, patch, patchMask);
    end
    patches(:, :, :, patchIndex) = patch;
    patchMasks(:, :, :, patchIndex) = patchMask;
end
end

function [top, left] = localBackgroundOrigin(stream, fieldMask, patchSize, ...
    rows, columns)
%LOCALBACKGROUNDORIGIN Draw a patch origin inside the illuminated field.
%   Uniform sampling over the whole frame would spend a large share of the
%   background patches on the black surround outside the camera aperture,
%   which teaches the network nothing it will ever be asked at inference.

maximumTop = rows - patchSize + 1;
maximumLeft = columns - patchSize + 1;

% FIELDMASK may be computed on a downsampled frame, so map full-resolution
% coordinates onto whatever grid it actually uses rather than assuming they
% share one.
rowScale = size(fieldMask, 1) / rows;
columnScale = size(fieldMask, 2) / columns;

for attempt = 1:16
    top = randi(stream, maximumTop);
    left = randi(stream, maximumLeft);
    centreRow = top + floor(patchSize / 2);
    centreColumn = left + floor(patchSize / 2);
    maskRow = min(max(round(centreRow * rowScale), 1), size(fieldMask, 1));
    maskColumn = min(max(round(centreColumn * columnScale), 1), ...
        size(fieldMask, 2));
    if fieldMask(maskRow, maskColumn)
        return;
    end
end
top = randi(stream, maximumTop);
left = randi(stream, maximumLeft);
end

function [patch, patchMask] = localAugment(stream, patch, patchMask)
%LOCALAUGMENT Rigid transforms plus modest photometric jitter.
%   Rotations are restricted to multiples of 90 degrees so the transform is
%   exact.  An arbitrary-angle rotation resamples the image, and §6.4 rules
%   out any augmentation that blurs the target: a microaneurysm is a few
%   pixels across and interpolation removes it.

quarterTurns = randi(stream, [0, 3]);
if quarterTurns > 0
    patch = rot90(patch, quarterTurns);
    patchMask = rot90(patchMask, quarterTurns);
end
if rand(stream) < 0.5
    patch = fliplr(patch);
    patchMask = fliplr(patchMask);
end
if rand(stream) < 0.5
    patch = flipud(patch);
    patchMask = flipud(patchMask);
end

brightnessShift = (rand(stream) * 2 - 1) * 10;
contrastGain = 0.9 + rand(stream) * 0.2;
adjusted = double(patch) * contrastGain + brightnessShift;
patch = uint8(min(255, max(0, adjusted)));
end
