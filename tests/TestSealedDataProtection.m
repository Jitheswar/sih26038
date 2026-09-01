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

        function testExternalValidationRefusesWithoutConfirmation(testCase)
            % eval/externalValidation is the one function permitted to read
            % data/sealed. It must never run by accident: the default call
            % has to fail, or a stray invocation spends the one-shot set.
            projectRoot = TestSealedDataProtection.projectRoot();
            addpath(fullfile(projectRoot, 'eval'));
            testCase.verifyError(@() externalValidation(), ...
                'eval:SealNotConfirmed');
            testCase.verifyError(@() externalValidation('ConfirmUnseal', false), ...
                'eval:SealNotConfirmed');
        end

        function testExternalValidationRequiresANamedOperator(testCase)
            % §10.4 names one key holder. An unseal with nobody's name on it
            % is not an auditable unseal.
            projectRoot = TestSealedDataProtection.projectRoot();
            addpath(fullfile(projectRoot, 'eval'));
            testCase.verifyError( ...
                @() externalValidation('ConfirmUnseal', true), ...
                'eval:MissingOperator');
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

        function testGradCamRejectsASymlinkPlacedUnderTheSeal(testCase)
            % Regression test. gradcam canonicalises the checkpoint path with
            % getCanonicalPath before checking it, and canonicalising resolves
            % symlinks. A link under data/sealed therefore used to reach the
            % guard as a path outside the seal, and was accepted: the observed
            % failure was explain:InvalidCheckpoint, meaning the file had been
            % opened, rather than explain:SealedData.
            testCase.assumeTrue(isunix, ...
                'Symlink creation in this test assumes a Unix shell.');

            outsideTarget = [tempname, '.mat'];
            fclose(fopen(outsideTarget, 'w'));
            linkPath = fullfile(TestSealedDataProtection.projectRoot(), ...
                'data', 'sealed', 'symlink_regression_probe.mat');

            testCase.addTeardown(@() TestSealedDataProtection.removeIfPresent(linkPath));
            testCase.addTeardown(@() TestSealedDataProtection.removeIfPresent(outsideTarget));

            [status, message] = system(sprintf('ln -sfn %s %s', ...
                outsideTarget, linkPath));
            testCase.assumeEqual(status, 0, ...
                sprintf('Could not create the test symlink: %s', message));

            testCase.verifyError(@() explain.gradcam(linkPath, ...
                zeros(4, 4, 3), 2), 'explain:SealedData');
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

        function removeIfPresent(path)
            % java.io.File.delete removes a dangling symlink, which isfile and
            % exist both report as absent once its target has gone. Teardowns
            % run last-added-first, so the link outlives its target here.
            f = java.io.File(path);
            if f.exists() || java.nio.file.Files.isSymbolicLink(f.toPath())
                f.delete();
            end
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
