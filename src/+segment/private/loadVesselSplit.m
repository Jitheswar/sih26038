function splitData = loadVesselSplit(config, projectRoot, splitName)
%LOADVESSELSPLIT Read one committed DRIVE vessel split CSV.
%   SPLITDATA = loadVesselSplit(CONFIG, PROJECTROOT, SPLITNAME) reads
%   data/splits/vessel_<SPLITNAME>.csv and resolves every path on it.
%
%   The CSV is read, never regenerated: the 14/3/3 division was drawn once
%   with a fixed seed and committed (§10.2), and redrawing it here would
%   silently move images between splits between runs.

splitName = char(splitName);
splitFile = fullfile(config.vessel_segmentation.split_directory, ...
    sprintf('vessel_%s.csv', splitName));
if ~isfile(splitFile)
    error('segment:MissingVesselSplit', ...
        ['Vessel split file does not exist: %s. Generate it once with ' ...
        'data.createVesselSplits and commit it.'], splitFile);
end

% Delimiter and header are stated rather than detected.  Every path column
% holds '/' characters, and readtable's automatic detection reads those as
% a second delimiter, consumes the real header row as data and returns
% thirteen columns named after the first frame's file path.
splitTable = readtable(splitFile, 'TextType', 'string', ...
    'Delimiter', ',', 'ReadVariableNames', true);
requiredColumns = {'image_id', 'split', 'relative_path', 'manual_path', ...
    'mask_path', 'vessel_fraction'};
if ~all(ismember(requiredColumns, splitTable.Properties.VariableNames))
    error('segment:InvalidVesselSplit', ...
        'Vessel split file %s is missing required columns.', splitFile);
end
if isempty(splitTable)
    error('segment:EmptyVesselSplit', ...
        'Vessel split file %s is empty.', splitFile);
end
if any(splitTable.split ~= string(splitName))
    error('segment:InvalidVesselSplit', ...
        'Vessel split file %s contains rows from another split.', splitFile);
end

imageCount = height(splitTable);
imagePaths = strings(imageCount, 1);
manualPaths = strings(imageCount, 1);
maskPaths = strings(imageCount, 1);
for rowIndex = 1:imageCount
    imagePaths(rowIndex) = localResolve(projectRoot, ...
        splitTable.relative_path(rowIndex), 'image');
    manualPaths(rowIndex) = localResolve(projectRoot, ...
        splitTable.manual_path(rowIndex), 'annotation');
    maskPaths(rowIndex) = localResolve(projectRoot, ...
        splitTable.mask_path(rowIndex), 'field-of-view mask');
end

splitData = struct();
splitData.splitName = string(splitName);
splitData.imageIds = splitTable.image_id;
splitData.imagePaths = imagePaths;
splitData.manualPaths = manualPaths;
splitData.maskPaths = maskPaths;
splitData.vesselFraction = splitTable.vessel_fraction;
splitData.imageCount = imageCount;
end

function resolved = localResolve(projectRoot, relativePath, description)
resolved = fullfile(projectRoot, char(relativePath));
if ~isfile(resolved)
    error('segment:MissingVesselFile', ...
        'Vessel split %s is not present: %s', description, resolved);
end
resolved = string(resolved);
end
