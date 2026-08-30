function [image, masks, discMask] = readLesionCase(projectRoot, imageId, ...
    setFolder, lesionTypes)
%READLESIONCASE Read one IDRiD frame and its lesion masks at native size.
%   [IMAGE, MASKS, DISCMASK] = readLesionCase(PROJECTROOT, IMAGEID,
%   SETFOLDER, LESIONTYPES) returns the uint8 RGB frame, an H-by-W-by-T
%   logical stack in LESIONTYPES order, and the optic-disc mask.
%
%   A mask file that does not exist means the grader marked no lesion of
%   that type on that image, so it reads as an all-false mask.  Twenty-eight
%   of the 54 Set-A frames have no soft-exudate file for this reason, and
%   treating those as missing supervision rather than as negatives would
%   drop half the training set and bias the soft-exudate head towards
%   predicting a lesion everywhere.

imageId = char(imageId);
setFolder = char(setFolder);

imagePath = fullfile(projectRoot, 'data', 'raw', 'A. Segmentation', ...
    '1. Original Images', setFolder, sprintf('%s.jpg', imageId));
if ~isfile(imagePath)
    error('segment:MissingImage', 'IDRiD frame is not present: %s', imagePath);
end
image = imread(imagePath);
if size(image, 3) ~= 3
    error('segment:InvalidImage', ...
        'IDRiD frame %s is not an RGB image.', imagePath);
end

rows = size(image, 1);
columns = size(image, 2);
typeCount = numel(lesionTypes);
masks = false(rows, columns, typeCount);
for typeIndex = 1:typeCount
    masks(:, :, typeIndex) = localReadMask(projectRoot, setFolder, ...
        imageId, lesionTypes{typeIndex}, rows, columns);
end

if nargout > 2
    discMask = localReadMask(projectRoot, setFolder, imageId, 'OD', ...
        rows, columns);
end
end

function mask = localReadMask(projectRoot, setFolder, imageId, lesionCode, ...
    rows, columns)
maskPath = common.lesionMaskPath(projectRoot, setFolder, imageId, lesionCode);
if ~isfile(maskPath)
    mask = false(rows, columns);
    return;
end

raw = imread(maskPath);
if ndims(raw) == 3
    raw = raw(:, :, 1);
end
mask = raw > 0;
if size(mask, 1) ~= rows || size(mask, 2) ~= columns
    error('segment:MaskSizeMismatch', ...
        ['Mask %s is %dx%d but its frame is %dx%d; the two must share a ' ...
        'pixel grid for patch extraction to be meaningful.'], maskPath, ...
        size(mask, 1), size(mask, 2), rows, columns);
end
end
