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

        function trainingAdvancesBatchNormalizationState(testCase)
            % Regression test: forward() computes batch normalization from
            % mini-batch statistics and returns the updated running
            % statistics as a second output. If the training loop drops
            % that output, net.State keeps its ImageNet values forever
            % while the weights fine-tune away from them - and
            % evaluateNetwork scores validation with predict(), which
            % reads net.State. Training loss then falls while validation
            % loss rises and predictions collapse onto a single class,
            % with no error raised anywhere.
            %
            % Smoke mode freezes the backbone through freezeBackboneGradients,
            % which acts on gradients only. So any change to these running
            % statistics can only have come from state propagation, never
            % from a weight update.
            resultsRoot = tempname;
            cleanup = onCleanup(@() TestGradingBaseline.removeDirectory(resultsRoot)); %#ok<NASGU>

            pristine = grade.train(TestGradingBaseline.defaultConfig(), ...
                'Mode', 'inspect');
            trained = grade.train(TestGradingBaseline.defaultConfig(), ...
                'Mode', 'smoke', 'ResultsRoot', resultsRoot);

            beforeState = pristine.network.State;
            afterState = trained.network.State;
            testCase.assertEqual(height(afterState), height(beforeState));
            testCase.assertGreaterThan(height(beforeState), 0, ...
                'ResNet-50 must expose batch normalization state.');

            changed = 0;
            for index = 1:height(beforeState)
                before = gather(extractdata(beforeState.Value{index}));
                after = gather(extractdata(afterState.Value{index}));
                testCase.verifyTrue(all(isfinite(after(:))), ...
                    'Batch normalization state must stay finite.');
                if ~isequal(before, after)
                    changed = changed + 1;
                end
            end

            testCase.verifyEqual(changed, height(beforeState), ...
                'Every batch normalization running statistic must advance during training.');
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

        function augmentBatchAcceptsExplicitStreamDeterministically(testCase)
            batch = repmat(single(reshape(0:191, [8 8 3])), [1 1 1 4]) / 255;
            stream1 = RandStream('mt19937ar', 'Seed', 123);
            stream2 = RandStream('mt19937ar', 'Seed', 123);

            first = grade.augmentBatch(batch, stream1);
            second = grade.augmentBatch(batch, stream2);

            testCase.verifyEqual(first, second);
        end

        function deterministicBatchSeedIsPureAndWellSpread(testCase)
            seedA = grade.deterministicBatchSeed(42, 1);
            seedB = grade.deterministicBatchSeed(42, 1);
            seedC = grade.deterministicBatchSeed(42, 17);
            seedD = grade.deterministicBatchSeed(7, 1);

            testCase.verifyEqual(seedA, seedB);
            testCase.verifyNotEqual(seedA, seedC);
            testCase.verifyNotEqual(seedA, seedD);
            testCase.verifyClass(seedA, 'uint32');
            testCase.verifyLessThan(double(seedA), 2^32);
        end

        function firstBatchContentIsIdenticalAcrossPoolSizes(testCase)
            % Regression test for design doc §13.2: a training batch's
            % content must not depend on how many workers are in the
            % parallel pool. Before the fix, DispatchInBackground let
            % each worker draw augmentation from its own unseeded global
            % stream, so the same logical batch came out with different
            % pixels depending on pool size; collateData now seeds a
            % RandStream from (config.grading.seed, batch identity)
            % instead, which this test exercises through the same
            % minibatchqueue construction createMiniBatchQueue.m uses.
            availableCores = feature('numcores');
            testCase.assumeTrue(availableCores > 2, ...
                'Needs at least 3 cores to compare two distinct pool sizes.');
            largePoolSize = min(6, availableCores);

            result = grade.train(TestGradingBaseline.defaultConfig(), 'Mode', 'inspect');
            config = result.config;
            stores = result.datastores;
            data = result.data;

            cleanupPool = onCleanup(@() TestGradingBaseline.deleteAnyPool()); %#ok<NASGU>

            hashSmallPool = TestGradingBaseline.firstBatchHash(config, stores, data, 2);
            hashLargePool = TestGradingBaseline.firstBatchHash(config, stores, data, largePoolSize);

            testCase.verifyEqual(hashSmallPool, hashLargePool);
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

        function deleteAnyPool()
            existingPool = gcp('nocreate');
            if ~isempty(existingPool)
                delete(existingPool);
            end
        end

        function hexHash = firstBatchHash(config, stores, data, poolSize)
            TestGradingBaseline.deleteAnyPool();
            parpool('local', poolSize);

            seed = config.grading.seed;
            sampleCount = numel(data.train.grades);
            labelStore = arrayDatastore(single(data.train.grades(:) + 1), ...
                'OutputType', 'same');
            indexStore = arrayDatastore((1:sampleCount).', 'OutputType', 'same');
            combinedStore = combine(stores.train, labelStore, indexStore);

            queue = minibatchqueue(combinedStore, 2, ...
                'MiniBatchSize', config.grading.batch_size, ...
                'MiniBatchFcn', @(imageCells, targetCells, indexCells) ...
                    TestGradingBaseline.collateForHash( ...
                        imageCells, targetCells, indexCells, seed), ...
                'OutputCast', {'single', 'single'}, ...
                'OutputAsDlarray', [true, true], ...
                'MiniBatchFormat', {'SSCB', 'CB'}, ...
                'OutputEnvironment', "cpu", ...
                'PartialMiniBatch', 'return', ...
                'DispatchInBackground', config.training.dispatch_in_background);

            [images, ~] = next(queue);
            bytes = typecast(single(gather(extractdata(images(:)))), 'uint8');
            digest = java.security.MessageDigest.getInstance('SHA-256');
            hexHash = sprintf('%02x', typecast(digest.digest(bytes), 'uint8'));
        end

        function [images, targets] = collateForHash(imageCells, targetCells, indexCells, seed)
            % Mirrors +grade/private/collateData.m's augmentation path,
            % calling the same public grade.deterministicBatchSeed and
            % grade.augmentBatch functions collateData calls; the
            % minibatchqueue wiring itself is duplicated from
            % +grade/private/createMiniBatchQueue.m only because MATLAB
            % refuses to add a "private" folder to the path from outside
            % its parent package.
            images = cat(4, imageCells{:});
            batchIndices = double(cell2mat(indexCells));
            batchSeed = grade.deterministicBatchSeed(seed, min(batchIndices(:)));
            stream = RandStream('mt19937ar', 'Seed', batchSeed);
            images = grade.augmentBatch(images, stream);
            targets = reshape(single(cell2mat(targetCells)), 1, []);
        end
    end
end
