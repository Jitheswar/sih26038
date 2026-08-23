function batchSeed = deterministicBatchSeed(seed, batchKey)
%DETERMINISTICBATCHSEED Mix a run seed and a batch identity into one seed.
%   BATCHSEED = DETERMINISTICBATCHSEED(SEED, BATCHKEY) combines SEED (the
%   run's rng seed, config.grading.seed) and BATCHKEY (an integer
%   identifying one mini-batch - collateData uses the lowest original
%   sample index the batch contains, which is fixed by the shuffle
%   permutation and so is the same regardless of pool size or worker
%   scheduling) into a single nonnegative integer below 2^32, suitable as
%   a RandStream seed.
%
%   Equal inputs always produce equal output, which is what makes a given
%   batch's augmentation reproducible no matter which worker computes it
%   or how many workers are in the pool (design doc §13.2). This
%   function has no dependency on global state, so it is safe to call
%   from any parallel pool worker.

mixed = mod(double(seed) * 2654435761 + double(batchKey) * 40503 + 1, 2^32 - 1);
batchSeed = uint32(mixed);
end
