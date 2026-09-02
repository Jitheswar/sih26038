classdef TestPreparedSplit < matlab.unittest.TestCase
    %TESTPREPAREDSPLIT The guard on splits a caller assembles rather than names.
    %   eval/ablationHarness.m normally reads a committed split by name, and
    %   that path refuses the test split and refuses anything under
    %   data/sealed.  eval/externalValidation.m needs to evaluate images
    %   that are not a committed split, so the harness also accepts a
    %   prepared struct.
    %
    %   That opening must not become the way round the guards it bypasses.
    %   These pin the conditions, because a guard protecting a one-shot
    %   irreversible resource that nothing tests is a guard that stops
    %   working quietly.

    methods (Static)
        function split = valid()
            root = fileparts(fileparts(mfilename('fullpath')));
            split = struct( ...
                'n', 2, ...
                'imageIds', ["a"; "b"], ...
                'grades', [0; 2], ...
                'files', [string(fullfile(root, 'data', 'raw', 'a.png')); ...
                          string(fullfile(root, 'data', 'raw', 'b.png'))], ...
                'name', "prepared", ...
                'provenance', "unit test");
        end

        function split = sealed()
            split = TestPreparedSplit.valid();
            split.files = ["/x/data/sealed/IMAGES/a.png"; ...
                           "/x/data/sealed/IMAGES/b.png"];
        end
    end

    methods (Test)
        function sealedPathsAreRefusedWithoutAuthorisation(testCase)
            % The important one. A prepared split must not be a way to read
            % data/sealed just by assembling it yourself.
            testCase.verifyError(@() ablationHarness( ...
                'Split', TestPreparedSplit.sealed(), ...
                'Configs', {'ablation_A10.json'}), ...
                'eval:SealedData');
        end

        function authorisationMustBeALogicalTrue(testCase)
            % A truthy value is not authorisation. Anything that is not
            % logical true must fail closed.
            for value = {1, "true", 'yes', [], false}
                split = TestPreparedSplit.sealed();
                split.sealedAccessAuthorised = value{1};
                testCase.verifyError(@() ablationHarness('Split', split, ...
                    'Configs', {'ablation_A10.json'}), 'eval:SealedData', ...
                    sprintf('accepted %s as authorisation', class(value{1})));
            end
        end

        function anIncompletePreparedSplitIsRefused(testCase)
            % Every field the harness indexes must be present, or it would
            % fail deep inside a feature pass rather than at the door.
            for field = ["n", "imageIds", "grades", "files", "name", "provenance"]
                split = rmfield(TestPreparedSplit.valid(), field);
                testCase.verifyError(@() ablationHarness('Split', split, ...
                    'Configs', {'ablation_A10.json'}), ...
                    'eval:InvalidPreparedSplit', ...
                    sprintf('accepted a split with no %s', field));
            end
        end

        function mismatchedLengthsAreRefused(testCase)
            % n disagreeing with the vectors would silently truncate or
            % index past the end of a split during an irreversible run.
            split = TestPreparedSplit.valid();
            split.n = 3;
            testCase.verifyError(@() ablationHarness('Split', split, ...
                'Configs', {'ablation_A10.json'}), 'eval:InvalidPreparedSplit');
        end

        function theNamedTestSplitIsStillRefused(testCase)
            % The prepared path must not have weakened the name-based
            % guards that were there before it.
            testCase.verifyError(@() ablationHarness('Split', 'test'), ...
                'eval:TestSplitRefused');
            testCase.verifyError(@() ablationHarness('Split', 'sealed'), ...
                'eval:SealedData');
        end
    end
end
