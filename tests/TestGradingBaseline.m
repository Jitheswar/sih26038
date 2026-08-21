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
    end
end
