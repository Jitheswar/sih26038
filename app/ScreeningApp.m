classdef ScreeningApp < handle
    %SCREENINGAPP App Designer-compatible integrated screening demo.
    %   app = ScreeningApp creates the local MATLAB screening UI.  All
    %   inference logic stays in app.runScreeningCase and report.generate;
    %   this class owns presentation only.
    %
    %   Layout note: the window is sized 1600x980 but a tiling window
    %   manager will resize it to whatever the tile allows, so every row and
    %   column below is either a fixed control height or a '1x' share.  No
    %   part of the layout assumes the requested width.

    properties (Access = public)
        UIFigure
        SelectImageButton
        ImagePathField
        ModelPathField
        CalibrationPathField
        ConfigPathField
        RunButton
        ExportButton
        OriginalAxes
        ProcessedAxes
        GradCAMAxes
        CandidateAxes
        QualityValue
        AdviceValue
        LevelValue
        ProbabilityValue
        DecisionValue
        AgreementValue
        EscalationValue
        EvidenceWarningValue
        EvidenceValue
        RuleTraceArea
        StatusValue
        ProcessingTimeValue
        % Demo-day escape hatch.  Set false to skip every reveal animation
        % and have results appear in their final state immediately.
        AnimationsEnabled = true
    end

    properties (Access = private)
        ProjectRoot
        ScreeningResult
        LastReport
        Theme
        CaseNameValue
        DecisionCard
        DecisionCaption
        LevelNameValue
        ProbabilityCaption
        QualityCaption
        StatusDot
        ImageObjects
        PendingReveal
        StageMarks
        StageNames
    end

    methods
        function app = ScreeningApp(varargin)
            app.ProjectRoot = fileparts(fileparts(mfilename('fullpath')));
            addpath(genpath(fullfile(app.ProjectRoot, 'src')));
            app.Theme = ScreeningApp.palette();
            app.createComponents();
            app.applyDefaults(varargin{:});
        end

        function delete(app)
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                delete(app.UIFigure);
            end
        end
    end

    methods (Static, Access = private)
        function t = palette()
            %PALETTE Single source of truth for every colour in the UI.
            %   Dark ground on purpose: fundus images are dark, low-contrast
            %   and warm, and they read far better against a neutral dark
            %   surface than against white, which blows out the perceived
            %   brightness of the retina and flattens the Grad-CAM ramp.
            t.bg        = [0.055, 0.066, 0.078];
            t.surface   = [0.086, 0.102, 0.121];
            t.raised    = [0.125, 0.145, 0.169];
            t.field     = [0.145, 0.165, 0.192];
            t.text      = [0.898, 0.914, 0.933];
            t.muted     = [0.514, 0.557, 0.608];
            t.faint     = [0.365, 0.404, 0.451];
            t.accent    = [0.298, 0.639, 0.980];
            t.accentInk = [0.043, 0.075, 0.118];
            t.green     = [0.243, 0.812, 0.545];
            t.amber     = [0.960, 0.647, 0.145];
            t.red       = [0.945, 0.361, 0.376];
            t.amberTint = [0.180, 0.145, 0.075];
        end
    end

    methods (Access = private)
        function createComponents(app)
            t = app.Theme;

            app.UIFigure = uifigure('Name', ...
                'Retinal Screening Aid  |  SIH26038', ...
                'Position', [40, 40, 1600, 980], 'Color', t.bg);

            root = uigridlayout(app.UIFigure, [2, 1]);
            root.RowHeight = {66, '1x'};
            root.ColumnWidth = {'1x'};
            root.Padding = [0, 0, 0, 0];
            root.RowSpacing = 0;
            root.BackgroundColor = t.bg;

            app.buildHeader(root);

            body = uigridlayout(root, [1, 2]);
            body.Layout.Row = 2;
            body.ColumnWidth = {330, '1x'};
            body.RowHeight = {'1x'};
            body.Padding = [14, 14, 14, 14];
            body.ColumnSpacing = 14;
            body.BackgroundColor = t.bg;

            app.buildRail(body);
            app.buildWorkspace(body);
            app.applyTypography();

            % Enter runs the case.  During a live demo the operator's hands
            % are on the image, not hunting for the button.
            app.UIFigure.KeyPressFcn = @(~, event) app.handleKey(event);
            % Explicit rather than relying on the default closereq, so the
            % window manager's close request has an unambiguous handler and
            % uiwait in the launcher is released.
            app.UIFigure.CloseRequestFcn = @(~, ~) delete(app.UIFigure);
            try
                app.UIFigure.WindowState = 'maximized';
            catch
                % Window managers that refuse the hint just keep the size above.
            end
        end

        function applyTypography(app)
            %APPLYTYPOGRAPHY Put one humanist sans across the whole window.
            %   MATLAB's default UI face differs by platform and renders the
            %   verdict numerals unevenly at display sizes.  Monospace fields
            %   are skipped: the evidence and rule-trace panels rely on column
            %   alignment, which a proportional face destroys.
            preferred = {'Noto Sans', 'Inter', 'Roboto', 'DejaVu Sans', ...
                'Open Sans'};
            installed = listfonts();
            chosen = '';
            for index = 1:numel(preferred)
                if any(strcmpi(installed, preferred{index}))
                    chosen = preferred{index};
                    break;
                end
            end
            if isempty(chosen)
                return;
            end
            components = findall(app.UIFigure);
            for index = 1:numel(components)
                component = components(index);
                if ~isprop(component, 'FontName')
                    continue;
                end
                if strcmpi(get(component, 'FontName'), 'monospace')
                    continue;
                end
                try
                    component.FontName = chosen;
                catch
                    % Components that reject the face keep their default.
                end
            end
        end

        function handleKey(app, event)
            if strcmp(event.Key, 'return') && strcmp(app.RunButton.Enable, 'on')
                app.runScreening();
            end
        end

        % ----------------------------------------------------------- header
        function buildHeader(app, parent)
            t = app.Theme;
            header = uigridlayout(parent, [1, 2]);
            header.Layout.Row = 1;
            header.ColumnWidth = {'1x', 'fit'};
            header.RowHeight = {'1x'};
            header.Padding = [20, 10, 20, 10];
            header.ColumnSpacing = 10;
            header.BackgroundColor = t.surface;

            titleBlock = uigridlayout(header, [2, 1]);
            titleBlock.Layout.Column = 1;
            titleBlock.RowHeight = {24, 16};
            titleBlock.Padding = [0, 0, 0, 0];
            titleBlock.RowSpacing = 2;
            titleBlock.BackgroundColor = t.surface;

            productLabel = uilabel(titleBlock, 'Text', 'Retinal Screening Aid', ...
                'FontSize', 19, 'FontWeight', 'bold', 'FontColor', t.text);
            productLabel.Layout.Row = 1;
            taglineLabel = uilabel(titleBlock, 'Text', ...
                'SIH26038  ·  Explainable diabetic retinopathy triage', ...
                'FontSize', 11.5, 'FontColor', t.muted);
            taglineLabel.Layout.Row = 2;

            % Badges carry the two facts a judge asks about first: which
            % operating point produced the published numbers, and whether the
            % sealed external set was touched.  Putting them in the chrome
            % means they are on screen for the whole demo without being said.
            badges = uigridlayout(header, [1, 2]);
            badges.Layout.Column = 2;
            badges.ColumnWidth = {'fit', 'fit'};
            badges.RowHeight = {26};
            badges.Padding = [0, 0, 0, 0];
            badges.ColumnSpacing = 8;
            badges.BackgroundColor = t.surface;

            [threshold, frozenOn] = app.frozenBadgeFacts();
            operatingBadge = uilabel(badges, 'Text', ...
                sprintf('  Operating point %s  ·  frozen %s  ', threshold, frozenOn), ...
                'FontSize', 11, 'FontWeight', 'bold', ...
                'FontColor', t.accent, 'BackgroundColor', t.raised, ...
                'HorizontalAlignment', 'center');
            operatingBadge.Layout.Column = 1;

            sealedBadge = uilabel(badges, 'Text', ...
                '  Sealed external set: not opened  ', ...
                'FontSize', 11, 'FontWeight', 'bold', ...
                'FontColor', t.green, 'BackgroundColor', t.raised, ...
                'HorizontalAlignment', 'center');
            sealedBadge.Layout.Column = 2;
        end

        function [threshold, frozenOn] = frozenBadgeFacts(app)
            %FROZENBADGEFACTS Threshold and freeze date for the header badge.
            %   Falls back to placeholders rather than inventing a number: a
            %   badge that states an operating point the config does not
            %   contain is worse than a badge that admits it is unset.
            threshold = 'unset';
            frozenOn = 'unset';
            configPath = fullfile(app.ProjectRoot, 'config', 'default.json');
            if ~isfile(configPath)
                return;
            end
            try
                config = jsondecode(fileread(configPath));
            catch
                return;
            end
            if ~isfield(config, 'operating_point')
                return;
            end
            operatingPoint = config.operating_point;
            if isfield(operatingPoint, 'referable_threshold')
                threshold = sprintf('%.2f', operatingPoint.referable_threshold);
            end
            if isfield(operatingPoint, 'frozen_on')
                frozenOn = char(string(operatingPoint.frozen_on));
            end
        end

        % ------------------------------------------------------------- rail
        function buildRail(app, parent)
            t = app.Theme;
            rail = uigridlayout(parent, [9, 1]);
            rail.Layout.Column = 1;
            rail.RowHeight = {104, 48, 36, 96, 176, 122, 180, '1x', 34};
            rail.ColumnWidth = {'1x'};
            rail.Padding = [0, 0, 0, 0];
            rail.RowSpacing = 12;
            rail.BackgroundColor = t.bg;
            % Fixed-height cards can exceed a short window.  Scrolling keeps
            % the footer disclaimer reachable instead of silently clipped.
            rail.Scrollable = 'on';

            % --- case card
            [caseCard, caseGrid] = app.card(rail, 1, {16, 30, 18});
            app.caption(caseGrid, 1, 'CASE');
            app.SelectImageButton = uibutton(caseGrid, 'push', ...
                'Text', 'Select fundus image', ...
                'FontSize', 12.5, 'FontColor', t.text, ...
                'BackgroundColor', t.field, ...
                'ButtonPushedFcn', @(~, ~) app.selectImage());
            app.SelectImageButton.Layout.Row = 2;
            app.CaseNameValue = uilabel(caseGrid, 'Text', 'No image selected', ...
                'FontSize', 11.5, 'FontColor', t.faint);
            app.CaseNameValue.Layout.Row = 3;
            caseCard.Tooltip = 'Pick any fundus image to screen.';

            % --- primary action
            app.RunButton = uibutton(rail, 'push', 'Text', 'Run screening', ...
                'FontSize', 15, 'FontWeight', 'bold', ...
                'FontColor', t.accentInk, 'BackgroundColor', t.accent, ...
                'ButtonPushedFcn', @(~, ~) app.runScreening());
            app.RunButton.Layout.Row = 2;

            app.ExportButton = uibutton(rail, 'push', ...
                'Text', 'Export report', 'Enable', 'off', ...
                'FontSize', 12, 'FontColor', t.muted, ...
                'BackgroundColor', t.surface, ...
                'ButtonPushedFcn', @(~, ~) app.exportReport());
            app.ExportButton.Layout.Row = 3;

            % --- status card
            [~, statusGrid] = app.card(rail, 4, {16, 20, 16});
            app.caption(statusGrid, 1, 'STATUS');
            statusRow = uigridlayout(statusGrid, [1, 2]);
            statusRow.Layout.Row = 2;
            statusRow.ColumnWidth = {10, '1x'};
            statusRow.RowHeight = {'1x'};
            statusRow.Padding = [0, 0, 0, 0];
            statusRow.ColumnSpacing = 7;
            statusRow.BackgroundColor = t.surface;
            app.StatusDot = uilabel(statusRow, 'Text', '●', ...
                'FontSize', 12, 'FontColor', t.muted);
            app.StatusDot.Layout.Column = 1;
            app.StatusValue = uilabel(statusRow, 'Text', 'Ready', ...
                'FontSize', 12.5, 'FontWeight', 'bold', 'FontColor', t.text);
            app.StatusValue.Layout.Column = 2;
            app.ProcessingTimeValue = uilabel(statusGrid, ...
                'Text', 'Processing time  --', ...
                'FontSize', 11, 'FontColor', t.faint);
            app.ProcessingTimeValue.Layout.Row = 3;

            % --- frozen model card
            [~, modelGrid] = app.card(rail, 5, ...
                {16, 13, 22, 13, 22, 13, 22});
            app.caption(modelGrid, 1, 'FROZEN MODEL');
            app.ModelPathField = app.pathField(modelGrid, 2, 3, ...
                'Checkpoint', 'Model checkpoint path');
            app.CalibrationPathField = app.pathField(modelGrid, 4, 5, ...
                'Temperature calibration', 'Temperature calibration path');
            app.ConfigPathField = app.pathField(modelGrid, 6, 7, ...
                'Configuration', 'Project configuration path');

            % The image path stays an editable field so a scripted demo can
            % set it, but it is not rail furniture: the operator reads the
            % file name from the case card above.
            app.ImagePathField = uieditfield(caseGrid, 'text', ...
                'Placeholder', 'Selected image path', 'Visible', 'off');
            app.ImagePathField.Layout.Row = 3;

            app.buildPerformanceCard(rail, 6);
            app.buildPipelineCard(rail, 7);

            % --- footer
            footer = uilabel(rail, 'Text', ...
                ['Screening aid and research prototype.', newline, ...
                'Not a medical device and not a clinical diagnosis.'], ...
                'FontSize', 10.5, 'FontColor', t.faint, 'WordWrap', 'on');
            footer.Layout.Row = 9;
        end

        function buildPerformanceCard(app, parent, row)
            %BUILDPERFORMANCECARD Headline validation numbers, always on screen.
            %   These are read from config/default.json rather than typed in,
            %   so the card cannot drift away from the frozen operating point
            %   it claims to describe.  Bare accuracy is deliberately absent.
            t = app.Theme;
            [~, grid] = app.card(parent, row, {16, 20, 20, 18});
            app.caption(grid, 1, 'VALIDATION PERFORMANCE');

            [sensitivity, specificity] = app.frozenValidationMetrics();
            sensitivityLabel = app.metricLine(grid, 2, 'Sensitivity', ...
                sensitivity, t.green);
            specificityLabel = app.metricLine(grid, 3, 'Specificity', ...
                specificity, t.accent);
            sensitivityLabel.Tooltip = 'Referable DR, ICDR >= 2.';
            specificityLabel.Tooltip = 'Referable DR, ICDR >= 2.';

            note = uilabel(grid, 'Text', ...
                'Referable DR  ·  internal validation  ·  n = 550', ...
                'FontSize', 10, 'FontColor', t.faint);
            note.Layout.Row = 4;
        end

        function buildPipelineCard(app, parent, row)
            %BUILDPIPELINECARD Which pipeline stages actually ran on this case.
            %   The marks are set from the result structure after inference,
            %   never from a script that assumes the happy path: a case the
            %   quality gate stops really does leave the later stages unlit,
            %   and the operator should be able to see that.
            t = app.Theme;
            app.StageNames = {'Quality gate', 'Preprocessing', ...
                'CNN grading', 'Grad-CAM', 'Lesion evidence', 'ICDR rules'};
            heights = [{16}, repmat({20}, 1, numel(app.StageNames))];
            [~, grid] = app.card(parent, row, heights);
            % Six stage rows plus the default card spacing overflowed the card
            % and clipped the last stage, which is exactly the one a stopped
            % case needs to show as unlit.
            grid.RowSpacing = 3;
            app.caption(grid, 1, 'PIPELINE');
            app.StageMarks = gobjects(1, numel(app.StageNames));
            for index = 1:numel(app.StageNames)
                line = uigridlayout(grid, [1, 2]);
                line.Layout.Row = index + 1;
                line.ColumnWidth = {14, '1x'};
                line.RowHeight = {'1x'};
                line.Padding = [0, 0, 0, 0];
                line.ColumnSpacing = 8;
                line.BackgroundColor = t.surface;
                mark = uilabel(line, 'Text', ' ', 'FontSize', 11, ...
                    'FontColor', t.faint);
                mark.Layout.Column = 1;
                name = uilabel(line, 'Text', app.StageNames{index}, ...
                    'FontSize', 11.5, 'FontColor', t.muted);
                name.Layout.Column = 2;
                app.StageMarks(index) = mark;
            end
        end

        function setStageMarks(app, states)
            t = app.Theme;
            for index = 1:numel(app.StageMarks)
                if index <= numel(states) && states(index)
                    app.StageMarks(index).Text = '●';
                    app.StageMarks(index).FontColor = t.green;
                else
                    app.StageMarks(index).Text = '○';
                    app.StageMarks(index).FontColor = t.faint;
                end
            end
        end

        function label = metricLine(app, parent, row, name, value, colour)
            %METRICLINE One "name ....... value" row inside a metric card.
            t = app.Theme;
            line = uigridlayout(parent, [1, 2]);
            line.Layout.Row = row;
            line.ColumnWidth = {'1x', 'fit'};
            line.RowHeight = {'1x'};
            line.Padding = [0, 0, 0, 0];
            line.ColumnSpacing = 8;
            line.BackgroundColor = t.surface;
            label = uilabel(line, 'Text', name, ...
                'FontSize', 12, 'FontColor', t.muted);
            label.Layout.Column = 1;
            valueLabel = uilabel(line, 'Text', value, ...
                'FontSize', 14, 'FontWeight', 'bold', 'FontColor', colour, ...
                'HorizontalAlignment', 'right');
            valueLabel.Layout.Column = 2;
        end

        function [sensitivity, specificity] = frozenValidationMetrics(app)
            %FROZENVALIDATIONMETRICS Validation sens/spec recorded by the freeze.
            sensitivity = 'not recorded';
            specificity = 'not recorded';
            configPath = fullfile(app.ProjectRoot, 'config', 'default.json');
            if ~isfile(configPath)
                return;
            end
            try
                config = jsondecode(fileread(configPath));
            catch
                return;
            end
            if ~isfield(config, 'operating_point')
                return;
            end
            operatingPoint = config.operating_point;
            if isfield(operatingPoint, 'validation_sensitivity')
                sensitivity = sprintf('%.1f%%', ...
                    operatingPoint.validation_sensitivity * 100);
            end
            if isfield(operatingPoint, 'validation_specificity')
                specificity = sprintf('%.1f%%', ...
                    operatingPoint.validation_specificity * 100);
            end
        end

        function field = pathField(app, parent, captionRow, fieldRow, ...
                captionText, placeholder)
            %PATHFIELD Small labelled path entry used by the frozen-model card.
            t = app.Theme;
            label = uilabel(parent, 'Text', captionText, ...
                'FontSize', 10, 'FontColor', t.faint);
            label.Layout.Row = captionRow;
            field = uieditfield(parent, 'text', 'Placeholder', placeholder, ...
                'FontSize', 10.5, 'FontName', 'monospace', ...
                'FontColor', t.muted, 'BackgroundColor', t.field);
            field.Layout.Row = fieldRow;
        end

        % -------------------------------------------------------- workspace
        function buildWorkspace(app, parent)
            t = app.Theme;
            main = uigridlayout(parent, [4, 1]);
            main.Layout.Column = 2;
            main.RowHeight = {118, 26, '1x', 224};
            main.ColumnWidth = {'1x'};
            main.Padding = [0, 0, 0, 0];
            main.RowSpacing = 12;
            main.BackgroundColor = t.bg;

            app.buildVerdictStrip(main);

            % Amber only once a case has been graded.  A standing warning on
            % an idle app reads as a fault to act on, and trains the operator
            % to ignore the one case where it carries information.
            app.EvidenceWarningValue = uilabel(main, 'Text', '', ...
                'FontSize', 11, 'FontColor', t.amber, 'WordWrap', 'on', ...
                'VerticalAlignment', 'center');
            app.EvidenceWarningValue.Layout.Row = 2;

            app.buildImageGrid(main);
            app.buildEvidenceRow(main);
            app.buildNarrativeStore(main);
        end

        function buildVerdictStrip(app, parent)
            %BUILDVERDICTSTRIP The four numbers the operator actually decides on.
            %   The decision tile is deliberately the largest element on the
            %   screen.  In the previous layout the decision was one bold
            %   12-point line in a column of sixteen identical grey lines,
            %   which made the single most consequential output of the whole
            %   pipeline the hardest thing on screen to find.
            t = app.Theme;
            strip = uigridlayout(parent, [1, 4]);
            strip.Layout.Row = 1;
            strip.ColumnWidth = {'1.6x', '1x', '1x', '1x'};
            strip.RowHeight = {'1x'};
            strip.Padding = [0, 0, 0, 0];
            strip.ColumnSpacing = 12;
            strip.BackgroundColor = t.bg;

            [app.DecisionCard, decisionGrid] = app.tile(strip, 1);
            app.caption(decisionGrid, 1, 'DECISION');
            app.DecisionValue = uilabel(decisionGrid, 'Text', '--', ...
                'FontSize', 27, 'FontWeight', 'bold', 'FontColor', t.muted);
            app.DecisionValue.Layout.Row = 2;
            app.DecisionCaption = uilabel(decisionGrid, ...
                'Text', 'Awaiting a case', ...
                'FontSize', 10.5, 'FontColor', t.faint, 'WordWrap', 'on');
            app.DecisionCaption.Layout.Row = 3;

            [~, probabilityGrid] = app.tile(strip, 2);
            app.caption(probabilityGrid, 1, 'REFERABLE RISK');
            app.ProbabilityValue = uilabel(probabilityGrid, 'Text', '--', ...
                'FontSize', 26, 'FontWeight', 'bold', 'FontColor', t.muted);
            app.ProbabilityValue.Layout.Row = 2;
            app.ProbabilityCaption = uilabel(probabilityGrid, ...
                'Text', 'Calibrated', ...
                'FontSize', 10.5, 'FontColor', t.faint);
            app.ProbabilityCaption.Layout.Row = 3;

            [~, levelGrid] = app.tile(strip, 3);
            app.caption(levelGrid, 1, 'ICDR GRADE');
            app.LevelValue = uilabel(levelGrid, 'Text', '--', ...
                'FontSize', 27, 'FontWeight', 'bold', 'FontColor', t.muted);
            app.LevelValue.Layout.Row = 2;
            app.LevelNameValue = uilabel(levelGrid, 'Text', 'Not graded', ...
                'FontSize', 10.5, 'FontColor', t.faint, 'WordWrap', 'on');
            app.LevelNameValue.Layout.Row = 3;

            [~, qualityGrid] = app.tile(strip, 4);
            app.caption(qualityGrid, 1, 'IMAGE QUALITY');
            app.QualityValue = uilabel(qualityGrid, 'Text', '--', ...
                'FontSize', 16, 'FontWeight', 'bold', 'FontColor', t.muted);
            app.QualityValue.Layout.Row = 2;
            app.QualityCaption = uilabel(qualityGrid, 'Text', 'Not assessed', ...
                'FontSize', 10.5, 'FontColor', t.faint, 'WordWrap', 'on');
            app.QualityCaption.Layout.Row = 3;

        end

        function buildNarrativeStore(app, parent)
            %BUILDNARRATIVESTORE Off-screen home for the narrative properties.
            %   Agreement, escalation reason and recapture advice are shown to
            %   the operator inside the evidence panel and the verdict strip,
            %   but they stay addressable as labels so the public property
            %   surface of this class does not change.  They are parented to a
            %   hidden panel rather than to the main grid, because a grid
            %   places every child in a row and three extra children would
            %   silently grow the layout from four rows to seven.
            store = uipanel(parent, 'Visible', 'off', 'BorderType', 'none');
            store.Layout.Row = 2;
            storeGrid = uigridlayout(store, [3, 1]);
            app.AgreementValue = uilabel(storeGrid, 'Text', '');
            app.AgreementValue.Layout.Row = 1;
            app.EscalationValue = uilabel(storeGrid, 'Text', '');
            app.EscalationValue.Layout.Row = 2;
            app.AdviceValue = uilabel(storeGrid, 'Text', '');
            app.AdviceValue.Layout.Row = 3;
        end

        function buildImageGrid(app, parent)
            t = app.Theme;
            images = uigridlayout(parent, [2, 2]);
            images.Layout.Row = 3;
            images.RowHeight = {'1x', '1x'};
            images.ColumnWidth = {'1x', '1x'};
            images.Padding = [0, 0, 0, 0];
            images.RowSpacing = 12;
            images.ColumnSpacing = 12;
            images.BackgroundColor = t.bg;

            app.OriginalAxes = app.imageCard(images, 1, 1, ...
                'Original fundus', 'As captured');
            app.ProcessedAxes = app.imageCard(images, 1, 2, ...
                'Preprocessed', 'Shared with training');
            app.GradCAMAxes = app.imageCard(images, 2, 1, ...
                'Grad-CAM', 'Where the network looked');
            app.CandidateAxes = app.imageCard(images, 2, 2, ...
                'Lesion candidates', 'Classical detector');
        end

        function ax = imageCard(app, parent, row, column, titleText, subtitleText)
            %IMAGECARD One titled image panel whose axes fills the card.
            %   The axes background is the card colour so the letterboxing a
            %   non-matching aspect ratio produces reads as intentional
            %   matting rather than as a broken or half-drawn plot.
            t = app.Theme;
            card = uipanel(parent, 'BorderType', 'none', ...
                'BackgroundColor', t.surface);
            card.Layout.Row = row;
            card.Layout.Column = column;

            grid = uigridlayout(card, [2, 1]);
            grid.RowHeight = {30, '1x'};
            grid.ColumnWidth = {'1x'};
            grid.Padding = [12, 10, 12, 8];
            grid.RowSpacing = 2;
            grid.BackgroundColor = t.surface;

            heading = uigridlayout(grid, [1, 2]);
            heading.Layout.Row = 1;
            heading.ColumnWidth = {'fit', '1x'};
            heading.RowHeight = {'1x'};
            heading.Padding = [0, 0, 0, 0];
            heading.ColumnSpacing = 10;
            heading.BackgroundColor = t.surface;

            titleLabel = uilabel(heading, 'Text', titleText, ...
                'FontSize', 12.5, 'FontWeight', 'bold', 'FontColor', t.text);
            titleLabel.Layout.Column = 1;
            subtitleLabel = uilabel(heading, 'Text', subtitleText, ...
                'FontSize', 10.5, 'FontColor', t.faint);
            subtitleLabel.Layout.Column = 2;

            ax = uiaxes(grid);
            ax.Layout.Row = 2;
            app.blankAxes(ax);
        end

        function blankAxes(app, ax)
            t = app.Theme;
            ax.Color = t.surface;
            ax.XTick = [];
            ax.YTick = [];
            ax.Box = 'off';
            ax.XColor = 'none';
            ax.YColor = 'none';
            title(ax, '');
            % With no title, ticks or axis labels to draw, the default loose
            % inset is pure dead space: it was costing roughly a fifth of each
            % image panel and left the fundus floating in a large empty card.
            try
                ax.LooseInset = [0, 0, 0, 0];
            catch
                % Releases that manage the inset themselves need no cleanup.
            end
            % The floating "..." overflow menu on every axes reads as
            % leftover debris in a presentation.  Scroll-to-zoom still works
            % without it, which is what matters when a judge wants a closer
            % look at a microaneurysm.
            try
                ax.Toolbar.Visible = 'off';
            catch
                % Older releases without an axes toolbar need no cleanup.
            end
        end

        function buildEvidenceRow(app, parent)
            t = app.Theme;
            evidenceRow = uigridlayout(parent, [1, 2]);
            evidenceRow.Layout.Row = 4;
            evidenceRow.ColumnWidth = {'1.15x', '1.5x'};
            evidenceRow.RowHeight = {'1x'};
            evidenceRow.Padding = [0, 0, 0, 0];
            evidenceRow.ColumnSpacing = 12;
            evidenceRow.BackgroundColor = t.bg;

            [~, evidenceGrid] = app.card(evidenceRow, 1, {16, '1x'}, 1);
            app.caption(evidenceGrid, 1, 'EVIDENCE AND AGREEMENT');
            app.EvidenceValue = uitextarea(evidenceGrid, 'Editable', 'off', ...
                'Value', {'Awaiting a case.'}, 'WordWrap', 'on', ...
                'FontName', 'monospace', 'FontSize', 11, ...
                'FontColor', t.text, 'BackgroundColor', t.surface);
            app.EvidenceValue.Layout.Row = 2;

            [~, traceGrid] = app.card(evidenceRow, 1, {16, '1x'}, 2);
            app.caption(traceGrid, 1, 'ICDR RULE TRACE');
            app.RuleTraceArea = uitextarea(traceGrid, 'Editable', 'off', ...
                'Value', {'Awaiting a case.'}, 'WordWrap', 'on', ...
                'FontName', 'monospace', 'FontSize', 10.5, ...
                'FontColor', t.muted, 'BackgroundColor', t.surface);
            app.RuleTraceArea.Layout.Row = 2;
        end

        % ------------------------------------------------- layout primitives
        function [card, grid] = card(app, parent, row, rowHeights, column)
            %CARD A flat surface panel plus its inner grid.
            t = app.Theme;
            card = uipanel(parent, 'BorderType', 'none', ...
                'BackgroundColor', t.surface);
            card.Layout.Row = row;
            if nargin >= 5
                card.Layout.Column = column;
            end
            grid = uigridlayout(card, [numel(rowHeights), 1]);
            grid.RowHeight = rowHeights;
            grid.ColumnWidth = {'1x'};
            grid.Padding = [14, 12, 14, 12];
            grid.RowSpacing = 6;
            grid.BackgroundColor = t.surface;
        end

        function [card, grid] = tile(app, parent, column)
            %TILE A verdict-strip cell: caption, large value, small caption.
            t = app.Theme;
            card = uipanel(parent, 'BorderType', 'none', ...
                'BackgroundColor', t.surface);
            card.Layout.Column = column;
            grid = uigridlayout(card, [3, 1]);
            grid.RowHeight = {13, 38, 42};
            grid.ColumnWidth = {'1x'};
            grid.Padding = [13, 8, 13, 6];
            grid.RowSpacing = 2;
            grid.BackgroundColor = t.surface;
        end

        function label = caption(app, parent, row, text)
            %CAPTION Small uppercase section heading.
            t = app.Theme;
            label = uilabel(parent, 'Text', text, ...
                'FontSize', 10, 'FontWeight', 'bold', 'FontColor', t.faint);
            label.Layout.Row = row;
        end

        % ----------------------------------------------------------- wiring
        function applyDefaults(app, varargin)
            configPath = fullfile(app.ProjectRoot, 'config', 'default.json');
            % The UI must grade with the model the reported numbers describe.
            % These defaults were hardcoded to the 22 August checkpoint and its
            % calibration, both of which predate the operating point frozen on
            % 23 August, so the demo a judge runs graded with one model while
            % every published figure came from another.  eval/appSmoke.m had
            % the same defect and was fixed; the UI was missed.  Read the
            % frozen paths from config/default.json, which is where the freeze
            % is recorded.
            [checkpointPath, calibrationPath] = ...
                app.frozenOperatingPoint(configPath);
            if mod(numel(varargin), 2) ~= 0
                error('app:InvalidUIOptions', 'UI options must be name-value pairs.');
            end
            for index = 1:2:numel(varargin)
                name = lower(char(varargin{index}));
                value = char(varargin{index + 1});
                switch name
                    case 'configpath'
                        configPath = value;
                    case 'checkpointpath'
                        checkpointPath = value;
                    case 'calibrationpath'
                        calibrationPath = value;
                    otherwise
                        error('app:InvalidUIOptions', 'Unknown UI option: %s', name);
                end
            end
            app.ConfigPathField.Value = configPath;
            app.ModelPathField.Value = checkpointPath;
            app.CalibrationPathField.Value = calibrationPath;
            % The rail is too narrow to show an absolute path in full, so the
            % untruncated value has to be reachable somewhere.
            app.ConfigPathField.Tooltip = configPath;
            app.ModelPathField.Tooltip = checkpointPath;
            app.CalibrationPathField.Tooltip = calibrationPath;
        end

        function [checkpointPath, calibrationPath] = ...
                frozenOperatingPoint(app, configPath)
            %FROZENOPERATINGPOINT Model and calibration recorded by the freeze.
            %   Falls back to empty paths rather than to a stale checkpoint: a
            %   blank field is an obvious prompt to pick a model, whereas a
            %   silently wrong one grades against numbers nobody published.
            checkpointPath = '';
            calibrationPath = '';
            if ~isfile(configPath)
                return;
            end
            config = jsondecode(fileread(configPath));
            if ~isfield(config, 'operating_point')
                return;
            end
            operatingPoint = config.operating_point;
            if isfield(operatingPoint, 'model')
                checkpointPath = fullfile(app.ProjectRoot, operatingPoint.model);
            end
            if isfield(operatingPoint, 'calibration')
                calibrationPath = fullfile(app.ProjectRoot, ...
                    operatingPoint.calibration);
                if isfolder(calibrationPath)
                    calibrationPath = fullfile(calibrationPath, ...
                        'temperature_fit.mat');
                end
            end
        end

        function selectImage(app)
            try
                [filename, directory] = uigetfile( ...
                    {'*.png;*.jpg;*.jpeg;*.tif;*.tiff', 'Fundus images'}, ...
                    'Select fundus image');
            catch exception
                % A blocking file dialog is refused whenever MATLAB was
                % started non-interactively.  Losing the file chooser must not
                % leave the operator with no way to load a case at all, so the
                % path field takes over the same slot in the card.
                app.ImagePathField.Visible = 'on';
                app.CaseNameValue.Visible = 'off';
                app.showError(['File chooser unavailable (', ...
                    exception.message, ') Type or paste an image path into ', ...
                    'the field instead.']);
                return;
            end
            if isequal(filename, 0)
                return;
            end
            app.ImagePathField.Value = fullfile(directory, filename);
            app.refreshCaseName();
            app.setStatus('Image selected. Ready to run.', app.Theme.text, ...
                app.Theme.accent);
        end

        function refreshCaseName(app)
            %REFRESHCASENAME Show the file name, keep the path in the tooltip.
            %   Reads back from the field rather than from the file chooser so
            %   a scripted demo that sets the path directly still updates.
            t = app.Theme;
            imagePath = strtrim(app.ImagePathField.Value);
            if isempty(imagePath)
                app.CaseNameValue.Text = 'No image selected';
                app.CaseNameValue.FontColor = t.faint;
                app.CaseNameValue.Tooltip = '';
                return;
            end
            [~, name, extension] = fileparts(imagePath);
            app.CaseNameValue.Text = [name, extension];
            app.CaseNameValue.FontColor = t.text;
            app.CaseNameValue.Tooltip = imagePath;
        end

        function setStatus(app, text, textColour, dotColour)
            app.StatusValue.Text = text;
            app.StatusValue.FontColor = textColour;
            app.StatusDot.FontColor = dotColour;
        end

        function runScreening(app)
            t = app.Theme;
            imagePath = strtrim(app.ImagePathField.Value);
            app.refreshCaseName();
            if isempty(imagePath)
                app.showError('Select an image before running screening.');
                return;
            end
            app.setStatus('Running quality gate and pipeline...', t.text, t.amber);
            app.RunButton.Enable = 'off';
            app.RunButton.Text = 'Screening...';
            app.RunButton.BackgroundColor = t.raised;
            app.RunButton.FontColor = t.muted;
            app.clearResultSurfaces();
            drawnow;

            % A uifigure is rendered by a separate front end, so this
            % indeterminate bar keeps animating while MATLAB is blocked inside
            % the pipeline.  A bar driven from MATLAB would freeze instead,
            % because the inference call never yields to the event loop.
            progress = uiprogressdlg(app.UIFigure, ...
                'Title', 'Screening in progress', ...
                'Message', 'Quality gate, grading, Grad-CAM, lesion evidence, rules.', ...
                'Indeterminate', 'on', 'Cancelable', 'off');
            timer = tic;
            failure = '';
            try
                app.ScreeningResult = app.runCase(imagePath, ...
                    app.ModelPathField.Value, app.CalibrationPathField.Value, ...
                    app.ConfigPathField.Value);
                elapsed = toc(timer);
            catch exception
                failure = exception.message;
            end
            delete(progress);

            app.RunButton.Enable = 'on';
            app.RunButton.Text = 'Run screening';
            app.RunButton.BackgroundColor = t.accent;
            app.RunButton.FontColor = t.accentInk;

            if ~isempty(failure)
                app.showError(failure);
                return;
            end
            app.ProcessingTimeValue.Text = sprintf( ...
                'Processing time  %.2f s', elapsed);
            app.renderResult(app.ScreeningResult);
            app.ExportButton.Enable = 'on';
            app.ExportButton.FontColor = t.text;
            app.setStatus('Screening complete', t.text, t.green);
        end

        function result = runCase(~, imagePath, checkpointPath, calibrationPath, configPath)
            % The object handle is discarded so that "app" below resolves to
            % the +app package rather than to this class.
            result = app.runScreeningCase(imagePath, checkpointPath, ...
                calibrationPath, configPath);
        end

        % --------------------------------------------------------- rendering
        function renderResult(app, result)
            app.renderImages(result);
            app.renderVerdict(result);
            app.renderEvidence(result);
            app.playReveal();
        end

        function clearResultSurfaces(app)
            %CLEARRESULTSURFACES Blank the previous verdict before a new run.
            %   Leaving the last case's decision on screen while a different
            %   image is being graded is the one presentation bug that could
            %   actually mislead someone about a patient.
            t = app.Theme;
            for label = [app.DecisionValue, app.ProbabilityValue, ...
                    app.LevelValue, app.QualityValue]
                label.Text = '--';
                label.FontColor = t.muted;
            end
            app.DecisionCaption.Text = 'Screening...';
            app.ProbabilityCaption.Text = 'Calibrated';
            app.LevelNameValue.Text = '';
            app.QualityCaption.Text = '';
            app.EvidenceWarningValue.Text = '';
            app.EvidenceWarningValue.BackgroundColor = 'none';
            app.EvidenceValue.Value = {'Screening...'};
            app.RuleTraceArea.Value = {'Screening...'};
            for ax = [app.OriginalAxes, app.ProcessedAxes, ...
                    app.GradCAMAxes, app.CandidateAxes]
                cla(ax);
                app.blankAxes(ax);
            end
            app.ImageObjects = struct();
            app.setStageMarks(false(1, numel(app.StageNames)));
        end

        % --------------------------------------------------------- animation
        function playReveal(app)
            %PLAYREVEAL Staggered reveal of the images, then of the verdict.
            %   Animation runs only after inference has returned.  MATLAB is
            %   single threaded and the pipeline call never yields, so nothing
            %   driven from here could animate during the compute itself; that
            %   is what the indeterminate progress dialog is for.
            if ~app.AnimationsEnabled
                app.settleReveal();
                return;
            end
            try
                app.tickStagesIn();
                app.fadeImagesIn();
                app.revealVerdict();
            catch
                % A reveal that fails must never cost the operator the result.
                app.settleReveal();
            end
        end

        function tickStagesIn(app)
            %TICKSTAGESIN Light each completed stage in pipeline order.
            states = app.PendingReveal.stages;
            for index = 1:numel(app.StageMarks)
                app.setStageMarks(states & ((1:numel(states)) <= index));
                drawnow limitrate;
                pause(0.055);
            end
            app.setStageMarks(states);
        end

        function fadeImagesIn(app)
            if isempty(app.ImageObjects)
                return;
            end
            names = fieldnames(app.ImageObjects);
            frames = 14;
            for frame = 1:frames
                eased = 1 - (1 - frame / frames) ^ 3;
                for index = 1:numel(names)
                    handle = app.ImageObjects.(names{index});
                    if isempty(handle) || ~isvalid(handle)
                        continue;
                    end
                    % Each panel starts a beat after the one before it, so the
                    % reveal reads left to right as the pipeline order.
                    handle.AlphaData = ...
                        max(0, min(1, eased * 1.7 - (index - 1) * 0.17));
                end
                drawnow limitrate;
                pause(0.016);
            end
            app.settleImages();
        end

        function settleImages(app)
            if isempty(app.ImageObjects)
                return;
            end
            names = fieldnames(app.ImageObjects);
            for index = 1:numel(names)
                handle = app.ImageObjects.(names{index});
                if ~isempty(handle) && isvalid(handle)
                    handle.AlphaData = 1;
                end
            end
        end

        function revealVerdict(app)
            t = app.Theme;
            reveal = app.PendingReveal;
            frames = 16;
            for frame = 1:frames
                eased = 1 - (1 - frame / frames) ^ 3;
                app.DecisionValue.FontColor = ...
                    t.surface + (reveal.decisionColour - t.surface) * eased;
                app.LevelValue.FontColor = ...
                    t.surface + (t.text - t.surface) * eased;
                app.QualityValue.FontColor = ...
                    t.surface + (reveal.qualityColour - t.surface) * eased;
                if ~isempty(reveal.probability)
                    app.ProbabilityValue.FontColor = t.surface + ...
                        (reveal.probabilityColour - t.surface) * eased;
                    % Counting the calibrated risk up to its value gives the
                    % number a moment of attention it never had as static text.
                    app.ProbabilityValue.Text = sprintf('%.1f%%', ...
                        reveal.probability * 100 * eased);
                end
                drawnow limitrate;
                pause(0.014);
            end
            app.settleReveal();
        end

        function settleReveal(app)
            %SETTLEREVEAL Snap every animated element to its final state.
            t = app.Theme;
            app.settleImages();
            if isempty(app.PendingReveal)
                return;
            end
            reveal = app.PendingReveal;
            app.setStageMarks(reveal.stages);
            app.DecisionValue.FontColor = reveal.decisionColour;
            app.LevelValue.FontColor = t.text;
            app.QualityValue.FontColor = reveal.qualityColour;
            if isempty(reveal.probability)
                app.ProbabilityValue.Text = '--';
                app.ProbabilityValue.FontColor = t.muted;
            else
                app.ProbabilityValue.Text = ...
                    sprintf('%.1f%%', reveal.probability * 100);
                app.ProbabilityValue.FontColor = reveal.probabilityColour;
            end
        end

        function renderImages(app, result)
            % Field order is the reveal order, which is the pipeline order.
            app.ImageObjects = struct();
            app.ImageObjects.original = app.drawImage(app.OriginalAxes, ...
                localDisplay(result.originalImage));
            app.ImageObjects.processed = app.drawImage(app.ProcessedAxes, ...
                localDisplay(result.processedImage));
            if isfield(result.gradCAMResult, 'overlay')
                app.ImageObjects.gradcam = app.drawImage(app.GradCAMAxes, ...
                    result.gradCAMResult.overlay);
            else
                app.ImageObjects.gradcam = app.drawPlaceholder( ...
                    app.GradCAMAxes, ...
                    'Not generated: inference did not reach Grad-CAM.');
            end
            if isfield(result.lesionCandidateEvidence, 'candidateOverlay')
                app.ImageObjects.candidate = app.drawImage(app.CandidateAxes, ...
                    localDisplay(result.lesionCandidateEvidence.candidateOverlay));
            else
                app.ImageObjects.candidate = app.drawPlaceholder( ...
                    app.CandidateAxes, ...
                    'Not generated: no candidate overlay for this case.');
            end
        end

        function handle = drawImage(app, ax, image)
            cla(ax);
            handle = imshow(image, 'Parent', ax);
            app.blankAxes(ax);
            if app.AnimationsEnabled
                handle.AlphaData = 0;
            end
        end

        function handle = drawPlaceholder(app, ax, message)
            t = app.Theme;
            cla(ax);
            app.blankAxes(ax);
            text(ax, 0.5, 0.5, message, 'Units', 'normalized', ...
                'HorizontalAlignment', 'center', 'Color', t.faint, ...
                'FontSize', 11);
            handle = gobjects(0);
        end

        function renderVerdict(app, result)
            t = app.Theme;

            decision = char(result.threeWayDecision.decision);
            [decisionColour, decisionMeaning] = localDecisionStyle(decision, t);
            app.DecisionValue.Text = upper(decision);
            app.DecisionCard.BackgroundColor = t.surface;
            app.DecisionCaption.Text = decisionMeaning;
            app.DecisionCaption.FontColor = t.muted;

            probability = result.calibratedReferableProbability;
            if isempty(probability)
                probabilityColour = t.muted;
                app.ProbabilityCaption.Text = 'Not computed';
            else
                % A calibrated probability is a clinical quantity, so it is
                % shown the way a clinician reads one.  The previous six
                % decimal places implied a precision the calibration set
                % cannot support and buried the magnitude.
                probabilityColour = localProbabilityColour(probability, t);
                app.ProbabilityCaption.Text = 'Calibrated';
            end

            level = result.predictedICDRLevel;
            app.LevelValue.Text = localText(level);
            app.LevelNameValue.Text = localLevelName(level);

            qualityClass = char(result.qualityResult.class);
            app.QualityValue.Text = qualityClass;

            % Final colours are handed to the reveal rather than applied here,
            % so the animation has somewhere to animate from and so a failed
            % or disabled animation can still snap straight to this state.
            app.PendingReveal = struct( ...
                'decisionColour', decisionColour, ...
                'probability', probability, ...
                'probabilityColour', probabilityColour, ...
                'qualityColour', localQualityColour(qualityClass, t), ...
                'stages', localStageStates(result));
            if app.AnimationsEnabled
                app.DecisionValue.FontColor = t.surface;
                app.LevelValue.FontColor = t.surface;
                app.QualityValue.FontColor = t.surface;
                app.ProbabilityValue.FontColor = t.surface;
                app.ProbabilityValue.Text = '0.0%';
            else
                app.settleReveal();
            end
            advice = localJoin(result.qualityAdvice);
            if strcmpi(advice, 'None')
                app.QualityCaption.Text = 'No recapture needed';
            else
                app.QualityCaption.Text = advice;
            end
            app.AdviceValue.Text = sprintf('Recapture advice: %s', advice);

            app.AgreementValue.Text = sprintf('Agreement: %s', ...
                char(result.agreementStatus));
            app.EscalationValue.Text = sprintf('Escalation reason: %s', ...
                localDecisionReason(result));

            app.EvidenceWarningValue.Text = ...
                ['  Classical candidate evidence is provisional and is not ', ...
                'clinically validated lesion segmentation.'];
            app.EvidenceWarningValue.BackgroundColor = t.amberTint;
        end

        function renderEvidence(app, result)
            app.EvidenceValue.Value = localEvidenceLines(result);
            if isfield(result.icdrRuleResult, 'ruleTrace')
                app.RuleTraceArea.Value = ...
                    strsplit(char(result.icdrRuleResult.ruleTrace), newline);
            else
                app.RuleTraceArea.Value = ...
                    {'Rule engine not run: the quality gate stopped inference.'};
            end
        end

        function exportReport(app)
            t = app.Theme;
            if isempty(app.ScreeningResult)
                app.showError('Run screening before exporting a report.');
                return;
            end
            app.ExportButton.Enable = 'off';
            app.ExportButton.Text = 'Exporting...';
            app.setStatus('Rendering report...', t.text, t.amber);
            drawnow;

            % Same reason as the screening bar: report.generate blocks MATLAB
            % inside exportgraphics, so the animation has to come from the
            % uifigure front end rather than from a bar this code steps.
            progress = uiprogressdlg(app.UIFigure, 'Title', 'Exporting report', ...
                'Message', 'Rendering panels and writing the PDF.', ...
                'Indeterminate', 'on', 'Cancelable', 'off');
            failure = '';
            try
                app.LastReport = report.generate(app.ScreeningResult, ...
                    'ResultsRoot', fullfile(app.ProjectRoot, 'results'));
            catch exception
                failure = exception.message;
            end
            delete(progress);

            app.ExportButton.Enable = 'on';
            app.ExportButton.Text = 'Export report';
            if ~isempty(failure)
                app.showError(failure);
                return;
            end

            [~, name, extension] = fileparts(char(app.LastReport.reportPath));
            app.setStatus(sprintf('Report exported: %s%s', name, extension), ...
                t.text, t.green);
            app.StatusValue.Tooltip = char(app.LastReport.reportPath);
            uialert(app.UIFigure, sprintf('%s\n\n%s', ...
                'Report, four-panel figure, overlays and text companion written to:', ...
                char(app.LastReport.resultsDirectory)), 'Report exported', ...
                'Icon', 'success');
        end

        function showError(app, message)
            t = app.Theme;
            app.setStatus(message, t.red, t.red);
            app.StatusValue.Tooltip = message;
            app.RunButton.Enable = 'on';
            app.RunButton.Text = 'Run screening';
        end
    end
