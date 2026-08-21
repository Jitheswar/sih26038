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
