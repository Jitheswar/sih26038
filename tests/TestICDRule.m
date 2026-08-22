classdef TestICDRule < matlab.unittest.TestCase
    %TESTICDRULE Tests the deterministic ICDR evidence rule engine.

    methods (TestClassSetup)
        function addSourcePath(~)
            testFile = which('TestICDRule');
            projectRoot = fileparts(fileparts(testFile));
            addpath(genpath(fullfile(projectRoot, 'src')));
        end
    end

    methods (Test)
        function noLesionsProducesLevelZero(testCase)
            result = grade.icdrRule(TestICDRule.evidence());

            testCase.verifyEqual(result.icdrLevel, 0);
            testCase.verifyFalse(result.referable);
            testCase.verifyEqual(result.firedCriterion, 'no-apparent-retinopathy');
            testCase.verifyNotEmpty(result.ruleTrace);
            testCase.verifyNotEmpty(result.evidenceSummary);
            testCase.verifyNotEmpty(result.uncertaintyWarning);
            testCase.verifyNotEmpty(result.escalationRecommendation);
        end

        function microaneurysmsOnlyProducesLevelOne(testCase)
            evidence = TestICDRule.evidence();
            evidence.microaneurysmCount.value = 3;

            result = grade.icdrRule(evidence);

            testCase.verifyEqual(result.icdrLevel, 1);
            testCase.verifyFalse(result.referable);
            testCase.verifyEqual(result.firedCriterion, 'microaneurysms-only');
        end

        function hardExudatesOnlyProduceLevelTwo(testCase)
            evidence = TestICDRule.evidence();
            evidence.hardExudateCount.value = 1;

            result = grade.icdrRule(evidence);

            testCase.verifyEqual(result.icdrLevel, 2);
            testCase.verifyTrue(result.referable);
        end

        function softExudatesOnlyProduceLevelTwo(testCase)
            evidence = TestICDRule.evidence();
            evidence.softExudateCount.value = 1;

            result = grade.icdrRule(evidence);

            testCase.verifyEqual(result.icdrLevel, 2);
            testCase.verifyTrue(result.referable);
        end

        function haemorrhagesBelowSevereThresholdProduceLevelTwo(testCase)
            evidence = TestICDRule.evidence();
            evidence.haemorrhageCountPerQuadrant.value = [21, 20, 0, 0];

            result = grade.icdrRule(evidence);

            testCase.verifyEqual(result.icdrLevel, 2);
            testCase.verifyTrue(result.referable);
            testCase.verifySubstring(result.ruleTrace, 'strictly >20');
        end

        function moreThan20HaemorrhagesInAllQuadrantsProduceLevelThree(testCase)
            evidence = TestICDRule.evidence();
            evidence.haemorrhageCountPerQuadrant.value = [21, 21, 21, 21];

            result = grade.icdrRule(evidence);

            testCase.verifyEqual(result.icdrLevel, 3);
            testCase.verifyTrue(result.referable);
            testCase.verifySubstring(result.firedCriterion, 'more-than-20');
        end

        function exactly20HaemorrhagesInAllQuadrantsDoNotMeetSevereCriterion(testCase)
            evidence = TestICDRule.evidence();
            evidence.haemorrhageCountPerQuadrant.value = [20, 20, 20, 20];

            result = grade.icdrRule(evidence);

            testCase.verifyEqual(result.icdrLevel, 2);
            testCase.verifyFalse(contains(result.firedCriterion, 'more-than-20'));
            testCase.verifySubstring(result.ruleTrace, 'not fired');
        end

        function MoreThan20HaemorrhagesInOnlyThreeQuadrantsDoNotMeetSevereCriterion(testCase)
            evidence = TestICDRule.evidence();
            evidence.haemorrhageCountPerQuadrant.value = [21, 21, 21, 0];

            result = grade.icdrRule(evidence);

            testCase.verifyEqual(result.icdrLevel, 2);
            testCase.verifyFalse(contains(result.firedCriterion, 'more-than-20'));
        end

        function venousBeadingInExactlyOneQuadrantDoesNotMeetSevereCriterion(testCase)
            evidence = TestICDRule.evidence();
            evidence.venousBeadingPerQuadrant.value = [true, false, false, false];

            result = grade.icdrRule(evidence);

            testCase.verifyEqual(result.icdrLevel, 2);
            testCase.verifyFalse(contains(result.firedCriterion, 'venous-beading'));
        end

        function venousBeadingInTwoQuadrantsProducesLevelThree(testCase)
            evidence = TestICDRule.evidence();
            evidence.venousBeadingPerQuadrant.value = [true, true, false, false];

            result = grade.icdrRule(evidence);

            testCase.verifyEqual(result.icdrLevel, 3);
            testCase.verifyEqual(result.firedCriterion, ...
                'venous-beading-in-two-or-more-quadrants');
        end

        function irmaInOneQuadrantProducesLevelThree(testCase)
            evidence = TestICDRule.evidence();
            evidence.irmaPerQuadrant.value = [true, false, false, false];

            result = grade.icdrRule(evidence);

            testCase.verifyEqual(result.icdrLevel, 3);
            testCase.verifyEqual(result.firedCriterion, ...
                'prominent-IRMA-in-one-or-more-quadrants');
        end

        function neovascularisationProducesLevelFour(testCase)
            evidence = TestICDRule.evidence();
            evidence.neovascularisation.value = true;

            result = grade.icdrRule(evidence);

            testCase.verifyEqual(result.icdrLevel, 4);
            testCase.verifyTrue(result.referable);
            testCase.verifyTrue(result.humanEscalationRecommended);
            testCase.verifySubstring(result.escalationRecommendation, 'human');
        end

        function vitreousHaemorrhageProducesLevelFour(testCase)
            evidence = TestICDRule.evidenceWithSeparateHaemorrhageFields();
            evidence.vitreousHaemorrhage.value = true;

            result = grade.icdrRule(evidence);

            testCase.verifyEqual(result.icdrLevel, 4);
        end

        function preretinalHaemorrhageProducesLevelFour(testCase)
            evidence = TestICDRule.evidenceWithSeparateHaemorrhageFields();
            evidence.preretinalHaemorrhage.value = true;

            result = grade.icdrRule(evidence);

            testCase.verifyEqual(result.icdrLevel, 4);
        end

        function microaneurysmsPlusHardExudatesProduceLevelTwo(testCase)
            evidence = TestICDRule.evidence();
            evidence.microaneurysmCount.value = 4;
            evidence.hardExudateCount.value = 2;

            result = grade.icdrRule(evidence);

            testCase.verifyEqual(result.icdrLevel, 2);
        end

        function proliferativeCriteriaTakePriorityOverSevereCriteria(testCase)
            evidence = TestICDRule.evidence();
            evidence.haemorrhageCountPerQuadrant.value = [21, 21, 21, 21];
            evidence.neovascularisation.value = true;

            result = grade.icdrRule(evidence);

            testCase.verifyEqual(result.icdrLevel, 4);
            testCase.verifyEqual(result.firedCriterion, 'neovascularisation');
            testCase.verifySubstring(result.ruleTrace, 'Level 4 criteria checked first');
        end

        function unknownLesionEvidenceDoesNotMeanZero(testCase)
            evidence = TestICDRule.evidence();
            evidence.microaneurysmCount = TestICDRule.unknown();
            evidence.hardExudateCount = TestICDRule.unknown();

            result = grade.icdrRule(evidence);

            testCase.verifyEqual(result.icdrLevel, 0);
            testCase.verifyTrue(result.uncertain);
            testCase.verifySubstring(result.uncertaintyWarning, 'unknown');
            testCase.verifySubstring(result.ruleTrace, 'not treated as zero');
            testCase.verifyTrue(result.humanEscalationRecommended);
        end

        function unknownNeovascularisationProducesUncertaintyWarning(testCase)
            evidence = TestICDRule.evidence();
            evidence.neovascularisation = TestICDRule.unknown();

            result = grade.icdrRule(evidence);

            testCase.verifyTrue(result.uncertain);
            testCase.verifySubstring(result.uncertaintyWarning, 'neovascularisation');
            testCase.verifyTrue(result.humanEscalationRecommended);
        end

        function unknownEvidenceRecommendsEscalation(testCase)
            evidence = TestICDRule.evidence();
            evidence.irmaPerQuadrant = TestICDRule.unknown();

            result = grade.icdrRule(evidence);

            testCase.verifyTrue(result.humanEscalationRecommended);
            testCase.verifySubstring(result.escalationRecommendation, 'Escalate');
        end

        function everyOutputHasReadableRuleTrace(testCase)
            result = grade.icdrRule(TestICDRule.evidence());

            testCase.verifySubstring(result.ruleTrace, 'Received evidence');
            testCase.verifySubstring(result.ruleTrace, 'Criterion fired');
            testCase.verifySubstring(result.ruleTrace, 'Final ICDR level');
            testCase.verifySubstring(result.ruleTrace, 'Referable DR');
            testCase.verifySubstring(result.ruleTrace, 'Human escalation recommended');
        end

        function candidateEvidenceIsNotCalledValidated(testCase)
            result = grade.icdrRule(TestICDRule.evidence());

            testCase.verifySubstring(result.evidenceSummary, 'not confirmed lesions');
            testCase.verifySubstring(result.ruleTrace, 'not clinically confirmed lesions');
            testCase.verifyEqual(result.clinicalValidationStatus, ...
                'not clinically validated');
        end

        function missingRequiredFieldIsRejected(testCase)
            evidence = TestICDRule.evidence();
            evidence = rmfield(evidence, 'hardExudateCount');

            testCase.verifyError(@() grade.icdrRule(evidence), ...
                'grade:MissingEvidenceField');
        end

        function negativeCountIsRejected(testCase)
            evidence = TestICDRule.evidence();
            evidence.microaneurysmCount.value = -1;

            testCase.verifyError(@() grade.icdrRule(evidence), ...
                'grade:InvalidEvidenceValue');
        end

        function nonIntegerCountIsRejected(testCase)
            evidence = TestICDRule.evidence();
            evidence.hardExudateCount.value = 1.5;

            testCase.verifyError(@() grade.icdrRule(evidence), ...
                'grade:InvalidEvidenceValue');
        end

        function wrongNumberOfQuadrantsIsRejected(testCase)
            evidence = TestICDRule.evidence();
            evidence.haemorrhageCountPerQuadrant.value = [1, 2, 3];

            testCase.verifyError(@() grade.icdrRule(evidence), ...
                'grade:InvalidEvidenceValue');
        end

        function invalidLogicalValueIsRejected(testCase)
            evidence = TestICDRule.evidence();
            evidence.neovascularisation.value = 1;

            testCase.verifyError(@() grade.icdrRule(evidence), ...
                'grade:InvalidEvidenceValue');
        end

        function incorrectlyRepresentedUnknownEvidenceIsRejected(testCase)
            evidence = TestICDRule.evidence();
            evidence.neovascularisation.known = 'unknown';

            testCase.verifyError(@() grade.icdrRule(evidence), ...
                'grade:InvalidEvidenceKnownStatus');
        end
    end

    methods (Static, Access = private)
        function evidence = evidence()
            evidence = struct();
            evidence.evidenceSource = 'classical candidate evidence';
            evidence.clinicalValidationStatus = 'not clinically validated';
            evidence.microaneurysmCount = TestICDRule.known(0);
            evidence.haemorrhageCountPerQuadrant = TestICDRule.known(zeros(1, 4));
            evidence.hardExudateCount = TestICDRule.known(0);
            evidence.softExudateCount = TestICDRule.known(0);
            evidence.venousBeadingPerQuadrant = TestICDRule.known(false(1, 4));
            evidence.irmaPerQuadrant = TestICDRule.known(false(1, 4));
            evidence.neovascularisation = TestICDRule.known(false);
            evidence.vitreousOrPreretinalHaemorrhage = TestICDRule.known(false);
        end

        function evidence = evidenceWithSeparateHaemorrhageFields()
            evidence = TestICDRule.evidence();
            evidence = rmfield(evidence, 'vitreousOrPreretinalHaemorrhage');
            evidence.vitreousHaemorrhage = TestICDRule.known(false);
            evidence.preretinalHaemorrhage = TestICDRule.known(false);
        end

        function item = known(value)
            item = struct('value', value, 'known', true);
        end

        function item = unknown()
            item = struct('value', [], 'known', false);
        end
    end
end
