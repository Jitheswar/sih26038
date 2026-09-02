classdef TestUnsealProtocol < matlab.unittest.TestCase
    %TESTUNSEALPROTOCOL The §10.4 guards, and the rehearsal that exercises them.
    %   The sealed set is opened once and eval/externalValidation.m refuses
    %   a second run, so every guard here protects something that cannot be
    %   recovered if it fails.

    methods (Test)
        function nothingRunsWithoutConfirmation(testCase)
            testCase.verifyError(@() externalValidation(), ...
                'eval:SealNotConfirmed');
        end

        function aRehearsalCannotAlsoOpenTheSeal(testCase)
            % The two options must be mutually exclusive. A rehearsal that
            % could open the seal by passing one extra argument is not a
            % rehearsal.
            testCase.verifyError(@() externalValidation( ...
                'Rehearse', 'validation', 'ConfirmUnseal', true, ...
                'Operator', 'tester'), ...
                'eval:RehearsalConfirmsUnseal');
        end

        function aRehearsalRefusesTheTestAndSealedSplits(testCase)
            testCase.verifyError(@() externalValidation('Rehearse', 'test'), ...
                'eval:SealedData');
            testCase.verifyError(@() externalValidation('Rehearse', 'sealed'), ...
                'eval:SealedData');
        end

        function anUnsealNamesItsOperator(testCase)
            % §10.4 names one key holder, and the record is worthless
            % without it.
            testCase.verifyError(@() externalValidation('ConfirmUnseal', true), ...
                'eval:MissingOperator');
        end

        function theSealIsStillIntact(testCase)
            % Not a test of the code so much as of this repository: if a
            % run ever opened the seal, every later external number means
            % something different and the suite should say so out loud.
            root = fileparts(fileparts(mfilename('fullpath')));
            recordPath = fullfile(root, 'data', 'sealed', 'UNSEAL_RECORD.json');
            testCase.verifyFalse(isfile(recordPath), ...
                sprintf(['An unseal record exists at %s. The sealed set ' ...
                'has been opened; §10.4 allows that once, and any later ' ...
                'external figure is not a first-run result.'], recordPath));
        end
    end
end
