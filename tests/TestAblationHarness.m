classdef TestAblationHarness < matlab.unittest.TestCase
    %TESTABLATIONHARNESS Tests for the A1-A13 ablation evaluation path.
    %
    %   eval/ablationHarness.m composes the screening modules itself rather
    %   than calling app.runScreeningCase, so that the deployed inference
    %   path which produced the frozen operating point is not modified to
    %   carry ablation switches.  The cost of that choice is drift: two
    %   orchestrations of the same modules can diverge silently.
    %
    %   agreesWithDeployedPipelineForA10 is the pin.  If it fails, the
    %   harness no longer reproduces the deployed pipeline and every number
    %   it has produced is void.
    %
    %   The pin follows config/default.json rather than naming a fixed
    %   configuration.  It pointed at A5 while the classical channel and the
    %   exact level comparison shipped; A10 was adopted on 31 August 2026,
    %   so it points at A10.  Re-point it whenever the deployed
    %   configuration changes, and never relax it to make it pass.

    methods (TestClassSetup)
        function addSourcePath(~)
            projectRoot = TestAblationHarness.projectRoot();
            addpath(genpath(fullfile(projectRoot, 'src')));
            addpath(fullfile(projectRoot, 'eval'));
            addpath(fullfile(projectRoot, 'eval', 'metrics'));
        end
    end

    methods (Test)
        function agreesWithDeployedPipelineForA10(testCase)
            projectRoot = TestAblationHarness.projectRoot();
            imageCount = 4;
            resultsRoot = tempname;
            cleanup = onCleanup(@() TestAblationHarness.removeDirectory(resultsRoot)); %#ok<NASGU>

            harnessResult = ablationHarness('Configs', {'ablation_A10.json'}, ...
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
                    sprintf(['A10 decision for %s disagrees with ' ...
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

        function deferralWithoutLesionEvidenceStillDecides(testCase)
            % A4 switches the lesion channel off and leaves deferral on.
            % Delegating that to grade.decisionPolicy raised
            % missing-rule-evidence on every image and escalated all of
            % them, so A4 measured the contradiction between a pipeline
            % flag and a locked safety invariant rather than measuring
            % deferral.  The reduced policy is composed in the harness and
            % must be able to reach a disposition without the lesion
            % channel.
            resultsRoot = tempname;
            cleanup = onCleanup(@() TestAblationHarness.removeDirectory(resultsRoot)); %#ok<NASGU>

            result = ablationHarness('Configs', {'ablation_A4.json'}, ...
                'Split', 'validation', 'Limit', 8, 'ResultsRoot', resultsRoot);
            decisions = result.metrics(1).decisions.decision;

            testCase.verifyGreaterThan(result.metrics(1).coverage, 0, ...
                'A4 must handle some case autonomously; zero coverage means the policy cannot act.');
            testCase.verifyFalse(any(strcmp(decisions, "failed")), ...
                'A4 must not fail cases for want of an evidence channel it switched off.');
        end

        function fullPipelineReachesMoreThanEscalation(testCase)
            % The three-way decision must reach more than one outcome.  A5
            % escalated all 550 validation cases because capability gaps
            % were treated as per-case safety exceptions.
            resultsRoot = tempname;
            cleanup = onCleanup(@() TestAblationHarness.removeDirectory(resultsRoot)); %#ok<NASGU>

            result = ablationHarness('Configs', {'ablation_A5.json'}, ...
                'Split', 'validation', 'Limit', 8, 'ResultsRoot', resultsRoot);
            decisions = result.metrics(1).decisions.decision;

            testCase.verifyGreaterThan(result.metrics(1).coverage, 0, ...
                'A5 escalating every case means the decision layer is disabled, not conservative.');
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

        function perCaseRowsReconcileWithTheAggregates(testCase)
            % The safety column counts referable patients sent home, and
            % until now nothing recorded which ones they were. These rows
            % are only worth having if they add up to the same numbers the
            % table reports, so the reconciliation is the test.
            result = ablationHarness('Configs', {'ablation_A10.json'}, ...
                'Limit', 4, 'ResultsRoot', tempname());
            perCase = readtable(fullfile(result.resultsDirectory, ...
                'per_case.csv'), 'TextType', 'string');
            testCase.assertNotEmpty(perCase);

            metrics = result.metrics(1);
            rows = perCase(perCase.config == "A10", :);
            testCase.verifyEqual(height(rows), metrics.n, ...
                'One row per evaluated case.');
            testCase.verifyEqual(sum(rows.autonomous), ...
                metrics.autonomousCount, 'Autonomous count must agree.');
            testCase.verifyEqual(sum(rows.missed_referable), ...
                metrics.missedReferable, ...
                'The safety column must be the sum of its own rows.');
            testCase.verifyEqual(sum(rows.decision == "auto-clear"), ...
                metrics.decisionCounts.autoClear);
            testCase.verifyEqual(sum(rows.decision == "refer"), ...
                metrics.decisionCounts.refer);
            testCase.verifyEqual(sum(rows.decision == "escalate"), ...
                metrics.decisionCounts.escalate);
        end

        function everyMissedReferableIsNamed(testCase)
            % The point of the rows: a patient the pipeline sent home can
            % be identified, graded and looked at. A count cannot be.
            result = ablationHarness('Configs', {'ablation_A10.json'}, ...
                'Limit', 4, 'ResultsRoot', tempname());
            perCase = readtable(fullfile(result.resultsDirectory, ...
                'per_case.csv'), 'TextType', 'string');
            missed = perCase(perCase.missed_referable == 1, :);
            for index = 1:height(missed)
                testCase.verifyNotEqual(missed.image_id(index), "", ...
                    'A missed patient must carry an image id.');
                testCase.verifyGreaterThanOrEqual(missed.truth_grade(index), 2, ...
                    'A missed referable case must be graded referable.');
                testCase.verifyTrue(missed.autonomous(index), ...
                    'A patient the pipeline escalated was not sent home.');
            end
        end

        function exportedEvidenceIsWhatTheDecisionsUsed(testCase)
            % The cache holds the classical channel and a configuration
            % reading the learned one swaps it in when it composes its
            % decisions, so an export taken from the cache sweeps a
            % configuration against evidence it never saw. This pins that
            % the exported values reproduce the statistic the decision was
            % actually taken from, which is the invariant that broke.
            result = ablationHarness('Configs', {'ablation_A10.json'}, ...
                'Limit', 6, 'ResultsRoot', tempname());
            directory = char(result.resultsDirectory);
            loaded = load(fullfile(directory, 'spatial_evidence.mat'), 'evidence');
            testCase.assertTrue(any(strcmp( ...
                string({loaded.evidence.config}), "A10")), ...
                'No spatial evidence recorded for the configuration that ran.');
            evidence = loaded.evidence(strcmp( ...
                string({loaded.evidence.config}), "A10"));

            rows = readtable(fullfile(directory, 'per_case.csv'), ...
                'TextType', 'string');
            rows = rows(rows.config == "A10", :);
            [found, where] = ismember(rows.image_id, evidence.imageIds);
            testCase.assertTrue(all(found), ...
                'Every per-case row must have exported evidence.');

            for index = 1:height(rows)
                entry = evidence.values{where(index)};
                if isempty(entry) || ~entry.known || entry.candidatesScored == 0
                    continue;
                end
                testCase.verifyEqual( ...
                    mean(entry.values >= 0.35), ...
                    rows.spatial_statistic(index), 'AbsTol', 1e-9, ...
                    sprintf(['Exported evidence for %s does not reproduce ' ...
                    'the statistic its decision used.'], rows.image_id(index)));
            end
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
