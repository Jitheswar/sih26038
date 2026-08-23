function image = readPreprocessedImage(filename, config)
%READPREPROCESSEDIMAGE Read one image through the single shared pipeline.
%   The pipeline is deterministic and every epoch re-reads the same files,
%   so outputs are memoised under .cache/preprocessed_v1. A cache miss or
%   an unwritable cache never changes the returned image.

cacheFile = localCacheFile(filename, config);
if isfile(cacheFile)
    cached = load(cacheFile, 'image');
    image = cached.image;
    return;
end

rawImage = imread(filename);
[image, ~, ~] = common.preprocess(rawImage, config, 'training');
if size(image, 3) == 1
    image = repmat(image, 1, 1, 3);
end
image = single(image);

localStoreCache(cacheFile, image);
end

function cacheFile = localCacheFile(filename, config)
thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(fileparts(fileparts(thisFile))));

fileMetadata = dir(filename);
if isscalar(fileMetadata)
    identity = sprintf('|%s|%d|%d', ...
        char(string(filename)), fileMetadata.datenum, fileMetadata.bytes);
else
    error('grade:MissingImage', 'Image file does not exist: %s', filename);
end

keyText = [identity, '|', jsonencode(config)];
digest = java.security.MessageDigest.getInstance('SHA-256');
hashed = typecast(digest.digest(uint8(keyText)), 'uint64');
key = sprintf('%016x%016x%016x%016x', hashed(1), hashed(2), hashed(3), hashed(4));

cacheDirectory = fullfile(projectRoot, '.cache', 'preprocessed_v1');
if ~isfolder(cacheDirectory)
    try
        mkdir(cacheDirectory);
    catch
        % Fall through; localStoreCache tolerates the missing directory.
    end
end
cacheFile = fullfile(cacheDirectory, [key, '.mat']);
end

function localStoreCache(cacheFile, image)
try
    % tempname returns no extension; save would append '.mat' to it and
    % break the subsequent move, so give the temporary file its extension.
    temporaryFile = [tempname(fileparts(cacheFile)), '.mat'];
    save(temporaryFile, '-v7', 'image');
    movefile(temporaryFile, cacheFile, 'f');
catch
    % Caching is best effort only.
end
end
