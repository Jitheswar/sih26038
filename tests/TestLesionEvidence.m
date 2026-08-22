classdef TestLesionEvidence < matlab.unittest.TestCase
    %TESTLESIONEVIDENCE Tests the classical candidate evidence milestone.

    methods (TestClassSetup)
        function addSourcePath(~)
            testFile = which('TestLesionEvidence');
            projectRoot = fileparts(fileparts(testFile));
            addpath(genpath(fullfile(projectRoot, 'src')));
        end
    end

    methods (Test)
        function circularResponseProducesCandidate(testCase)
            image = TestLesionEvidence.syntheticImage(true, false);
            result = segment.detectMicroaneurysmCandidates(image, ...
                struct('responseThreshold', 0.02));

            testCase.verifyGreaterThan(result.candidateCount, 0);
            testCase.verifyTrue(any(result.candidateCoordinates(:, 1) < 50));
        end

        function elongatedVesselLikeResponseIsSuppressedOrLowerScored(testCase)
            circularImage = TestLesionEvidence.syntheticImage(true, false);
            elongatedImage = TestLesionEvidence.syntheticImage(false, true);
            configuration = struct('responseThreshold', 0.02);
            circular = segment.detectMicroaneurysmCandidates(circularImage, configuration);
            elongated = segment.detectMicroaneurysmCandidates(elongatedImage, configuration);

            testCase.verifyTrue(elongated.candidateCount <= circular.candidateCount || ...
                max([0; elongated.candidateScores]) < max([0; circular.candidateScores]));
        end

        function coordinatesAreInsideFov(testCase)
            result = segment.detect(TestLesionEvidence.syntheticImage(true, false));

            if result.candidateCount > 0
                linear = sub2ind(size(result.fovMask), ...
                    round(result.candidateCoordinates(:, 2)), ...
                    round(result.candidateCoordinates(:, 1)));
                testCase.verifyTrue(all(result.fovMask(linear)));
            end
        end

        function areasAndScoresAreFiniteAndNonNegative(testCase)
            result = segment.detect(TestLesionEvidence.syntheticImage(true, false));

            testCase.verifyTrue(all(isfinite(result.candidateAreas)));
            testCase.verifyTrue(all(result.candidateAreas >= 0));
            testCase.verifyTrue(all(isfinite(result.candidateScores)));
            testCase.verifyTrue(all(result.candidateScores >= 0));
        end

        function emptyFovReturnsEmptyCandidates(testCase)
            result = segment.detectMicroaneurysmCandidates(zeros(64, 64, 3));

            testCase.verifyEmpty(result.candidateCoordinates);
            testCase.verifyEqual(result.candidateCount, 0);
            testCase.verifyFalse(any(result.fovMask(:)));
        end

        function missingVesselMaskIsRecorded(testCase)
            result = segment.detect(TestLesionEvidence.syntheticImage(true, false));

            testCase.verifyFalse(result.vesselSuppression.available);
            testCase.verifySubstring(result.vesselSuppression.status, 'unavailable');
            testCase.verifySubstring(result.metadata.vesselSuppressionStatus, 'unavailable');
        end

        function invalidImageHasUsefulError(testCase)
            testCase.verifyError(@() segment.detectMicroaneurysmCandidates([]), ...
                'segment:InvalidImage');
            testCase.verifyError(@() segment.detectMicroaneurysmCandidates(ones(8, 8) * 2), ...
                'segment:InvalidImage');
        end

        function suppliedCoordinateFrameAssignsQuadrants(testCase)
            coordinates = [80, 45; 80, 55; 20, 45; 20, 55];
            frame = struct('opticDiscCenter', [50, 50], ...
                'foveaCenter', [80, 50]);
            [labels, counts, metadata] = segment.assignQuadrants( ...
                coordinates, frame, [100, 100]);

            testCase.verifyEqual(labels, {'ST'; 'IT'; 'SN'; 'IN'});
            testCase.verifyEqual([counts.ST, counts.IT, counts.SN, counts.IN], [1, 1, 1, 1]);
            testCase.verifyEqual(metadata.coordinateFrameMethod, 'optic-disc-fovea');
            testCase.verifyFalse(metadata.isApproximate);
        end

        function approximateFallbackIsLabelled(testCase)
            [~, ~, metadata] = segment.assignQuadrants([10, 10], struct(), [40, 40]);

            testCase.verifyTrue(metadata.isApproximate);
            testCase.verifySubstring(metadata.coordinateFrameMethod, 'approximate');
            testCase.verifySubstring(metadata.description, 'unavailable');
        end

        function candidateOverlayMatchesInputDimensions(testCase)
            image = TestLesionEvidence.syntheticImage(true, false);
            detection = segment.detect(image);
            evidence = explain.buildLesionEvidence(image, detection);

            testCase.verifyEqual(size(evidence.candidateOverlay), size(image));
        end

        function candidatesAreNeverConfirmedClinicalLesions(testCase)
            detection = segment.detect(TestLesionEvidence.syntheticImage(true, false));
            evidence = explain.buildLesionEvidence( ...
                TestLesionEvidence.syntheticImage(true, false), detection);

            testCase.verifyTrue(all(strcmp(detection.candidateClassLabels, ...
                'microaneurysm candidate')));
            testCase.verifySubstring(evidence.evidenceText, ...
                'Classical candidate evidence - not clinically validated lesion segmentation.');
            testCase.verifyNotEmpty(strfind(lower(evidence.evidenceText), 'candidate')); %#ok<STRCLFH>
        end

        function configuredThresholdIsUsed(testCase)
            image = TestLesionEvidence.syntheticImage(true, false);
            low = segment.detectMicroaneurysmCandidates(image, ...
                struct('threshold', 0.01));
            high = segment.detectMicroaneurysmCandidates(image, ...
                struct('threshold', 0.90));

            testCase.verifyEqual(low.diagnostic.responseThreshold, 0.01);
            testCase.verifyEqual(high.diagnostic.responseThreshold, 0.90);
            testCase.verifyGreaterThan(low.candidateCount, high.candidateCount);
        end
    end

    methods (Static, Access = private)
        function image = syntheticImage(circle, vessel)
            n = 128;
            [x, y] = meshgrid(1:n, 1:n);
            fov = (x - 64) .^ 2 + (y - 64) .^ 2 <= 55 ^ 2;
            green = 0.45 * ones(n);
            green(~fov) = 0;
            if circle
                green((x - 42) .^ 2 + (y - 48) .^ 2 <= 3 ^ 2) = 0.05;
            end
            if vessel
                green(abs(y - 84) <= 2 & x > 25 & x < 105) = 0.05;
            end
            image = cat(3, 0.80 * green, green, 0.62 * green);
        end
    end
end
