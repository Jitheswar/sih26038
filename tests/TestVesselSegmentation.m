classdef TestVesselSegmentation < matlab.unittest.TestCase
    %TESTVESSELSEGMENTATION Cover the DRIVE vessel segmentation path (§6.3).

    properties (Constant, Access = private)
        SplitNames = {'train', 'validation', 'test'}
        ExpectedHeader = {'image_id', 'split', 'relative_path', ...
            'manual_path', 'mask_path', 'vessel_fraction'}
        ExpectedCounts = struct('train', 14, 'validation', 3, 'test', 3)
    end

    methods (TestClassSetup)
        function addSourceAndEvaluationPaths(~)
            testFile = which('TestVesselSegmentation');
            projectRoot = fileparts(fileparts(testFile));
            addpath(genpath(fullfile(projectRoot, 'src')));
            addpath(genpath(fullfile(projectRoot, 'eval')));
        end
    end

    methods (Test)
        function testSplitFilesExistWithExpectedShape(testCase)
            for index = 1:numel(testCase.SplitNames)
                splitName = testCase.SplitNames{index};
                splitTable = TestVesselSegmentation.readSplit(splitName);
                testCase.verifyEqual( ...
                    splitTable.Properties.VariableNames, ...
                    testCase.ExpectedHeader, ...
                    sprintf('Unexpected header in vessel_%s.csv.', splitName));
                testCase.verifyEqual(height(splitTable), ...
                    testCase.ExpectedCounts.(splitName), ...
                    sprintf('Unexpected row count in vessel_%s.csv.', ...
                    splitName));
                testCase.verifyTrue(all(splitTable.split == string(splitName)));
            end
        end

        function testNoFrameAppearsInTwoSplits(testCase)
            % The same property §10.2 asserts for the patient-level splits.
            % DRIVE has one frame per subject so a frame identifier is the
            % subject identifier here.
            allIds = strings(0, 1);
            for index = 1:numel(testCase.SplitNames)
                splitTable = TestVesselSegmentation.readSplit( ...
                    testCase.SplitNames{index});
                allIds = [allIds; splitTable.image_id]; %#ok<AGROW>
            end
            testCase.verifyEqual(numel(allIds), 20, ...
                'The three splits must cover DRIVE''s twenty annotated frames.');
            testCase.verifyEqual(numel(unique(allIds)), numel(allIds), ...
                'A DRIVE frame appears in more than one vessel split.');
        end

        function testHeldOutSplitsTakeOneFrameFromEachTercile(testCase)
            % The property stratification actually provides.  The twenty
            % frames are ordered by vessel fraction and cut into terciles,
            % and each held-out split takes exactly one frame from each, so
            % a three-frame split cannot be drawn from one end of the
            % density range.  An earlier version asserted that a split
            % spanned some fraction of the training range instead, which was
            % an arbitrary threshold that the real stratification does not
            % promise and does not meet.
            combined = [TestVesselSegmentation.readSplit('train'); ...
                TestVesselSegmentation.readSplit('validation'); ...
                TestVesselSegmentation.readSplit('test')];
            testCase.verifyEqual(height(combined), 20);

            [~, order] = sort(combined.vessel_fraction);
            tercileOf = zeros(height(combined), 1);
            edges = round(linspace(0, height(combined), 4));
            for tercile = 1:3
                tercileOf(order(edges(tercile) + 1:edges(tercile + 1))) = ...
                    tercile;
            end

            for splitName = ["validation", "test"]
                rows = combined.split == splitName;
                testCase.verifyEqual(sort(tercileOf(rows))', [1, 2, 3], ...
                    sprintf(['The %s split must hold one frame from each ' ...
                    'vessel-density tercile.'], splitName));
            end
        end

        function testPreprocessReturnsOneChannelInUnitRange(testCase)
            image = TestVesselSegmentation.syntheticFrame();
            vessel = struct('green_clahe', true, 'clahe_clip_limit', 0.01, ...
                'clahe_tiles', 4);
            prepared = segment.vesselPreprocess(image, vessel);

            testCase.verifySize(prepared, [size(image, 1), size(image, 2)], ...
                'The prepared frame must stay on the caller''s pixel grid.');
            testCase.verifyClass(prepared, 'single');
            testCase.verifyGreaterThanOrEqual(min(prepared(:)), 0);
            testCase.verifyLessThanOrEqual(max(prepared(:)), 1);
        end

        function testPreprocessReadsTheGreenChannel(testCase)
            % §6.3 specifies green.  A frame whose green channel is constant
            % and whose red and blue channels carry structure must come back
            % without that structure, which no assertion about the output
            % range would catch.
            image = zeros(64, 64, 3, 'uint8');
            image(:, :, 1) = repmat(uint8(linspace(0, 255, 64)), 64, 1);
            image(:, :, 3) = 200;
            image(:, :, 2) = 128;

            vessel = struct('green_clahe', false);
            prepared = segment.vesselPreprocess(image, vessel);
            testCase.verifyEqual(double(max(prepared(:)) - min(prepared(:))), ...
                0, 'AbsTol', 1e-6, ...
                'Only the green channel may reach the network.');
        end

        function testNetworkHasOneInputAndOneOutputChannel(testCase)
            config = TestVesselSegmentation.smallConfig();
            result = segment.trainVesselSegmentation(config, ...
                'Mode', 'inspect');
            net = result.net;

            patchSize = config.vessel_segmentation.patch_size;
            input = dlarray(zeros(patchSize, patchSize, 1, 2, 'single'), ...
                'SSCB');
            logits = predict(net, input);
            testCase.verifySize(extractdata(logits), ...
                [patchSize, patchSize, 1, 2], ...
                'The vessel head must emit exactly one channel.');
        end

        function testInspectModeReadsTheCommittedSplits(testCase)
            result = segment.trainVesselSegmentation( ...
                TestVesselSegmentation.smallConfig(), 'Mode', 'inspect');
            testCase.verifyEqual(result.status, "configured");
            testCase.verifyEqual(result.trainImageCount, 14);
            testCase.verifyEqual(result.validationImageCount, 3);
        end

        function testPatchSamplerStaysInsideTheFieldOfView(testCase)
            rng(1, 'twister');
            [prepared, vessels, fieldOfView] = ...
                TestVesselSegmentation.syntheticCase();
            vessel = struct('patch_size', 32, 'vessel_patch_fraction', 0.5);

            [patches, masks] = segment.sampleVesselPatches(prepared, ...
                vessels, fieldOfView, 24, vessel, false);

            testCase.verifySize(patches, [32, 32, 1, 24]);
            testCase.verifySize(masks, [32, 32, 1, 24]);
            testCase.verifyClass(patches, 'single');
            testCase.verifyClass(masks, 'logical');
            testCase.verifyTrue(all(isfinite(patches(:))));
        end

        function testPatchSamplerHonoursTheVesselFraction(testCase)
            rng(2, 'twister');
            [prepared, vessels, fieldOfView] = ...
                TestVesselSegmentation.syntheticCase();
            vessel = struct('patch_size', 32, 'vessel_patch_fraction', 1.0);

            [~, masks] = segment.sampleVesselPatches(prepared, vessels, ...
                fieldOfView, 16, vessel, false);
            centre = squeeze(masks(17, 17, 1, :));
            testCase.verifyTrue(all(centre), ...
                ['At vessel_patch_fraction 1.0 every patch centre must ' ...
                'land on an annotated vessel pixel.']);
        end

        function testLossFallsAsThePredictionImproves(testCase)
            targets = dlarray(single(TestVesselSegmentation.stripeMask()), ...
                'SSCB');
            options = struct('diceWeight', 0.5);

            good = dlarray(single(8 * (2 * ...
                TestVesselSegmentation.stripeMask() - 1)), 'SSCB');
            bad = -good;

            goodLoss = double(extractdata( ...
                segment.vesselLoss(good, targets, options)));
            badLoss = double(extractdata( ...
                segment.vesselLoss(bad, targets, options)));

            testCase.verifyLessThan(goodLoss, badLoss, ...
                'A correct prediction must score below an inverted one.');
            testCase.verifyGreaterThanOrEqual(goodLoss, 0);
        end

        function testDiceTermMatchesItsDefinition(testCase)
            % A direct numerical check of the Dice term, smoothing included,
            % so a change to the formula surfaces as a number here rather
            % than as a slightly different training curve nobody reads.
            %
            % This replaced an attempt to assert that the term is symmetric
            % between a false positive and a false negative.  That property
            % is not well posed on a single target: true positives and false
            % negatives sum to the target size, so a prediction cannot trade
            % one for the other while holding the rest fixed, and the test
            % was really measuring the change in true positives.  The
            % difference from the lesion path is a configuration property -
            % lesionConfiguration refuses beta < alpha and vesselConfiguration
            % has no such term - and it is tested where it lives.
            %
            % Target: rows 1 to 8 of a 16x16 frame, 128 of 256 pixels.
            % Prediction: rows 1 to 4, saturated, giving 64 true positives,
            % no false positives and 64 false negatives.
            %   Dice = (2*64 + 1) / (64 + 128 + 1) = 129/193
            target = zeros(16, 16, 1, 1, 'single');
            target(1:8, :) = 1;
            prediction = -20 * ones(16, 16, 1, 1, 'single');
            prediction(1:4, :) = 20;

            options = struct('diceWeight', 1.0);
            [loss, dice] = segment.vesselLoss( ...
                dlarray(prediction, 'SSCB'), dlarray(target, 'SSCB'), ...
                options);

            testCase.verifyEqual(double(extractdata(dice)), 129 / 193, ...
                'AbsTol', 1e-4, ...
                'The Dice term must match its documented definition.');
            testCase.verifyEqual(double(extractdata(loss)), ...
                1 - 129 / 193, 'AbsTol', 1e-4, ...
                'At diceWeight 1.0 the loss is exactly one minus Dice.');
        end

        function testInferenceReturnsMapsOnTheCallersPixelGrid(testCase)
            [model, image, fieldOfView] = ...
                TestVesselSegmentation.smallModel();
            result = segment.segmentVessels(image, model, ...
                'Environment', "cpu", 'FieldOfView', fieldOfView);

            testCase.verifyEqual(result.imageSize, ...
                [size(image, 1), size(image, 2)]);
            testCase.verifySize(result.probabilityMap, ...
                [size(image, 1), size(image, 2)], ...
                ['Probability maps must come back on the pixel grid the ' ...
                'caller passed in, whatever tiling happened inside.']);
            testCase.verifyTrue(all(isfinite(result.probabilityMap(:))), ...
                'Tiling must cover the frame, leaving no unwritten pixels.');
            testCase.verifyGreaterThanOrEqual(min(result.probabilityMap(:)), 0);
            testCase.verifyLessThanOrEqual(max(result.probabilityMap(:)), 1);
        end

        function testInferenceIsSilentOutsideTheFieldOfView(testCase)
            [model, image, fieldOfView] = ...
                TestVesselSegmentation.smallModel();
            result = segment.segmentVessels(image, model, ...
                'Environment', "cpu", 'FieldOfView', fieldOfView);

            outside = result.probabilityMap(~fieldOfView);
            testCase.verifyTrue(all(outside == 0), ...
                ['There is no retina outside the camera aperture, so ' ...
                'there can be no vessel probability there. Leaving it ' ...
                'would also inflate a specificity §6.3 reports inside ' ...
                'the field of view.']);
        end

        function testConfigurationRefusesAPatchTheEncoderCannotHalve(testCase)
            config = jsondecode(fileread( ...
                TestVesselSegmentation.configPath()));
            % 48 is a multiple of 16, so it clears the patch-size check
            % that runs first, but it is not a multiple of 2^5, so five
            % encoder stages cannot halve it exactly.  At depth 4 this
            % configuration is legal, which is why the earlier version of
            % this test passed for the wrong reason.
            config.vessel_segmentation.patch_size = 48;
            config.vessel_segmentation.encoder_depth = 5;
            % tile_overlap must stay under half the patch or its own check
            % fires first.
            config.vessel_segmentation.tile_overlap = 8;

            testCase.verifyError(@() segment.trainVesselSegmentation( ...
                config, 'Mode', 'inspect'), ...
                'segment:InvalidVesselEncoderDepth');
        end

        function testConfigurationRefusesADisabledStage(testCase)
            config = jsondecode(fileread( ...
                TestVesselSegmentation.configPath()));
            config.vessel_segmentation.enabled = false;

            testCase.verifyError(@() segment.trainVesselSegmentation( ...
                config, 'Mode', 'inspect'), ...
                'segment:VesselSegmentationDisabled');
        end

        function testConfigurationRequiresTheProjectSeed(testCase)
            config = jsondecode(fileread( ...
                TestVesselSegmentation.configPath()));
            config.vessel_segmentation.seed = 7;

            testCase.verifyError(@() segment.trainVesselSegmentation( ...
                config, 'Mode', 'inspect'), 'segment:InvalidVesselSeed');
        end

        function testConfiguredCheckpointExists(testCase)
            % A checkpoint path that has been deleted or never produced
            % turns into a confusing failure deep inside inference.
            config = jsondecode(fileread( ...
                TestVesselSegmentation.configPath()));
            checkpoint = config.vessel_segmentation.checkpoint;
            if isempty(checkpoint)
                return;
            end
            fullPath = fullfile(TestVesselSegmentation.projectRoot(), ...
                checkpoint);
            testCase.verifyTrue(isfile(fullPath), sprintf( ...
                'vessel_segmentation.checkpoint names a missing file: %s', ...
                checkpoint));
        end

        function testEvaluationRefusesTheSealedSplit(testCase)
            testCase.verifyError( ...
                @() vesselSegmentationEvaluation('Split', 'sealed'), ...
                'eval:SealedData');
        end
    end

    methods (Static, Access = private)
        function root = projectRoot()
            root = fileparts(fileparts(mfilename('fullpath')));
        end

        function path = configPath()
            path = fullfile(TestVesselSegmentation.projectRoot(), ...
                'config', 'default.json');
        end

        function splitTable = readSplit(splitName)
            splitFile = fullfile(TestVesselSegmentation.projectRoot(), ...
                'data', 'splits', sprintf('vessel_%s.csv', splitName));
            splitTable = readtable(splitFile, 'TextType', 'string', ...
                'Delimiter', ',', 'ReadVariableNames', true);
        end

        function config = smallConfig()
            %SMALLCONFIG The committed config shrunk to run fast on CPU.
            config = jsondecode(fileread( ...
                TestVesselSegmentation.configPath()));
            config.vessel_segmentation.patch_size = 32;
            config.vessel_segmentation.base_filters = 4;
            config.vessel_segmentation.encoder_depth = 2;
            config.vessel_segmentation.tile_overlap = 8;
        end

        function [model, image, fieldOfView] = smallModel()
            %SMALLMODEL A tiny untrained network plus a synthetic frame.
            %   Shape and tiling behaviour do not depend on what the network
            %   has learned, so these tests use an untrained one and stay
            %   fast enough to run on CPU in the ordinary suite.
            config = TestVesselSegmentation.smallConfig();
            result = segment.trainVesselSegmentation(config, ...
                'Mode', 'inspect');
            model = struct('net', result.net, 'config', result.config);

            image = TestVesselSegmentation.syntheticFrame();
            [columns, rows] = meshgrid(1:size(image, 2), 1:size(image, 1));
            centreRow = size(image, 1) / 2;
            centreColumn = size(image, 2) / 2;
            fieldOfView = (rows - centreRow) .^ 2 + ...
                (columns - centreColumn) .^ 2 <= (0.42 * size(image, 1)) ^ 2;
        end

        function image = syntheticFrame()
            rng(7, 'twister');
            image = uint8(60 + 40 * rand(96, 100, 3));
            image(20:22, :, 2) = 200;
            image(:, 40:41, 2) = 30;
        end

        function [prepared, vessels, fieldOfView] = syntheticCase()
            image = TestVesselSegmentation.syntheticFrame();
            prepared = segment.vesselPreprocess(image, ...
                struct('green_clahe', false));
            vessels = false(size(prepared));
            vessels(30:60, 30:60) = true;
            fieldOfView = false(size(prepared));
            fieldOfView(10:end - 10, 10:end - 10) = true;
        end

        function mask = stripeMask()
            mask = zeros(16, 16, 1, 1, 'single');
            mask(1:8, :, 1, 1) = 1;
        end
    end
end
