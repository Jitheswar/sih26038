function splitTables = createVesselSplits(projectRoot, outputDir, seed)
%CREATEVESSELSPLITS Create fixed DRIVE vessel segmentation split CSV files.
%   SPLITTABLES = data.createVesselSplits(PROJECTROOT, OUTPUTDIR, SEED)
%   writes vessel_train.csv, vessel_validation.csv and vessel_test.csv.
%
%   Why the splits are carved out of DRIVE's training half rather than
%   following DRIVE's own 20/20 division (§6.3).  §6.3 records that the
%   official challenge site withholds the test-set annotations and expects
%   online submission, while the commonly circulated archive ships first-
%   and second-observer segmentations for those images, and it asks that we
%   say which annotations we used if we score the test set locally.  The
%   archive this project holds is the withholding one: data/raw/test
%   contains images and field-of-view masks only, with no 1st_manual
%   directory, verified against the SHA-256 in data/PROVENANCE.md.  So
%   there is no local ground truth for DRIVE's own test half and no way to
%   score against it.  The twenty annotated training images are the whole of
%   the labelled data, and they are divided 14/3/3 here.
%
%   What that costs, stated plainly.  A three-image test split is small
%   enough that its metrics carry wide intervals, and it is not the DRIVE
%   benchmark, so numbers from it are not comparable to published DRIVE
%   results the way §6.3 anticipated under R6.1.  Comparability was already
%   lost when the archive arrived without test annotations; splitting is
%   what makes an honest held-out number possible at all.  The alternative,
%   scoring the images the network trained on, would produce a better
%   number and mean nothing.
%
%   Stratification is by vessel fraction inside the field of view, in
%   terciles, one image drawn per tercile into validation and one into
%   test.  Measured over the twenty images that fraction runs 0.087 to
%   0.168, and an unstratified draw of three can land entirely in one end of
%   that range, which would make a three-image split report the sparsest or
%   densest corner of DRIVE rather than DRIVE.
%
%   Generated once with a fixed seed and committed.  Regenerating at run
%   time is a bug whatever the seed (§10.2).

if nargin < 3
    seed = 42;
end
if nargin < 2 || strlength(string(outputDir)) == 0
    error('data:createVesselSplits:MissingOutputDir', ...
        'An output directory is required.');
end
if nargin < 1 || strlength(string(projectRoot)) == 0
    error('data:createVesselSplits:MissingProjectRoot', ...
        'A project root is required.');
end

rng(seed, 'twister');

projectRoot = char(projectRoot);
imageTable = localIndexTrainingHalf(projectRoot);

if height(imageTable) ~= 20
    error('data:createVesselSplits:UnexpectedCounts', ...
        ['Expected the DRIVE training half to hold 20 annotated images, ' ...
        'found %d.'], height(imageTable));
end

% One validation and one test image per tercile.  With 20 images the
% terciles hold 7, 7 and 6, so this leaves 14 for training.
[~, order] = sort(imageTable.vessel_fraction);
tercileEdges = round(linspace(0, height(imageTable), 4));
assignment = strings(height(imageTable), 1);
for tercile = 1:3
    rows = order(tercileEdges(tercile) + 1:tercileEdges(tercile + 1));
    rows = rows(randperm(numel(rows)));
    assignment(rows(1)) = "validation";
    assignment(rows(2)) = "test";
    assignment(rows(3:end)) = "train";
end

splitTables = struct();
for splitName = ["train", "validation", "test"]
    splitTable = imageTable(assignment == splitName, :);
    splitTable.split = repmat(splitName, height(splitTable), 1);
    splitTable = movevars(splitTable, 'split', 'After', 'image_id');
    splitTable = sortrows(splitTable, 'image_id');
    splitTables.(splitName) = splitTable;
end

