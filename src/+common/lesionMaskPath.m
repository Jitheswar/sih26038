function maskFile = lesionMaskPath(projectRoot, setFolder, imageId, lesionCode)
%LESIONMASKPATH Resolve the IDRiD ground-truth mask path for one lesion type.
%   MASKFILE = common.lesionMaskPath(PROJECTROOT, SETFOLDER, IMAGEID, CODE)
%   returns the absolute path the IDRiD segmentation package uses for the
%   given lesion code, whether or not that file exists.
%
%   SETFOLDER is 'a. Training Set' or 'b. Testing Set'.  CODE is one of
%   MA, HE, EX, SE or OD.
%
%   This lives in +common because the split generator, the training patch
%   sampler and the evaluation harness all have to agree on it, and the
%   IDRiD directory names carry numeric prefixes, spaces and full stops
%   that are easy to mistype differently in three places.

arguments
    projectRoot (1, :) char
    setFolder (1, :) char
    imageId (1, :) char
    lesionCode (1, :) char
end

codes = {'MA', 'HE', 'EX', 'SE', 'OD'};
folders = { ...
    '1. Microaneurysms', ...
    '2. Haemorrhages', ...
    '3. Hard Exudates', ...
    '4. Soft Exudates', ...
    '5. Optic Disc'};

match = strcmpi(lesionCode, codes);
if ~any(match)
    error('common:lesionMaskPath:UnknownLesionCode', ...
        'Lesion code must be one of MA, HE, EX, SE or OD, not %s.', lesionCode);
end
if ~any(strcmp(setFolder, {'a. Training Set', 'b. Testing Set'}))
    error('common:lesionMaskPath:UnknownSet', ...
        'Set folder must be ''a. Training Set'' or ''b. Testing Set''.');
end

maskFile = fullfile(projectRoot, 'data', 'raw', 'A. Segmentation', ...
    '2. All Segmentation Groundtruths', setFolder, folders{match}, ...
    sprintf('%s_%s.tif', imageId, upper(codes{match})));
end
