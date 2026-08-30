classdef TestScreeningApp < matlab.unittest.TestCase
    %TESTSCREENINGAPP Cover the demo UI's render path.
    %
    %   TestLauncher notes that the launcher is the one part of the demo no
    %   MATLAB test executes.  That was true of the render path too, and it
    %   is how a panel caption that named the wrong evidence channel could
    %   survive a green suite and first appear in front of a judge: the
    %   caption read "Classical detector" as a build-time constant, which
    %   stopped being true when the learned channel was adopted on 31 August
    %   2026.
    %
    %   ScreeningApp.showCase is the public seam these tests use.  The app
    %   builds under matlab -batch: a uifigure is created without being
    %   shown, and only blocking dialogs are refused, which is why the file
    %   chooser stays out of this path.

    properties (Access = private)
        App
    end

    methods (TestClassSetup)
        function addSourcePath(~)
            projectRoot = TestScreeningApp.projectRoot();
            addpath(genpath(fullfile(projectRoot, 'src')));
            addpath(fullfile(projectRoot, 'app'));
        end
    end

    methods (TestMethodTeardown)
        function closeApp(testCase)
            if ~isempty(testCase.App) && isvalid(testCase.App)
                delete(testCase.App);
            end
            testCase.App = [];
        end
    end

    methods (Test)
        function testAppBuildsWithoutACase(testCase)
            testCase.App = ScreeningApp();
            testCase.verifyTrue(isvalid(testCase.App.UIFigure));
            testCase.verifyNotEmpty(testCase.App.CandidateCaption, ...
                ['The lesion panel caption must exist before a case runs, ' ...
                'because the render path assigns to it.']);
        end

        function testEvidenceCaptionNamesTheDeployedChannel(testCase)
            imagePath = TestScreeningApp.sampleImage(testCase);
            testCase.App = ScreeningApp();
            testCase.App.showCase(imagePath);

            expected = char(TestScreeningApp.expectedEvidenceSource());
            testCase.verifyEqual(testCase.App.CandidateCaption.Text, ...
                expected, ...
                ['The lesion panel caption must name whichever channel ' ...
                'grade.icdrRule actually used, not a channel named in the ' ...
                'layout code. A constant here goes stale silently the next ' ...
                'time pipeline.learned_lesion_evidence changes.']);
        end

        function testEvidenceWarningNamesTheSameChannel(testCase)
            imagePath = TestScreeningApp.sampleImage(testCase);
            testCase.App = ScreeningApp();
            testCase.App.showCase(imagePath);

            warningText = testCase.App.EvidenceWarningValue.Text;
            testCase.verifySubstring(warningText, ...
                char(TestScreeningApp.expectedEvidenceSource()), ...
                'The caption and the warning must not name different channels.');
            testCase.verifySubstring(warningText, 'provisional', ...
                ['The provisional-evidence disclaimer must survive any ' ...
                'rewording of this line: it is the claim the report makes ' ...
                'on every case (§8.4).']);
        end

        function testRenderProducesADecision(testCase)
            imagePath = TestScreeningApp.sampleImage(testCase);
            testCase.App = ScreeningApp();
            testCase.App.showCase(imagePath);

            verdict = upper(strtrim(testCase.App.DecisionValue.Text));
            testCase.verifyTrue(ismember(verdict, ...
                {'AUTO-CLEAR', 'REFER', 'ESCALATE'}), sprintf( ...
                'The verdict strip showed "%s", which is not one of the ordered dispositions.', ...
                verdict));
        end
    end

    methods (Static, Access = private)
        function root = projectRoot()
            root = fileparts(fileparts(mfilename('fullpath')));
        end

        function source = expectedEvidenceSource()
            %EXPECTEDEVIDENCESOURCE What the config says should be running.
            %   Derived from configuration rather than hardcoded, so this
            %   test keeps asserting the property (the UI agrees with the
            %   rule engine) rather than a particular channel.
            config = jsondecode(fileread(fullfile( ...
                TestScreeningApp.projectRoot(), 'config', 'default.json')));
            if isfield(config.pipeline, 'learned_lesion_evidence') && ...
                    config.pipeline.learned_lesion_evidence
                heads = config.lesion_segmentation.evidence_heads;
                if ischar(heads)
                    heads = {heads};
                end
                source = sprintf('learned lesion segmentation (%s)', ...
                    strjoin(cellstr(heads), ', '));
            else
                source = 'classical candidate evidence';
            end
        end

        function imagePath = sampleImage(testCase)
            %SAMPLEIMAGE The first frame of the committed validation split.
            %   Never the test split and never the sealed set (§10.4).
            projectRoot = TestScreeningApp.projectRoot();
            splitFile = fullfile(projectRoot, 'data', 'splits', ...
                'validation.csv');
            testCase.assumeTrue(isfile(splitFile), ...
                'The validation split is required for a UI render test.');
            splitTable = readtable(splitFile, 'TextType', 'string');
            imagePath = fullfile(projectRoot, ...
                char(splitTable.relative_path(1)));
            testCase.assumeTrue(isfile(imagePath), ...
                'The validation image named by the split is not present.');
        end
    end
end
