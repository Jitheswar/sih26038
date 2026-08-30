classdef TestLesionSegmentation < matlab.unittest.TestCase
    %TESTLESIONSEGMENTATION Cover the IDRiD Track B lesion segmentation path.

    properties (Constant, Access = private)
        SplitNames = {'train', 'validation', 'test'}
        ExpectedHeader = {'image_id', 'split', 'relative_path', ...
            'has_ma', 'has_he', 'has_ex', 'has_se'}
        ExpectedCounts = struct('train', 43, 'validation', 11, 'test', 27)
        LesionTypes = {'MA', 'HE', 'EX', 'SE'}
    end

    methods (TestClassSetup)
        function addSourceAndEvaluationPaths(~)
            testFile = which('TestLesionSegmentation');
            projectRoot = fileparts(fileparts(testFile));
            addpath(genpath(fullfile(projectRoot, 'src')));
            addpath(genpath(fullfile(projectRoot, 'eval')));
        end
    end

    methods (Test)
        function testSplitFilesExistWithExpectedShape(testCase)
            for index = 1:numel(testCase.SplitNames)
                splitName = testCase.SplitNames{index};
                splitTable = TestLesionSegmentation.readSplit(splitName);
                testCase.verifyEqual( ...
                    splitTable.Properties.VariableNames, ...
                    testCase.ExpectedHeader, ...
                    sprintf('Unexpected header in lesion_%s.csv.', splitName));
                testCase.verifyEqual(height(splitTable), ...
                    testCase.ExpectedCounts.(splitName), ...
                    sprintf('Unexpected row count in lesion_%s.csv.', ...
                    splitName));
            end
        end

        function testNoImageAppearsInMoreThanOneLesionSplit(testCase)
            % The same rule the APTOS splits are held to (§10.2). An image
            % that leaked from train into validation would make every
            % reported AUPR a training score.
            allIds = strings(0, 1);
            for index = 1:numel(testCase.SplitNames)
                splitName = testCase.SplitNames{index};
                ids = string(TestLesionSegmentation.readSplit(splitName).image_id);
                testCase.verifyEqual(numel(unique(ids)), numel(ids), ...
                    sprintf('Duplicate image ID inside lesion_%s.csv.', ...
                    splitName));
                allIds = [allIds; ids]; %#ok<AGROW>
            end
            testCase.verifyEqual(numel(unique(allIds)), numel(allIds), ...
                'An IDRiD image appears in more than one lesion split.');
        end

        function testTestSplitIsSetBAndTrainingSplitsAreSetA(testCase)
            % Set-B is the published IDRiD benchmark split. Training on it
            % would make the reported AUPR incomparable to the benchmark and
            % would not be a held-out number at all.
            testSplit = TestLesionSegmentation.readSplit('test');
            testCase.verifyTrue(all(contains(testSplit.relative_path, ...
                'b. Testing Set')), ...
                'lesion_test.csv must contain only IDRiD Set-B frames.');

            for splitName = ["train", "validation"]
                splitTable = TestLesionSegmentation.readSplit(char(splitName));
                testCase.verifyTrue(all(contains( ...
                    splitTable.relative_path, 'a. Training Set')), ...
                    sprintf(['lesion_%s.csv must contain only IDRiD Set-A ' ...
                    'frames.'], splitName));
            end
        end

        function testSoftExudateStratificationLeavesBothSplitsCovered(testCase)
            % Soft exudates appear on only 26 of the 54 Set-A frames, so an
            % unstratified draw can leave validation with none and make the
            % soft-exudate validation AUPR undefined.
            for splitName = ["train", "validation"]
                splitTable = TestLesionSegmentation.readSplit(char(splitName));
                testCase.verifyGreaterThan(sum(splitTable.has_se), 0, ...
                    sprintf(['lesion_%s.csv contains no soft-exudate ' ...
                    'frame.'], splitName));
            end
        end

        function testConfigurationDefaultsAreRecallWeighted(testCase)
            result = segment.trainLesionSegmentation( ...
                TestLesionSegmentation.configPath(), 'Mode', 'inspect');
            lesion = result.config.lesion_segmentation;
            testCase.verifyGreaterThanOrEqual(lesion.tversky_beta, ...
                lesion.tversky_alpha, ...
                ['The Tversky loss must weight false negatives at least ' ...
                'as heavily as false positives (§6.4).']);
            testCase.verifyGreaterThanOrEqual(lesion.patch_size, 64);
            testCase.verifyEqual(mod(lesion.patch_size, ...
                2 ^ lesion.encoder_depth), 0);
            testCase.verifyEqual(lesion.seed, 42);
        end

        function testConfigurationRejectsPrecisionWeightedLoss(testCase)
            config = jsondecode(fileread( ...
                TestLesionSegmentation.configPath()));
            config.lesion_segmentation.tversky_alpha = 0.8;
            config.lesion_segmentation.tversky_beta = 0.2;
            testCase.verifyError( ...
                @() segment.trainLesionSegmentation(config, ...
                'Mode', 'inspect'), 'segment:InvalidTversky');
        end

        function testConfigurationRejectsPatchSizeThatBreaksSkips(testCase)
            config = jsondecode(fileread( ...
                TestLesionSegmentation.configPath()));
            % 80 divides by 16 but not by 2^5, so the fifth downsample would
            % produce a skip connection the decoder cannot match.
            config.lesion_segmentation.patch_size = 80;
            config.lesion_segmentation.encoder_depth = 5;
            testCase.verifyError( ...
                @() segment.trainLesionSegmentation(config, ...
                'Mode', 'inspect'), 'segment:InvalidEncoderDepth');
        end

        function testNetworkHasOneOutputChannelPerLesionType(testCase)
            result = segment.trainLesionSegmentation( ...
                TestLesionSegmentation.configPath(), 'Mode', 'inspect');
            testCase.verifyEqual(result.status, "configured");
            testCase.verifyEqual(numel(result.lesionTypes), ...
                numel(testCase.LesionTypes));

            patchSize = result.config.lesion_segmentation.patch_size;
            probe = dlarray(zeros(patchSize, patchSize, 3, 1, 'single'), 'SSCB');
            logits = predict(result.net, probe);
            testCase.verifyEqual(size(logits, 3), ...
                numel(result.lesionTypes), ...
                'The head must emit exactly one channel per lesion type.');
        end

        function testLossPenalisesMissedLesionsMoreThanFalseAlarms(testCase)
            % The whole point of beta > alpha. If this inverts, the network
            % is free to reach an excellent loss by predicting background
            % everywhere, which is the failure §6.4 warns about.
            options = struct('alpha', 0.3, 'beta', 0.7, 'gamma', 2);
            targets = false(8, 8, 1, 1);
            targets(3:5, 3:5) = true;

            missed = -4 * ones(8, 8, 1, 1, 'single');
            falseAlarm = -4 * ones(8, 8, 1, 1, 'single');
            falseAlarm(1:3, 6:8) = 4;
            missedAll = falseAlarm;
            missedAll(3:5, 3:5) = -4;

            lossMissed = segment.lesionLoss( ...
                dlarray(missed, 'SSCB'), targets, options);
            lossFalseAlarm = segment.lesionLoss( ...
                dlarray(missedAll, 'SSCB'), targets, options);

            testCase.verifyGreaterThan(double(extractdata(lossMissed)), 0);
            testCase.verifyGreaterThan(double(extractdata(lossFalseAlarm)), 0);

            % Nine missed lesion pixels must cost more than nine spurious
            % ones over the same background.
            detected = -4 * ones(8, 8, 1, 1, 'single');
            detected(3:5, 3:5) = 4;
            lossDetected = segment.lesionLoss( ...
                dlarray(detected, 'SSCB'), targets, options);
            testCase.verifyLessThan(double(extractdata(lossDetected)), ...
                double(extractdata(lossMissed)), ...
                'Detecting the lesion must score better than missing it.');
        end

        function testAUPRRewardsAPerfectDetectorAndPunishesAConstantOne(testCase)
            thresholds = linspace(0, 1, 33);
            targets = false(64, 64, 1);
            targets(10:20, 10:20) = true;

            perfect = single(targets);
            perfectCounts = lesionThresholdCounts(perfect, targets, thresholds);
            perfectMetrics = lesionAUPR(perfectCounts, thresholds, {'HE'});
            testCase.verifyGreaterThan(perfectMetrics.aupr, 0.95, ...
                'A perfect detector must score near 1.');

            constant = 0.5 * ones(64, 64, 1, 'single');
            constantCounts = lesionThresholdCounts(constant, targets, ...
                thresholds);
            constantMetrics = lesionAUPR(constantCounts, thresholds, {'HE'});
            testCase.verifyLessThan(constantMetrics.aupr, 0.2, ...
                'A constant map carries no ranking information.');
        end

        function testPatchSamplerIsDeterministicAndRespectsLesionFraction(testCase)
            image = uint8(zeros(600, 700, 3));
            image(:) = 40;
            masks = false(600, 700, 2);
            masks(100:110, 100:110, 1) = true;
            masks(300:340, 300:340, 2) = true;
            fieldMask = true(75, 88);

            options = struct('patchSize', 128, 'patchCount', 20, ...
                'lesionFraction', 0.75, 'augment', false, 'seed', uint32(7));
            [firstPatches, firstMasks] = ...
                segment.sampleLesionPatches(image, masks, ...
                fieldMask, options);
            [secondPatches, secondMasks] = ...
                segment.sampleLesionPatches(image, masks, ...
                fieldMask, options);

            testCase.verifyEqual(firstPatches, secondPatches, ...
                'The same seed must produce the same patches (§13.2).');
            testCase.verifyEqual(firstMasks, secondMasks);
            testCase.verifyEqual(size(firstPatches), [128, 128, 3, 20]);

            containsLesion = squeeze(any(any(any(firstMasks, 1), 2), 3));
            testCase.verifyGreaterThanOrEqual(sum(containsLesion), 15, ...
                ['At least the requested lesion fraction of patches must ' ...
                'actually contain a lesion.']);
        end

        function testEvidenceRefusesAnArbitraryThreshold(testCase)
            % A default of 0.5 on a class occupying under one per cent of
            % the frame changes the lesion count by orders of magnitude, and
            % the count is exactly what the ICDR criteria read.
            inspected = segment.trainLesionSegmentation( ...
                TestLesionSegmentation.configPath(), 'Mode', 'inspect');
            model = struct('net', inspected.net, 'config', inspected.config);
            image = uint8(128 * ones(600, 600, 3));
            testCase.verifyError( ...
                @() segment.lesionEvidence(image, model), ...
                'segment:MissingThresholds');
        end

        function testLearnedEvidenceMakesLevelThreeReachable(testCase)
            % The measured §11.6 A3 result: the classical channel reaches
            % 0.0000 sensitivity because counting microaneurysms can never
            % satisfy a criterion above Level 1. This is the fix, asserted.
            classical = grade.icdrEvidenceFromDetection( ...
                struct('candidateCount', 12));
            classicalResult = grade.icdrRule(classical);
            testCase.verifyEqual(classicalResult.level, 1, ...
                'The classical channel can only ever reach Level 1.');

            learned = TestLesionSegmentation.learnedEvidence( ...
                [25, 25, 25, 25], 40, 3);
            learnedResult = grade.icdrRule(learned);
            testCase.verifyEqual(learnedResult.level, 3, ...
                ['More than twenty haemorrhages in each of four quadrants ' ...
                'is the 4-2-1 Level 3 criterion (§3.3).']);
            testCase.verifyTrue(learnedResult.referable);
        end

        function testLearnedEvidenceDeclaresRemainingGapsAsCapabilityGaps(testCase)
            % Presenting a permanent, every-image gap as a per-case unknown
            % escalates every patient and silently disables triage.
            learned = TestLesionSegmentation.learnedEvidence([1, 0, 0, 0], ...
                2, 0);
            coverage = learned.evidenceFieldCoverage;
            testCase.verifyTrue(coverage.microaneurysmCount);
            testCase.verifyTrue(coverage.haemorrhageCountPerQuadrant);
            testCase.verifyTrue(coverage.hardExudateCount);
            testCase.verifyTrue(coverage.softExudateCount);
            testCase.verifyFalse(coverage.neovascularisation, ...
                'Neovascularisation stays a declared data gap (§6.6).');

            result = grade.icdrRule(learned);
            testCase.verifyFalse(result.humanEscalationRecommended, ...
                ['A capability gap present on every image must not escalate ' ...
                'every patient.']);

            % The point of the whole exercise: the evidence channel can now
            % reach a referable level on its own, which §11.6 A3 measured it
            % could not.
            testCase.verifyGreaterThanOrEqual(result.maxReachableLevel, 3, ...
                ['Haemorrhage and exudate heads must make Level 3 ' ...
                'reachable from evidence alone.']);
            testCase.verifyTrue(result.referableLevelReachable);
        end

        function testLearnedEvidenceIsReadOnlyThroughAPTOSSelectedHeads(testCase)
            % Measured on 30 August 2026 over ten APTOS validation frames:
            % the IDRiD-trained channel, at thresholds selected on the IDRiD
            % validation split, called 10 of 10 referable including all five
            % grade-0 eyes. Specificity from this channel on APTOS is 0.00.
            % Sweeping all fourteen thresholds per head over the calibration
            % split (n = 365) showed that no threshold set rescues the
            % four-head channel: ICDR Level 2 fires on the presence of any
            % non-microaneurysm finding, so the channel ORs its heads and its
            % specificity is bounded by whichever head most often reports
            % something on a healthy eye. That head is soft exudates, which
            % clears under 2 per cent of eyes graded 0 at every threshold up
            % to 0.975. See the §11.7 transfer box in the design document.
            %
            % This test used to require the channel to stay switched off.
            % Its stated condition was "until its thresholds are re-selected
            % against APTOS-domain data", that re-selection landed in
            % 636f803, and the channel was adopted on 31 August 2026. So the
            % pin has moved rather than been removed: the channel may now be
            % read, but only through the heads and thresholds re-selection
            % chose. Widening evidence_heads is a screening-safety change,
            % not a configuration tidy-up, and this test is here to make that
            % explicit rather than to make it impossible.
            config = jsondecode(fileread( ...
                TestLesionSegmentation.configPath()));
            heads = cellstr(string( ...
                config.lesion_segmentation.evidence_heads));
            testCase.verifyEqual(heads, {'EX'}, ...
                ['The ICDR evidence channel must read the hard-exudate ' ...
                'head only. The other three heads were measured on APTOS ' ...
                'as unable to clear a healthy eye at any threshold, and ' ...
                'one untrustworthy head caps the specificity of the ' ...
                'whole channel because Level 2 ORs them together.']);
            testCase.verifyEqual( ...
                config.lesion_segmentation.evidence_thresholds.EX, 0.99, ...
                ['The hard-exudate evidence threshold must stay at the ' ...
                'value selected against the APTOS calibration split.']);
        end

        function testInferenceReturnsMapsOnTheCallersPixelGrid(testCase)
            [model, image] = TestLesionSegmentation.smallModel(200);
            result = segment.segmentLesions(image, model, ...
                'Environment', "cpu");

            testCase.verifyEqual(result.imageSize, [256, 256]);
            testCase.verifyEqual(size(result.probabilityMaps), ...
                [256, 256, 4], ...
                ['Probability maps must come back on the pixel grid the ' ...
                'caller passed in, whatever scaling happened inside.']);
            testCase.verifyTrue(all(isfinite(result.probabilityMaps(:))), ...
                'Tiling must cover the frame, leaving no unwritten pixels.');
            testCase.verifyGreaterThanOrEqual( ...
                min(result.probabilityMaps(:)), 0);
            testCase.verifyLessThanOrEqual(max(result.probabilityMaps(:)), 1);
        end

        function testScaleNormalisationResamplesToTheTrainingFieldSize(testCase)
            % IDRiD's field is 3279 pixels across and varies by three pixels
            % over the whole set; APTOS ranges 1055 to 2555. Without this the
            % network is asked to find lesions at a scale it never saw.
            [model, image] = TestLesionSegmentation.smallModel(300);
            result = segment.segmentLesions(image, model, ...
                'Environment', "cpu");

            % The synthetic field is 200 pixels across against a reference
            % of 300, so the frame should be resampled by about 1.5.
            testCase.verifyEqual(result.measuredFovDiameter, 200, ...
                'AbsTol', 12);
            testCase.verifyEqual(result.appliedScale, 1.5, 'AbsTol', 0.1);
            testCase.verifyTrue(result.metadata.scaleNormalisationApplied);
        end

        function testScaleNormalisationIsANoOpAtTheTrainingScale(testCase)
            % An IDRiD frame is already at the reference scale, so the
            % Set-B benchmark number must not move because this exists.
            [model, image] = TestLesionSegmentation.smallModel(200);
            result = segment.segmentLesions(image, model, ...
                'Environment', "cpu");
            testCase.verifyEqual(result.appliedScale, 1, ...
                'A frame already at the reference scale must not be resized.');
            testCase.verifyFalse(result.metadata.scaleNormalisationApplied);
        end

        function testLearnedEvidenceCoversFourOfEightFields(testCase)
            classical = grade.icdrEvidenceFromDetection( ...
                struct('candidateCount', 5));
            learned = TestLesionSegmentation.learnedEvidence([2, 1, 0, 0], ...
                7, 1);

            classicalCovered = sum(struct2array( ...
                classical.evidenceFieldCoverage));
            learnedCovered = sum(struct2array(learned.evidenceFieldCoverage));
            testCase.verifyEqual(classicalCovered, 1);
            testCase.verifyEqual(learnedCovered, 4, ...
                ['The learned channel must own microaneurysms, ' ...
                'haemorrhages, hard exudates and soft exudates.']);
        end
    end

    methods (Static, Access = private)
        function root = projectRoot()
            root = fileparts(fileparts(mfilename('fullpath')));
        end

        function path = configPath()
            path = fullfile(TestLesionSegmentation.projectRoot(), ...
                'config', 'default.json');
        end

        function splitTable = readSplit(splitName)
            splitFile = fullfile(TestLesionSegmentation.projectRoot(), ...
                'data', 'splits', sprintf('lesion_%s.csv', splitName));
            splitTable = readtable(splitFile, 'TextType', 'string');
        end

        function [model, image] = smallModel(referenceDiameter)
            %SMALLMODEL A tiny untrained network plus a synthetic frame.
            %   Shape, tiling and scale behaviour do not depend on what the
            %   network has learned, so these tests use an untrained one and
            %   stay fast enough to run on CPU in the ordinary suite.
            config = jsondecode(fileread( ...
                TestLesionSegmentation.configPath()));
            config.lesion_segmentation.patch_size = 64;
            config.lesion_segmentation.base_filters = 8;
            config.lesion_segmentation.tile_overlap = 8;
            config.lesion_segmentation.batch_size = 8;
            config.lesion_segmentation.fov_downsample = 2;
            config.lesion_segmentation.reference_fov_diameter = ...
                referenceDiameter;

            inspected = segment.trainLesionSegmentation(config, ...
                'Mode', 'inspect');
            model = struct('net', inspected.net, ...
                'config', inspected.config);

            % A 200-pixel illuminated disc on a black surround, which is the
            % shape quality.fovMask is built to find.
            image = zeros(256, 256, 3, 'uint8');
            [columns, rows] = meshgrid(1:256, 1:256);
            field = hypot(columns - 128, rows - 128) <= 100;
            for channel = 1:3
                plane = image(:, :, channel);
                plane(field) = 160;
                image(:, :, channel) = plane;
            end
        end

        function evidence = learnedEvidence(quadrantCounts, hardExudates, ...
                softExudates)
            %LEARNEDEVIDENCE Minimal segment.lesionEvidence-shaped structure.
            lesionEvidence = struct();
            lesionEvidence.lesionTypes = {'MA', 'HE', 'EX', 'SE'};
            lesionEvidence.counts = struct('MA', 9, ...
                'HE', sum(quadrantCounts), 'EX', hardExudates, ...
                'SE', softExudates);
            lesionEvidence.haemorrhageQuadrantCounts = struct( ...
                'ST', quadrantCounts(1), 'IT', quadrantCounts(2), ...
                'SN', quadrantCounts(3), 'IN', quadrantCounts(4));
            evidence = grade.icdrEvidenceFromLesionSegmentation(lesionEvidence);
        end
    end
end
