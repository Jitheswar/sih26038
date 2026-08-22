classdef TestRunScreeningCase < matlab.unittest.TestCase
    %TESTRUNSCREENINGCASE Tests the integrated screening orchestration seam.

    methods (TestClassSetup)
        function addApplicationPaths(~)
            testFile = which('TestRunScreeningCase');
            projectRoot = fileparts(fileparts(testFile));
            addpath(genpath(fullfile(projectRoot, 'src')));
            addpath(genpath(fullfile(projectRoot, 'eval')));
        end
    end

    methods (Test)
        function validClearImageProducesCompleteResult(testCase)
            [imagePath, checkpointPath, calibrationPath, configPath] = ...
                TestRunScreeningCase.inputs();
            result = app.runScreeningCase(imagePath, checkpointPath, ...
                calibrationPath, configPath);

            required = {'originalImage', 'processedImage', 'qualityResult', ...
                'qualityAdvice', 'predictedICDRLevel', ...
                'calibratedReferableProbability', 'classProbabilities', ...
                'gradCAMResult', 'lesionCandidateEvidence', ...
                'icdrRuleResult', 'threeWayDecision', 'agreementStatus', ...
                'reportMetadata', 'warnings', 'limitations'};
            testCase.verifyTrue(all(isfield(result, required)));
            testCase.verifyEqual(result.status, "completed");
            testCase.verifyEqual(result.reportMetadata.sealedDataAccessed, false);
            testCase.verifyEqual(result.classProbabilitiesAreCalibrated, false);
            testCase.verifyTrue(result.calibratedClassProbabilitiesAreCalibrated);
            testCase.verifyTrue(isfinite(result.calibratedReferableProbability));
            testCase.verifyGreaterThanOrEqual(result.calibratedReferableProbability, 0);
            testCase.verifyLessThanOrEqual(result.calibratedReferableProbability, 1);
            testCase.verifyTrue(ismember(result.threeWayDecision.decision, ...
                {'auto-clear', 'refer', 'escalate'}));
            testCase.verifySubstring(strjoin(result.warnings, newline), ...
                'provisional');
            testCase.verifyTrue(result.icdrRuleResult.uncertain);
            testCase.verifyEqual(result.threeWayDecision.decision, 'escalate');
            testCase.verifySubstring(result.classProbabilitiesDescription, ...
                'Raw softmax');
            testCase.verifySubstring(result.classProbabilitiesDescription, ...
                'not calibrated confidence');
        end

        function invalidImagePathHasClearError(testCase)
            [~, checkpointPath, calibrationPath, configPath] = ...
                TestRunScreeningCase.inputs();
            testCase.verifyError(@() app.runScreeningCase( ...
                fullfile(tempdir, 'does-not-exist.png'), checkpointPath, ...
                calibrationPath, configPath), 'app:MissingImage');
        end

        function unreadableImageHasClearError(testCase)
            [~, checkpointPath, calibrationPath, configPath] = ...
                TestRunScreeningCase.inputs();
            filename = [tempname, '.png'];
            cleanup = onCleanup(@() TestRunScreeningCase.removeFile(filename)); %#ok<NASGU>
            fileIdentifier = fopen(filename, 'w');
            fwrite(fileIdentifier, 'not an image', 'char');
            fclose(fileIdentifier);
            testCase.verifyError(@() app.runScreeningCase( ...
                filename, checkpointPath, calibrationPath, configPath), ...
                'app:UnreadableImage');
        end

        function ungradableImageStopsSafely(testCase)
            [~, checkpointPath, calibrationPath, configPath] = ...
                TestRunScreeningCase.inputs();
            image = zeros(160, 160, 3, 'uint8');
            result = app.runScreeningCase(image, checkpointPath, ...
                calibrationPath, configPath);
            testCase.verifyEqual(result.status, "stopped_quality_gate");
            testCase.verifyEqual(result.qualityResult.class, 'ungradable');
            testCase.verifyEmpty(result.predictedICDRLevel);
            testCase.verifyEqual(result.threeWayDecision.decision, 'escalate');
            testCase.verifyTrue(isempty(fieldnames(result.gradCAMResult)));
        end

        function missingModelCheckpointHasClearError(testCase)
            [imagePath, ~, calibrationPath, configPath] = ...
                TestRunScreeningCase.inputs();
            testCase.verifyError(@() app.runScreeningCase(imagePath, ...
                fullfile(tempdir, 'missing-model.mat'), calibrationPath, ...
                configPath), 'app:MissingCheckpoint');
        end

        function missingCalibrationFileHasClearError(testCase)
            [imagePath, checkpointPath, ~, configPath] = ...
                TestRunScreeningCase.inputs();
            testCase.verifyError(@() app.runScreeningCase(imagePath, ...
                checkpointPath, fullfile(tempdir, 'missing-calibration.mat'), ...
                configPath), 'app:MissingCalibration');
        end

        function levelFourAlwaysEscalates(testCase)
            [imagePath, checkpointPath, calibrationPath, configPath] = ...
                TestRunScreeningCase.inputs();
            config = jsondecode(fileread(configPath));
            config.app.icdrEvidence = TestRunScreeningCase.levelFourEvidence();
            result = app.runScreeningCase(imagePath, checkpointPath, ...
                calibrationPath, config);
            testCase.verifyEqual(result.icdrRuleResult.level, 4);
            testCase.verifyEqual(result.threeWayDecision.decision, 'escalate');
            testCase.verifyTrue(ismember('rule-engine-recommends-escalation', ...
                result.threeWayDecision.reasonCodes));
        end

        function sealedDataIsNeverAccepted(testCase)
            [~, checkpointPath, calibrationPath, configPath] = ...
                TestRunScreeningCase.inputs();
            testCase.verifyError(@() app.runScreeningCase( ...
                fullfile(fileparts(configPath), 'data', 'sealed', 'image.png'), ...
                checkpointPath, calibrationPath, configPath), 'app:SealedData');
        end
    end

    methods (Static, Access = private)
        function [imagePath, checkpointPath, calibrationPath, configPath] = inputs()
            testFile = which('TestRunScreeningCase');
            projectRoot = fileparts(fileparts(testFile));
            imagePath = fullfile(projectRoot, 'data', 'raw', 'aptos2019', ...
                'train_images', '001639a390f0.png');
            checkpointPath = fullfile(projectRoot, 'results', ...
                '20260822_030539', 'best_model.mat');
            calibrationPath = fullfile(projectRoot, 'results', ...
                '20260822_091625', 'temperature_fit.mat');
            configPath = fullfile(projectRoot, 'config', 'default.json');
        end

        function evidence = levelFourEvidence()
            knownFalseCount = struct('value', 0, 'known', true);
            knownFalseVector = struct('value', false(1, 4), 'known', true);
            evidence = struct( ...
                'microaneurysmCount', knownFalseCount, ...
                'haemorrhageCountPerQuadrant', struct('value', zeros(1, 4), 'known', true), ...
                'hardExudateCount', knownFalseCount, ...
                'softExudateCount', knownFalseCount, ...
                'venousBeadingPerQuadrant', knownFalseVector, ...
                'irmaPerQuadrant', knownFalseVector, ...
                'neovascularisation', struct('value', true, 'known', true), ...
                'vitreousOrPreretinalHaemorrhage', knownFalseVector, ...
                'evidenceSource', 'test injected clinical evidence', ...
                'clinicalValidationStatus', 'test-only known evidence');
            evidence.vitreousOrPreretinalHaemorrhage = ...
                struct('value', false, 'known', true);
        end

        function removeFile(filename)
            if isfile(filename)
                delete(filename);
            end
        end
    end
end
