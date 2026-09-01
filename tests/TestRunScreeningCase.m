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
            % Six of the eight evidence fields have no detector in this
            % build, so the rule engine is uncertain on every image.  That is
            % a capability gap and it must not by itself route the case to a
            % human.  This assertion used to pin 'escalate', which is how a
            % pipeline that escalated all 550 validation cases kept a green
            % test suite: the test encoded the defect as the expectation.
            testCase.verifyFalse(result.icdrRuleResult.caseUnknownEvidence);
            testCase.verifyFalse(result.icdrRuleResult.humanEscalationRecommended);
            % Two fields are covered: microaneurysm count from the classical
            % candidate detector, and hard exudate count from the learned
            % head adopted on 31 August 2026.  It was seven gap fields and an
            % unreachable referral level while the classical channel shipped
            % alone.  The hard-exudate head is what lifts the rule engine's
            % ceiling to Level 2, and so what makes the §8.6 level comparison
            % run on this image at all.
            testCase.verifyNumElements( ...
                result.icdrRuleResult.capabilityGapFields, 6);
            testCase.verifyTrue(result.icdrRuleResult.referableLevelReachable);
            % The limitation must still reach the clinician-facing output.
            % It is named 'evidence-capability-gap' rather than
            % 'capability-capped' because the rule engine is no longer capped
            % below the referral boundary, while six of its eight fields
            % still have no detector and the clinician must be told so.
            testCase.verifySubstring(result.threeWayDecision.explanation, ...
                'evidence-capability-gap');
            testCase.verifySubstring(strjoin(result.warnings, newline), ...
                'Capability gap');
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

        function limitationsAgreeWithTheEvidenceActuallyUsed(testCase)
            % Regression test. The limitations block and the ICDR rule trace
            % are printed in the same report, and used to contradict each
            % other: limitations said "No learned lesion segmentation is
            % used." while the trace on the same page said the evidence came
            % from learned lesion segmentation. A reader has no way to tell
            % which half to believe, so assert they cannot disagree.
            %
            % Written to follow whichever channel the config selects, so it
            % keeps checking the real invariant if the default config changes.
            [imagePath, checkpointPath, calibrationPath, configPath] = ...
                TestRunScreeningCase.inputs();
            result = app.runScreeningCase(imagePath, checkpointPath, ...
                calibrationPath, configPath);

            limitationsText = strjoin(result.limitations, newline);
            evidenceSource = char(result.icdrRuleResult.evidenceSource);
            usedLearnedSegmentation = contains(lower(evidenceSource), ...
                'learned lesion segmentation');

            if usedLearnedSegmentation
                testCase.verifyFalse( ...
                    contains(limitationsText, ...
                        'No learned lesion segmentation is used.'), ...
                    ['The report states that no learned lesion segmentation ', ...
                    'is used, but the evidence source for this case was: ', ...
                    evidenceSource]);
                testCase.verifySubstring(limitationsText, ...
                    'not clinically validated');
            else
                testCase.verifySubstring(limitationsText, ...
                    'No learned lesion segmentation is used.');
            end
        end

        function reportDoesNotLabelAnAutoClearAsAnEscalation(testCase)
            % Regression test. The report printed a hardcoded field named
            % "Escalation reason:" whose value is the reason for whatever was
            % decided, so an auto-cleared case rendered as
            %   Escalation reason: Auto-clear: concordant, ...
            % Anyone skimming the report reads "Escalation" and concludes the
            % case escalated. The GUI carried the same label, over a helper
            % already named localDecisionReason.
            [imagePath, checkpointPath, calibrationPath, configPath] = ...
                TestRunScreeningCase.inputs();
            result = app.runScreeningCase(imagePath, checkpointPath, ...
                calibrationPath, configPath);

            resultsRoot = fullfile(tempdir, ['report_label_' ...
                char(matlab.lang.makeValidName(datestr(now, 'HHMMSSFFF')))]);
            testCase.addTeardown(@() TestRunScreeningCase.removeTree(resultsRoot));
            generated = report.generate(result, 'ResultsRoot', resultsRoot);

            reportText = fileread(strrep(char(generated.reportPath), ...
                '.pdf', '.txt'));
            testCase.verifySubstring(reportText, 'Decision reason:');
            testCase.verifyFalse(contains(reportText, 'Escalation reason:'), ...
                ['The report labels its decision-reason field as an ', ...
                'escalation reason, which misreads on any case that did ', ...
                'not escalate.']);
        end

    end

    methods (Static, Access = private)
        function removeTree(path)
            if isfolder(path)
                rmdir(path, 's');
            end
        end

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
