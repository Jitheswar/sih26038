classdef TestCalibration < matlab.unittest.TestCase
    %TESTCALIBRATION Tests temperature scaling and calibration metrics.

    methods (TestClassSetup)
        function addCalibrationPaths(~)
            testFile = which('TestCalibration');
            projectRoot = fileparts(fileparts(testFile));
            addpath(genpath(fullfile(projectRoot, 'src')));
            addpath(genpath(fullfile(projectRoot, 'eval')));
        end
    end

    methods (Test)
        function temperatureOneLeavesLogitsUnchanged(testCase)
            logits = [2 -1 0; 0 3 1; -2 0 4; 1 1 -1; 0 -2 2];
            [~, scaledLogits] = grade.applyTemperature(logits, 1);
            testCase.verifyEqual(scaledLogits, logits);
        end

        function temperatureChangesProbabilitiesPredictably(testCase)
            logits = [2; 0; 0; 0; 0];
            probabilities = grade.applyTemperature(logits, 2);
            expected = exp([1; 0; 0; 0; 0]) / (exp(1) + 4);
            testCase.verifyEqual(probabilities, expected, 'AbsTol', 1e-12);
        end

        function nonPositiveTemperatureIsRejected(testCase)
            logits = zeros(5, 2);
            testCase.verifyError(@() grade.applyTemperature(logits, 0), ...
                'grade:InvalidTemperature');
            testCase.verifyError(@() grade.applyTemperature(logits, -1), ...
                'grade:InvalidTemperature');
        end

        function probabilitiesAreNormalizedAndFinite(testCase)
            logits = [1000 -1000; 0 0; -1000 1000; 5 -5; -3 3];
            probabilities = grade.applyTemperature(logits, 0.5);
            testCase.verifyEqual(sum(probabilities, 1), [1 1], 'AbsTol', 1e-12);
            testCase.verifyTrue(all(isfinite(probabilities(:))));
        end

        function perfectConfidenceDoesNotCrashFitting(testCase)
            logits = -1000 * ones(5, 5);
            logits(1, 1) = 1000;
            logits(2, 2) = 1000;
            logits(3, 3) = 1000;
            logits(4, 4) = 1000;
            logits(5, 5) = 1000;
            fit = grade.fitTemperature(logits, 0:4);
            testCase.verifyTrue(isfinite(fit.temperature));
            testCase.verifyGreaterThan(fit.temperature, 0);
            testCase.verifyNotEqual(fit.optimizationStatus, "failed");
        end

        function calibrationMetadataIdentifiesCalibrationOnly(testCase)
            logits = eye(5);
            fit = grade.fitTemperature(logits, 0:4, ...
                'CalibrationSplitIdentifier', 'calibration.csv', ...
                'ModelCheckpointPath', 'results/baseline/best_model.mat', ...
                'TrainingConfiguration', struct('seed', 42));
            testCase.verifyEqual(fit.calibrationSplitIdentifier, "calibration.csv");
            testCase.verifyFalse(contains(lower(char(fit.calibrationSplitIdentifier)), 'test'));
            testCase.verifyEqual(fit.trainingConfiguration.seed, 42);
        end

        function testSetPathIsRejectedByFitting(testCase)
            logits = zeros(5, 2);
            labels = [0 1];
            testCase.verifyError(@() grade.fitTemperature(logits, labels, ...
                'CalibrationSplitIdentifier', fullfile('data', 'splits', 'test.csv')), ...
                'grade:InvalidCalibrationSplit');
        end

        function referableLabelsUseGradeTwoBoundary(testCase)
            labels = (0:4).';
            raw = eye(5);
            metrics = eval.calibrationMetrics(labels, raw, raw);
            testCase.verifyEqual(metrics.raw.referableDR.labels, [0; 0; 1; 1; 1]);
            testCase.verifyEqual(metrics.calibrated.referableDR.labels, [0; 0; 1; 1; 1]);
        end

        function handComputedECEAndBrierMatch(testCase)
            labels = [0; 1];
            probabilities = [0.8 0.2; 0.2 0.8; 0 0; 0 0; 0 0];
            metrics = eval.calibrationMetrics(labels, probabilities, probabilities);
            testCase.verifyEqual(metrics.raw.multiclassECE, 0.2, 'AbsTol', 1e-12);
            testCase.verifyEqual(metrics.raw.multiclassBrierScore, 0.08, 'AbsTol', 1e-12);
            testCase.verifyEqual(metrics.raw.meanNegativeLogLikelihood, -log(0.8), ...
                'AbsTol', 1e-12);
            testCase.verifyEqual(metrics.raw.referableDR.binaryECE, 0, 'AbsTol', 1e-12);
            testCase.verifyEqual(metrics.raw.referableDR.binaryBrierScore, 0, ...
                'AbsTol', 1e-12);
        end

        function rawAndCalibratedProbabilitiesRemainSeparate(testCase)
            logits = [2 0; 0 2; 0 0; 0 0; 0 0];
            labels = [0; 1];
            fit = grade.fitTemperature(logits, labels);
            raw = grade.applyTemperature(logits, 1);
            calibrated = grade.applyTemperature(logits, fit.temperature);
            metrics = eval.calibrationMetrics(labels, raw, calibrated);
            testCase.verifyTrue(isfield(metrics, 'raw'));
            testCase.verifyTrue(isfield(metrics, 'calibrated'));
            testCase.verifyFalse(isequal(raw, calibrated));
            testCase.verifyTrue(all(isfinite(calibrated(:))));
        end
    end
end
