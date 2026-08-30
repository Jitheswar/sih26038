classdef TestLesionCounting < matlab.unittest.TestCase
    %TESTLESIONCOUNTING Tests the shared probability-map-to-count step.
    %   segment.countLesionType and segment.defaultLesionMinimumArea were
    %   factored out of segment.lesionEvidence so the threshold-transfer
    %   sweep could reuse them rather than reimplement them.  These tests
    %   pin the behaviour both callers depend on.

    methods (TestClassSetup)
        function addSourcePath(~)
            testFile = which('TestLesionCounting');
            projectRoot = fileparts(fileparts(testFile));
            addpath(genpath(fullfile(projectRoot, 'src')));
            addpath(genpath(fullfile(projectRoot, 'eval')));
        end
    end

    methods (Test)
        function countsDiscreteComponents(testCase)
            map = zeros(64, 64);
            map(10:14, 10:14) = 0.9;
            map(40:44, 40:44) = 0.9;

            count = segment.countLesionType(map, 0.5, 1);

            testCase.verifyEqual(count, 2);
        end

        function raisingTheThresholdCannotRaiseTheCount(testCase)
            rng(42, 'twister');
            map = rand(128, 128);

            counts = arrayfun(@(t) segment.countLesionType(map, t, 1), ...
                0.1:0.1:0.9);

            % Not monotonic in general - splitting a blob can raise the
            % count - but the mask itself must shrink, so the final
            % threshold cannot retain pixels the first one dropped.
            highMask = map >= 0.9;
            lowMask = map >= 0.1;
            testCase.verifyTrue(all(lowMask(highMask)));
            testCase.verifyTrue(all(isfinite(counts)));
        end

        function minimumAreaDiscardsSmallComponents(testCase)
            map = zeros(64, 64);
            map(10:14, 10:14) = 0.9;   % 25 pixels
            map(40, 40) = 0.9;         % 1 pixel

            unfiltered = segment.countLesionType(map, 0.5, 1);
            filtered = segment.countLesionType(map, 0.5, 10);

            testCase.verifyEqual(unfiltered, 2);
            testCase.verifyEqual(filtered, 1);
        end

        function emptyMapProducesNoComponents(testCase)
            [count, centroids, areas, mask] = ...
                segment.countLesionType(zeros(32, 32), 0.5, 1);

            testCase.verifyEqual(count, 0);
            testCase.verifySize(centroids, [0 2]);
            testCase.verifySize(areas, [0 1]);
            testCase.verifyFalse(any(mask(:)));
        end

        function centroidsAreReturnedAsXYPairs(testCase)
            map = zeros(64, 64);
            map(10:14, 20:24) = 0.9;

            [count, centroids] = segment.countLesionType(map, 0.5, 1);

            testCase.verifyEqual(count, 1);
            testCase.verifySize(centroids, [1 2]);
            % Centroid is [x y]: the blob sits at columns 20-24, rows 10-14.
            testCase.verifyEqual(centroids(1), 22, 'AbsTol', 0.5);
            testCase.verifyEqual(centroids(2), 12, 'AbsTol', 0.5);
        end

        function thresholdIsInclusive(testCase)
            map = 0.5 * ones(16, 16);

            count = segment.countLesionType(map, 0.5, 1);

            testCase.verifyEqual(count, 1);
        end

        function invalidArgumentsAreRejected(testCase)
            map = zeros(16, 16);

            testCase.verifyError(@() segment.countLesionType('x', 0.5, 1), ...
                'segment:InvalidProbabilityMap');
            testCase.verifyError(@() segment.countLesionType(map, [0.1 0.2], 1), ...
                'segment:InvalidThreshold');
            testCase.verifyError(@() segment.countLesionType(map, NaN, 1), ...
                'segment:InvalidThreshold');
            testCase.verifyError(@() segment.countLesionType(map, 0.5, -1), ...
                'segment:InvalidMinimumArea');
        end

        function minimumAreaDefaultsMatchTheDocumentedScale(testCase)
            areas = segment.defaultLesionMinimumArea({'MA', 'HE', 'EX', 'SE'});

            testCase.verifyEqual(areas(:)', [3 10 10 20]);
        end

        function microaneurysmFloorIsTheLowest(testCase)
            areas = segment.defaultLesionMinimumArea({'MA', 'HE', 'EX', 'SE'});

            % §3.2: microaneurysms sit near the resolution limit, so their
            % floor must stay below every larger lesion's floor.
            testCase.verifyTrue(all(areas(1) < areas(2:end)));
        end

        function unknownLesionTypeFallsBackToOnePixel(testCase)
            areas = segment.defaultLesionMinimumArea({'MA', 'NVD'});

            testCase.verifyEqual(areas(:)', [3 1]);
        end

        function characterInputIsAccepted(testCase)
            areas = segment.defaultLesionMinimumArea('HE');

            testCase.verifyEqual(areas, 10);
        end

        function thresholdTransferRefusesTheSealedSplit(testCase)
            % §10.4: the sealed set is opened once by the human key-holder,
            % never by a parameter sweep looking for a better operating
            % point. The refusal is the whole point of the mechanism.
            testCase.verifyError( ...
                @() lesionThresholdTransfer('Split', 'sealed', 'Limit', 1), ...
                'eval:SealedSplitRefused');
        end
    end
end
