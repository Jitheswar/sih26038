classdef TestGradingBaseline < matlab.unittest.TestCase
    %TESTGRADINGBASELINE Tests for the five-class APTOS grading baseline.

    methods (TestClassSetup)
        function addSourceAndEvaluationPaths(~)
            testFile = which('TestGradingBaseline');
            projectRoot = fileparts(fileparts(testFile));
            addpath(genpath(fullfile(projectRoot, 'src')));
            addpath(genpath(fullfile(projectRoot, 'eval')));
        end
    end

    methods (Test)
        function modelHasFiveOutputClasses(testCase)
            result = grade.train(TestGradingBaseline.defaultConfig(), ...
                'Mode', 'inspect');

            testCase.verifyEqual(result.modelConfig.numClasses, 5);
            testCase.verifyEqual(result.network.Layers(end - 1).OutputSize, 5);
        end

        function configuredInputSizeIsRespected(testCase)
            result = grade.train(TestGradingBaseline.defaultConfig(), ...
                'Mode', 'inspect');

            testCase.verifyEqual(result.modelConfig.inputSize, [448 448 3]);
            testCase.verifyEqual(result.config.grading.input_size, 448);
        end

        function datastoresUseOnlyTheirDeclaredSplits(testCase)
            result = grade.train(TestGradingBaseline.defaultConfig(), ...
                'Mode', 'inspect');
            trainFiles = string(result.datastores.train.Files);
            validationFiles = string(result.datastores.validation.Files);
            testFiles = string(result.datastores.test.Files);

            testCase.verifyEqual(result.data.train.split, "train");
            testCase.verifyEqual(result.data.validation.split, "validation");
            testCase.verifyEqual(result.data.test.split, "test");
            testCase.verifyEmpty(intersect(trainFiles, validationFiles));
            testCase.verifyEmpty(intersect(trainFiles, testFiles));
            testCase.verifyEmpty(intersect(validationFiles, testFiles));
            testCase.verifyTrue(all(contains(trainFiles, "aptos2019")));
            testCase.verifyTrue(all(contains(validationFiles, "aptos2019")));
            testCase.verifyTrue(all(contains(testFiles, "aptos2019")));
        end

        function testDatastoreCannotSelectCheckpoint(testCase)
            result = grade.train(TestGradingBaseline.defaultConfig(), ...
                'Mode', 'inspect');

            testCase.verifyEqual(result.checkpointSelection.split, "validation");
            testCase.verifyFalse(result.checkpointSelection.testUsed);
            testCase.verifyEqual(result.checkpointSelection.metric, ...
                "validationMacroRecallThenLoss");
        end

        function classWeightsExistForAllFiveClasses(testCase)
            result = grade.train(TestGradingBaseline.defaultConfig(), ...
                'Mode', 'inspect');

            testCase.verifySize(result.classWeights, [5 1]);
            testCase.verifyTrue(all(isfinite(result.classWeights)));
            testCase.verifyTrue(all(result.classWeights > 0));
            testCase.verifyEqual(numel(result.data.train.classCounts), 5);
        end

        function smokeTrainingCompletesAndLogsAllClasses(testCase)
            resultsRoot = tempname;
            cleanup = onCleanup(@() TestGradingBaseline.removeDirectory(resultsRoot)); %#ok<NASGU>
            result = grade.train(TestGradingBaseline.defaultConfig(), ...
                'Mode', 'smoke', 'ResultsRoot', resultsRoot);

            testCase.verifyEqual(result.status, "completed");
            testCase.verifyEqual(result.history.epochsCompleted, 1);
            testCase.verifyTrue(isfolder(result.resultsDirectory));
            testCase.verifySize(result.history.validation(1).confusionMatrix, [5 5]);
            testCase.verifySize(result.history.validation(1).perClassRecall, [5 1]);
            testCase.verifyTrue(all(isfinite(result.history.validation(1).perClassRecall)));
            testCase.verifyEqual(result.history.validation(1).zeroRecallLevels, ...
                find(result.history.validation(1).perClassRecall == 0) - 1);
            testCase.verifyFalse(result.checkpointSelection.testUsed);
        end

        % The EvaluateTest opt-in path is deliberately not exercised end to
        % end by this automated suite: the held-out test split is touched
        % once, by hand, after the operating point is frozen (see
        % docs/SIH26038_design.html §10.4/§11.2). Only smoke/inspect modes
        % run here, plus fast-failing option validation that never reaches
        % data loading.
        function smokeModeNeverEvaluatesTheTestSplit(testCase)
            resultsRoot = tempname;
            cleanup = onCleanup(@() TestGradingBaseline.removeDirectory(resultsRoot)); %#ok<NASGU>

            output = evalc(['result = grade.train(TestGradingBaseline.defaultConfig(), ' ...
                '''Mode'', ''smoke'', ''ResultsRoot'', resultsRoot);']);

            testCase.verifyFalse(result.checkpointSelection.testUsed);
            testCase.verifyEmpty(result.testMetrics);
            testCase.verifyEmpty(strfind(output, 'TEST epoch')); %#ok<STREMP>
            testCase.verifyFalse(isfile( ...
                fullfile(char(result.resultsDirectory), 'test_metrics.mat')));
        end

        function preprocessedCacheServesIdenticalImages(testCase)
            % The preprocessing memoisation must serve byte-identical
            % tensors. Preprocessing itself is deterministic, so a warmed
            % cache must reproduce the freshly computed result exactly.
            first = grade.train(TestGradingBaseline.defaultConfig(), ...
                'Mode', 'inspect');
            sampleCount = 3;
            freshImages = cell(sampleCount, 1);
            for index = 1:sampleCount
                freshImages{index} = read(first.datastores.train);
            end

            % A second store over the same files is served from cache.
            second = grade.train(TestGradingBaseline.defaultConfig(), ...
                'Mode', 'inspect');
            for index = 1:sampleCount
                testCase.verifyEqual(read(second.datastores.train), ...
                    freshImages{index});
            end
        end

        function augmentBatchIsDeterministicUnderSeed(testCase)
            batch = repmat(single(reshape(0:191, [8 8 3])), [1 1 1 4]) / 255;
            rng(7, 'twister');
            first = grade.augmentBatch(batch);
            rng(7, 'twister');
            second = grade.augmentBatch(batch);

            testCase.verifyEqual(first, second);
        end

        function augmentBatchStaysWithinJitterEnvelope(testCase)
            batch = single(100 * ones([8 8 3 6]));
            rng(11, 'twister');
            augmented = grade.augmentBatch(batch);

            testCase.verifyEqual(size(augmented), size(batch));
            testCase.verifyEqual(class(augmented), 'single');
            testCase.verifyTrue(all(isfinite(augmented(:))));
            % Gain in [0.9, 1.1] and bias in [-10, 10] around constant 100
            % keeps every value inside this envelope.
            testCase.verifyTrue(all(augmented(:) >= 100 * 0.9 - 10 - 1e-5));
            testCase.verifyTrue(all(augmented(:) <= 100 * 1.1 + 10 + 1e-5));
        end

        function augmentBatchVariesAcrossSamplesAndSeeds(testCase)
            batch = repmat(single(reshape(0:191, [8 8 3])), [1 1 1 16]);
            rng(3, 'twister');
            first = grade.augmentBatch(batch);
            rng(31337, 'twister');
            second = grade.augmentBatch(batch);

            testCase.verifyTrue(~isequal(first, second), ...
                'Different seeds must produce different augmentations.');
        end

        function evaluateTestIsRejectedOutsideNormalMode(testCase)
            testCase.verifyError(@() grade.train(TestGradingBaseline.defaultConfig(), ...
                'Mode', 'smoke', 'EvaluateTest', true), 'grade:InvalidEvaluateTest');
        end

        function evaluateTestRejectsNonLogicalValues(testCase)
            testCase.verifyError(@() grade.train(TestGradingBaseline.defaultConfig(), ...
                'EvaluateTest', '0'), 'grade:InvalidEvaluateTest');
        end
    end

    methods (Static, Access = private)
        function configFile = defaultConfig()
            testFile = which('TestGradingBaseline');
            projectRoot = fileparts(fileparts(testFile));
            configFile = fullfile(projectRoot, 'config', 'default.json');
        end

        function removeDirectory(directory)
            if isfolder(directory)
                rmdir(directory, 's');
            end
        end
    end
end
