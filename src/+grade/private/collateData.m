function [images, targets] = collateData(imageCells, targetCells, indexCells, augment, seed)
%COLLATEDATA Concatenate lazy image records into a CNN mini-batch.
%   The optional fourth argument enables train-only augmentation. Under
%   DispatchInBackground this function runs on a parallel pool worker,
%   not on the client, and each worker owns its own independent,
%   unseeded global stream. Augmentation draws come instead from a
%   RandStream seeded deterministically from SEED and this batch's
%   original sample indices (INDEXCELLS), so every worker computes the
%   same result for the same batch regardless of which worker it is or
%   how many workers exist (design doc §13.2).

if nargin < 4
    augment = false;
end
if nargin < 5
    seed = 42;
end

if iscell(imageCells)
    images = cat(4, imageCells{:});
else
    images = imageCells;
end

if augment
    if iscell(indexCells)
        batchIndices = double(cell2mat(indexCells));
    else
        batchIndices = double(indexCells);
    end
    batchSeed = grade.deterministicBatchSeed(seed, min(batchIndices(:)));
    stream = RandStream('mt19937ar', 'Seed', batchSeed);
    images = grade.augmentBatch(images, stream);
end

if iscell(targetCells)
    targets = reshape(single(cell2mat(targetCells)), 1, []);
else
    targets = reshape(single(targetCells), 1, []);
end
end
