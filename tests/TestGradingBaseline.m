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
            % Look the head up by name rather than by position. addLayers
            % appends the dropout layer to the end of the Layers array
            % regardless of where it sits in the graph, so Layers(end-1)
            % is not the classification head once dropout is enabled.
            layers = result.network.Layers;
            headIndex = find(arrayfun(@(l) strcmp(l.Name, 'fc1000'), layers));
            testCase.verifyNumElements(headIndex, 1);
            testCase.verifyEqual(layers(headIndex).OutputSize, 5);
        end

        function dropoutSitsInFrontOfTheClassificationHead(testCase)
            % The head must stay regularised and fc1000 must stay the last
            % learnable layer, because freezeBackboneGradients keys warmup
            % on that name.
            result = grade.train(TestGradingBaseline.defaultConfig(), ...
                'Mode', 'inspect');
            net = result.network;

            testCase.verifyGreaterThan(result.config.grading.dropout, 0);
            isDropout = arrayfun(@(l) isa(l, 'nnet.cnn.layer.DropoutLayer'), ...
                net.Layers);
            testCase.verifyTrue(any(isDropout), ...
                'A dropout layer must guard the classification head.');

            % avg_pool -> head_dropout -> fc1000, verified through the
            % connection table rather than layer order.
            connections = net.Connections;
            testCase.verifyTrue(any(strcmp(connections.Source, 'avg_pool') & ...
                strcmp(connections.Destination, 'head_dropout')));
            testCase.verifyTrue(any(strcmp(connections.Source, 'head_dropout') & ...
                strcmp(connections.Destination, 'fc1000')));
            testCase.verifyFalse(any(strcmp(connections.Source, 'avg_pool') & ...
                strcmp(connections.Destination, 'fc1000')), ...
                'avg_pool must no longer feed fc1000 directly.');
        end

        function dropoutCanBeDisabledFromConfiguration(testCase)
            % §11.6: a pipeline stage turns off from config, never by
            % editing code, so the pre-dropout architecture must stay
            % reachable without touching buildNetwork.
            config = jsondecode(fileread(TestGradingBaseline.defaultConfig()));
            config.grading.dropout = 0;
            result = grade.train(config, 'Mode', 'inspect');

            isDropout = arrayfun(@(l) isa(l, 'nnet.cnn.layer.DropoutLayer'), ...
                result.network.Layers);
            testCase.verifyFalse(any(isDropout));
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
        function weightDecayLeavesFrozenBackboneWeightsAlone(testCase)
            % Decoupled weight decay shrinks a weight every step whether or
            % not it received a gradient. Applied to a frozen backbone that
            % is exactly wrong: pretrained ImageNet features would decay
            % toward zero with nothing pushing back, degrading the
            % representation before fine-tuning starts. Smoke mode freezes
            % everything except fc1000, so every backbone weight must come
            % out bit-identical while the head is free to move.
            resultsRoot = tempname;
            cleanup = onCleanup(@() TestGradingBaseline.removeDirectory(resultsRoot)); %#ok<NASGU>

            config = jsondecode(fileread(TestGradingBaseline.defaultConfig()));
            testCase.assertGreaterThan(config.training.weight_decay, 0, ...
                'This test is only meaningful with decay enabled.');

            pristine = grade.train(config, 'Mode', 'inspect');
            trained = grade.train(config, 'Mode', 'smoke', ...
                'ResultsRoot', resultsRoot);

            before = pristine.network.Learnables;
            after = trained.network.Learnables;
            testCase.assertEqual(height(after), height(before));

            headMoved = false;
            for index = 1:height(before)
                isWeight = before.Parameter(index) == "Weights";
                isHead = string(before.Layer(index)) == "fc1000";
                beforeValue = gather(extractdata(before.Value{index}));
                afterValue = gather(extractdata(after.Value{index}));
                if isWeight && ~isHead
                    testCase.verifyEqual(afterValue, beforeValue, ...
                        sprintf(['Frozen backbone weight "%s" changed; ' ...
                        'weight decay must skip frozen layers.'], ...
                        string(before.Layer(index))));
                elseif isWeight && isHead && ~isequal(afterValue, beforeValue)
                    headMoved = true;
                end
            end

            testCase.verifyTrue(headMoved, ...
                'The unfrozen head must still train.');
        end

        function newTrainingControlsAreValidated(testCase)
            % §11.6: these are config knobs, so bad values must fail loudly
            % rather than silently falling back to a default.
            base = jsondecode(fileread(TestGradingBaseline.defaultConfig()));

            negativeDecay = base; negativeDecay.training.weight_decay = -1;
            testCase.verifyError(@() grade.train(negativeDecay, 'Mode', 'inspect'), ...
                'grade:InvalidWeightDecay');

            fractionalPatience = base;
            fractionalPatience.training.early_stopping_patience = 1.5;
            testCase.verifyError(@() grade.train(fractionalPatience, 'Mode', 'inspect'), ...
                'grade:InvalidEarlyStoppingPatience');

            badDropout = base; badDropout.grading.dropout = 1;
            testCase.verifyError(@() grade.train(badDropout, 'Mode', 'inspect'), ...
                'grade:InvalidDropout');

            paddingScale = base;
            paddingScale.augmentation.scale_jitter = [0.9, 1.4];
            testCase.verifyError(@() grade.train(paddingScale, 'Mode', 'inspect'), ...
                'grade:InvalidAugmentation');

            % And the defaults that make the run reproducible must survive
            % a round trip through readConfiguration.
            configured = grade.train(base, 'Mode', 'inspect');
            testCase.verifyGreaterThanOrEqual( ...
                configured.config.training.early_stopping_patience, 0);
            testCase.verifyGreaterThanOrEqual( ...
                configured.config.training.weight_decay, 0);
            testCase.verifyTrue( ...
                islogical(configured.config.training.save_every_epoch));
            testCase.verifyLessThanOrEqual( ...
                configured.config.augmentation.scale_jitter(2), 1);
        end

        function cacheKeyIgnoresFieldsPreprocessingNeverReads(testCase)
            % Changing a training hyperparameter must not invalidate the
            % preprocessed-image cache. On 2026-08-23 adding grading.dropout
            % and training.weight_decay silently invalidated 16 GB of cache
            % and cost an hour re-preprocessing 2564 unchanged images,
            % because the key hashed the entire configuration.
            base = jsondecode(fileread(TestGradingBaseline.defaultConfig()));
            imagePath = TestGradingBaseline.firstTrainingImagePath();

            reference = TestGradingBaseline.cacheKeyFor(imagePath, base);

            unrelated = base;
            unrelated.grading.dropout = 0.25;
            unrelated.training.weight_decay = 0.99;
            unrelated.training.max_epochs = 3;
            unrelated.training.early_stopping_patience = 1;
            unrelated.augmentation.rotation = false;
            unrelated.decision_policy.autoClearThreshold = 0.11;
            testCase.verifyEqual( ...
                TestGradingBaseline.cacheKeyFor(imagePath, unrelated), reference, ...
                'Training-only settings must not change the cache key.');
        end

        function cacheKeyChangesWhenPreprocessingChanges(testCase)
            % The dangerous direction: if a field that DOES change the
            % pixels is left out of the key, the cache serves stale images
            % for a changed pipeline and no metric will ever name it.
            base = jsondecode(fileread(TestGradingBaseline.defaultConfig()));
            imagePath = TestGradingBaseline.firstTrainingImagePath();
            reference = TestGradingBaseline.cacheKeyFor(imagePath, base);

            variants = struct('name', {}, 'config', {});
            v = base; v.pipeline.quality_gate = ~base.pipeline.quality_gate;
            variants(end+1) = struct('name', 'pipeline.quality_gate', 'config', v);
            v = base; v.pipeline.enhancement = ~base.pipeline.enhancement;
            variants(end+1) = struct('name', 'pipeline.enhancement', 'config', v);
            v = base; v.grading.input_size = 512;
            variants(end+1) = struct('name', 'grading.input_size', 'config', v);
            v = base; v.preprocessing.output_type = 'double';
            variants(end+1) = struct('name', 'preprocessing.output_type', 'config', v);
            v = base; v.preprocessing.channel_mean = [0.1 0.1 0.1];
            variants(end+1) = struct('name', 'preprocessing.channel_mean', 'config', v);
            v = base; v.preprocessing.channel_std = [0.5 0.5 0.5];
            variants(end+1) = struct('name', 'preprocessing.channel_std', 'config', v);
            v = base; v.preprocessing.fov_mode = 'mask';
            variants(end+1) = struct('name', 'preprocessing.fov_mode', 'config', v);
            v = base; v.preprocessing.clahe = false;
            variants(end+1) = struct('name', 'preprocessing.clahe', 'config', v);

            for index = 1:numel(variants)
                testCase.verifyNotEqual( ...
                    TestGradingBaseline.cacheKeyFor(imagePath, variants(index).config), ...
                    reference, sprintf( ...
                    ['Changing %s changes the preprocessed pixels, so it ' ...
                    'must change the cache key.'], variants(index).name));
            end
        end

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
            % Photometric envelope in isolation: with the rigid transforms
            % switched off, a constant image can only be rescaled and
            % shifted, so no value may leave the gain/bias envelope.
            batch = single(100 * ones([8 8 3 6]));
            options = struct('rotation', false, 'flips', true, ...
                'scale_jitter', [1 1], 'brightness_shift', 10, ...
                'contrast_gain', [0.9 1.1]);
            rng(11, 'twister');
            augmented = grade.augmentBatch(batch, [], options);

            testCase.verifyEqual(size(augmented), size(batch));
            testCase.verifyEqual(class(augmented), 'single');
            testCase.verifyTrue(all(isfinite(augmented(:))));
            testCase.verifyTrue(all(augmented(:) >= 100 * 0.9 - 10 - 1e-5));
            testCase.verifyTrue(all(augmented(:) <= 100 * 1.1 + 10 + 1e-5));
        end

        function augmentBatchRotationOnlyFillsOutsideTheFrame(testCase)
            % Rotation introduces a zero fill in the frame corners. On a
            % real fundus those corners are already black after the
            % field-of-view crop, but the invariant worth pinning is that
            % rotation never invents a value: everything is either the
            % fill or inside the photometric envelope.
            batch = single(100 * ones([16 16 3 6]));
            options = struct('rotation', true, 'flips', false, ...
                'scale_jitter', [1 1], 'brightness_shift', 10, ...
                'contrast_gain', [0.9 1.1]);
            rng(11, 'twister');
            augmented = grade.augmentBatch(batch, [], options);

            testCase.verifyEqual(size(augmented), size(batch));
            testCase.verifyTrue(all(isfinite(augmented(:))));
            % Bilinear resampling interpolates between the content (100)
            % and the zero fill, so boundary pixels legitimately land
            % anywhere in [0, 100]. What must hold is that it never
            % overshoots either end: no rotation may invent intensity
            % brighter than the brightest real pixel, which is how an
            % interpolation bug would show up on a fundus as phantom
            % lesion-bright specks.
            testCase.verifyGreaterThanOrEqual(min(augmented(:)), ...
                single(0 * 0.9 - 10 - 1e-3));
            testCase.verifyLessThanOrEqual(max(augmented(:)), ...
                single(100 * 1.1 + 10 + 1e-3));
        end

        function rotationDoesNotOvershootIntoPhantomBrightness(testCase)
            % Sharper version of the overshoot check on a textured image
            % with no photometric jitter at all: rotation alone must keep
            % every pixel inside the original intensity range plus the
            % zero fill, never above the true maximum.
            content = single(reshape(linspace(20, 200, 16 * 16 * 3), [16 16 3]));
            batch = repmat(content, [1 1 1 4]);
            options = struct('rotation', true, 'flips', false, ...
                'scale_jitter', [1 1], 'brightness_shift', 0, ...
                'contrast_gain', [1 1]);
            rng(23, 'twister');
            augmented = grade.augmentBatch(batch, [], options);

            testCase.verifyLessThanOrEqual(max(augmented(:)), ...
                max(content(:)) + 1e-3, ...
                'Rotation must not create intensity above the source maximum.');
            testCase.verifyGreaterThanOrEqual(min(augmented(:)), -1e-3, ...
                'Rotation fill must not go below zero.');
        end

        function augmentBatchZoomNeverPadsTheFrame(testCase)
            % scale_jitter is capped at 1 so the crop is always a strict
            % sub-window: zooming out would need padding, and padded
            % borders are evidence the camera never captured.
            batch = single(100 * ones([16 16 3 8]));
            options = struct('rotation', false, 'flips', false, ...
                'scale_jitter', [0.5 1.0], 'brightness_shift', 0, ...
                'contrast_gain', [1 1]);
            rng(5, 'twister');
            augmented = grade.augmentBatch(batch, [], options);

            testCase.verifyEqual(size(augmented), size(batch));
            testCase.verifyEqual(double(augmented(:)), ...
                100 * ones(numel(augmented), 1), 'AbsTol', 1e-3, ...
                'A zoom crop of a constant image must stay constant.');
        end

        function augmentBatchRejectsScaleAboveOne(testCase)
            batch = single(100 * ones([8 8 3 2]));
            options = struct('scale_jitter', [1.0 1.2]);

            testCase.verifyError(@() grade.augmentBatch(batch, [], options), ...
                'grade:InvalidAugmentation');
        end

        function augmentBatchProducesMoreThanEightOrientations(testCase)
            % The point of arbitrary-angle rotation: ICDR level 3 has 135
            % unique images oversampled to about nine repeats per epoch,
            % and quarter turns plus flips gave it only 8 distinct views.
            batch = repmat(single(reshape(1:768, [16 16 3])), [1 1 1 1]);
            views = cell(1, 24);
            for index = 1:24
                stream = RandStream('mt19937ar', 'Seed', index);
                views{index} = grade.augmentBatch(batch, stream);
            end
            distinct = 0;
            for index = 1:24
                isNew = true;
                for other = 1:index - 1
                    if isequal(views{index}, views{other})
                        isNew = false;
                        break;
                    end
                end
                distinct = distinct + isNew;
            end

            testCase.verifyGreaterThan(distinct, 8, ...
                'Augmentation must reach more than the 8 dihedral views.');
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

        function key = cacheKeyFor(imagePath, config)
            key = grade.preprocessingCacheKey(imagePath, config);
        end

        function imagePath = firstTrainingImagePath()
            testFile = which('TestGradingBaseline');
            projectRoot = fileparts(fileparts(testFile));
            split = readtable(fullfile(projectRoot, 'data', 'splits', ...
                'train.csv'), 'TextType', 'string');
            imagePath = fullfile(projectRoot, split.relative_path(1));
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
