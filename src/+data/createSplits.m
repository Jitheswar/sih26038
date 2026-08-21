function splitTables = createSplits(labelsFile, outputDir, seed)
%CREATESPLITS Create fixed, stratified APTOS development split CSV files.

if nargin < 3
    seed = 42;
end

rng(seed, 'twister');

if nargin < 2 || strlength(string(outputDir)) == 0
    error('data:createSplits:MissingOutputDir', 'An output directory is required.');
end

labels = readtable(labelsFile, 'TextType', 'string');
requiredColumns = {'id_code', 'diagnosis'};
if ~all(ismember(requiredColumns, labels.Properties.VariableNames))
    error('data:createSplits:InvalidLabels', ...
        'The labels file must contain id_code and diagnosis columns.');
end

imageIds = string(labels.id_code);
grades = double(labels.diagnosis);
if any(ismissing(imageIds)) || any(~isfinite(grades))
    error('data:createSplits:InvalidLabels', 'Image IDs and grades must be complete.');
end
if any(grades ~= floor(grades)) || any(~ismember(grades, 0:4))
    error('data:createSplits:InvalidGrades', 'APTOS grades must be integer values from 0 to 4.');
end
if numel(unique(imageIds)) ~= numel(imageIds)
    error('data:createSplits:DuplicateImage', 'The labels file contains duplicate image IDs.');
end

splitNames = {'train', 'validation', 'calibration', 'test'};
splitProportions = [0.70, 0.15, 0.10, 0.05];
gradeValues = 0:4;
assignment = strings(height(labels), 1);

for grade = gradeValues
    gradeRows = find(grades == grade);
    gradeRows = gradeRows(randperm(numel(gradeRows)));
    allocation = allocateCounts(numel(gradeRows), splitProportions);

    cursor = 1;
    for splitIndex = 1:numel(splitNames)
        nextCursor = cursor + allocation(splitIndex) - 1;
        selectedRows = gradeRows(cursor:nextCursor);
        assignment(selectedRows) = splitNames{splitIndex};
        cursor = nextCursor + 1;
    end
end

if ~isfolder(outputDir)
    mkdir(outputDir);
end

splitTables = struct();
for splitIndex = 1:numel(splitNames)
    splitName = splitNames{splitIndex};
    rows = find(assignment == splitName);
    splitTable = table( ...
        imageIds(rows), ...
        imageIds(rows), ...
        grades(rows), ...
        "data/raw/aptos2019/train_images/" + imageIds(rows) + ".png", ...
        'VariableNames', {'image_id', 'patient_id', 'grade', 'relative_path'});
    splitTable = sortrows(splitTable, 'image_id');
    writetable(splitTable, fullfile(outputDir, splitName + ".csv"));
    splitTables.(splitName) = splitTable;
end
end

function allocation = allocateCounts(totalCount, proportions)
rawCounts = totalCount .* proportions;
allocation = floor(rawCounts);
remaining = totalCount - sum(allocation);
[~, order] = sort(rawCounts - allocation, 'descend');
allocation(order(1:remaining)) = allocation(order(1:remaining)) + 1;

if any(allocation < 1)
    error('data:createSplits:UnrepresentedGrade', ...
        'A grade cannot be represented in all four splits with the selected proportions.');
end
end

