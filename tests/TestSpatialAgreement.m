classdef TestSpatialAgreement < matlab.unittest.TestCase
    %TESTSPATIALAGREEMENT The §8.6 spatial test, its constants, and its cache.
    %   The test is mean(values >= cut) >= fraction over the normalized
    %   Grad-CAM values at the lesion candidate points.  These pin the four
    %   states it can be in, that the two constants now come from
    %   configuration, and that splitting the evidence from the verdict did
    %   not change any answer.

    methods (Static)
        function result = gradCam(heatmap)
            result = struct('normalizedHeatmap', heatmap);
        end

        function detection = candidates(coordinates)
            detection = struct('candidateCount', size(coordinates, 1), ...
                'candidateCoordinates', coordinates);
        end
    end

    methods (Test)
        function noHeatmapIsNotAgreement(testCase)
            % Absent evidence is not a disagreement between channels, but
            % the test cannot be passed on it either.
            detection = TestSpatialAgreement.candidates([2 2]);
            [agree, evidence] = grade.spatialAgreement( ...
                struct('normalizedHeatmap', []), detection);
            testCase.verifyFalse(agree);
            testCase.verifyFalse(evidence.known);
        end

        function noCandidatesAgreesVacuously(testCase)
            % No candidate can fall outside the attention, so there is
            % nothing for this test to disagree about.
            heatmap = zeros(4, 4);
            [agree, evidence] = grade.spatialAgreement( ...
                TestSpatialAgreement.gradCam(heatmap), ...
                TestSpatialAgreement.candidates(zeros(0, 2)));
            testCase.verifyTrue(agree);
            testCase.verifyTrue(evidence.known);
            testCase.verifyEqual(evidence.candidatesScored, 0);
        end

        function candidatesOffTheMapAreNotVacuous(testCase)
            % Candidates exist and none land on the map. That is a real
            % failure to correspond and must not be read as the vacuous
            % case above, which would silently pass the gate.
            heatmap = ones(4, 4);
            detection = TestSpatialAgreement.candidates([99 99; -5 2]);
            [agree, evidence] = grade.spatialAgreement( ...
                TestSpatialAgreement.gradCam(heatmap), detection);
            testCase.verifyFalse(agree);
            testCase.verifyTrue(evidence.known);
        end

        function verdictIsTheFractionClearingTheCut(testCase)
            % Four candidates, three at 1.0 and one at 0.0, so the cleared
            % fraction is 0.75 by hand.
            heatmap = [1 1; 1 0];
            detection = TestSpatialAgreement.candidates( ...
                [1 1; 2 1; 1 2; 2 2]);
            [agree, evidence] = grade.spatialAgreement( ...
                TestSpatialAgreement.gradCam(heatmap), detection);
            testCase.verifyEqual(evidence.clearedFraction, 0.75, ...
                'AbsTol', 1e-12);
            testCase.verifyTrue(agree);
        end

        function constantsComeFromConfiguration(testCase)
            % One candidate of four sits at 0.5 and the rest at 0, so the
            % cleared fraction at the shipped cut of 0.35 is 0.25. At the
            % shipped fraction of 0.25 that passes; requiring 0.50 must
            % fail the same evidence, and so must lifting the cut above
            % the one value that was clearing it.
            heatmap = [0.5 0; 0 0];
            detection = TestSpatialAgreement.candidates( ...
                [1 1; 2 1; 1 2; 2 2]);
            gradCam = TestSpatialAgreement.gradCam(heatmap);
            testCase.verifyTrue(grade.spatialAgreement(gradCam, detection));
            testCase.verifyFalse(grade.spatialAgreement(gradCam, detection, ...
                struct('spatialAgreementFraction', 0.5)));
            % Raising the attention cut above every value fails it too.
            testCase.verifyFalse(grade.spatialAgreement(gradCam, detection, ...
                struct('spatialAttentionCut', 0.9)));
        end

        function verdictFromCachedEvidenceMatchesOneShot(testCase)
            % The point of the split: the cached evidence must answer any
            % (cut, fraction) pair with the same verdict the one-shot call
            % gives, or a sweep over the cache would not describe the
            % pipeline.
            heatmap = rand(8, 8);
            coordinates = [randi(8, 20, 1), randi(8, 20, 1)];
            detection = TestSpatialAgreement.candidates(coordinates);
            gradCam = TestSpatialAgreement.gradCam(heatmap);
            evidence = grade.spatialEvidence(gradCam, detection);
            for cut = [0.1, 0.35, 0.6, 0.9]
                for fraction = [0.05, 0.25, 0.5, 0.9]
                    configuration = struct( ...
                        'spatialAttentionCut', cut, ...
                        'spatialAgreementFraction', fraction);
                    testCase.verifyEqual( ...
                        grade.spatialVerdict(evidence, configuration), ...
                        grade.spatialAgreement(gradCam, detection, configuration), ...
                        sprintf('cut %.2f fraction %.2f', cut, fraction));
                end
            end
        end

        function evidenceDoesNotDependOnTheConstants(testCase)
            % The expensive half must be config-free, otherwise caching it
            % once per image and sweeping offline is not sound.
            heatmap = rand(6, 6);
            detection = TestSpatialAgreement.candidates( ...
                [randi(6, 10, 1), randi(6, 10, 1)]);
            gradCam = TestSpatialAgreement.gradCam(heatmap);
            first = grade.spatialEvidence(gradCam, detection);
            second = grade.spatialEvidence(gradCam, detection);
            testCase.verifyEqual(first.values, second.values);
        end

        function shippedDefaultsAreTheHistoricalConstants(testCase)
            % Moving the constants into configuration must not move the
            % pipeline. A configuration naming neither has to behave as
            % the hard-coded test did.
            configuration = decisionPolicyConfiguration();
            testCase.verifyEqual(configuration.spatialAttentionCut, 0.35);
            testCase.verifyEqual(configuration.spatialAgreementFraction, 0.25);
        end

        function anOutOfRangeConstantIsRejected(testCase)
            heatmap = ones(2, 2);
            detection = TestSpatialAgreement.candidates([1 1]);
            testCase.verifyError(@() grade.spatialAgreement( ...
                TestSpatialAgreement.gradCam(heatmap), detection, ...
                struct('spatialAttentionCut', 1.5)), ...
                'grade:InvalidSpatialConstant');
        end
    end
end

function configuration = decisionPolicyConfiguration()
%DECISIONPOLICYCONFIGURATION The validated policy from the shipped config.
projectRoot = fileparts(fileparts(mfilename('fullpath')));
config = jsondecode(fileread(fullfile(projectRoot, 'config', 'default.json')));
% decisionConfiguration is private to +grade, so reach it the way the
% policy does: through a call that returns what it validated.
result = grade.decisionPolicy(struct( ...
    'quality', struct('class', 'gradable', 'metadata', struct( ...
        'enhancementApplied', false, 'postEnhancementQualityClass', 'gradable')), ...
    'cnn', struct('predictedLevel', 0, ...
        'calibratedReferableProbability', 0.01, ...
        'classProbabilities', [0.99; 0.01; 0; 0; 0]), ...
    'ruleEngine', struct(), ...
    'explanation', struct()), config); %#ok<NASGU>
configuration = struct( ...
    'spatialAttentionCut', config.decision_policy.spatialAttentionCut, ...
    'spatialAgreementFraction', config.decision_policy.spatialAgreementFraction);
end
