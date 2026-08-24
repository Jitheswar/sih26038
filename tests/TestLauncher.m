classdef TestLauncher < matlab.unittest.TestCase
    %TESTLAUNCHER Guards on start.sh that a MATLAB-only suite cannot see.
    %   The launcher is the one part of the demo no MATLAB test executes, and
    %   it is where two demo-breaking defects have already landed:
    %
    %   - The GUI was launched with -batch, which sets batchStartupOptionUsed
    %     and puts MATLAB in a configuration that refuses every blocking
    %     dialog.  The window opened and looked correct, then "Select fundus
    %     image" failed the moment the operator clicked it.
    %   - MATLAB handles SIGINT itself and survives Ctrl+C, so without a trap
    %     the app window and the process stayed alive and the terminal never
    %     came back.
    %
    %   Both are properties of the shell script, so they are asserted here
    %   against its text.

    methods (Test)
        function guiLaunchesInteractively(testCase)
            line = TestLauncher.guiLaunchLine(testCase);
            testCase.verifyEmpty(strfind(line, '-batch'), ...
                ['The GUI must not launch with -batch. It sets ', ...
                'batchStartupOptionUsed, MATLAB then refuses every blocking ', ...
                'dialog, and uigetfile fails when the operator clicks ', ...
                'Select fundus image.']);
            testCase.verifyNotEmpty(strfind(line, '-nodesktop'), ...
                'The GUI must launch in MATLAB''s interactive configuration.');
        end

        function interruptsAreTrapped(testCase)
            script = TestLauncher.launcherText(testCase);
            testCase.verifyNotEmpty( ...
                regexp(script, '^\s*trap\s+on_interrupt\s+INT', 'once', 'lineanchors'), ...
                ['start.sh must trap INT. MATLAB installs its own SIGINT ', ...
                'handler and survives Ctrl+C, so without the trap the demo ', ...
                'cannot be stopped from the terminal.']);
        end

        function everyMatlabInvocationGoesThroughRunMatlab(testCase)
            script = TestLauncher.launcherText(testCase);
            lines = regexp(script, '\n', 'split');
            invoking = lines(~cellfun(@isempty, ...
                regexp(lines, '^\s*"\$MATLAB_BIN"', 'once')));
            testCase.verifyNotEmpty(invoking, ...
                'Expected start.sh to invoke MATLAB at least once.');
            for index = 1:numel(invoking)
                testCase.verifyNotEmpty(strfind(invoking{index}, '"$@"'), ...
                    ['Every MATLAB call must go through run_matlab, which ', ...
                    'records the pid the interrupt trap needs. A direct ', ...
                    'invocation cannot be stopped with Ctrl+C: ', ...
                    strtrim(invoking{index})]);
            end
        end
    end

    methods (Static, Access = private)
        function text = launcherText(testCase)
            path = fullfile(TestLauncher.projectRoot(), 'start.sh');
            testCase.assertTrue(isfile(path), ...
                sprintf('Launcher not found at %s', path));
            text = fileread(path);
        end

        function line = guiLaunchLine(testCase)
            script = TestLauncher.launcherText(testCase);
            lines = regexp(script, '\n', 'split');
            matches = lines(~cellfun(@isempty, ...
                regexp(lines, 'ScreeningApp', 'once')));
            matches = matches(~cellfun(@isempty, ...
                regexp(matches, 'run_matlab|\$MATLAB_BIN', 'once')));
            testCase.assertNotEmpty(matches, ...
                'No GUI launch line found in start.sh.');
            line = matches{1};
        end

        function root = projectRoot()
            root = fileparts(fileparts(mfilename('fullpath')));
        end
    end
end
