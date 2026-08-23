function [key, identity] = preprocessingCacheKey(filename, config)
%PREPROCESSINGCACHEKEY Cache identity for one preprocessed training image.
%   KEY = grade.preprocessingCacheKey(FILENAME, CONFIG) returns the
%   SHA-256 hex key under which readPreprocessedImage memoises the output
%   of common.preprocess for FILENAME under CONFIG. [KEY, IDENTITY] also
%   returns the name/value pairs the key was built from.
%
%   The key covers the file's own identity (path, modification time, size)
%   and only those configuration fields common.preprocess actually reads.
%   It deliberately excludes everything else: hashing the whole
%   configuration made a change to grading.dropout or training.weight_decay
%   invalidate every cached image, which on 2026-08-23 discarded 16 GB of
%   cache and cost an hour re-preprocessing 2564 unchanged images.
%
%   The list below mirrors localConfiguration in src/+common/preprocess.m.
%   A preprocessing option added there must be added here as well: the
%   cost of omitting one is not a slow run but a silent wrong one, where
%   the cache serves pixels from the previous pipeline. TestGradingBaseline
%   pins both directions.

if ~(ischar(filename) || (isstring(filename) && isscalar(filename)))
    error('grade:InvalidCacheKeyInput', 'FILENAME must be text.');
end
filename = char(filename);
fileMetadata = dir(filename);
if ~isscalar(fileMetadata)
    error('grade:MissingImage', 'Image file does not exist: %s', filename);
end

paths = {
    {'pipeline', 'quality_gate'}
    {'quality_gate'}
    {'pipeline', 'enhancement'}
    {'enhancement'}
    {'preprocessing', 'resolution'}
    {'preprocessing', 'input_size'}
    {'grading', 'input_size'}
    {'input_size'}
    {'preprocessing', 'fov_mode'}
    {'fov_mode'}
    {'preprocessing', 'crop_fov'}
    {'quality'}
    {'qualityConfig'}
    {'preprocessing', 'illumination_sigma'}
    {'illumination_sigma'}
    {'preprocessing', 'clahe'}
    {'clahe'}
    {'preprocessing', 'output_type'}
    {'output_type'}
    {'preprocessing', 'channel_mean'}
    {'preprocessing', 'channel_std'}
    {'preprocessing', 'normalization', 'mean'}
    {'preprocessing', 'normalization', 'std'}
    {'normalization', 'mean'}
    {'normalization', 'std'}
    {'training_channel_mean'}
    {'training_channel_std'}
    {'channel_mean'}
    {'channel_std'}
    };

identity = cell(0, 2);
for index = 1:numel(paths)
    path = paths{index};
    candidate = config;
    found = true;
    for component = 1:numel(path)
        if ~isstruct(candidate) || ~isscalar(candidate) || ...
                ~isfield(candidate, path{component})
            found = false;
            break;
        end
        candidate = candidate.(path{component});
    end
    if found
        identity(end + 1, :) = {strjoin(path, '.'), candidate}; %#ok<AGROW>
    end
end

keyText = sprintf('|%s|%d|%d|%s', filename, fileMetadata.datenum, ...
    fileMetadata.bytes, jsonencode(identity));
digest = java.security.MessageDigest.getInstance('SHA-256');
hashed = typecast(digest.digest(uint8(keyText)), 'uint64');
key = sprintf('%016x%016x%016x%016x', hashed(1), hashed(2), hashed(3), hashed(4));
end
