classdef TestLesionEvidenceHeads < matlab.unittest.TestCase
    %TESTLESIONEVIDENCEHEADS Tests restricting which lesion heads are trusted.
    %   §11.7 measured the soft-exudate head reporting a median of 46
    %   lesions on APTOS eyes graded 0.  ICDR Level 2 fires on the presence
    %   of any non-microaneurysm finding, so the evidence channel ORs its
    %   heads together and one untrustworthy head caps the specificity of
    %   the whole channel.  Restricting the heads is the remedy, and these
    %   tests pin the two properties it depends on: a dropped head must
    %   disappear from the evidence, and it must be declared a capability
    %   gap rather than a per-case unknown.

    methods (TestClassSetup)
        function addSourcePath(~)
            testFile = which('TestLesionEvidenceHeads');
            projectRoot = fileparts(fileparts(testFile));
            addpath(genpath(fullfile(projectRoot, 'src')));
        end
    end

    methods (Test)
        function unrestrictedEvidenceKnowsEveryTrainedHead(testCase)
            evidence = grade.icdrEvidenceFromLesionSegmentation( ...
                TestLesionEvidenceHeads.lesionEvidence());

            coverage = evidence.evidenceFieldCoverage;
            testCase.verifyTrue(coverage.microaneurysmCount);
            testCase.verifyTrue(coverage.haemorrhageCountPerQuadrant);
            testCase.verifyTrue(coverage.hardExudateCount);
            testCase.verifyTrue(coverage.softExudateCount);
        end

        function restrictingToExudatesDropsTheOtherHeads(testCase)
            evidence = grade.icdrEvidenceFromLesionSegmentation( ...
                TestLesionEvidenceHeads.lesionEvidence(), [], {'EX'});

            coverage = evidence.evidenceFieldCoverage;
            testCase.verifyTrue(coverage.hardExudateCount);
            testCase.verifyFalse(coverage.softExudateCount);
            testCase.verifyFalse(coverage.haemorrhageCountPerQuadrant);
            testCase.verifyFalse(coverage.microaneurysmCount);
            testCase.verifyEqual(evidence.hardExudateCount.value, 7);
        end

        function aDroppedHeadIsACapabilityGapNotACaseUnknown(testCase)
            % The distinction is load-bearing: grade.icdrRule escalates on a
            % case-level unknown, so a permanent restriction reported as a
            % per-case unknown would escalate every patient and disable the
            % triage the system exists to perform (§8.5).
            result = grade.icdrRule( ...
                grade.icdrEvidenceFromLesionSegmentation( ...
                TestLesionEvidenceHeads.lesionEvidence(), [], {'EX'}));

            testCase.verifyTrue(ismember('softExudateCount', ...
                result.capabilityGapFields));
            testCase.verifyFalse(ismember('softExudateCount', ...
                result.caseUnknownFields));
            testCase.verifyFalse(result.caseUnknownEvidence);
        end

        function restrictingChangesTheLevelWhenTheDroppedHeadDroveIt(testCase)
            % Soft exudates alone reach Level 2. With only hard exudates
            % trusted and none present, the same frame is not referable.
            noisy = TestLesionEvidenceHeads.lesionEvidence();
            noisy.counts.EX = 0;
            noisy.counts.SE = 40;

            unrestricted = grade.icdrRule( ...
                grade.icdrEvidenceFromLesionSegmentation(noisy));
            restricted = grade.icdrRule( ...
                grade.icdrEvidenceFromLesionSegmentation(noisy, [], {'EX'}));

            testCase.verifyTrue(unrestricted.referable);
            testCase.verifyFalse(restricted.referable);
        end

        function requestingAHeadTheNetworkLacksIsAnError(testCase)
            testCase.verifyError(@() ...
                grade.icdrEvidenceFromLesionSegmentation( ...
                TestLesionEvidenceHeads.lesionEvidence(), [], {'NVD'}), ...
                'grade:NoTrustedLesionHeads');
        end

        function characterHeadIsAccepted(testCase)
            evidence = grade.icdrEvidenceFromLesionSegmentation( ...
                TestLesionEvidenceHeads.lesionEvidence(), [], 'EX');

            testCase.verifyTrue(evidence.evidenceFieldCoverage.hardExudateCount);
            testCase.verifyFalse(evidence.evidenceFieldCoverage.softExudateCount);
        end
    end

    methods (Static)
        function evidence = lesionEvidence()
            %LESIONEVIDENCE A minimal stand-in for segment.lesionEvidence.
            evidence = struct( ...
                'lesionTypes', {{'MA', 'HE', 'EX', 'SE'}}, ...
                'counts', struct('MA', 12, 'HE', 5, 'EX', 7, 'SE', 3), ...
                'haemorrhageQuadrantCounts', ...
                    struct('ST', 2, 'IT', 1, 'SN', 1, 'IN', 1));
        end
    end
end
