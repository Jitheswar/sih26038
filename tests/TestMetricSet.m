classdef TestMetricSet < matlab.unittest.TestCase
    %TESTMETRICSET Tests for the §11.3 metrics added alongside the harness.
    %
    %   Every expected value here is computed by hand in the test comment.
    %   A metric that is only smoke-tested will happily report a plausible
    %   wrong number for the rest of the project's life.

    methods (TestClassSetup)
        function addSourcePath(~)
            projectRoot = fileparts(fileparts(which('TestMetricSet')));
            addpath(genpath(fullfile(projectRoot, 'src')));
            addpath(fullfile(projectRoot, 'eval'));
            addpath(fullfile(projectRoot, 'eval', 'metrics'));
        end
    end

    methods (Test)
        % ------------------------------------------- quadratic weighted kappa

        function kappaIsOneForPerfectAgreement(testCase)
            labels = [0; 1; 2; 3; 4];
            result = quadraticWeightedKappa(labels, labels);
            testCase.verifyEqual(result.kappa, 1, 'AbsTol', 1e-12);
        end

        function kappaIsZeroAtChanceAgreement(testCase)
            % true [0 0 1 1] against predicted [0 1 0 1].
            % Confusion has 1 in each of the four 0/1 cells, so observed
            % disagreement equals expected disagreement and kappa is 0.
            trueLabels = [0; 0; 1; 1];
            predicted = [0; 1; 0; 1];
            result = quadraticWeightedKappa(trueLabels, predicted);
            testCase.verifyEqual(result.kappa, 0, 'AbsTol', 1e-12);
        end

        function kappaIsNegativeForSystematicReversal(testCase)
            trueLabels = [0; 0; 4; 4];
            predicted = [4; 4; 0; 0];
            result = quadraticWeightedKappa(trueLabels, predicted);
            testCase.verifyLessThan(result.kappa, -0.9);
        end

        function kappaPenalisesDistantConfusionMore(testCase)
            trueLabels = [0; 1; 2; 3; 4];
            adjacent = [1; 2; 3; 4; 3];
            distant = [4; 4; 4; 0; 0];
            adjacentKappa = quadraticWeightedKappa(trueLabels, adjacent).kappa;
            distantKappa = quadraticWeightedKappa(trueLabels, distant).kappa;
            testCase.verifyGreaterThan(adjacentKappa, distantKappa);
        end

        function kappaIsUndefinedWhenEverythingIsOneGrade(testCase)
            % No variance in either rater: agreement is perfect but chance
            % agreement is also perfect, so kappa must not report 1.
            result = quadraticWeightedKappa([2; 2; 2], [2; 2; 2]);
            testCase.verifyTrue(isnan(result.kappa));
        end

        % ---------------------------------------------------------- ROC / AUC

        function aucMatchesHandComputedValue(testCase)
            % scores [0.1 0.4 0.35 0.8], labels [0 0 1 1].
            % Concordant pairs: (0.35,0.1) (0.8,0.1) (0.8,0.4) = 3 of 4.
            scores = [0.1; 0.4; 0.35; 0.8];
            labels = [false; false; true; true];
            result = rocMetrics(labels, scores);
            testCase.verifyEqual(result.auc, 0.75, 'AbsTol', 1e-12);
        end

        function aucIsOneForPerfectSeparation(testCase)
            scores = [0.1; 0.2; 0.8; 0.9];
            labels = [false; false; true; true];
            testCase.verifyEqual(rocMetrics(labels, scores).auc, 1, 'AbsTol', 1e-12);
        end

        function aucIsHalfForTiedScores(testCase)
            % Every score identical: the ranking carries no information.
            scores = [0.5; 0.5; 0.5; 0.5];
            labels = [false; false; true; true];
            testCase.verifyEqual(rocMetrics(labels, scores).auc, 0.5, 'AbsTol', 1e-12);
        end

        function aucIsUndefinedWithOneClassPresent(testCase)
            result = rocMetrics([true; true], [0.2; 0.9]);
            testCase.verifyTrue(isnan(result.auc));
        end

        % ------------------------------------------------- precision / recall

        function averagePrecisionMatchesHandComputedValue(testCase)
            % scores [0.9 0.8 0.7], labels [1 0 1].
            % precision at each positive: 1/1 and 2/3; recall steps 0.5 each.
            % AP = 1*0.5 + (2/3)*0.5 = 0.833333...
            scores = [0.9; 0.8; 0.7];
            labels = [true; false; true];
            result = precisionRecallMetrics(labels, scores);
            testCase.verifyEqual(result.averagePrecision, 5/6, 'AbsTol', 1e-12);
        end

        function averagePrecisionIsOneForPerfectRanking(testCase)
            scores = [0.9; 0.8; 0.2; 0.1];
            labels = [true; true; false; false];
            result = precisionRecallMetrics(labels, scores);
            testCase.verifyEqual(result.averagePrecision, 1, 'AbsTol', 1e-12);
        end

        function baselinePrecisionIsThePositiveRate(testCase)
            labels = [true; false; false; false];
            result = precisionRecallMetrics(labels, [0.4; 0.3; 0.2; 0.1]);
            testCase.verifyEqual(result.baselinePrecision, 0.25, 'AbsTol', 1e-12);
        end

        % --------------------------------------------------- predictive values

        function predictiveValuesMatchHandComputedValues(testCase)
            % sens 0.9, spec 0.9, prevalence 0.1.
            % PPV = .09/(.09+.09) = 0.5;  NPV = .81/(.81+.01) = 0.987804...
            result = predictiveValues(0.9, 0.9, 0.1);
            testCase.verifyEqual(result.ppv, 0.5, 'AbsTol', 1e-12);
            testCase.verifyEqual(result.npv, 0.81 / 0.82, 'AbsTol', 1e-12);
        end

        function positivePredictiveValueFallsWithPrevalence(testCase)
            high = predictiveValues(0.95, 0.9, 0.4).ppv;
            low = predictiveValues(0.95, 0.9, 0.02).ppv;
            testCase.verifyGreaterThan(high, low);
        end

        function predictiveValuesRejectRatesOutsideUnitInterval(testCase)
            testCase.verifyError(@() predictiveValues(1.2, 0.9, 0.1), 'eval:InvalidRate');
            testCase.verifyError(@() predictiveValues(0.9, 0.9, -0.1), 'eval:InvalidRate');
        end

        % ------------------------------------------------------- risk-coverage

        function riskCoverageMatchesHandComputedValue(testCase)
            % correct [T T F] ranked by confidence [3 2 1].
            % risk at coverage 1/3, 2/3, 1 is 0, 0, 1/3; AURC = mean = 1/9.
            result = riskCoverage([true; true; false], [3; 2; 1]);
            testCase.verifyEqual(result.aurc, 1/9, 'AbsTol', 1e-12);
            testCase.verifyEqual(result.risk(end), 1/3, 'AbsTol', 1e-12);
        end

        function goodConfidenceRankingBeatsBadOne(testCase)
            correct = [true; true; true; false];
            good = [4; 3; 2; 1];
            bad = [1; 2; 3; 4];
            testCase.verifyLessThan(riskCoverage(correct, good).aurc, ...
                riskCoverage(correct, bad).aurc);
        end

        function riskAtFullCoverageIsTheBaseErrorRate(testCase)
            correct = [true; false; true; false];
            result = riskCoverage(correct, [4; 3; 2; 1]);
            testCase.verifyEqual(result.risk(end), result.baseRisk, 'AbsTol', 1e-12);
        end

        % ---------------------------------------------- misses at coverage

        function missesAtFullCoverageAreTheClassifierOwnMissCount(testCase)
            % truth [T T F F T] against predicted [T F F T F].
            % Referable and sent home at ranks 2 and 5, so 2 misses.
            % Any disagreement at ranks 2, 4 and 5, so 3 symmetric errors.
            truth = [true; true; false; false; true];
            predicted = [true; false; false; true; false];
            result = missesAtCoverage(truth, predicted, [5; 4; 3; 2; 1], 1);
            testCase.verifyEqual(result.misses, 2);
            testCase.verifyEqual(result.symmetricErrors, 3);
            testCase.verifyEqual(result.totalMisses, 2);
            testCase.verifyEqual(result.retained, 5);
            testCase.verifyEqual(result.achievedCoverage, 1, 'AbsTol', 1e-12);
            testCase.verifyEqual(result.n, 5);
        end

        function missesCountReferableSentHomeAndNotFalsePositives(testCase)
            % Every case not referable and every case predicted referable:
            % four false positives and no patient sent home.  riskCoverage
            % scores this as total failure because it treats the two errors
            % alike; the veto's subject is the patient who goes home.
            truth = [false; false; false; false];
            predicted = [true; true; true; true];
            confidence = [4; 3; 2; 1];
            result = missesAtCoverage(truth, predicted, confidence, 1);
            testCase.verifyEqual(result.misses, 0);
            testCase.verifyEqual(result.symmetricErrors, 4);
            testCase.verifyEqual( ...
                riskCoverage(predicted == truth, confidence).risk(end), 1, ...
                'AbsTol', 1e-12);
        end

        function truncationShedsTheLeastConfidentMisses(testCase)
            % confidence ranks the five cases idx2, idx4, idx1, idx5, idx3.
            % Misses sit at idx3 and idx5, the two least confident; a third
            % error, a false positive, sits at idx2, the most confident.
            % Retaining 3, 4 and 5 cases gives 0, 1 and 2 misses against
            % 1, 2 and 3 symmetric errors.
            truth = [true; false; true; true; true];
            predicted = [true; true; false; true; false];
            confidence = [0.5; 0.9; 0.1; 0.7; 0.3];
            result = missesAtCoverage(truth, predicted, confidence, ...
                [0.6; 0.8; 1.0]);
            testCase.verifyEqual(result.retained, [3; 4; 5]);
            testCase.verifyEqual(result.misses, [0; 1; 2]);
            testCase.verifyEqual(result.symmetricErrors, [1; 2; 3]);
        end

        function tiedConfidenceAtTheBoundaryIsExcludedWhole(testCase)
            % Three cases tied at 0.5.  Asking for 3 of 5 cuts that group,
            % so the whole group is dropped and only the 0.9 case is kept:
            % 1 retained and 0 misses, not 3 retained and 2 misses.
            % Asking for 4 of 5 cuts below the group, which keeps it.
            truth = [true; true; true; true; true];
            predicted = [true; false; false; false; false];
            confidence = [0.9; 0.5; 0.5; 0.5; 0.1];
            cut = missesAtCoverage(truth, predicted, confidence, 0.6);
            testCase.verifyEqual(cut.retained, 1);
            testCase.verifyEqual(cut.achievedCoverage, 0.2, 'AbsTol', 1e-12);
            testCase.verifyEqual(cut.misses, 0);

            below = missesAtCoverage(truth, predicted, confidence, 0.8);
            testCase.verifyEqual(below.retained, 4);
            testCase.verifyEqual(below.misses, 3);
        end

        function tieExclusionDoesNotDependOnInputOrder(testCase)
            % Two cases tied at 0.5, one a miss and one correct, with the
            % boundary between them.  Keeping whichever the input happened
            % to list first would report 1 miss for one ordering and 0 for
            % the other; dropping the group reports 0 for both.
            confidence = [0.9; 0.5; 0.5];
            truth = [false; true; true];
            first = missesAtCoverage(truth, [false; false; true], confidence, 2/3);
            second = missesAtCoverage(truth, [false; true; false], confidence, 2/3);
            testCase.verifyEqual(first.retained, 1);
            testCase.verifyEqual(second.retained, 1);
            testCase.verifyEqual(first.misses, 0);
            testCase.verifyEqual(second.misses, 0);
        end

        function everyConfidenceTiedRetainsNothingBelowFullCoverage(testCase)
            % A ranking that does not rank cannot hold any coverage below
            % all of it, so the baseline is zero misses over zero cases and
            % vetoes everything.  Full coverage has no boundary to cut and
            % still reports the classifier's own count.
            truth = [true; true; true; true];
            predicted = [false; false; false; false];
            confidence = [0.5; 0.5; 0.5; 0.5];
            half = missesAtCoverage(truth, predicted, confidence, 0.5);
            testCase.verifyEqual(half.retained, 0);
            testCase.verifyEqual(half.misses, 0);
            full = missesAtCoverage(truth, predicted, confidence, 1);
            testCase.verifyEqual(full.retained, 4);
            testCase.verifyEqual(full.misses, 4);
        end

        function zeroCoverageRetainsNothing(testCase)
            result = missesAtCoverage([true; true], [false; false], [2; 1], 0);
            testCase.verifyEqual(result.retained, 0);
            testCase.verifyEqual(result.misses, 0);
            testCase.verifyEqual(result.symmetricErrors, 0);
        end

        function curveIsReportedAtEachDistinctConfidenceLevel(testCase)
            % confidence [0.9 0.5 0.5 0.1] resolves three truncations, plus
            % the empty one: 0, 1, 3 and 4 cases retained.  Misses sit at
            % idx2, inside the tied pair, and at idx4, so the cumulative
            % miss counts are 0, 0, 1 and 2.
            truth = [true; true; true; true];
            predicted = [true; false; true; false];
            result = missesAtCoverage(truth, predicted, [0.9; 0.5; 0.5; 0.1], 1);
            testCase.verifyEqual(result.curve.retained, [0; 1; 3; 4]);
            testCase.verifyEqual(result.curve.coverage, [0; 0.25; 0.75; 1], ...
                'AbsTol', 1e-12);
            testCase.verifyEqual(result.curve.misses, [0; 0; 1; 2]);
            testCase.verifyEqual(result.curve.symmetricErrors, [0; 0; 1; 2]);
        end

        function unusableCoverageAndConfidenceAreRejected(testCase)
            truth = [true; false];
            predicted = [false; false];
            testCase.verifyError( ...
                @() missesAtCoverage(truth, predicted, [2; 1], 1.2), ...
                'eval:InvalidCoverage');
            testCase.verifyError( ...
                @() missesAtCoverage(truth, predicted, [2; 1], -0.1), ...
                'eval:InvalidCoverage');
            testCase.verifyError( ...
                @() missesAtCoverage(truth, predicted, [2; 1], NaN), ...
                'eval:InvalidCoverage');
            testCase.verifyError( ...
                @() missesAtCoverage(truth, predicted, [NaN; 1], 1), ...
                'eval:InvalidConfidence');
        end

        function mismatchedLengthsAreRejected(testCase)
            testCase.verifyError(@() rocMetrics([true; false], [0.1; 0.2; 0.3]), ...
                'eval:LengthMismatch');
            testCase.verifyError(@() riskCoverage([true; false], [1; 2; 3]), ...
                'eval:LengthMismatch');
            testCase.verifyError( ...
                @() missesAtCoverage([true; false], [true; false], [1; 2; 3], 1), ...
                'eval:LengthMismatch');
            testCase.verifyError( ...
                @() missesAtCoverage([true; false], [true; false; true], [1; 2], 1), ...
                'eval:LengthMismatch');
        end
    end
end
