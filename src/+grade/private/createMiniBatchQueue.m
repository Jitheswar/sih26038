function queue = createMiniBatchQueue(imageStore, grades, batchSize, environment, varargin)
%CREATEMINIBATCHQUEUE Build a lazy queue with image and integer targets.
%   Optional fifth argument enables background prefetch so CPU-side
%   preprocessing overlaps GPU compute; delivery timing changes only.
%   Optional sixth argument enables train-only batch augmentation.
%   Optional seventh argument is the run seed (design doc §13.2), used by
%   collateData to derive each batch's augmentation stream from
%   (seed, batch identity) rather than from whichever worker computes it.
%   Optional eighth argument is the config.augmentation block, which sets
%   the augmentation envelope; omitted, augmentBatch uses its defaults.
%
%   DispatchInBackground fans batches out across the whole parallel pool,
%   and which batch lands in which delivery position from next() is not
%   guaranteed independent of pool size (verified empirically: two pool
%   sizes returned the same two batches in swapped order). The seed fix
%   here makes a given batch's *content* identical no matter who computes
%   it, but cannot make delivery *order* pool-size-invariant - that
%   requires DispatchInBackground false, which is this codebase's
%   default (see config default.json and readConfiguration.m).

if nargin < 5
    dispatchInBackground = true;
else
    dispatchInBackground = logical(varargin{1});
end
if nargin < 6
    augment = false;
else
    augment = logical(varargin{2});
end
if nargin < 7
    seed = 42;
else
    seed = double(varargin{3});
end
if nargin < 8
    augmentationOptions = struct();
else
    augmentationOptions = varargin{4};
end

sampleCount = numel(grades);
labelStore = arrayDatastore(single(grades(:) + 1), ...
    'OutputType', 'same');
indexStore = arrayDatastore((1:sampleCount).', 'OutputType', 'same');
combinedStore = combine(imageStore, labelStore, indexStore);
queue = minibatchqueue(combinedStore, 2, ...
    'MiniBatchSize', batchSize, ...
    'MiniBatchFcn', @(imageCells, targetCells, indexCells) ...
        collateData(imageCells, targetCells, indexCells, augment, seed, ...
            augmentationOptions), ...
    'OutputCast', {'single', 'single'}, ...
    'OutputAsDlarray', [true, true], ...
    'MiniBatchFormat', {'SSCB', 'CB'}, ...
    'OutputEnvironment', environment, ...
    'PartialMiniBatch', 'return', ...
    'DispatchInBackground', dispatchInBackground);
end
