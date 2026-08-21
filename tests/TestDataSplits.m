classdef TestDataSplits < matlab.unittest.TestCase
    methods (TestClassSetup)
        function addSourcePath(~)
            testFile = which('TestDataSplits');
            projectRoot = fileparts(fileparts(testFile));
            addpath(genpath(fullfile(projectRoot, 'src')));
        end
    end

    methods (Test)
        function testNoPatientOverlap(testCase)
            [~, splitDir] = TestDataSplits.paths();
            tables = TestDataSplits.readSplits(splitDir);
            for left = 1:numel(tables)
                for right = left + 1:numel(tables)
                    overlap = intersect( ...
                        string(tables{left}.patient_id), ...
                        string(tables{right}.patient_id));
                    testCase.verifyEmpty(overlap, ...
                        sprintf('Patient overlap between split %d and %d.', left, right));
                end
            end
        end

        function testExpectedGradesRepresentedWherePossible(testCase)
            [labelsFile, splitDir] = TestDataSplits.paths();
            labels = readtable(labelsFile, 'TextType', 'string');
            grades = double(labels.diagnosis);
            expectedGrades = 0:4;
            testCase.verifyTrue(all(arrayfun( ...
                @(grade) sum(grades == grade) >= 4, expectedGrades)));

            tables = TestDataSplits.readSplits(splitDir);
            for splitIndex = 1:numel(tables)
                splitGrades = double(tables{splitIndex}.grade);
                testCase.verifyTrue(all(ismember(expectedGrades, unique(splitGrades))), ...
                    sprintf('Split %d is missing an expected grade.', splitIndex));
            end
        end

        function testEveryImageExactlyOneSplit(testCase)
            [labelsFile, splitDir] = TestDataSplits.paths();
            labels = readtable(labelsFile, 'TextType', 'string');
            sourceIds = string(labels.id_code);
            tables = TestDataSplits.readSplits(splitDir);
            splitIds = vertcat(tables{:});
            splitIds = string(splitIds.image_id);

            testCase.verifyEqual(numel(splitIds), numel(sourceIds));
            testCase.verifyEqual(numel(unique(splitIds)), numel(sourceIds));
            testCase.verifyEqual(sort(splitIds), sort(sourceIds));
        end

        function testCommittedSplitsPassValidator(testCase)
            [labelsFile, splitDir] = TestDataSplits.paths();
            report = data.validateSplits(labelsFile, splitDir);
            testCase.verifyTrue(report.patientOverlapChecked);
            testCase.verifyTrue(report.everyImageExactlyOnce);
            testCase.verifyEqual(report.totalRows, 3662);
        end

        function testSplitFilesAreReproducible(testCase)
            [labelsFile, committedDir] = TestDataSplits.paths();
            firstDir = tempname;
            secondDir = tempname;
            mkdir(firstDir);
            mkdir(secondDir);
            cleanup = onCleanup(@() TestDataSplits.removeTemporaryDirs(firstDir, secondDir)); %#ok<NASGU>

            data.createSplits(labelsFile, firstDir, 42);
            data.createSplits(labelsFile, secondDir, 42);
            splitNames = {'train', 'validation', 'calibration', 'test'};
            for splitIndex = 1:numel(splitNames)
                splitName = splitNames{splitIndex};
                first = fileread(fullfile(firstDir, splitName + ".csv"));
                second = fileread(fullfile(secondDir, splitName + ".csv"));
                committed = fileread(fullfile(committedDir, splitName + ".csv"));
                testCase.verifyEqual(first, second);
                testCase.verifyEqual(first, committed);
            end
        end
    end

    methods (Static, Access = private)
        function [labelsFile, splitDir] = paths()
            testFile = which('TestDataSplits');
            projectRoot = fileparts(fileparts(testFile));
            labelsFile = fullfile(projectRoot, 'data', 'raw', 'aptos2019', 'train.csv');
            splitDir = fullfile(projectRoot, 'data', 'splits');
        end

        function tables = readSplits(splitDir)
            splitNames = {'train', 'validation', 'calibration', 'test'};
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
