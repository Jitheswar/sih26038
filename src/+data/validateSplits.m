function report = validateSplits(labelsFile, splitDir)
%VALIDATESPLITS Validate fixed APTOS split files and their grade coverage.

splitNames = {'train', 'validation', 'calibration', 'test'};
source = readtable(labelsFile, 'TextType', 'string');
sourceIds = string(source.id_code);
sourceGrades = double(source.diagnosis);

splitTables = cell(numel(splitNames), 1);
allRows = table();
for splitIndex = 1:numel(splitNames)
    splitName = splitNames{splitIndex};
    splitFile = fullfile(splitDir, splitName + ".csv");
    if ~isfile(splitFile)
        error('data:validateSplits:MissingFile', 'Missing split file: %s', splitFile);
    end

    splitTable = readtable(splitFile, 'TextType', 'string');
    requiredColumns = {'image_id', 'patient_id', 'grade', 'relative_path'};
    if ~all(ismember(requiredColumns, splitTable.Properties.VariableNames))
        error('data:validateSplits:InvalidSchema', ...
            'Split %s does not contain the required columns.', splitName);
    end
    if numel(unique(string(splitTable.image_id))) ~= height(splitTable)
        error('data:validateSplits:DuplicateImage', ...
            'Split %s contains duplicate image IDs.', splitName);
    end
    if numel(unique(string(splitTable.patient_id))) ~= height(splitTable)
        error('data:validateSplits:DuplicatePatient', ...
            'Split %s contains duplicate patient IDs.', splitName);
    end

    splitTables{splitIndex} = splitTable;
    allRows = [allRows; splitTable]; %#ok<AGROW>
end

for left = 1:numel(splitNames)
    leftPatients = string(splitTables{left}.patient_id);
    for right = left + 1:numel(splitNames)
        rightPatients = string(splitTables{right}.patient_id);
        overlap = intersect(leftPatients, rightPatients);
        if ~isempty(overlap)
            error('data:validateSplits:PatientOverlap', ...
                'Patient IDs overlap between %s and %s.', splitNames{left}, splitNames{right});
        end
    end
end

allIds = string(allRows.image_id);
if numel(unique(allIds)) ~= height(allRows)
    error('data:validateSplits:DuplicateAcrossSplits', ...
        'An image ID appears in more than one split.');
end
if ~isequal(sort(allIds), sort(sourceIds))
    error('data:validateSplits:ImageCoverage', ...
        'The split files do not contain exactly the labelled APTOS image set.');
end

[isKnown, sourceLocations] = ismember(allIds, sourceIds);
if ~all(isKnown)
    error('data:validateSplits:UnknownImage', 'A split contains an unknown image ID.');
end
if ~isequal(double(allRows.grade), sourceGrades(sourceLocations))
    error('data:validateSplits:GradeMismatch', ...
        'At least one split grade does not match the source labels.');
end

sourceClasses = unique(sourceGrades)';
sourceClassCounts = arrayfun(@(grade) sum(sourceGrades == grade), sourceClasses);
classesExpectedInEverySplit = sourceClasses(sourceClassCounts >= numel(splitNames));
gradeCounts = zeros(numel(splitNames), numel(sourceClasses));
for splitIndex = 1:numel(splitNames)
    splitGrades = double(splitTables{splitIndex}.grade);
    gradeCounts(splitIndex, :) = arrayfun(@(grade) sum(splitGrades == grade), sourceClasses);
    if ~all(ismember(classesExpectedInEverySplit, unique(splitGrades)))
        error('data:validateSplits:MissingGrade', ...
            'Split %s is missing a grade that can be represented.', splitNames{splitIndex});
    end
end

report = struct();
report.splitNames = splitNames;
report.rowCounts = cellfun(@height, splitTables)';
report.gradeValues = sourceClasses;
report.gradeCounts = gradeCounts;
report.classesExpectedInEverySplit = classesExpectedInEverySplit;
report.totalRows = height(allRows);
report.patientOverlapChecked = true;
report.everyImageExactlyOnce = true;
end

