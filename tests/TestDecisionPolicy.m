classdef TestDecisionPolicy < matlab.unittest.TestCase
    %TESTDECISIONPOLICY Tests the three-way screening decision policy.

    methods (TestClassSetup)
        function addSourcePath(~)
            testFile = which('TestDecisionPolicy');
            projectRoot = fileparts(fileparts(testFile));
            addpath(genpath(fullfile(projectRoot, 'src')));
        end
    end

    methods (Test)
        function goodLevelZeroAutoClears(testCase)
            result = grade.decisionPolicy( ...
                TestDecisionPolicy.input(0, 0.05), TestDecisionPolicy.config());

            testCase.verifyDecision(result, 'auto-clear');
            testCase.verifyEqual(result.reasonCodes, {'concordant'});
            testCase.verifyFalse(result.humanReviewRequired);
            testCase.verifyFalse(result.referralSlipRequired);
        end

        function goodLevelOneAutoClears(testCase)
            result = grade.decisionPolicy( ...
                TestDecisionPolicy.input(1, 0.10), TestDecisionPolicy.config());

            testCase.verifyDecision(result, 'auto-clear');
            testCase.verifyEqual(result.agreementStatus, 'concordant');
        end

        function levelTwoAboveReferralThresholdIsReferred(testCase)
            result = grade.decisionPolicy( ...
                TestDecisionPolicy.input(2, 0.80), TestDecisionPolicy.config());

            testCase.verifyDecision(result, 'refer');
            testCase.verifyTrue(result.referralSlipRequired);
            testCase.verifyFalse(result.humanReviewRequired);
        end

        function levelThreeWithSupportingEvidenceIsReferred(testCase)
            result = grade.decisionPolicy( ...
                TestDecisionPolicy.input(3, 0.90), TestDecisionPolicy.config());

            testCase.verifyDecision(result, 'refer');
            testCase.verifyEqual(result.cnnPredictedLevel, 3);
            testCase.verifyEqual(result.icdrRuleLevel, 3);
        end

        function levelFourAlwaysEscalates(testCase)
            result = grade.decisionPolicy( ...
                TestDecisionPolicy.input(4, 0.99), TestDecisionPolicy.config());

            testCase.verifyDecision(result, 'escalate');
            testCase.verifyTrue(ismember('cnn-level-4', result.reasonCodes));
            testCase.verifyTrue(result.humanReviewRequired);
        end

        function ungradableImageEscalates(testCase)
            input = TestDecisionPolicy.input(0, 0.05);
            input.quality.class = 'ungradable';
            result = grade.decisionPolicy(input, TestDecisionPolicy.config());

            testCase.verifyDecision(result, 'escalate');
            testCase.verifyTrue(ismember('quality-ungradable', result.reasonCodes));
        end

        function unsuccessfulBorderlineEnhancementEscalates(testCase)
            input = TestDecisionPolicy.input(0, 0.05);
            input.quality.class = 'borderline';
            input.quality.enhancementApplied = false;
            result = grade.decisionPolicy(input, TestDecisionPolicy.config());

            testCase.verifyDecision(result, 'escalate');
            testCase.verifyTrue(ismember( ...
                'borderline-quality-not-clearly-gradable', result.reasonCodes));
        end

        function highUncertaintyEscalates(testCase)
            input = TestDecisionPolicy.input(0, 0.05);
            input.cnn.uncertaintyScore = 0.80;
            result = grade.decisionPolicy(input, TestDecisionPolicy.config());

            testCase.verifyDecision(result, 'escalate');
            testCase.verifyEqual(result.uncertaintyStatus, 'high');
            testCase.verifyTrue(ismember('high-uncertainty', result.reasonCodes));
        end

        function unsupportedReferableCnnEscalates(testCase)
            input = TestDecisionPolicy.input(2, 0.80);
            input.explanation.lesionEvidenceSupportsCNN = false;
            input.explanation.lesionEvidenceMetadata = struct( ...
                'candidateEvidence', false, 'referable', false);
            input.ruleEngine = TestDecisionPolicy.rule(0, false);
            result = grade.decisionPolicy(input, TestDecisionPolicy.config());

            testCase.verifyDecision(result, 'escalate');
            testCase.verifyEqual(result.agreementStatus, ...
                'CNN referable but evidence unsupported');
            testCase.verifyTrue(ismember( ...
                'cnn-referable-evidence-unsupported', result.reasonCodes));
        end

        function referableEvidenceWithNonReferableCnnEscalates(testCase)
            input = TestDecisionPolicy.input(0, 0.05);
            input.ruleEngine = TestDecisionPolicy.rule(2, true);
            input.explanation.lesionEvidenceSupportsCNN = false;
            input.explanation.lesionEvidenceMetadata = struct( ...
                'candidateEvidence', false, 'referable', true);
            result = grade.decisionPolicy(input, TestDecisionPolicy.config());

            testCase.verifyDecision(result, 'escalate');
            testCase.verifyEqual(result.agreementStatus, ...
                'evidence referable but CNN non-referable');
            testCase.verifyTrue(ismember( ...
                'evidence-referable-cnn-nonreferable', result.reasonCodes));
        end

        function unknownNeovascularisationEscalates(testCase)
            input = TestDecisionPolicy.input(0, 0.05);
            input.ruleEngine = TestDecisionPolicy.rule(0, false);
            input.ruleEngine.uncertain = true;
            input.ruleEngine.missingEvidenceFields = {'neovascularisation'};
            result = grade.decisionPolicy(input, TestDecisionPolicy.config());

            testCase.verifyDecision(result, 'escalate');
            testCase.verifyTrue(ismember( ...
                'unknown-neovascularisation-status', result.reasonCodes));
            testCase.verifyTrue(ismember( ...
                'required-evidence-unknown', result.reasonCodes));
        end

        function spatialDisagreementEscalates(testCase)
            input = TestDecisionPolicy.input(0, 0.05);
            input.explanation.gradCamAndLesionEvidenceSpatiallyAgree = false;
            result = grade.decisionPolicy(input, TestDecisionPolicy.config());

            testCase.verifyDecision(result, 'escalate');
            testCase.verifyEqual(result.agreementStatus, 'spatially inconsistent');
            testCase.verifyTrue(ismember( ...
                'explanation-disagreement', result.reasonCodes));
        end

        function missingRuleEvidenceEscalates(testCase)
            input = TestDecisionPolicy.input(0, 0.05);
            input.ruleEngine = struct();
            result = grade.decisionPolicy(input, TestDecisionPolicy.config());

            testCase.verifyDecision(result, 'escalate');
            testCase.verifyEqual(result.icdrRuleLevel, NaN);
            testCase.verifyTrue(ismember('missing-rule-evidence', result.reasonCodes));
        end

        function missingCalibratedProbabilityNeverUsesRawSoftmax(testCase)
            input = TestDecisionPolicy.input(0, 0.05);
            input.cnn = rmfield(input.cnn, 'calibratedReferableProbability');
            input.cnn.classProbabilities = [0.99 0.005 0.003 0.001 0.001];
            result = grade.decisionPolicy(input, TestDecisionPolicy.config());

            testCase.verifyDecision(result, 'escalate');
            testCase.verifyTrue(isnan(result.calibratedProbability));
            testCase.verifyTrue(ismember( ...
                'missing-calibrated-probability', result.reasonCodes));
        end

        function candidateEvidenceIsProvisional(testCase)
            input = TestDecisionPolicy.input(2, 0.80);
            input.ruleEngine.evidenceSource = 'classical-candidate-detector';
            input.ruleEngine.clinicalValidationStatus = ...
                'not clinically validated';
            input.ruleEngine.candidateEvidenceWarning = ...
                'Candidate evidence is provisional and not clinically validated.';
            result = grade.decisionPolicy(input, TestDecisionPolicy.config());

            testCase.verifyEqual(result.candidateEvidenceStatus, ...
                'provisional_not_clinically_validated');
            testCase.verifySubstring(result.explanation, 'provisional');
            testCase.verifyTrue(ismember( ...
                'candidate-evidence-provisional', result.reasonCodes));
        end

        function reasonCodesAreDeterministic(testCase)
            input = TestDecisionPolicy.input(4, 0.99);
            input.quality.class = 'ungradable';
            input.cnn.uncertaintyScore = 0.90;
            input.explanation.gradCamAndLesionEvidenceSpatiallyAgree = false;
            first = grade.decisionPolicy(input, TestDecisionPolicy.config());
            second = grade.decisionPolicy(input, TestDecisionPolicy.config());

            testCase.verifyEqual(first.reasonCodes, second.reasonCodes);
            testCase.verifyEqual(first.decisionReason, second.decisionReason);
            testCase.verifyEqual(first.explanation, second.explanation);
        end

        function outputsExposeRequiredFieldsAndOnlyThreeDecisions(testCase)
            result = grade.decisionPolicy( ...
                TestDecisionPolicy.input(0, 0.05), TestDecisionPolicy.config());
            required = {'decision', 'decisionReason', 'reasonCodes', ...
                'recommendedAction', 'referralSlipRequired', ...
                'humanReviewRequired', 'calibratedProbability', ...
                'cnnPredictedLevel', 'icdrRuleLevel', 'agreementStatus', ...
                'uncertaintyStatus', 'evidenceQualityStatus', ...
                'explanation'};

            testCase.verifyTrue(all(isfield(result, required)));
            testCase.verifyTrue(ismember(result.decision, ...
                {'auto-clear', 'refer', 'escalate'}));
        end

        function capabilityGapDoesNotForceEscalation(testCase)
            % The defect this pins: four reason codes fired on every image
            % while the only evidence source was classical microaneurysm
            % detection, and they were evaluated before any threshold was
            % read.  Measured over the full validation split the pipeline
            % escalated 550 of 550 cases, so the three-way decision only ever
            % went one way and the ablation could not compare A4 or A5 at any
            % coverage.
            input = TestDecisionPolicy.input(0, 0.05);
            input.ruleEngine = TestDecisionPolicy.cappedRule(0);
            result = grade.decisionPolicy(input, TestDecisionPolicy.config());

            testCase.verifyDecision(result, 'auto-clear');
            testCase.verifyEqual(result.agreementStatus, 'concordant');
        end

        function capabilityCappedRuleDoesNotBlockReferral(testCase)
            % A rule engine capped below Level 2 cannot confirm referability,
            % so requiring its confirmation required the impossible and no
            % case could ever be referred.  Its silence is not a denial.
            input = TestDecisionPolicy.input(2, 0.80);
            input.ruleEngine = TestDecisionPolicy.cappedRule(1);
            result = grade.decisionPolicy(input, TestDecisionPolicy.config());

            testCase.verifyDecision(result, 'refer');
            testCase.verifyTrue(result.referralSlipRequired);
            testCase.verifySubstring(result.agreementBasis, 'capability-capped');
        end

        function disclosuresAreReportedWithoutDecidingTheCase(testCase)
            % Nothing the previous policy surfaced may become invisible; the
            % build limitations must still reach the clinician-facing report.
            input = TestDecisionPolicy.input(0, 0.05);
            input.ruleEngine = TestDecisionPolicy.cappedRule(0);
            result = grade.decisionPolicy(input, TestDecisionPolicy.config());

            testCase.verifyDecision(result, 'auto-clear');
            testCase.verifyTrue(ismember('evidence-capability-gap', ...
                result.reasonCodes));
            testCase.verifyTrue(ismember('unknown-neovascularisation-status', ...
                result.reasonCodes));
            testCase.verifyTrue(ismember('candidate-evidence-provisional', ...
                result.reasonCodes));
            testCase.verifySubstring(result.explanation, ...
                'evidence-capability-gap');
        end

        function caseLevelUnknownEvidenceStillEscalates(testCase)
            % The safety rule that matters is unchanged: a field a detector
            % owns but could not determine on this image still escalates.
            input = TestDecisionPolicy.input(0, 0.05);
            input.ruleEngine = TestDecisionPolicy.cappedRule(0);
            input.ruleEngine.caseUnknownEvidence = true;
            result = grade.decisionPolicy(input, TestDecisionPolicy.config());

            testCase.verifyDecision(result, 'escalate');
            testCase.verifyTrue(ismember('required-evidence-unknown', ...
                result.reasonCodes));
        end

        function escalateOnCapabilityGapRestoresConservativePolicy(testCase)
            % The refuse-everything policy stays reachable from configuration
            % so the ablation can measure both over one code path, per the
            % rule that pipeline stages switch from config and never by
            % editing code.
            input = TestDecisionPolicy.input(0, 0.05);
            input.ruleEngine = TestDecisionPolicy.cappedRule(0);
            config = TestDecisionPolicy.config();
            config.decisionPolicy.escalateOnCapabilityGap = true;

            result = grade.decisionPolicy(input, config);

            testCase.verifyDecision(result, 'escalate');
            testCase.verifyTrue(ismember('evidence-capability-gap', ...
                result.reasonCodes));
        end

        function levelFourEscalatesEvenWithCapabilityGaps(testCase)
            input = TestDecisionPolicy.input(4, 0.99);
            input.ruleEngine = TestDecisionPolicy.cappedRule(1);
            result = grade.decisionPolicy(input, TestDecisionPolicy.config());

            testCase.verifyDecision(result, 'escalate');
            testCase.verifyTrue(ismember('cnn-level-4', result.reasonCodes));
        end

        function findingKindsRunParallelToReasonCodes(testCase)
            % findingKinds names what each reason code is, so it has to line
            % up with reasonCodes entry for entry or the naming is worse than
            % no naming at all.
            input = TestDecisionPolicy.input(4, 0.99);
            input.quality.class = 'ungradable';
            input.ruleEngine = TestDecisionPolicy.cappedRule(1);
            result = grade.decisionPolicy(input, TestDecisionPolicy.config());

            testCase.verifyNumElements(result.findingKinds, ...
                numel(result.reasonCodes));
            testCase.verifyTrue(iscellstr(result.findingKinds)); %#ok<ISCLSTR>
            testCase.verifyTrue(all(ismember(result.findingKinds, ...
                {'safety exception', 'advisory finding', 'capability gap'})));
            testCase.verifyEqual(TestDecisionPolicy.kindOf(result, ...
                'cnn-level-4'), 'safety exception');
            testCase.verifyEqual(TestDecisionPolicy.kindOf(result, ...
                'quality-ungradable'), 'safety exception');
        end

        function advisoryFindingAndCapabilityGapAreDistinguishable(testCase)
            % The bucket this splits.  An advisory finding says something
            % about this image; a capability gap says something about this
            % build and is true of every image.  A reader who cannot tell
            % them apart cannot tell "this image's attention was odd" from
            % "no detector in this build produces that field".
            config = TestDecisionPolicy.config();
            config.decisionPolicy.escalateOnExplanationDisagreement = false;
            input = TestDecisionPolicy.input(0, 0.05);
            input.ruleEngine = TestDecisionPolicy.cappedRule(0);
            input.explanation.gradCamAndLesionEvidenceSpatiallyAgree = false;

            result = grade.decisionPolicy(input, config);

            testCase.verifyDecision(result, 'auto-clear');
            testCase.verifyEqual(TestDecisionPolicy.kindOf(result, ...
                'explanation-spatially-inconsistent'), 'advisory finding');
            testCase.verifyEqual(TestDecisionPolicy.kindOf(result, ...
                'candidate-evidence-provisional'), 'advisory finding');
            testCase.verifyEqual(TestDecisionPolicy.kindOf(result, ...
                'evidence-capability-gap'), 'capability gap');
            testCase.verifyEqual(TestDecisionPolicy.kindOf(result, ...
                'unknown-neovascularisation-status'), 'capability gap');
        end

        function escalateOnCapabilityGapPromotesOnlyCapabilityGaps(testCase)
            % escalateOnCapabilityGap is the maximally conservative policy
            % for the build-level gaps.  Whether an advisory finding
            % escalates is a different question, governed by
            % escalateOnExplanationDisagreement, and this flag must not
            % answer it too.
            config = TestDecisionPolicy.config();
            config.decisionPolicy.escalateOnExplanationDisagreement = false;
            config.decisionPolicy.escalateOnCapabilityGap = true;
            input = TestDecisionPolicy.input(0, 0.05);
            input.ruleEngine = TestDecisionPolicy.cappedRule(0);
            input.explanation.gradCamAndLesionEvidenceSpatiallyAgree = false;

            result = grade.decisionPolicy(input, config);

            testCase.verifyDecision(result, 'escalate');
            testCase.verifyEqual(TestDecisionPolicy.kindOf(result, ...
                'evidence-capability-gap'), 'safety exception');
            testCase.verifyEqual(TestDecisionPolicy.kindOf(result, ...
                'explanation-spatially-inconsistent'), 'advisory finding');
        end

        function anAdvisoryFindingAloneNeverForcesEscalation(testCase)
            % The same case with the capability gaps removed.  Nothing here
            % is a fact that disqualifies the decision, so the advisory
            % findings are reported and the case is still decided.
            config = TestDecisionPolicy.config();
            config.decisionPolicy.escalateOnExplanationDisagreement = false;
            config.decisionPolicy.escalateOnCapabilityGap = true;
            input = TestDecisionPolicy.input(0, 0.05);
            input.ruleEngine.evidenceSource = 'classical-candidate-detector';
            input.explanation.gradCamAndLesionEvidenceSpatiallyAgree = false;

            result = grade.decisionPolicy(input, config);

            testCase.verifyDecision(result, 'auto-clear');
            testCase.verifyEqual(TestDecisionPolicy.kindOf(result, ...
                'candidate-evidence-provisional'), 'advisory finding');
            testCase.verifyEqual(TestDecisionPolicy.kindOf(result, ...
                'explanation-spatially-inconsistent'), 'advisory finding');
        end
    end

    methods (Static, Access = private)
        function kind = kindOf(result, code)
            %KINDOF The finding kind recorded for one reason code.
            index = find(strcmp(result.reasonCodes, code), 1);
            if isempty(index)
                kind = sprintf('%s was not raised at all', code);
                return;
            end
            kind = result.findingKinds{index};
        end

        function input = input(level, probability)
            input = struct();
            input.quality = struct( ...
                'class', 'gradable', ...
                'metadata', struct('source', 'test'), ...
                'enhancementApplied', false);
            input.cnn = struct( ...
                'predictedLevel', level, ...
                'calibratedReferableProbability', probability, ...
                'classProbabilities', [], ...
                'uncertaintyScore', [], ...
                'uncertaintyThreshold', []);
            input.ruleEngine = TestDecisionPolicy.rule(level, level >= 2);
            input.explanation = struct( ...
                'gradCamMetadata', struct('available', true), ...
                'lesionEvidenceMetadata', struct( ...
                'candidateEvidence', false, 'referable', level >= 2), ...
                'gradCamAndLesionEvidenceSpatiallyAgree', true, ...
                'lesionEvidenceSupportsCNN', true);
        end

        function rule = cappedRule(level)
            %CAPPEDRULE The rule result app.runScreeningCase actually produces.
            %   Seven of the eight evidence fields have no detector in this
            %   build, so they are capability gaps rather than case-level
            %   unknowns and the engine cannot reach Level 2.
            gaps = {'haemorrhageCountPerQuadrant', 'hardExudateCount', ...
                'softExudateCount', 'venousBeadingPerQuadrant', ...
                'irmaPerQuadrant', 'neovascularisation', ...
                'vitreousOrPreretinalHaemorrhage'};
            rule = struct( ...
                'icdrLevel', level, ...
                'level', level, ...
                'referable', false, ...
                'escalationRecommendation', 'No escalation recommended.', ...
                'humanEscalationRecommended', false, ...
                'uncertain', true, ...
                'caseUnknownEvidence', false, ...
                'missingEvidenceFields', {gaps}, ...
                'capabilityGapFields', {gaps}, ...
                'caseUnknownFields', {{}}, ...
                'maxReachableLevel', 1, ...
                'referableLevelReachable', false, ...
                'evidenceSource', 'classical candidate evidence', ...
                'clinicalValidationStatus', ...
                'not clinically validated lesion segmentation');
        end

        function rule = rule(level, referable)
            rule = struct( ...
                'icdrLevel', level, ...
                'level', level, ...
                'referable', referable, ...
                'escalationRecommendation', 'No escalation recommended.', ...
                'humanEscalationRecommended', false, ...
                'uncertain', false, ...
                'missingEvidenceFields', {{}}, ...
                'evidenceSource', 'validated-reference-evidence', ...
                'clinicalValidationStatus', 'clinically validated');
        end

        function config = config()
            config = struct();
            config.decisionPolicy = struct( ...
                'referableThreshold', 0.70, ...
                'autoClearThreshold', 0.20, ...
                'uncertaintyThreshold', 0.50, ...
                'requireEvidenceForAutoClear', true, ...
                'alwaysEscalateLevel4', true, ...
                'escalateOnUnknownEvidence', true, ...
                'escalateOnExplanationDisagreement', true);
        end
    end

    methods (Access = private)
        function verifyDecision(testCase, result, expected)
            testCase.verifyEqual(result.decision, expected);
            testCase.verifyEqual(result.humanReviewRequired, ...
                strcmp(expected, 'escalate'));
        end
    end
end