end

function image = localDisplay(image)
if isinteger(image) || islogical(image)
    image = im2double(image);
else
    image = double(image);
end
if ndims(image) == 2 || size(image, 3) == 1
    image = repmat(image, 1, 1, 3);
end
image = min(max(image, 0), 1);
end

function [colour, meaning] = localDecisionStyle(decision, theme)
%LOCALDECISIONSTYLE Colour and plain-language gloss for a decision.
%   The gloss says what happens to the patient, because "escalate" alone
%   does not tell an operator whether anyone is going home.
switch lower(decision)
    case 'auto-clear'
        colour = theme.green;
        meaning = 'No referable disease. Patient can be cleared here.';
    case 'refer'
        colour = theme.amber;
        meaning = 'Referable disease. Route to an ophthalmologist.';
    case 'escalate'
        colour = theme.red;
        meaning = 'Pipeline will not decide alone. Needs a human grader.';
    otherwise
        colour = theme.muted;
        meaning = 'Decision not produced.';
end
end

function states = localStageStates(result)
%LOCALSTAGESTATES Which pipeline stages left a trace in this result.
%   Read from the result rather than assumed, so a case stopped by the
%   quality gate shows the later stages as not run.
states = false(1, 6);
states(1) = isfield(result, 'qualityResult') && ~isempty(result.qualityResult);
states(2) = isfield(result, 'processedImage') && ~isempty(result.processedImage);
states(3) = isfield(result, 'predictedICDRLevel') && ...
    ~isempty(result.predictedICDRLevel);
