function [images, targets] = collateData(imageCells, targetCells, augment)
%COLLATEDATA Concatenate lazy image records into a CNN mini-batch.
%   The optional third argument enables train-only augmentation, applied
%   per sample on the client side so randomness stays on the seeded
%   global stream (design doc §13.2).

if nargin < 3
    augment = false;
end

if iscell(imageCells)
    images = cat(4, imageCells{:});
else
    images = imageCells;
end

if augment
    images = grade.augmentBatch(images);
end

if iscell(targetCells)
    targets = reshape(single(cell2mat(targetCells)), 1, []);
else
    targets = reshape(single(targetCells), 1, []);
end
end
