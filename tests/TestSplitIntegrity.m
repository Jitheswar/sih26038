classdef TestSplitIntegrity < matlab.unittest.TestCase
    properties (Constant, Access = private)
        SplitNames = {'train', 'validation', 'calibration', 'test'}
        ExpectedHeader = {'image_id', 'patient_id', 'grade', 'relative_path'}
        ExpectedImageCount = 3662
        SplitSeed = 42
        ExpectedGradeCounts = [
            1264, 259, 699, 135, 207;
            271, 56, 150, 29, 44;
            180, 37, 100, 19, 29;
            90, 18, 50, 10, 15]
    end

    methods (Test)
        function testAllAptosImagesAppearExactlyOnce(testCase)
            [labelsFile, splitDir] = TestSplitIntegrity.paths();
            labels = readtable(labelsFile, 'TextType', 'string');
            sourceIds = string(labels.id_code);
            splitTables = TestSplitIntegrity.readSplits(splitDir);
            splitIds = vertcat(splitTables{:});
            splitIds = string(splitIds.image_id);

            testCase.verifyEqual(numel(sourceIds), testCase.ExpectedImageCount);
            testCase.verifyEqual(numel(splitIds), testCase.ExpectedImageCount);
            testCase.verifyEqual(numel(unique(sourceIds)), testCase.ExpectedImageCount);
            testCase.verifyEqual(numel(unique(splitIds)), testCase.ExpectedImageCount);
            testCase.verifyEqual(sort(splitIds), sort(sourceIds));
        end

        function testNoImageIdAppearsInMoreThanOneSplit(testCase)
            [~, splitDir] = TestSplitIntegrity.paths();
            splitTables = TestSplitIntegrity.readSplits(splitDir);
            for left = 1:numel(splitTables)
                leftIds = string(splitTables{left}.image_id);
                testCase.verifyEqual(numel(unique(leftIds)), numel(leftIds), ...
                    sprintf('Duplicate image ID within %s.', testCase.SplitNames{left}));
                for right = left + 1:numel(splitTables)
                    overlap = intersect(leftIds, string(splitTables{right}.image_id));
                    testCase.verifyEmpty(overlap, sprintf( ...
                        'Image ID overlap between %s and %s.', ...
                        testCase.SplitNames{left}, testCase.SplitNames{right}));
                end
            end
        end

        function testNoPatientIdAppearsInMoreThanOneSplit(testCase)
            [~, splitDir] = TestSplitIntegrity.paths();
            splitTables = TestSplitIntegrity.readSplits(splitDir);
            for left = 1:numel(splitTables)
                leftPatients = string(splitTables{left}.patient_id);
                testCase.verifyEqual(numel(unique(leftPatients)), numel(leftPatients), ...
                    sprintf('Duplicate patient ID within %s.', testCase.SplitNames{left}));
                for right = left + 1:numel(splitTables)
                    overlap = intersect(leftPatients, ...
                        string(splitTables{right}.patient_id));
                    testCase.verifyEmpty(overlap, sprintf( ...
                        'Patient ID overlap between %s and %s.', ...
                        testCase.SplitNames{left}, testCase.SplitNames{right}));
                end
            end
        end

        function testPatientIdIsDocumentedSurrogate(testCase)
            [~, splitDir] = TestSplitIntegrity.paths();
            splitTables = TestSplitIntegrity.readSplits(splitDir);
            for splitIndex = 1:numel(splitTables)
                splitTable = splitTables{splitIndex};
                testCase.verifyEqual(string(splitTable.patient_id), ...
                    string(splitTable.image_id), sprintf( ...
                    'patient_id is not the documented image_id surrogate in %s.', ...
                    testCase.SplitNames{splitIndex}));
            end
        end

        function testEverySplitHasExpectedHeader(testCase)
            [~, splitDir] = TestSplitIntegrity.paths();
            splitTables = TestSplitIntegrity.readSplits(splitDir);
            for splitIndex = 1:numel(splitTables)
                testCase.verifyEqual(splitTables{splitIndex}.Properties.VariableNames, ...
                    testCase.ExpectedHeader, sprintf( ...
                    'Unexpected header in %s.', testCase.SplitNames{splitIndex}));
            end
        end

        function testEveryGradeIsBetweenZeroAndFour(testCase)
            [~, splitDir] = TestSplitIntegrity.paths();
            splitTables = TestSplitIntegrity.readSplits(splitDir);
            for splitIndex = 1:numel(splitTables)
                grades = double(splitTables{splitIndex}.grade);
                testCase.verifyTrue(all(isfinite(grades)), sprintf( ...
                    'Non-finite grade in %s.', testCase.SplitNames{splitIndex}));
                testCase.verifyTrue(all(ismember(grades, 0:4)), sprintf( ...
                    'Grade outside 0-4 in %s.', testCase.SplitNames{splitIndex}));
            end
        end

        function testExactSplitCountsAndGradeDistributions(testCase)
            [~, splitDir] = TestSplitIntegrity.paths();
            splitTables = TestSplitIntegrity.readSplits(splitDir);
            for splitIndex = 1:numel(splitTables)
                grades = double(splitTables{splitIndex}.grade);
                observed = arrayfun(@(grade) sum(grades == grade), 0:4);
                testCase.verifyEqual(observed, ...
                    testCase.ExpectedGradeCounts(splitIndex, :), sprintf( ...
                    'Unexpected grade distribution in %s.', ...
                    testCase.SplitNames{splitIndex}));
            end
        end

        function testSplitsAreReproducibleAndTrackedByGit(testCase)
            [labelsFile, committedDir, projectRoot] = TestSplitIntegrity.paths();
            firstDir = tempname;
            secondDir = tempname;
            mkdir(firstDir);
            mkdir(secondDir);
            cleanup = onCleanup(@() TestSplitIntegrity.removeTemporaryDirs( ...
                firstDir, secondDir)); %#ok<NASGU>

            data.createSplits(labelsFile, firstDir, testCase.SplitSeed);
            data.createSplits(labelsFile, secondDir, testCase.SplitSeed);
            for splitIndex = 1:numel(testCase.SplitNames)
                splitName = testCase.SplitNames{splitIndex};
                first = fileread(fullfile(firstDir, splitName + ".csv"));
                second = fileread(fullfile(secondDir, splitName + ".csv"));
                committed = fileread(fullfile(committedDir, splitName + ".csv"));
                testCase.verifyEqual(first, second, sprintf( ...
                    'Two fixed-seed generations differ for %s.', splitName));
                testCase.verifyEqual(first, committed, sprintf( ...
                    'Committed %s.csv does not match fixed-seed generation.', ...
                    splitName));
            end

            trackedPaths = cellfun(@(name) fullfile('data', 'splits', ...
                name + ".csv"), testCase.SplitNames, 'UniformOutput', false);
            pathArguments = strjoin(cellfun(@(path) ['"' char(path) '"'], ...
                trackedPaths, 'UniformOutput', false), ' ');
            command = sprintf('git -C "%s" ls-files --error-unmatch -- %s', ...
                projectRoot, pathArguments);
            [status, ~] = system(command);
            testCase.verifyEqual(status, 0, ...
                'One or more split files is not tracked by Git.');
        end
    end

    methods (Static, Access = private)
        function [labelsFile, splitDir, projectRoot] = paths()
            testFile = which('TestSplitIntegrity');
            projectRoot = fileparts(fileparts(testFile));
            labelsFile = fullfile(projectRoot, 'data', 'raw', ...
                'aptos2019', 'train.csv');
            splitDir = fullfile(projectRoot, 'data', 'splits');
        end

        function tables = readSplits(splitDir)
            splitNames = TestSplitIntegrity.SplitNames;
            tables = cell(numel(splitNames), 1);
            for splitIndex = 1:numel(splitNames)
                tables{splitIndex} = readtable( ...
                    fullfile(splitDir, splitNames{splitIndex} + ".csv"), ...
                    'TextType', 'string');
            end
        end

        function removeTemporaryDirs(firstDir, secondDir)
            if isfolder(firstDir)
                rmdir(firstDir, 's');
            end
            if isfolder(secondDir)
                rmdir(secondDir, 's');
            end
        end
    end
end