states(4) = isfield(result, 'gradCAMResult') && ...
    isfield(result.gradCAMResult, 'overlay');
states(5) = isfield(result, 'lesionCandidateEvidence') && ...
    isfield(result.lesionCandidateEvidence, 'quadrantCounts');
states(6) = isfield(result, 'icdrRuleResult') && ...
    isfield(result.icdrRuleResult, 'ruleTrace');
end

function colour = localProbabilityColour(probability, theme)
if probability >= 0.40
    colour = theme.amber;
else
    colour = theme.green;
end
end

function colour = localQualityColour(qualityClass, theme)
switch lower(qualityClass)
    case 'gradable'
        colour = theme.green;
    case 'borderline'
        colour = theme.amber;
    case 'ungradable'
        colour = theme.red;
    otherwise
        colour = theme.muted;
end
end

function name = localLevelName(level)
%LOCALLEVELNAME ICDR severity name for a numeric grade.
if isempty(level)
    name = 'Not graded';
    return;
end
names = {'No apparent retinopathy', 'Mild non-proliferative', ...
    'Moderate non-proliferative', 'Severe non-proliferative', ...
    'Proliferative retinopathy'};
if isnumeric(level) && isscalar(level) && level >= 0 && level <= 4 ...
        && level == fix(level)
    name = names{level + 1};
