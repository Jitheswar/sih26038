function splitData = loadLesionSplit(config, projectRoot, splitName)
%LOADLESIONSPLIT Read one committed IDRiD lesion split CSV.
%   SPLITDATA = loadLesionSplit(CONFIG, PROJECTROOT, SPLITNAME) reads
%   data/splits/lesion_<SPLITNAME>.csv and resolves every image path.
%
%   The CSV is read, never regenerated: the train/validation division was
%   drawn once with a fixed seed and committed (§10.2), and redrawing it
%   here would silently move images between splits between runs.

splitName = char(splitName);
splitFile = fullfile(config.lesion_segmentation.split_directory, ...
    sprintf('lesion_%s.csv', splitName));
if ~isfile(splitFile)
    error('segment:MissingSplit', ...
        ['Lesion split file does not exist: %s. Generate it once with ' ...
        'data.createLesionSplits and commit it.'], splitFile);
end

splitTable = readtable(splitFile, 'TextType', 'string');
requiredColumns = {'image_id', 'split', 'relative_path', ...
    'has_ma', 'has_he', 'has_ex', 'has_se'};
if ~all(ismember(requiredColumns, splitTable.Properties.VariableNames))
    error('segment:InvalidSplit', ...
        'Lesion split file %s is missing required columns.', splitFile);
end
if isempty(splitTable)
    error('segment:EmptySplit', 'Lesion split file %s is empty.', splitFile);
end
if any(splitTable.split ~= string(splitName))
    error('segment:InvalidSplit', ...
        'Lesion split file %s contains rows from another split.', splitFile);
end

imageCount = height(splitTable);
imagePaths = strings(imageCount, 1);
setFolders = strings(imageCount, 1);
for rowIndex = 1:imageCount
    relativePath = char(splitTable.relative_path(rowIndex));
    imagePath = fullfile(projectRoot, relativePath);
    if ~isfile(imagePath)
        error('segment:MissingImage', ...
            'Lesion split image is not present: %s', imagePath);
    end
    imagePaths(rowIndex) = string(imagePath);
    setFolders(rowIndex) = string(localSetFolder(relativePath));
end

splitData = struct();
splitData.split = string(splitName);
splitData.imageIds = string(splitTable.image_id);
splitData.imagePaths = imagePaths;
splitData.setFolders = setFolders;
splitData.imageCount = imageCount;
splitData.coverage = struct( ...
    'MA', logical(splitTable.has_ma), ...
    'HE', logical(splitTable.has_he), ...
    'EX', logical(splitTable.has_ex), ...
    'SE', logical(splitTable.has_se));
end

function setFolder = localSetFolder(relativePath)
%LOCALSETFOLDER Recover which IDRiD set an image belongs to from its path.
%   The mask directories are keyed by the same set folder as the images, so
%   the split file does not need a separate column for it.

if contains(relativePath, 'a. Training Set')
    setFolder = 'a. Training Set';
elseif contains(relativePath, 'b. Testing Set')
    setFolder = 'b. Testing Set';
else
    error('segment:InvalidSplit', ...
        ['Lesion split path does not name an IDRiD set folder: %s'], ...
        relativePath);
end
end