if height(splitTables.train) ~= 14 || height(splitTables.validation) ~= 3 ...
        || height(splitTables.test) ~= 3
    error('data:createVesselSplits:UnexpectedSplitSizes', ...
        'Expected a 14/3/3 division, produced %d/%d/%d.', ...
        height(splitTables.train), height(splitTables.validation), ...
        height(splitTables.test));
end

if ~isfolder(outputDir)
    mkdir(outputDir);
end
for splitName = ["train", "validation", "test"]
    writetable(splitTables.(splitName), ...
        fullfile(outputDir, sprintf('vessel_%s.csv', splitName)), ...
        'QuoteStrings', true);
end
end

function imageTable = localIndexTrainingHalf(projectRoot)
%LOCALINDEXTRAININGHALF Index DRIVE's annotated half and measure each image.
%   The vessel fraction is measured inside the field-of-view mask, not over
%   the whole frame.  The field of view covers roughly 69 per cent of a
%   DRIVE frame and the corners outside it are black, so a whole-frame
%   fraction would report the camera's aperture as much as the retina's
%   vasculature and would order the images differently.

imageDir = fullfile(projectRoot, 'data', 'raw', 'training', 'images');
manualDir = fullfile(projectRoot, 'data', 'raw', 'training', '1st_manual');
maskDir = fullfile(projectRoot, 'data', 'raw', 'training', 'mask');

for directory = {imageDir, manualDir, maskDir}
    if ~isfolder(directory{1})
        error('data:createVesselSplits:MissingDataset', ...
            ['DRIVE directory is not present: %s. See data/PROVENANCE.md ' ...
            'for the archive this project indexes.'], directory{1});
    end
end

files = dir(fullfile(imageDir, '*_training.tif'));
files = files(~[files.isdir]);
[~, order] = sort(string({files.name}));
files = files(order);

imageCount = numel(files);
imageIds = strings(imageCount, 1);
relativePaths = strings(imageCount, 1);
manualPaths = strings(imageCount, 1);
maskPaths = strings(imageCount, 1);
vesselFraction = zeros(imageCount, 1);

for fileIndex = 1:imageCount
    name = files(fileIndex).name;
    stem = extractBefore(string(name), '_');

    manualName = sprintf('%s_manual1.gif', stem);
    maskName = sprintf('%s_training_mask.gif', stem);
    manualPath = fullfile(manualDir, manualName);
    maskPath = fullfile(maskDir, maskName);
    if ~isfile(manualPath)
        error('data:createVesselSplits:MissingAnnotation', ...
            'DRIVE annotation is not present: %s', manualPath);
    end
    if ~isfile(maskPath)
        error('data:createVesselSplits:MissingFieldOfView', ...
            'DRIVE field-of-view mask is not present: %s', maskPath);
    end

    vessels = imread(manualPath) > 0;
    fieldOfView = imread(maskPath) > 0;
    if ~isequal(size(vessels), size(fieldOfView))
        error('data:createVesselSplits:SizeMismatch', ...
            'Annotation and field-of-view mask differ in size for %s.', stem);
    end

    % DRIVE_21 rather than 21.  A bare numeric id is read back as a
    % number by every CSV reader that guesses types, and the lesion splits
    % already use a dataset-prefixed id (IDRiD_01) for the same reason.
    imageIds(fileIndex) = "DRIVE_" + stem;
    relativePaths(fileIndex) = string(fullfile('data', 'raw', 'training', ...
        'images', name));
    manualPaths(fileIndex) = string(fullfile('data', 'raw', 'training', ...
        '1st_manual', manualName));
    maskPaths(fileIndex) = string(fullfile('data', 'raw', 'training', ...
        'mask', maskName));
    vesselFraction(fileIndex) = mean(vessels(fieldOfView));
end

imageTable = table(imageIds, relativePaths, manualPaths, maskPaths, ...
    vesselFraction, 'VariableNames', {'image_id', 'relative_path', ...
    'manual_path', 'mask_path', 'vessel_fraction'});
end