else
    name = 'Not graded';
end
end

function text = localJoin(values)
if isempty(values)
    text = 'None';
elseif iscell(values)
    text = strjoin(cellfun(@char, values, 'UniformOutput', false), '; ');
else
    text = char(string(values));
end
end

function text = localText(value)
if isempty(value)
    text = '--';
elseif isnumeric(value)
    text = sprintf('%d', value);
else
    text = char(string(value));
end
end

function text = localDecisionReason(result)
if isfield(result.threeWayDecision, 'decisionReason')
    text = char(result.threeWayDecision.decisionReason);
else
    text = 'Quality gate stopped inference.';
end
end

function lines = localEvidenceLines(result)
%LOCALEVIDENCELINES Left-hand evidence panel contents.
%   Agreement and the escalation reason are folded in here so the operator
%   reads the verdict's justification next to the evidence it rests on.
lines = {};
lines{end + 1} = sprintf('Agreement       %s', char(result.agreementStatus));
lines{end + 1} = sprintf('Reason          %s', localDecisionReason(result));
lines{end + 1} = '';

if isfield(result.lesionCandidateEvidence, 'quadrantCounts')
    counts = result.lesionCandidateEvidence.quadrantCounts;
    total = size(result.lesionCandidateEvidence.candidateCoordinates, 1);
    lines{end + 1} = sprintf('Candidates      %d', total);
    lines{end + 1} = sprintf('ST / IT / SN / IN   %d / %d / %d / %d', ...
        counts.ST, counts.IT, counts.SN, counts.IN);
    if isfield(result.gradCAMResult, 'convolutionalLayerName')
        lines{end + 1} = sprintf('Grad-CAM layer  %s', ...
            char(result.gradCAMResult.convolutionalLayerName));
        lines{end + 1} = sprintf('Heatmap source  %s', ...
            char(result.gradCAMResult.rawHeatmapResolution));
    end
    lines{end + 1} = '';
    lines{end + 1} = 'Candidate evidence is provisional.';
else
    lines{end + 1} = 'Candidate counts  not generated';
end
end
