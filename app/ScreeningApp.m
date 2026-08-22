classdef ScreeningApp < handle
    %SCREENINGAPP App Designer-compatible integrated screening demo.
    %   app = ScreeningApp creates the local MATLAB screening UI.  All
    %   inference logic stays in app.runScreeningCase and report.generate.

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
    end

    properties (Access = private)
        ProjectRoot
        ScreeningResult
        LastReport
    end

    methods
        function app = ScreeningApp(varargin)
            app.ProjectRoot = fileparts(fileparts(mfilename('fullpath')));
            addpath(genpath(fullfile(app.ProjectRoot, 'src')));
            app.createComponents();
            app.applyDefaults(varargin{:});
        end

        function delete(app)
            if ~isempty(app.UIFigure) && isvalid(app.UIFigure)
                delete(app.UIFigure);
            end
        end
    end

    methods (Access = private)
        function createComponents(app)
            app.UIFigure = uifigure('Name', 'SIH26038 DR Screening Aid', ...
                'Position', [50, 50, 1500, 950], 'Color', [0.96, 0.97, 0.98]);
            outer = uigridlayout(app.UIFigure, [1, 2]);
            outer.ColumnWidth = {320, '1x'};
            outer.RowHeight = {'1x'};
            outer.Padding = [12, 12, 12, 12];
            outer.ColumnSpacing = 12;

            controls = uigridlayout(outer, [18, 1]);
            controls.RowHeight = {28, 24, 28, 24, 28, 24, 28, 24, ...
                36, 36, 30, 28, 28, 28, 28, 28, 28, '1x'};
            controls.Padding = [8, 8, 8, 8];
            controls.BackgroundColor = [1, 1, 1];

            titleLabel = uilabel(controls, 'Text', 'Screening case', ...
                'FontSize', 18, 'FontWeight', 'bold');
            titleLabel.Layout.Row = 1;
            titleLabel.Layout.Column = 1;
            app.SelectImageButton = uibutton(controls, 'push', ...
                'Text', 'Select image', 'ButtonPushedFcn', ...
                @(~, ~) app.selectImage());
            app.SelectImageButton.Layout.Row = 2;
            app.ImagePathField = uieditfield(controls, 'text', ...
                'Placeholder', 'Selected image path');
            app.ImagePathField.Layout.Row = 3;
            app.ModelPathField = uieditfield(controls, 'text', ...
                'Placeholder', 'Model checkpoint path');
            app.ModelPathField.Layout.Row = 4;
            app.CalibrationPathField = uieditfield(controls, 'text', ...
                'Placeholder', 'Temperature calibration path');
            app.CalibrationPathField.Layout.Row = 5;
            app.ConfigPathField = uieditfield(controls, 'text', ...
                'Placeholder', 'Project configuration path');
            app.ConfigPathField.Layout.Row = 6;
            app.RunButton = uibutton(controls, 'push', 'Text', 'Run screening', ...
                'FontWeight', 'bold', 'ButtonPushedFcn', ...
                @(~, ~) app.runScreening());
            app.RunButton.Layout.Row = 7;
            app.ExportButton = uibutton(controls, 'push', ...
                'Text', 'Export report', 'Enable', 'off', ...
                'ButtonPushedFcn', @(~, ~) app.exportReport());
            app.ExportButton.Layout.Row = 8;

            app.StatusValue = uilabel(controls, 'Text', 'Ready', ...
                'FontWeight', 'bold', 'FontColor', [0.1, 0.25, 0.45]);
            app.StatusValue.Layout.Row = 9;
            app.ProcessingTimeValue = uilabel(controls, 'Text', 'Processing time: -');
            app.ProcessingTimeValue.Layout.Row = 10;

            app.QualityValue = uilabel(controls, 'Text', 'Quality: -');
            app.QualityValue.Layout.Row = 11;
            app.AdviceValue = uilabel(controls, 'Text', 'Recapture advice: -', ...
                'WordWrap', 'on');
            app.AdviceValue.Layout.Row = 12;
            app.LevelValue = uilabel(controls, 'Text', 'ICDR level: -');
            app.LevelValue.Layout.Row = 13;
            app.ProbabilityValue = uilabel(controls, ...
                'Text', 'Calibrated referable probability: -', 'WordWrap', 'on');
            app.ProbabilityValue.Layout.Row = 14;
            app.DecisionValue = uilabel(controls, 'Text', 'Decision: -', ...
                'FontWeight', 'bold');
            app.DecisionValue.Layout.Row = 15;
            app.AgreementValue = uilabel(controls, 'Text', 'Agreement: -', ...
                'WordWrap', 'on');
            app.AgreementValue.Layout.Row = 16;
            app.EscalationValue = uilabel(controls, 'Text', 'Escalation reason: -', ...
                'WordWrap', 'on');
            app.EscalationValue.Layout.Row = 17;
            app.EvidenceWarningValue = uilabel(controls, ...
                'Text', 'Evidence-quality warning: candidate evidence is provisional.', ...
                'WordWrap', 'on', 'FontColor', [0.55, 0.18, 0.05]);
            app.EvidenceWarningValue.Layout.Row = 18;

            workspace = uigridlayout(outer, [3, 2]);
            workspace.RowHeight = {'1x', '1x', 230};
            workspace.ColumnWidth = {'1x', '1x'};
            workspace.Padding = [0, 0, 0, 0];
            app.OriginalAxes = uiaxes(workspace);
            app.OriginalAxes.Layout.Row = 1;
            app.OriginalAxes.Layout.Column = 1;
            title(app.OriginalAxes, 'Original fundus image');
            app.ProcessedAxes = uiaxes(workspace);
            app.ProcessedAxes.Layout.Row = 1;
            app.ProcessedAxes.Layout.Column = 2;
            title(app.ProcessedAxes, 'Enhanced / processed image');
            app.GradCAMAxes = uiaxes(workspace);
            app.GradCAMAxes.Layout.Row = 2;
            app.GradCAMAxes.Layout.Column = 1;
            title(app.GradCAMAxes, 'Grad-CAM overlay');
            app.CandidateAxes = uiaxes(workspace);
            app.CandidateAxes.Layout.Row = 2;
            app.CandidateAxes.Layout.Column = 2;
            title(app.CandidateAxes, 'Classical candidate overlay');

            evidencePanel = uipanel(workspace, 'Title', 'Evidence and status');
            evidencePanel.Layout.Row = 3;
            evidencePanel.Layout.Column = [1, 2];
            evidenceGrid = uigridlayout(evidencePanel, [1, 2]);
            evidenceGrid.ColumnWidth = {'1x', '2x'};
            app.EvidenceValue = uitextarea(evidenceGrid, 'Editable', 'off', ...
                'Value', {'Candidate counts: -', 'Quadrants: -', ...
                'Grad-CAM layer: -', 'Raw Grad-CAM resolution: -', ...
                'Provisional evidence warning: on'});
            app.EvidenceValue.Layout.Column = 1;
            app.EvidenceValue.WordWrap = 'on';
            app.EvidenceValue.FontName = 'Consolas';
            app.EvidenceValue.FontSize = 11;
            app.RuleTraceArea = uitextarea(evidenceGrid, 'Editable', 'off', ...
                'Value', {'ICDR rule trace: -'});
            app.RuleTraceArea.Layout.Column = 2;
            app.RuleTraceArea.WordWrap = 'on';
            app.RuleTraceArea.FontName = 'Consolas';
            app.RuleTraceArea.FontSize = 10;
        end

        function applyDefaults(app, varargin)
            configPath = fullfile(app.ProjectRoot, 'config', 'default.json');
            checkpointPath = fullfile(app.ProjectRoot, 'results', ...
                '20260822_030539', 'best_model.mat');
            calibrationPath = fullfile(app.ProjectRoot, 'results', ...
                '20260822_091625', 'temperature_fit.mat');
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
        end

        function selectImage(app)
            [filename, directory] = uigetfile( ...
                {'*.png;*.jpg;*.jpeg;*.tif;*.tiff', 'Fundus images'}, ...
                'Select fundus image');
            if isequal(filename, 0)
                return;
            end
            app.ImagePathField.Value = fullfile(directory, filename);
            app.StatusValue.Text = 'Image selected. Ready to run.';
        end

        function runScreening(app)
            imagePath = strtrim(app.ImagePathField.Value);
            if isempty(imagePath)
                app.showError('Select an image before running screening.');
                return;
            end
            app.StatusValue.Text = 'Running quality gate and screening pipeline...';
            app.StatusValue.FontColor = [0.75, 0.40, 0.05];
            app.RunButton.Enable = 'off';
            drawnow;
            timer = tic;
            try
                app.ScreeningResult = app.runCase(imagePath, ...
                    app.ModelPathField.Value, app.CalibrationPathField.Value, ...
                    app.ConfigPathField.Value);
                elapsed = toc(timer);
                app.ProcessingTimeValue.Text = sprintf( ...
                    'Processing time: %.2f seconds', elapsed);
                app.renderResult(app.ScreeningResult);
                app.ExportButton.Enable = 'on';
                app.StatusValue.Text = 'Screening completed.';
                app.StatusValue.FontColor = [0.05, 0.45, 0.20];
            catch exception
                app.showError(exception.message);
            end
            app.RunButton.Enable = 'on';
        end

        function result = runCase(~, imagePath, checkpointPath, calibrationPath, configPath)
            result = app.runScreeningCase(imagePath, checkpointPath, ...
                calibrationPath, configPath);
        end

        function renderResult(app, result)
            cla(app.OriginalAxes);
            imshow(localDisplay(result.originalImage), 'Parent', app.OriginalAxes);
            cla(app.ProcessedAxes);
            imshow(localDisplay(result.processedImage), 'Parent', app.ProcessedAxes);
            cla(app.GradCAMAxes);
            if isfield(result.gradCAMResult, 'overlay')
                imshow(result.gradCAMResult.overlay, 'Parent', app.GradCAMAxes);
            else
                text(app.GradCAMAxes, 0.05, 0.5, 'Not generated', ...
                    'Units', 'normalized');
            end
            cla(app.CandidateAxes);
            if isfield(result.lesionCandidateEvidence, 'candidateOverlay')
                imshow(localDisplay(result.lesionCandidateEvidence.candidateOverlay), ...
                    'Parent', app.CandidateAxes);
            else
                text(app.CandidateAxes, 0.05, 0.5, 'Not generated', ...
                    'Units', 'normalized');
            end
            app.QualityValue.Text = sprintf('Quality: %s', ...
                char(result.qualityResult.class));
            app.AdviceValue.Text = sprintf('Recapture advice: %s', ...
                localJoin(result.qualityAdvice));
            app.LevelValue.Text = sprintf('ICDR level: %s', ...
                localText(result.predictedICDRLevel));
            app.ProbabilityValue.Text = sprintf( ...
                'Calibrated referable probability: %s', ...
                localProbability(result.calibratedReferableProbability));
            app.DecisionValue.Text = sprintf('Decision: %s', ...
                char(result.threeWayDecision.decision));
            app.AgreementValue.Text = sprintf('Agreement: %s', ...
                char(result.agreementStatus));
            app.EscalationValue.Text = sprintf('Escalation reason: %s', ...
                localDecisionReason(result));
            app.EvidenceWarningValue.Text = ...
                'Evidence-quality warning: classical candidate evidence is provisional and not clinically validated lesion segmentation.';
            app.EvidenceValue.Value = localEvidenceLines(result);
            if isfield(result.icdrRuleResult, 'ruleTrace')
                app.RuleTraceArea.Value = strsplit(char(result.icdrRuleResult.ruleTrace), newline);
            else
                app.RuleTraceArea.Value = {'ICDR rule trace: not run after quality stop'};
            end
        end

        function exportReport(app)
            if isempty(app.ScreeningResult)
                app.showError('Run screening before exporting a report.');
                return;
            end
            try
                app.LastReport = report.generate(app.ScreeningResult, ...
                    'ResultsRoot', fullfile(app.ProjectRoot, 'results'));
                app.StatusValue.Text = sprintf('Report exported: %s', ...
                    char(app.LastReport.reportPath));
                app.StatusValue.FontColor = [0.05, 0.45, 0.20];
            catch exception
                app.showError(exception.message);
            end
        end

        function showError(app, message)
            app.StatusValue.Text = ['Error: ', message];
            app.StatusValue.FontColor = [0.70, 0.05, 0.05];
            app.RunButton.Enable = 'on';
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
    text = '-';
elseif isnumeric(value)
    text = sprintf('%d', value);
else
    text = char(string(value));
end
end

function text = localProbability(value)
if isempty(value)
    text = '-';
else
    text = sprintf('%.6f', value);
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
lines = {'Candidate counts: not generated'};
if isfield(result.lesionCandidateEvidence, 'quadrantCounts')
    counts = result.lesionCandidateEvidence.quadrantCounts;
    total = size(result.lesionCandidateEvidence.candidateCoordinates, 1);
    lines = {sprintf('Candidate count: %d', total), ...
        sprintf('Quadrants ST / IT / SN / IN: %d / %d / %d / %d', ...
        counts.ST, counts.IT, counts.SN, counts.IN)};
    if isfield(result.gradCAMResult, 'convolutionalLayerName')
        lines{end + 1} = sprintf('Grad-CAM layer: %s', ...
            char(result.gradCAMResult.convolutionalLayerName));
        lines{end + 1} = sprintf('Raw Grad-CAM resolution: %s', ...
            char(result.gradCAMResult.rawHeatmapResolution));
    end
    lines{end + 1} = 'Candidate evidence is provisional.';
end
end
