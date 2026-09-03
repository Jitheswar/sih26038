classdef TestSpatialConstantSweep < matlab.unittest.TestCase
    %TESTSPATIALCONSTANTSWEEP The sweep reads the deployed rule, not a copy.
    %   The sweep answers what the §8.6 gate's two constants are worth, and
    %   its answer is only as good as the verdict it applies.  It carried a
    %   local mirror of grade.spatialVerdict that flattened the two
    %   zero-candidate cases grade.spatialEvidence deliberately keeps
    %   distinguishable: candidates that all land off the map were scored as
    %   vacuous agreement, so the gate never fired on them at any pair.
    %
    %   That understates escalation load and, if such a case were ever one
    %   the classifier sends home, would report the gate as catching a
    %   patient it does not catch.  No case in the calibration or validation
    %   splits is out of frame, so the mirror never changed a published
    %   number, but the sealed set has not been read yet.  These pin the
    %   sweep to the shared rule so it cannot drift again.

    methods (TestClassSetup)
        function addSourcePath(~)
            projectRoot = fileparts(fileparts( ...
                which('TestSpatialConstantSweep')));
            addpath(genpath(fullfile(projectRoot, 'src')));
            addpath(fullfile(projectRoot, 'eval'));
            addpath(fullfile(projectRoot, 'eval', 'metrics'));
        end
    end

    methods (Static)
        function directory = writeRun(testCase, entries, truthReferable, probabilities, split, threshold)
            %WRITERUN A minimal ablation run directory the sweep can read.
            directory = fullfile(tempname(), 'run');
            mkdir(directory);
            testCase.addTeardown(@() rmdir(fileparts(directory), 's'));

            count = numel(entries);
            imageIds = string(compose('img%02d', (1:count)'));

            evidence = struct('config', {}, 'imageIds', {}, 'values', {}, ...
                'known', {}, 'candidatesScored', {});
            record = struct();
            record.config = "A10";
            record.imageIds = imageIds;
            record.values = entries(:)';
            record.known = cellfun(@(e) ~isempty(e) && e.known, entries(:)');
            record.candidatesScored = cellfun( ...
                @(e) TestSpatialConstantSweep.scored(e), entries(:)');
            evidence(end + 1) = record;
            save(fullfile(directory, 'spatial_evidence.mat'), 'evidence');

            rows = table(repmat("A10", count, 1), imageIds, ...
                truthReferable(:), probabilities(:), ...
                'VariableNames', {'config', 'image_id', ...
                'truth_referable', 'calibrated_probability'});
            writetable(rows, fullfile(directory, 'per_case.csv'), ...
                'QuoteStrings', 'all');

            summary = struct('split', split, 'n', count, ...
                'frozenOperatingPoint', struct('threshold', threshold));
            fid = fopen(fullfile(directory, 'ablation_summary.json'), 'w');
            fprintf(fid, '%s', jsonencode(summary));
            fclose(fid);
        end

        function count = scored(entry)
            if isempty(entry)
                count = 0;
            else
                count = entry.candidatesScored;
            end
        end

        function entry = offTheMap()
            %OFFTHEMAP Candidates exist and none land on the heatmap.
            entry = struct('values', zeros(0, 1), 'known', true, ...
                'candidatesScored', 0, 'outOfFrame', true);
        end

        function entry = noCandidates()
            %NOCANDIDATES The lesion channel found nothing.
            entry = struct('values', zeros(0, 1), 'known', true, ...
                'candidatesScored', 0);
        end

        function entry = scoredAt(values)
            entry = struct('values', values(:), 'known', true, ...
                'candidatesScored', numel(values));
        end
    end

    methods (Test)
        function candidatesOffTheMapEscalateAtEveryPair(testCase)
            % The defect this file exists for.  grade.spatialVerdict returns
            % agree = false here, so the gate fires; the sweep's old mirror
            % returned a cleared fraction of 1, which no fraction threshold
            % can fall below, so the gate never fired at any pair.
            entries = {TestSpatialConstantSweep.offTheMap()};
            directory = TestSpatialConstantSweep.writeRun(testCase, ...
                entries, 1, 0.05, 'calibration', 0.40);

            result = spatialConstantSweep(directory, ...
                'Cuts', [0.2 0.35 0.6], 'Fractions', [0.05 0.25 0.9], ...
                'ResultsRoot', '');

            % One must-catch patient, caught by every pair.
            testCase.verifyEqual(numel(result.mustCatch), 1);
            testCase.verifyTrue(all(result.caughtOfRequired(:) == 1), ...
                ['A candidate set that lands entirely off the map is a ' ...
                'failure to correspond, and the deployed gate escalates ' ...
                'it at every pair. The sweep must agree.']);
            testCase.verifyTrue(all(result.escalationLoad(:) == 1));
        end

        function noCandidatesAgreesAtEveryPair(testCase)
            % The other zero-candidate case, and it means the opposite.
            entries = {TestSpatialConstantSweep.noCandidates()};
            directory = TestSpatialConstantSweep.writeRun(testCase, ...
                entries, 1, 0.05, 'calibration', 0.40);

            result = spatialConstantSweep(directory, ...
                'Cuts', [0.2 0.35 0.6], 'Fractions', [0.05 0.25 0.9], ...
                'ResultsRoot', '');

            testCase.verifyTrue(all(result.caughtOfRequired(:) == 0), ...
                ['No candidate can fall outside the attention, so there ' ...
                'is nothing to disagree about and the gate does not fire.']);
            testCase.verifyTrue(all(result.escalationLoad(:) == 0));
        end

        function sweepMatchesTheDeployedVerdictCaseByCase(testCase)
            % The general guard: whatever the sweep says at a pair must be
            % what grade.spatialVerdict says at that pair.
            entries = { ...
                TestSpatialConstantSweep.scoredAt([0.9 0.8 0.1]), ...
                TestSpatialConstantSweep.scoredAt([0.05 0.05]), ...
                TestSpatialConstantSweep.offTheMap(), ...
                TestSpatialConstantSweep.noCandidates(), ...
                struct('values', zeros(0, 1), 'known', false, ...
                    'candidatesScored', 0)};
            directory = TestSpatialConstantSweep.writeRun(testCase, ...
                entries, [0 0 0 0 0], [0.9 0.9 0.9 0.9 0.9], ...
                'calibration', 0.40);

            cuts = [0.1 0.35 0.85];
            fractions = [0.05 0.25 0.75];
            result = spatialConstantSweep(directory, ...
                'Cuts', cuts, 'Fractions', fractions, 'ResultsRoot', '');

            for cutIndex = 1:numel(cuts)
                for fractionIndex = 1:numel(fractions)
                    configuration = struct( ...
                        'spatialAttentionCut', cuts(cutIndex), ...
                        'spatialAgreementFraction', fractions(fractionIndex));
                    expected = 0;
                    for entryIndex = 1:numel(entries)
                        agree = grade.spatialVerdict( ...
                            entries{entryIndex}, configuration);
                        expected = expected + double(~agree);
                    end
                    testCase.verifyEqual( ...
                        result.escalationLoad(cutIndex, fractionIndex), ...
                        expected / numel(entries), 'AbsTol', 1e-12, ...
                        sprintf(['Sweep and deployed verdict disagree at ' ...
                        'cut %.2f fraction %.2f.'], cuts(cutIndex), ...
                        fractions(fractionIndex)));
                end
            end
        end

        function theSweptSplitIsRecorded(testCase)
            % A pair selected on the split that reports it is the error
            % §10.4 exists to prevent, so which split was swept is part of
            % the answer rather than something a reader has to reconstruct.
            entries = {TestSpatialConstantSweep.scoredAt([0.9 0.1])};
            directory = TestSpatialConstantSweep.writeRun(testCase, ...
                entries, 1, 0.05, 'validation', 0.40);

            result = spatialConstantSweep(directory, ...
                'Cuts', 0.35, 'Fractions', 0.25, 'ResultsRoot', '');

            testCase.verifyEqual(result.split, "validation");
            testCase.verifyEqual(result.threshold, 0.40, 'AbsTol', 1e-12);
        end

        function theFrozenThresholdComesFromTheRun(testCase)
            % The patients the gate has to keep catching are the ones the
            % classifier sends home, which is defined against the frozen
            % threshold. Hardcoding it here is the §13.3 defect this whole
            % effort was chartered to repair.
            entries = { ...
                TestSpatialConstantSweep.scoredAt([0.9 0.9]), ...
                TestSpatialConstantSweep.scoredAt([0.9 0.9])};
            % Referable, and either side of a threshold of 0.30.
            directory = TestSpatialConstantSweep.writeRun(testCase, ...
                entries, [1 1], [0.20 0.45], 'calibration', 0.30);

            result = spatialConstantSweep(directory, ...
                'Cuts', 0.35, 'Fractions', 0.25, 'ResultsRoot', '');

            testCase.verifyEqual(numel(result.mustCatch), 1, ...
                ['Only the patient below the run''s own frozen threshold ' ...
                'is sent home by the classifier.']);
            testCase.verifyEqual(result.mustCatch(1), "img01");
        end

        function aRunWithoutASummaryIsRefused(testCase)
            entries = {TestSpatialConstantSweep.scoredAt([0.9 0.1])};
            directory = TestSpatialConstantSweep.writeRun(testCase, ...
                entries, 1, 0.05, 'calibration', 0.40);
            delete(fullfile(directory, 'ablation_summary.json'));

            testCase.verifyError( ...
                @() spatialConstantSweep(directory, 'ResultsRoot', ''), ...
                'eval:MissingAblationSummary');
        end
    end
end
