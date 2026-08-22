classdef TestEvaluationMetrics < matlab.unittest.TestCase
    %TESTEVALUATIONMETRICS Behavioral tests for the evaluation harness.

    methods (TestClassSetup)
        function addEvaluationPaths(~)
            testFile = which('TestEvaluationMetrics');
            projectRoot = fileparts(fileparts(testFile));
            addpath(fullfile(projectRoot, 'eval'));
            addpath(fullfile(projectRoot, 'eval', 'metrics'));
        end
    end

    methods (Test)
        function perfectFiveClassPredictions(testCase)
            actual = 0:4;
            predicted = 0:4;

            expectedMatrix = eye(5);
            testCase.verifyEqual(confusionMatrix(actual, predicted), expectedMatrix);
            testCase.verifyEqual(perClassRecall(actual, predicted), ones(5, 1));

            metrics = referableMetrics(actual, predicted);
            testCase.verifyEqual(metrics.sensitivity, 1);
            testCase.verifyEqual(metrics.specificity, 1);
        end

        function oneErrorInEachClass(testCase)
            actual = [0 1 2 3 4 0 1 2 3 4];
            predicted = [1 2 3 4 0 0 1 2 3 4];

            expectedMatrix = [
                1 1 0 0 0
                0 1 1 0 0
                0 0 1 1 0
                0 0 0 1 1
                1 0 0 0 1];
            testCase.verifyEqual(confusionMatrix(actual, predicted), expectedMatrix);
            testCase.verifyEqual(perClassRecall(actual, predicted), repmat(0.5, 5, 1));

            metrics = referableMetrics(actual, predicted);
            testCase.verifyEqual(metrics.sensitivity, 5 / 6);
            testCase.verifyEqual(metrics.specificity, 3 / 4);
        end

        function noPredictionsForOneClassProducesZeroRecall(testCase)
            actual = [0 1 2 3 4 4];
            predicted = [0 1 2 4 4 4];

            matrix = confusionMatrix(actual, predicted);
            recalls = perClassRecall(actual, predicted);

            testCase.verifySize(matrix, [5 5]);
            testCase.verifyEqual(matrix(:, 4), zeros(5, 1));
            testCase.verifyEqual(recalls, [1; 1; 1; 0; 1]);
        end

        function allPredictionsLevelZeroProduceCollapseWarning(testCase)
            actual = 0:4;
            predicted = zeros(1, 5);

            output = evalc('result = harness(actual, predicted);');

            testCase.verifyTrue(result.collapseWarning);
            testCase.verifyEqual(result.perClassRecall, [1; 0; 0; 0; 0]);
            testCase.verifyNotEmpty(strfind(output, 'WARNING')); %#ok<STREMP>
            testCase.verifyNotEmpty(strfind(output, 'majority-class collapse')); %#ok<STREMP>
            testCase.verifyNotEmpty(strfind(output, 'Full confusion matrix')); %#ok<STREMP>
            testCase.verifyNotEmpty(strfind(output, 'Binary sensitivity')); %#ok<STREMP>
            testCase.verifyNotEmpty(strfind(output, 'Binary specificity')); %#ok<STREMP>
            testCase.verifyNotEmpty(strfind(output, 'Number of samples')); %#ok<STREMP>
            testCase.verifyEmpty(strfind(lower(output), 'accuracy')); %#ok<STREMP>
        end

        function wilsonIntervalsMatchHandComputedBoundsForRegularCase(testCase)
            actual = [0 1 2 3 4 0 1 2 3 4];
            predicted = [1 2 3 4 0 0 1 2 3 4];

            metrics = referableMetrics(actual, predicted);

            testCase.verifyEqual(metrics.sensitivityCILower, 0.4364905634, 'AbsTol', 1e-8);
            testCase.verifyEqual(metrics.sensitivityCIUpper, 0.9699474141, 'AbsTol', 1e-8);
            testCase.verifyEqual(metrics.specificityCILower, 0.3006360524, 'AbsTol', 1e-8);
            testCase.verifyEqual(metrics.specificityCIUpper, 0.9544139374, 'AbsTol', 1e-8);
        end

        function wilsonIntervalsMatchHandComputedBoundsForZeroOverNCase(testCase)
            actual = [0 0 2 2];
            predicted = [0 0 0 0];

            metrics = referableMetrics(actual, predicted);

            testCase.verifyEqual(metrics.sensitivity, 0);
            testCase.verifyEqual(metrics.sensitivityCILower, 0, 'AbsTol', 1e-8);
            testCase.verifyEqual(metrics.sensitivityCIUpper, 0.6576280471, 'AbsTol', 1e-8);

            testCase.verifyEqual(metrics.specificity, 1);
            testCase.verifyEqual(metrics.specificityCILower, 0.3423719529, 'AbsTol', 1e-8);
            testCase.verifyEqual(metrics.specificityCIUpper, 1, 'AbsTol', 1e-8);
        end

        function wilsonIntervalsMatchHandComputedBoundsForNOverNCase(testCase)
            actual = [0 0 2 2];
            predicted = [2 2 2 2];

            metrics = referableMetrics(actual, predicted);

            testCase.verifyEqual(metrics.sensitivity, 1);
            testCase.verifyEqual(metrics.sensitivityCILower, 0.3423719529, 'AbsTol', 1e-8);
            testCase.verifyEqual(metrics.sensitivityCIUpper, 1, 'AbsTol', 1e-8);

            testCase.verifyEqual(metrics.specificity, 0);
            testCase.verifyEqual(metrics.specificityCILower, 0, 'AbsTol', 1e-8);
            testCase.verifyEqual(metrics.specificityCIUpper, 0.6576280471, 'AbsTol', 1e-8);
        end

        function wilsonIntervalsAreNaNWhenDenominatorIsZero(testCase)
            actual = [2 2];
            predicted = [2 2];

            metrics = referableMetrics(actual, predicted);

            testCase.verifyTrue(isnan(metrics.specificity));
            testCase.verifyTrue(isnan(metrics.specificityCILower));
            testCase.verifyTrue(isnan(metrics.specificityCIUpper));
        end

        function harnessPrintsWilsonIntervalsAndCounts(testCase)
            actual = [0 0 2 2];
            predicted = [0 0 0 0];

            output = evalc('harness(actual, predicted);');

            testCase.verifyNotEmpty(strfind(output, 'Wilson CI')); %#ok<STREMP>
            testCase.verifyNotEmpty(strfind(output, '0/2')); %#ok<STREMP>
            testCase.verifyNotEmpty(strfind(output, '2/2')); %#ok<STREMP>
        end

        function referableThresholdStartsAtLevelTwo(testCase)
            actual = [0 1 2 3 4];
            predicted = [0 1 1 3 4];

            metrics = referableMetrics(actual, predicted);

            testCase.verifyEqual(metrics.sensitivity, 2 / 3);
            testCase.verifyEqual(metrics.specificity, 1);
            testCase.verifyEqual(metrics.referableThreshold, 2);
        end

        function invalidLabelsOutsideFiveClassRangeAreRejected(testCase)
            testCase.verifyError( ...
                @() confusionMatrix([0 1 5], [0 1 2]), ...
                'evaluation:InvalidLabels');
        end

        function differentLengthLabelAndPredictionVectorsAreRejected(testCase)
            testCase.verifyError( ...
                @() confusionMatrix([0 1], [0]), ...
                'evaluation:LabelLengthMismatch');
        end

        function emptyInputVectorsAreRejected(testCase)
            testCase.verifyError( ...
                @() confusionMatrix([], []), ...
                'evaluation:EmptyInput');
        end
    end
end
