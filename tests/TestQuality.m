classdef TestQuality < matlab.unittest.TestCase
    %TESTQUALITY Behavioral tests for the deterministic image quality gate.

    methods (TestClassSetup)
        function addSourcePath(~)
            testFile = which('TestQuality');
            projectRoot = fileparts(fileparts(testFile));
            addpath(genpath(fullfile(projectRoot, 'src')));
        end
    end

    methods (Test)
        function clearRgbImageIsGradable(testCase)
            image = TestQuality.syntheticFundus(256, true);

            [result, processed] = quality.assess(image, struct());

            testCase.verifyEqual(result.class, 'gradable');
            testCase.verifyFalse(result.isEnhanced);
            testCase.verifyEqual(size(processed), size(image));
            testCase.verifyEmpty(result.advice);
            testCase.verifyEqual(result.features.fovAreaRatio, ...
                nnz(result.fovMask) / numel(result.fovMask));
        end

        function grayscaleImageIsAccepted(testCase)
            image = TestQuality.syntheticFundus(192, false);

            [result, processed] = quality.assess(image);

            testCase.verifyTrue(ismember(result.class, ...
                {'gradable', 'borderline', 'ungradable'}));
            testCase.verifyEqual(ndims(processed), 2);
            testCase.verifyEqual(size(processed), size(image));
        end

        function blurredImageGetsFocusFeedback(testCase)
            image = TestQuality.syntheticFundus(256, true);
            image = imgaussfilt(image, 8);

            [result, ~] = quality.assess(image);

            testCase.verifyTrue(ismember(result.class, {'borderline', 'ungradable'}));
            testCase.verifyTrue(any(strcmp(result.advice, 'Image out of focus')));
        end

        function darkImageGetsLightingFeedback(testCase)
            image = 0.10 * TestQuality.syntheticFundus(256, true);

            [result, ~] = quality.assess(image);

            testCase.verifyTrue(ismember(result.class, {'borderline', 'ungradable'}));
            testCase.verifyTrue(any(strcmp(result.advice, 'Image too dark')));
        end

        function brightImageGetsExposureFeedback(testCase)
            image = min(4 * TestQuality.syntheticFundus(256, true), 1);

            [result, ~] = quality.assess(image);

            testCase.verifyTrue(ismember(result.class, {'borderline', 'ungradable'}));
            testCase.verifyTrue(any(strcmp(result.advice, 'Image over-exposed')));
        end

        function blackBorderIsExcludedFromMeasurements(testCase)
            image = TestQuality.syntheticFundus(256, true);
            [mask, info] = quality.fovMask(image);
            features = quality.qualityFeatures(image, mask);
            gray = im2gray(im2double(image));

            testCase.verifyFalse(mask(1, 1));
            testCase.verifyGreaterThan(info.areaRatio, 0.40);
            testCase.verifyGreaterThan(features.meanIntensity, mean(gray(:)) * 1.4);
            testCase.verifyEqual(features.fovAreaRatio, info.areaRatio, 'AbsTol', 1e-12);
        end

        function borderlineEnhancementPreservesDimensionsAndClass(testCase)
            image = uint8(round(255 * 0.40 * TestQuality.syntheticFundus(128, true)));

            [result, processed] = quality.assess(image);

            testCase.verifyEqual(result.class, 'borderline');
            testCase.verifyTrue(result.isEnhanced);
            testCase.verifyEqual(size(processed), size(image));
            testCase.verifyClass(processed, class(image));
        end

        function invalidInputsAreRejected(testCase)
            testCase.verifyError(@() quality.assess([]), 'quality:EmptyImage');
            testCase.verifyError(@() quality.assess(ones(10, 10, 2)), ...
                'quality:InvalidImage');
            testCase.verifyError(@() quality.assess(ones(10, 10) * 2), ...
                'quality:InvalidImage');
        end
    end

    methods (Static, Access = private)
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
