function splitTables = createLesionSplits(projectRoot, outputDir, seed)
%CREATELESIONSPLITS Create fixed IDRiD lesion segmentation split CSV files.
%   SPLITTABLES = data.createLesionSplits(PROJECTROOT, OUTPUTDIR, SEED)
%   writes lesion_train.csv, lesion_validation.csv and lesion_test.csv.
%
%   IDRiD ships its own 54/27 Set-A / Set-B division, and Set-B is the
%   published benchmark set for the lesion sub-challenge (§6.4).  Set-B
%   therefore becomes lesion_test and is never trained on and never used to
%   select an epoch.  The train/validation division is carved out of Set-A
%   only, once, with a fixed seed, and committed - regenerating it at run
%   time is a bug whatever the seed (§10.2).
%
%   Stratification is by soft-exudate presence.  Every Set-A image carries
%   microaneurysm and hard-exudate masks and all but one carry haemorrhage
%   masks, so those cannot stratify anything; soft exudates appear on only
%   26 of 54 images and an unstratified draw can leave the validation split
%   with almost none, which would make the soft-exudate validation AUPR
%   meaningless.

if nargin < 3
    seed = 42;
end
if nargin < 2 || strlength(string(outputDir)) == 0
    error('data:createLesionSplits:MissingOutputDir', ...
        'An output directory is required.');
end
if nargin < 1 || strlength(string(projectRoot)) == 0
    error('data:createLesionSplits:MissingProjectRoot', ...
        'A project root is required.');
end

rng(seed, 'twister');

projectRoot = char(projectRoot);
setATable = localIndexSet(projectRoot, 'a. Training Set');
setBTable = localIndexSet(projectRoot, 'b. Testing Set');

if height(setATable) ~= 54 || height(setBTable) ~= 27
    error('data:createLesionSplits:UnexpectedCounts', ...
        ['Expected the IDRiD segmentation package to hold 54 Set-A and ' ...
        '27 Set-B images, found %d and %d.'], height(setATable), ...
        height(setBTable));
end

% 43/11 keeps eleven validation images, which is the smallest split that
% still holds five or six soft-exudate cases after stratification.
validationFraction = 0.20;
assignment = strings(height(setATable), 1);
for hasSoftExudate = [true, false]
    stratumRows = find(setATable.has_se == hasSoftExudate);
    stratumRows = stratumRows(randperm(numel(stratumRows)));
    validationCount = max(1, round(validationFraction * numel(stratumRows)));
    assignment(stratumRows(1:validationCount)) = "validation";
    assignment(stratumRows(validationCount + 1:end)) = "train";
end

splitTables = struct();
splitTables.train = setATable(assignment == "train", :);
splitTables.validation = setATable(assignment == "validation", :);
splitTables.test = setBTable;

if ~isfolder(outputDir)
    mkdir(outputDir);
end
splitNames = fieldnames(splitTables);
for splitIndex = 1:numel(splitNames)
    splitName = splitNames{splitIndex};
    table = splitTables.(splitName);
    table.split = repmat(string(splitName), height(table), 1);
    table = table(:, {'image_id', 'split', 'relative_path', ...
        'has_ma', 'has_he', 'has_ex', 'has_se'});
    table = sortrows(table, 'image_id');
    splitTables.(splitName) = table;
    writetable(table, fullfile(outputDir, ...
        sprintf('lesion_%s.csv', splitName)), 'QuoteStrings', true);
    fprintf('%-10s n=%2d  MA %2d  HE %2d  EX %2d  SE %2d\n', splitName, ...
        height(table), sum(table.has_ma), sum(table.has_he), ...
        sum(table.has_ex), sum(table.has_se));
end
end

function indexTable = localIndexSet(projectRoot, setFolder)
%LOCALINDEXSET Enumerate one IDRiD segmentation set and its mask coverage.
%   A missing mask file means the grader marked no lesion of that type on
%   that image, which is an empty mask, not absent supervision.  Soft
%   exudates are absent from 28 of 54 Set-A images for exactly this reason,
%   and treating those as unlabelled would silently drop half the set.

segmentationRoot = fullfile(projectRoot, 'data', 'raw', 'A. Segmentation');
imageDir = fullfile(segmentationRoot, '1. Original Images', setFolder);
if ~isfolder(imageDir)
    error('data:createLesionSplits:MissingImages', ...
        'IDRiD segmentation images are not present: %s', imageDir);
end

files = dir(fullfile(imageDir, '*.jpg'));
files = files(~[files.isdir]);
[~, order] = sort(string({files.name}));
files = files(order);

imageIds = strings(numel(files), 1);
relativePaths = strings(numel(files), 1);
coverage = false(numel(files), 4);
suffixes = {'MA', 'HE', 'EX', 'SE'};
for fileIndex = 1:numel(files)
    [~, stem] = fileparts(files(fileIndex).name);
    imageIds(fileIndex) = string(stem);
    relativePaths(fileIndex) = string(fullfile('data', 'raw', ...
        'A. Segmentation', '1. Original Images', setFolder, ...
        files(fileIndex).name));
    for suffixIndex = 1:numel(suffixes)
        maskFile = common.lesionMaskPath(projectRoot, setFolder, stem, ...
            suffixes{suffixIndex});
        coverage(fileIndex, suffixIndex) = isfile(maskFile);
    end
end

indexTable = table(imageIds, relativePaths, coverage(:, 1), coverage(:, 2), ...
    coverage(:, 3), coverage(:, 4), 'VariableNames', ...
    {'image_id', 'relative_path', 'has_ma', 'has_he', 'has_ex', 'has_se'});
end
