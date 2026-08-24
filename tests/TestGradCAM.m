classdef TestGradCAM < matlab.unittest.TestCase
    %TESTGRADCAM Tests for the ResNet-50 Grad-CAM explanation path.

    methods (TestClassSetup)
        function addSourcePath(~)
            testFile = which('TestGradCAM');
            projectRoot = fileparts(fileparts(testFile));
            addpath(genpath(fullfile(projectRoot, 'src')));
        end
    end

    methods (Test)
        function validImageProducesCompleteExplanation(testCase)
            [checkpointFile, imageFile, projectRoot] = TestGradCAM.testInputs();
            resultsRoot = tempname;
            cleanup = onCleanup(@() TestGradCAM.removeDirectory(resultsRoot)); %#ok<NASGU>

            targetClass = 2;
            result = explain.gradcam(checkpointFile, imageFile, targetClass, ...
                'ResultsRoot', resultsRoot);

            originalImage = imread(imageFile);
            checkpoint = load(checkpointFile, 'net');
            layerNames = string({checkpoint.net.Layers.Name});

            testCase.verifyEqual(result.status, "completed");
            testCase.verifyTrue(all(isfinite(result.rawHeatmap(:))));
            testCase.verifyNotEmpty(result.rawHeatmap);
            testCase.verifyEqual(result.targetClass, targetClass);
            testCase.verifyTrue(isscalar(result.predictedClass));
            testCase.verifyTrue(ismember(result.predictedClass, 0:4));
            testCase.verifyTrue(isfinite(result.modelProbability));
            testCase.verifyEqual(size(result.overlay), size(originalImage));
            testCase.verifyEqual(size(result.resizedHeatmap), ...
                [size(originalImage, 1), size(originalImage, 2)]);
            testCase.verifyEqual(size(result.rawHeatmap), ...
                [result.rawHeatmapHeight, result.rawHeatmapWidth]);
            testCase.verifyEqual(result.rawHeatmapHeight, ...
                result.layers.final.rawHeatmapHeight);
            testCase.verifyEqual(result.rawHeatmapWidth, ...
                result.layers.final.rawHeatmapWidth);
            testCase.verifyTrue(ismember(result.convolutionalLayerName, layerNames));
            testCase.verifyTrue(ismember(result.earlierConvolutionalLayerName, ...
                layerNames));
            testCase.verifyGreaterThan(result.layers.earlier.rawHeatmapHeight, ...
                result.rawHeatmapHeight);
            testCase.verifyGreaterThan(result.layers.earlier.rawHeatmapWidth, ...
                result.rawHeatmapWidth);
            testCase.verifyTrue(isfile(result.overlayPath));
            testCase.verifyTrue(isfile(result.reportPath));
            testCase.verifyTrue(isfile(result.matPath));
            testCase.verifyFalse(result.probabilitiesAreCalibrated);

            reportText = fileread(result.reportTextPath);
            testCase.verifySubstring(reportText, char(result.convolutionalLayerName));
            testCase.verifySubstring(reportText, result.rawHeatmapResolution);
            testCase.verifySubstring(reportText, ...
                'regional model attention');
            testCase.verifySubstring(reportText, ...
                'not precise microaneurysm localisation');
        end

        function writeArtifactsFalseKeepsMapsAndWritesNothing(testCase)
            [checkpointFile, imageFile, ~] = TestGradCAM.testInputs();
            resultsRoot = tempname;
            cleanup = onCleanup(@() TestGradCAM.removeDirectory(resultsRoot)); %#ok<NASGU>
            targetClass = 2;

            written = explain.gradcam(checkpointFile, imageFile, targetClass, ...
                'ResultsRoot', resultsRoot);
            skipped = explain.gradcam(checkpointFile, imageFile, targetClass, ...
                'WriteArtifacts', false);

            % Skipping persistence must not change a single returned value,
            % otherwise a bulk sweep is measuring a different explanation
            % from the one the deployed report path produces.
            testCase.verifyEqual(skipped.status, "completed");
            testCase.verifyEqual(skipped.rawHeatmap, written.rawHeatmap);
            testCase.verifyEqual(skipped.resizedHeatmap, written.resizedHeatmap);
            testCase.verifyEqual(skipped.normalizedHeatmap, written.normalizedHeatmap);
            testCase.verifyEqual(skipped.overlay, written.overlay);
            testCase.verifyEqual(skipped.convolutionalLayerName, ...
                written.convolutionalLayerName);
            testCase.verifyEqual(skipped.predictedClass, written.predictedClass);

            testCase.verifyFalse(skipped.artifactsWritten);
            testCase.verifyTrue(written.artifactsWritten);
            testCase.verifyEmpty(skipped.overlayPath);
            testCase.verifyEmpty(skipped.reportPath);
            testCase.verifyEmpty(skipped.matPath);
            testCase.verifyEmpty(skipped.reportTextPath);
            testCase.verifyEmpty(char(skipped.resultsDirectory));
        end

        function heatmapIsConfinedToTheFieldOfViewCrop(testCase)
            [checkpointFile, imageFile, ~] = TestGradCAM.testInputs();
            result = explain.gradcam(checkpointFile, imageFile, 2, ...
                'WriteArtifacts', false);

            metadata = result.preprocessingMetadata;
            testCase.assumeTrue(metadata.fovApplied && ...
                strcmp(metadata.fovMode, 'crop'), ...
                'This test needs a cropping field-of-view mode.');

            boundingBox = metadata.fovBoundingBox;
            heatmap = double(result.resizedHeatmap);
            columnStart = max(1, round(boundingBox(1)));
            rowStart = max(1, round(boundingBox(2)));
            columnEnd = min(size(heatmap, 2), columnStart + round(boundingBox(3)) - 1);
            rowEnd = min(size(heatmap, 1), rowStart + round(boundingBox(4)) - 1);

            outside = heatmap;
            outside(rowStart:rowEnd, columnStart:columnEnd) = 0;

            % The model never saw pixels outside the crop, so no attention
            % may be reported there. Before this was fixed the map was
            % stretched across the whole frame and the overlay pointed a
            % clinician at the wrong location.
            testCase.verifyEqual(max(abs(outside(:))), 0, ...
                'Grad-CAM reported attention outside the field-of-view crop.');

            inside = heatmap(rowStart:rowEnd, columnStart:columnEnd);
            testCase.verifyGreaterThan(max(inside(:)), 0, ...
                'The map inside the field of view is empty.');
        end

        function writeArtifactsRejectsNonLogicalValues(testCase)
            [checkpointFile, imageFile, ~] = TestGradCAM.testInputs();

            testCase.verifyError( ...
                @() explain.gradcam(checkpointFile, imageFile, 2, ...
                'WriteArtifacts', 'no'), 'explain:InvalidOptions');
        end

        function invalidTargetClassProducesClearError(testCase)
            [checkpointFile, imageFile, ~] = TestGradCAM.testInputs();

            testCase.verifyError( ...
                @() explain.gradcam(checkpointFile, imageFile, 5), ...
                'explain:InvalidTargetClass');
        end

        function missingCheckpointProducesClearError(testCase)
            [~, imageFile, ~] = TestGradCAM.testInputs();
            missingCheckpoint = fullfile(tempname, 'missing_best_model.mat');

            testCase.verifyError( ...
                @() explain.gradcam(missingCheckpoint, imageFile, 2), ...
                'explain:MissingCheckpoint');
        end
    end

    methods (Static, Access = private)
        function [checkpointFile, imageFile, projectRoot] = testInputs()
            testFile = which('TestGradCAM');
            projectRoot = fileparts(fileparts(testFile));
            checkpointFile = fullfile(projectRoot, 'results', ...
                '20260822_030539', 'best_model.mat');
            imageFile = fullfile(projectRoot, 'data', 'raw', 'aptos2019', ...
                'train_images', '001639a390f0.png');
        end

        function removeDirectory(directory)
            if isfolder(directory)
                rmdir(directory, 's');
            end
        end
    end
end
