function data = loadSplitData(config, projectRoot, splitName)
%LOADSPLITDATA Read one committed APTOS split without regenerating it.

splitFile = fullfile(config.data.split_directory, splitName + ".csv");
if ~isfile(splitFile)
    error('grade:MissingSplit', ...
        'Committed split file does not exist: %s', splitFile);
end

tableData = readtable(splitFile, 'TextType', 'string');
requiredColumns = ["image_id", "patient_id", "grade", "relative_path"];
if ~all(ismember(requiredColumns, string(tableData.Properties.VariableNames)))
    error('grade:InvalidSplit', 'Split %s.csv has an unexpected schema.', splitName);
end

relativePaths = string(tableData.relative_path);
if any(contains(lower(relativePaths), "sealed")) || ...
        any(~contains(lower(relativePaths), "data/raw/aptos2019"))
    error('grade:InvalidDataset', ...
        'Only APTOS paths under data/raw/aptos2019 are allowed.');
end

files = strings(height(tableData), 1);
for index = 1:height(tableData)
    files(index) = string(fullfile(projectRoot, char(relativePaths(index))));
end
if any(~isfile(files))
    missing = files(find(~isfile(files), 1));
    error('grade:MissingImage', 'Image file does not exist: %s', missing);
end

grades = double(tableData.grade);
if any(~ismember(grades, 0:4))
    error('grade:InvalidGrade', 'APTOS grades must be integers from 0 through 4.');
end

data = struct();
data.split = string(splitName);
data.table = tableData;
data.files = files;
data.grades = grades(:);
data.classCounts = arrayfun(@(level) sum(data.grades == level), 0:4).';
data.count = numel(data.grades);
end
