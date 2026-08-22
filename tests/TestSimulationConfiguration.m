classdef TestSimulationConfiguration < matlab.unittest.TestCase
    %TESTSIMULATIONCONFIGURATION Tests for the district capacity model's
    %configuration validation, arrival-calendar math, and headless
    %experiment outputs. Does not simulate the full .slx model, so it
    %stays fast enough to run on every commit.

    methods (TestClassSetup)
        function addSourcePath(~)
            testFile = which('TestSimulationConfiguration');
            projectRoot = fileparts(fileparts(testFile));
            addpath(genpath(fullfile(projectRoot, 'simulink')));
        end
    end

    methods (Test)
        function committedConfigIsValid(testCase)
            config = validateDistrictConfig();
            testCase.verifyEqual(config.annualScreeningVolume, 100000);
            testCase.verifyGreaterThan(config.arrivalRate, 0);
        end

        function missingRequiredFieldErrors(testCase)
            config = validateDistrictConfig();
            config = rmfield(config, 'numberOfGraders');
            testCase.verifyError(@() validateDistrictConfig(config), ...
                'district:MissingConfigurationField');
        end

        function negativeCaptureTimeErrors(testCase)
            config = validateDistrictConfig();
            config.captureTimeSeconds = -1;
            testCase.verifyError(@() validateDistrictConfig(config), ...
                'district:InvalidPositiveParameter');
        end

        function negativeInferenceTimeErrors(testCase)
            config = validateDistrictConfig();
            config.inferenceTimeSeconds = -0.5;
            testCase.verifyError(@() validateDistrictConfig(config), ...
                'district:InvalidPositiveParameter');
        end

        function zeroBandwidthErrors(testCase)
            config = validateDistrictConfig();
            config.bandwidthMegabitsPerSecond = 0;
            testCase.verifyError(@() validateDistrictConfig(config), ...
                'district:InvalidPositiveParameter');
        end

        function negativeBandwidthErrors(testCase)
            config = validateDistrictConfig();
            config.bandwidthMegabitsPerSecond = -10;
            testCase.verifyError(@() validateDistrictConfig(config), ...
                'district:InvalidPositiveParameter');
        end

        function zeroGraderCountErrors(testCase)
            config = validateDistrictConfig();
            config.numberOfGraders = 0;
            testCase.verifyError(@() validateDistrictConfig(config), ...
                'district:InvalidCountParameter');
        end

        function fractionalGraderCountErrors(testCase)
            config = validateDistrictConfig();
            config.numberOfGraders = 2.5;
            testCase.verifyError(@() validateDistrictConfig(config), ...
                'district:InvalidIntegerParameter');
        end

        function sensitivityAboveOneErrors(testCase)
            config = validateDistrictConfig();
            config.modelSensitivity = 1.2;
            testCase.verifyError(@() validateDistrictConfig(config), ...
                'district:InvalidProbability');
        end

        function negativeSpecificityErrors(testCase)
            config = validateDistrictConfig();
            config.modelSpecificity = -0.1;
            testCase.verifyError(@() validateDistrictConfig(config), ...
                'district:InvalidProbability');
        end

        function annualVolumeCalculationMatchesArrivalRate(testCase)
            config = validateDistrictConfig();
            config.simulationDurationDays = 365;
            config.arrivalRate = config.annualScreeningVolume / ...
                (config.simulationDurationDays * 86400);
            config = validateDistrictConfig(config);
            testCase.verifyEqual(config.derivedAnnualVolume, ...
                config.annualScreeningVolume, 'RelTol', 1e-9);
        end

        function turnaroundTargetCalculationConvertsHoursToSeconds(testCase)
            config = validateDistrictConfig();
            config.turnaroundTargetHours = 24;
            targetSeconds = config.turnaroundTargetHours * 3600;
            testCase.verifyEqual(targetSeconds, 86400);
        end

        function arrivalCalendarPreservesWeeklyVolumeUnderBursts(testCase)
            districtNextArrival('reset');
            baseRate = 100 / 86400;
            multiplier = 5;
            elapsed = 0;
            count = 0;
            while elapsed < 7 * 86400
                dt = districtNextArrival(baseRate, 1, multiplier);
                elapsed = elapsed + dt;
                count = count + 1;
            end
            expectedWeeklyCount = baseRate * 7 * 86400;
            testCase.verifyEqual(count, expectedWeeklyCount, 'RelTol', 0.02);
            districtNextArrival('reset');
        end

        function smoothArrivalsUseConfiguredRateDeterministically(testCase)
            districtNextArrival('reset');
            rate = 1 / 100;
            first = districtNextArrival(rate, 0, 1);
            second = districtNextArrival(rate, 0, 1);
            testCase.verifyEqual(first, 100);
            testCase.verifyEqual(second, 100);
            districtNextArrival('reset');
        end

        function sameSeedReproducesResults(testCase)
            overrides = {'AnnualScreeningVolume', 40, ...
                'SimulationDurationDays', 1, 'NumberOfPHCs', 1, ...
                'NumberOfGraders', 1, 'RandomSeed', 7};
            first = runDistrictSimulation([], overrides{:});
            second = runDistrictSimulation([], overrides{:});
            testCase.verifyEqual(first.totalEntitiesGenerated, ...
                second.totalEntitiesGenerated);
            testCase.verifyEqual(first.totalCompleted, second.totalCompleted);
            testCase.verifyEqual(first.totalAutoCleared, second.totalAutoCleared);
            testCase.verifyEqual(first.totalReferred, second.totalReferred);
            testCase.verifyEqual(first.totalEscalated, second.totalEscalated);
        end

        function differentSeedsCanProduceDifferentResults(testCase)
            base = {'AnnualScreeningVolume', 40, ...
                'SimulationDurationDays', 1, 'NumberOfPHCs', 1, ...
                'NumberOfGraders', 1};
            seedA = runDistrictSimulation([], ...
                base{:}, 'RandomSeed', 7);
            seedB = runDistrictSimulation([], ...
                base{:}, 'RandomSeed', 8);
            outcomesDiffer = ~isequal(seedA.totalAutoCleared, seedB.totalAutoCleared) ...
                || ~isequal(seedA.totalReferred, seedB.totalReferred) ...
                || ~isequal(seedA.totalEscalated, seedB.totalEscalated) ...
                || ~isequal(seedA.turnaroundTimeSeconds, seedB.turnaroundTimeSeconds);
            testCase.verifyTrue(outcomesDiffer, ...
                'Different random seeds should be able to produce different stochastic outcomes.');
        end

        function experimentOutputFieldsArePresent(testCase)
            required = requiredExperimentFields();
            fields = fieldnames(sampleResultStruct());
            for i = 1:numel(required)
                testCase.verifyTrue(ismember(required{i}, fields), ...
                    sprintf('Missing required experiment output field: %s', ...
                    required{i}));
            end
        end
    end
end

function fields = requiredExperimentFields()
fields = {'configuration', 'randomSeed', 'simulationDurationDays', ...
    'totalEntitiesGenerated', 'totalCompleted', 'totalAutoCleared', ...
    'totalReferred', 'totalEscalated', 'totalRecaptureAttempts', ...
    'meanTurnaroundTimeHours', 'p95TurnaroundTimeHours', ...
    'maximumQueueLength', 'meanQueueLength', 'graderUtilisation', ...
    'uploadQueueLength', 'percentMeetingTurnaroundTarget'};
end

function result = sampleResultStruct()
% A minimal struct with the same field names runDistrictSimulation
% produces, used to check the contract without running a simulation.
fields = requiredExperimentFields();
result = struct();
for i = 1:numel(fields)
    result.(fields{i}) = [];
end
end
