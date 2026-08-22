classdef TestSealedDataProtection < matlab.unittest.TestCase
%TESTSEALEDDATAPROTECTION Guards the Messidor-2 seal (design doc S10.4).
%   Fails if Messidor-2 material reappears under data/raw/, if it is
%   missing from data/sealed/, or if any pipeline entry point accepts a
%   path under data/sealed/ instead of rejecting it.

    methods (Test)
        function testMessidor2MaterialIsNotUnderDataRaw(testCase)
            rawDir = fullfile(TestSealedDataProtection.projectRoot(), 'data', 'raw');
            offenders = TestSealedDataProtection.findMessidor2Entries(rawDir);
            testCase.verifyEmpty(offenders, ...
                ['Messidor-2 material has reappeared under data/raw/, ', ...
                'which breaks the seal required by design doc S10.4. Found: ', ...
                strjoin(offenders, ', ')]);
        end

        function testMessidor2MaterialIsUnderDataSealed(testCase)
            sealedDir = fullfile(TestSealedDataProtection.projectRoot(), 'data', 'sealed');
            testCase.verifyTrue( ...
                isfile(fullfile(sealedDir, 'messidor2-dr-grades.zip')), ...
                'Messidor-2 grade archive is missing from data/sealed/.');
            testCase.verifyTrue( ...
                isfile(fullfile(sealedDir, 'messidor2_grades', 'messidor_data.csv')), ...
                'Messidor-2 grade CSV is missing from data/sealed/messidor2_grades/.');
        end

        function testRunScreeningCaseRejectsSealedImagePath(testCase)
            sealedImage = fullfile(TestSealedDataProtection.projectRoot(), ...
                'data', 'sealed', 'messidor2_grades', 'messidor_data.csv');
            testCase.verifyError(@() app.runScreeningCase(sealedImage, ...
                'checkpoint.mat', 1.0, struct()), 'app:SealedData');
        end

        function testGradCamRejectsSealedCheckpointPath(testCase)
            sealedCheckpoint = fullfile(TestSealedDataProtection.projectRoot(), ...
                'data', 'sealed', 'messidor2-dr-grades.zip');
            testCase.verifyError(@() explain.gradcam(sealedCheckpoint, ...
                zeros(4, 4, 3), 2), 'explain:SealedData');
        end

        function testFitTemperatureRejectsSealedCalibrationSplit(testCase)
            tempCheckpoint = [tempname, '.mat'];
            fclose(fopen(tempCheckpoint, 'w'));
            cleanup = onCleanup(@() delete(tempCheckpoint)); %#ok<NASGU>

            sealedSplit = fullfile(TestSealedDataProtection.projectRoot(), ...
                'data', 'sealed', 'messidor2_grades', 'messidor_data.csv');
            testCase.verifyError(@() grade.fitTemperature(tempCheckpoint, ...
                sealedSplit), 'grade:InvalidCalibrationSplit');
        end

        function testReportGenerateRejectsSealedResultsRoot(testCase)
            sealedResultsRoot = fullfile(TestSealedDataProtection.projectRoot(), ...
                'data', 'sealed', 'results');
            fakeResult = struct('placeholder', true);
            testCase.verifyError(@() report.generate(fakeResult, ...
                'ResultsRoot', sealedResultsRoot), 'report:SealedData');
        end
    end

    methods (Static, Access = private)
        function root = projectRoot()
            testFile = which('TestSealedDataProtection');
            root = fileparts(fileparts(testFile));
        end

        function offenders = findMessidor2Entries(rawDir)
            offenders = {};
            if ~isfolder(rawDir)
                return;
            end
            patterns = {'*messidor2*', '*messidor_data*', '*messidor_readme*'};
            for patternIndex = 1:numel(patterns)
                found = dir(fullfile(rawDir, '**', patterns{patternIndex}));
                for entryIndex = 1:numel(found)
                    offenders{end + 1} = fullfile(found(entryIndex).folder, ...
                        found(entryIndex).name); %#ok<AGROW>
                end
            end
            offenders = unique(offenders);
        end
    end
end
