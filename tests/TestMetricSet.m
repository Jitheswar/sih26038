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

        function mismatchedLengthsAreRejected(testCase)
            testCase.verifyError(@() rocMetrics([true; false], [0.1; 0.2; 0.3]), ...
                'eval:LengthMismatch');
            testCase.verifyError(@() riskCoverage([true; false], [1; 2; 3]), ...
                'eval:LengthMismatch');
        end
    end
end
