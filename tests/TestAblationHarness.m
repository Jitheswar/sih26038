classdef TestAblationHarness < matlab.unittest.TestCase
    %TESTABLATIONHARNESS Tests for the A1-A5 ablation evaluation path.
    %
    %   eval/ablationHarness.m composes the screening modules itself rather
    %   than calling app.runScreeningCase, so that the deployed inference
    %   path which produced the frozen operating point is not modified to
    %   carry ablation switches.  The cost of that choice is drift: two
    %   orchestrations of the same modules can diverge silently.
    %
    %   agreesWithDeployedPipelineForA5 is the pin.  If it fails, the
    %   harness no longer reproduces the deployed pipeline and every number
    %   it has produced is void.

    methods (TestClassSetup)
        function addSourcePath(~)
            projectRoot = TestAblationHarness.projectRoot();
            addpath(genpath(fullfile(projectRoot, 'src')));
            addpath(fullfile(projectRoot, 'eval'));
            addpath(fullfile(projectRoot, 'eval', 'metrics'));
        end
    end

    methods (Test)
        function agreesWithDeployedPipelineForA5(testCase)
            projectRoot = TestAblationHarness.projectRoot();
            imageCount = 4;
            resultsRoot = tempname;
            cleanup = onCleanup(@() TestAblationHarness.removeDirectory(resultsRoot)); %#ok<NASGU>

            harnessResult = ablationHarness('Configs', {'ablation_A5.json'}, ...
                'Split', 'validation', 'Limit', imageCount, ...
                'ResultsRoot', resultsRoot);
            harnessDecisions = harnessResult.metrics(1).decisions.decision;

            configPath = fullfile(projectRoot, 'config', 'default.json');
            defaultConfig = jsondecode(fileread(configPath));
            checkpointPath = fullfile(projectRoot, defaultConfig.operating_point.model);
            temperature = defaultConfig.operating_point.temperature;

            splitTable = readtable(fullfile(projectRoot, 'data', 'splits', ...
                'validation.csv'), 'TextType', 'string');

            for index = 1:imageCount
                imagePath = fullfile(projectRoot, char(splitTable.relative_path(index)));
                deployed = app.runScreeningCase(imagePath, checkpointPath, ...
                    temperature, configPath);
                expected = TestAblationHarness.deployedDecision(deployed);

                testCase.verifyEqual(harnessDecisions(index), expected, ...
                    sprintf(['A5 decision for %s disagrees with ' ...
                    'app.runScreeningCase. The ablation harness has drifted ' ...
                    'from the deployed pipeline.'], ...
                    char(splitTable.image_id(index))));
            end
        end

        function testSplitIsRefused(testCase)
            testCase.verifyError(@() ablationHarness('Split', 'test'), ...
                'eval:TestSplitRefused');
        end

        function sealedSplitIsRefused(testCase)
            testCase.verifyError(@() ablationHarness('Split', 'sealed'), ...
                'eval:SealedData');
        end

        function everyConfigurationRunsAtTheFrozenThreshold(testCase)
            projectRoot = TestAblationHarness.projectRoot();
            defaultConfig = jsondecode(fileread(fullfile(projectRoot, ...
                'config', 'default.json')));
            frozenThreshold = defaultConfig.operating_point.referable_threshold;
            frozenModel = defaultConfig.operating_point.model;

            names = {'A1', 'A2', 'A3', 'A4', 'A5'};
            for index = 1:numel(names)
                configPath = fullfile(projectRoot, 'config', ...
                    sprintf('ablation_%s.json', names{index}));
                config = jsondecode(fileread(configPath));

                % §11.6 requires one frozen threshold across the study. A
                % configuration carrying its own would make the comparison
                % meaningless.
                testCase.verifyEqual(config.operating_point.referable_threshold, ...
                    frozenThreshold, sprintf('%s does not use the frozen threshold.', names{index}));
                testCase.verifyEqual(config.operating_point.model, frozenModel, ...
                    sprintf('%s does not use the frozen model.', names{index}));
                testCase.verifyEqual(config.decision_policy.autoClearThreshold, ...
                    frozenThreshold, sprintf(['%s autoClearThreshold does not realise ' ...
                    'the frozen operating point.'], names{index}));
            end
        end

        function pipelineFlagsMatchTheDesignTable(testCase)
            projectRoot = TestAblationHarness.projectRoot();
            % Straight from the §11.6 table: quality_gate, lesion_evidence,
            % agreement_check, deferral.
            expected = struct( ...
                'A1', [false, false, false, false], ...
                'A2', [true,  false, false, false], ...
                'A3', [false, true,  false, false], ...
                'A4', [true,  false, false, true ], ...
                'A5', [true,  true,  true,  true ]);

            names = fieldnames(expected);
            for index = 1:numel(names)
                config = jsondecode(fileread(fullfile(projectRoot, 'config', ...
                    sprintf('ablation_%s.json', names{index}))));
                actual = [config.pipeline.quality_gate, ...
                    config.pipeline.lesion_evidence, ...
                    config.pipeline.agreement_check, ...
                    config.pipeline.deferral];
                testCase.verifyEqual(logical(actual), expected.(names{index}), ...
                    sprintf('%s pipeline flags do not match §11.6.', names{index}));
            end
        end

        function deferralOffNeverEscalates(testCase)
            resultsRoot = tempname;
            cleanup = onCleanup(@() TestAblationHarness.removeDirectory(resultsRoot)); %#ok<NASGU>

            result = ablationHarness('Configs', {'ablation_A1.json'}, ...
                'Split', 'validation', 'Limit', 6, 'ResultsRoot', resultsRoot);
            decisions = result.metrics(1).decisions.decision;

            testCase.verifyFalse(any(strcmp(decisions, "escalate")), ...
                'A1 has deferral off and must produce a forced two-way disposition.');
            testCase.verifyEqual(result.metrics(1).coverage, 1, ...
                'A1 handles every case autonomously by construction.');
        end

        function resultsDirectoryCarriesConfigAndTable(testCase)
            resultsRoot = tempname;
            cleanup = onCleanup(@() TestAblationHarness.removeDirectory(resultsRoot)); %#ok<NASGU>

            result = ablationHarness('Configs', {'ablation_A1.json'}, ...
                'Split', 'validation', 'Limit', 4, 'ResultsRoot', resultsRoot);
            directory = char(result.resultsDirectory);

            testCase.verifyTrue(isfile(fullfile(directory, 'ablation_table.csv')));
            testCase.verifyTrue(isfile(fullfile(directory, 'ablation_summary.json')));
            testCase.verifyTrue(isfile(fullfile(directory, 'ablation_results.mat')));
            testCase.verifyTrue(isfile(fullfile(directory, 'config_A1.json')));
            testCase.verifyFalse(result.sealedDataAccessed);
        end
    end

    methods (Static, Access = private)
        function root = projectRoot()
            root = fileparts(fileparts(which('TestAblationHarness')));
        end

        function decision = deployedDecision(deployed)
            if strcmp(deployed.status, "stopped_quality_gate")
                decision = "human-review";
            else
                decision = string(deployed.threeWayDecision.decision);
            end
        end

        function removeDirectory(directory)
            if isfolder(directory)
                rmdir(directory, 's');
            end
        end
    end
end
