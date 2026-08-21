classdef TestPreprocess < matlab.unittest.TestCase
    %TESTPREPROCESS Behavioral tests for the shared preprocessing seam.

    methods (TestClassSetup)
        function addSourcePath(~)
            testFile = which('TestPreprocess');
            projectRoot = fileparts(fileparts(testFile));
            addpath(genpath(fullfile(projectRoot, 'src')));
        end
    end

    methods (Test)
        function trainingAndInferenceUseIdenticalPreprocessing(testCase)
            image = TestPreprocess.syntheticFundus(96, true);
            config = TestPreprocess.configuration(48);

            training = grade.train(image, config);
            inference = grade.infer(image, config);

            testCase.verifyEqual(training.preprocessedImage, ...
                inference.preprocessedImage);
            testCase.verifyEqual(training.qualityMetadata, ...
                inference.qualityMetadata);
            testCase.verifyEqual(training.preprocessingMetadata, ...
                inference.preprocessingMetadata);
        end

        function outputMatchesConfiguredResolutionAndType(testCase)
            image = TestPreprocess.syntheticFundus(96, true);
            config = TestPreprocess.configuration([40, 56]);

            [processed, ~, metadata] = common.preprocess(image, config);

            testCase.verifySize(processed, [40, 56, 3]);
            testCase.verifyClass(processed, 'single');
            testCase.verifyEqual(metadata.outputSize, [40, 56, 3]);
            testCase.verifyEqual(metadata.outputClass, 'single');
        end

        function disabledEnhancementDoesNotApplyEnhancement(testCase)
            image = uint8(round(255 * 0.40 * ...
                TestPreprocess.syntheticFundus(96, true)));
            config = TestPreprocess.configuration(96);
            config.pipeline.enhancement = false;
            config.preprocessing.fov_mode = 'none';

            [processed, qualityMetadata, preprocessingMetadata] = ...
                common.preprocess(image, config);
            expected = im2single(image);

            testCase.verifyEqual(qualityMetadata.class, 'borderline');
            testCase.verifyFalse(preprocessingMetadata.enhancementApplied);
            testCase.verifyFalse(preprocessingMetadata.illuminationNormalizationApplied);
            testCase.verifyFalse(preprocessingMetadata.claheApplied);
            testCase.verifyEqual(processed, expected);
        end

        function fovCroppingIsDeterministic(testCase)
            image = TestPreprocess.syntheticFundus(96, true);
            config = TestPreprocess.configuration(32);

            [first, firstQuality, firstMetadata] = common.preprocess(image, config);
            [second, secondQuality, secondMetadata] = common.preprocess(image, config);

            testCase.verifyEqual(first, second);
            testCase.verifyEqual(firstQuality.fovMask, secondQuality.fovMask);
            testCase.verifyEqual(firstMetadata.fovBoundingBox, ...
                secondMetadata.fovBoundingBox);
            testCase.verifyTrue(firstMetadata.fovApplied);
        end

        function jsonConfigurationIsAccepted(testCase)
            image = TestPreprocess.syntheticFundus(64, true);
            testFile = which('TestPreprocess');
            projectRoot = fileparts(fileparts(testFile));
            configFile = fullfile(projectRoot, 'config', 'default.json');

            [processed, ~, metadata] = common.preprocess(image, configFile);

            testCase.verifySize(processed, [448, 448, 3]);
            testCase.verifyEqual(metadata.outputClass, 'single');
        end

        function invalidInputProducesUsefulError(testCase)
            config = TestPreprocess.configuration(32);
            testCase.verifyError( ...
                @() common.preprocess(ones(10, 10) * 2, config), ...
                'common:InvalidImage');
        end
    end

    methods (Static, Access = private)
        function config = configuration(inputSize)
            config = struct();
            config.pipeline = struct('quality_gate', true, 'enhancement', true);
            config.grading = struct('input_size', inputSize);
            config.preprocessing = struct( ...
                'fov_mode', 'crop', ...
                'channel_mean', [0, 0, 0], ...
                'channel_std', [1, 1, 1]);
        end

        function image = syntheticFundus(imageSize, rgb)
            coordinates = linspace(-1, 1, imageSize);
            [x, y] = meshgrid(coordinates, coordinates);
            field = x .^ 2 + y .^ 2 <= 0.82 ^ 2;
            radial = 0.28 + 0.06 * (1 - x) + 0.025 * (1 - y);
            detail = 0.055 * sin(21 * x) .* cos(17 * y) + ...
                0.025 * sin(31 * (x + y));
            green = min(max(radial + detail, 0), 1);
            green(~field) = 0;
            if rgb
                image = cat(3, 0.78 * green, green, 0.62 * green);
            else
                image = green;
            end
        end
    end
end
