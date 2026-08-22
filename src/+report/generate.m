function result = generate(screeningResult, varargin)
%GENERATE Export the one-page annotated screening report with exportgraphics.
%   RESULT = report.generate(SCREENINGRESULT) writes a dated PNG/PDF report,
%   four panel overlays, and a text companion under results/.

rng(42, 'twister');
if nargin < 1 || ~isstruct(screeningResult) || ~isscalar(screeningResult)
    error('report:InvalidInput', 'A scalar screening result is required.');
end

parser = inputParser;
parser.addParameter('ResultsRoot', localProjectResultsRoot(), ...
    @(value) ischar(value) || (isstring(value) && isscalar(value)));
parser.parse(varargin{:});
resultsRoot = char(parser.Results.ResultsRoot);
localRejectSealedPath(resultsRoot);
resultsDirectory = localDatedDirectory(resultsRoot);
mkdir(resultsDirectory);

figureHandle = figure('Visible', 'off', 'Color', [0.97, 0.97, 0.97], ...
    'Position', [50, 50, 1500, 1050]);
cleanup = onCleanup(@() close(figureHandle)); %#ok<NASGU>
layout = tiledlayout(figureHandle, 3, 3, 'TileSpacing', 'compact', ...
    'Padding', 'compact');

localImageTile(layout, screeningResult.originalImage, 'Original fundus image');
localImageTile(layout, screeningResult.processedImage, ...
    'Enhanced / processed image');
localImageTile(layout, localGradCAMOverlay(screeningResult), ...
    'Grad-CAM overlay');
localImageTile(layout, localCandidateOverlay(screeningResult), ...
    'Classical candidate overlay');

nexttile(layout, 5);
axis off;
localTextTile(screeningResult);

nexttile(layout, 6);
axis off;
localEvidenceTile(screeningResult);

nexttile(layout, 7);
axis off;
localTraceTile(screeningResult);

nexttile(layout, 8);
axis off;
localWarningsTile(screeningResult);

nexttile(layout, 9);
axis off;
footer = text(0.02, 0.72, localWrapText( ...
    'Screening aid. Not a diagnosis. Requires clinician confirmation.', 32), ...
    'Units', 'normalized', 'FontSize', 13, 'FontWeight', 'bold', ...
    'Interpreter', 'none', 'Color', [0.45, 0.05, 0.05]);
footer.HorizontalAlignment = 'left';

fourPanelPath = fullfile(resultsDirectory, 'screening_four_panel.png');
reportPngPath = fullfile(resultsDirectory, 'screening_report.png');
reportPdfPath = fullfile(resultsDirectory, 'screening_report.pdf');
textPath = fullfile(resultsDirectory, 'screening_report.txt');
localExportFourPanel(screeningResult, fourPanelPath);
localExportFigure(figureHandle, reportPngPath);
try
    exportgraphics(figureHandle, reportPdfPath, 'ContentType', 'vector');
catch exception
    error('report:ExportFailed', 'PDF report export failed: %s', exception.message);
end

overlayPaths = struct();
overlayPaths.original = localExportImage( ...
    screeningResult.originalImage, resultsDirectory, 'original.png');
overlayPaths.processed = localExportImage( ...
    screeningResult.processedImage, resultsDirectory, 'processed.png');
overlayPaths.gradCAM = localExportImage( ...
    localGradCAMOverlay(screeningResult), resultsDirectory, 'gradcam_overlay.png');
overlayPaths.candidates = localExportImage( ...
    localCandidateOverlay(screeningResult), resultsDirectory, 'candidate_overlay.png');

reportText = localReportText(screeningResult, overlayPaths);
localWriteText(textPath, reportText);

result = struct();
result.status = "completed";
result.resultsDirectory = string(resultsDirectory);
result.reportPath = string(reportPdfPath);
result.reportPngPath = string(reportPngPath);
result.fourPanelPath = string(fourPanelPath);
result.textPath = string(textPath);
result.overlayPaths = overlayPaths;
result.footer = "Screening aid. Not a diagnosis. Requires clinician confirmation.";
result.sealedDataAccessed = false;
end

function localExportFourPanel(screeningResult, outputPath)
figureHandle = figure('Visible', 'off', 'Color', [0.97, 0.97, 0.97], ...
    'Position', [50, 50, 1200, 900]);
cleanup = onCleanup(@() close(figureHandle)); %#ok<NASGU>
layout = tiledlayout(figureHandle, 2, 2, 'TileSpacing', 'compact', ...
    'Padding', 'compact');
localImageTile(layout, screeningResult.originalImage, 'Original fundus image');
localImageTile(layout, screeningResult.processedImage, ...
    'Enhanced / processed image');
localImageTile(layout, localGradCAMOverlay(screeningResult), 'Grad-CAM overlay');
localImageTile(layout, localCandidateOverlay(screeningResult), ...
    'Classical candidate overlay');
localExportFigure(figureHandle, outputPath);
end

function localImageTile(layout, image, titleText)
nexttile(layout);
axesHandle = gca;
if isempty(image)
    axis(axesHandle, 'off');
    text(0.05, 0.5, 'Not generated', 'Units', 'normalized', ...
        'Interpreter', 'none', 'Color', [0.2, 0.2, 0.2]);
else
    imshow(localDisplayImage(image), 'Parent', axesHandle);
    title(titleText, 'Interpreter', 'none', 'Color', [0.05, 0.05, 0.05]);
end
end

function localTextTile(screeningResult)
metadata = screeningResult.reportMetadata;
level = localTextOrUnknown(screeningResult.predictedICDRLevel);
probability = localProbability(screeningResult.calibratedReferableProbability);
decision = localDecision(screeningResult);
quality = localQuality(screeningResult);
lines = sprintf([ ...
    'QUALITY: %s\n', ...
    'ADVICE: %s\n', ...
    'ICDR LEVEL: %s\n', ...
    'CALIBRATED REFERABLE PROBABILITY: %s\n', ...
    'THREE-WAY DECISION: %s\n', ...
    'AGREEMENT: %s\n', ...
    'IMAGE: %s\n', ...
    'TIMESTAMP: %s'], quality, localAdvice(screeningResult), level, ...
    probability, decision, localAgreement(screeningResult), ...
    localFieldText(metadata, 'imageIdentifier'), ...
    localFieldText(metadata, 'timestamp'));
text(0.02, 0.98, lines, 'Units', 'normalized', 'VerticalAlignment', 'top', ...
    'Interpreter', 'none', 'FontSize', 10, 'Color', [0.05, 0.05, 0.05]);
end

function localEvidenceTile(screeningResult)
if ~isfield(screeningResult, 'lesionCandidateEvidence') || ...
        isempty(fieldnames(screeningResult.lesionCandidateEvidence))
    evidenceLines = 'Evidence was not generated because the quality gate stopped inference.';
else
    evidence = screeningResult.lesionCandidateEvidence;
    counts = evidence.quadrantCounts;
    evidenceLines = sprintf([ ...
        'EVIDENCE QUALITY: PROVISIONAL\n', ...
        'Candidate count: %d\n', ...
        'Quadrants ST / IT / SN / IN: %d / %d / %d / %d\n', ...
        'Grad-CAM layer: %s\n', ...
        'Raw Grad-CAM resolution: %s\n\n', ...
        'Classical candidate evidence is provisional and not clinically validated\n', ...
        'lesion segmentation.'], evidence.candidateCountsByQuadrant.ST + ...
        evidence.candidateCountsByQuadrant.IT + evidence.candidateCountsByQuadrant.SN + ...
        evidence.candidateCountsByQuadrant.IN, counts.ST, counts.IT, counts.SN, ...
        counts.IN, localGradCAMLayer(screeningResult), localGradCAMResolution(screeningResult));
end
text(0.02, 0.98, evidenceLines, 'Units', 'normalized', ...
    'VerticalAlignment', 'top', 'Interpreter', 'none', 'FontSize', 9, ...
    'Color', [0.05, 0.05, 0.05]);
end

function localTraceTile(screeningResult)
if isfield(screeningResult, 'icdrRuleResult') && ...
        isfield(screeningResult.icdrRuleResult, 'ruleTrace')
    trace = char(screeningResult.icdrRuleResult.ruleTrace);
else
    trace = 'ICDR rule trace was not generated because the quality gate stopped inference.';
end
text(0.02, 0.98, localWrapText(trace, 58), 'Units', 'normalized', ...
    'VerticalAlignment', 'top', 'Interpreter', 'none', 'FontSize', 6, ...
    'Color', [0.05, 0.05, 0.05]);
end

function localWarningsTile(screeningResult)
warnings = localCellText(screeningResult, 'warnings');
limitations = localCellText(screeningResult, 'limitations');
lines = sprintf('WARNINGS\n%s\n\nLIMITATIONS\n%s', ...
    strjoin(warnings, '\n'), strjoin(limitations, '\n'));
text(0.02, 0.98, localWrapText(lines, 58), 'Units', 'normalized', ...
    'VerticalAlignment', 'top', 'Interpreter', 'none', 'FontSize', 6, ...
    'Color', [0.05, 0.05, 0.05]);
end

function overlay = localGradCAMOverlay(screeningResult)
overlay = [];
if isfield(screeningResult, 'gradCAMResult') && ...
        isfield(screeningResult.gradCAMResult, 'overlay')
    overlay = screeningResult.gradCAMResult.overlay;
end
end

function overlay = localCandidateOverlay(screeningResult)
overlay = [];
if isfield(screeningResult, 'lesionCandidateEvidence') && ...
        isfield(screeningResult.lesionCandidateEvidence, 'candidateOverlay')
    overlay = screeningResult.lesionCandidateEvidence.candidateOverlay;
end
end

function path = localExportImage(image, resultsDirectory, filename)
path = fullfile(resultsDirectory, filename);
figureHandle = figure('Visible', 'off', 'Color', 'white');
cleanup = onCleanup(@() close(figureHandle)); %#ok<NASGU>
if isempty(image)
    axis off;
    text(0.05, 0.5, 'Not generated', 'Units', 'normalized', ...
        'Interpreter', 'none');
else
    axesHandle = axes(figureHandle);
    imshow(localDisplayImage(image), 'Parent', axesHandle);
    axis(axesHandle, 'image', 'off');
end
localExportFigure(figureHandle, path);
end

function localExportFigure(figureHandle, outputPath)
try
    exportgraphics(figureHandle, outputPath, 'Resolution', 150);
catch exception
    error('report:ExportFailed', 'Figure export failed: %s', exception.message);
end
end

function text = localReportText(screeningResult, overlayPaths)
text = sprintf([ ...
    'SIH26038 Explainable AI for DR Screening\n', ...
    'Image identifier: %s\n', ...
    'Timestamp: %s\n', ...
    'Quality status: %s\n', ...
    'Recapture advice: %s\n', ...
    'ICDR level: %s\n', ...
    'Calibrated referable probability: %s\n', ...
    'Three-way decision: %s\n', ...
    'Agreement status: %s\n', ...
    'Escalation reason: %s\n', ...
    'Candidate count: %s\n', ...
    'Quadrant counts: %s\n', ...
    'Grad-CAM layer: %s\n', ...
    'Raw Grad-CAM resolution: %s\n\n', ...
    'ICDR rule trace:\n%s\n\n', ...
    'Warnings:\n%s\n\n', ...
    'Limitations:\n%s\n\n', ...
    'Overlay paths:\nOriginal: %s\nProcessed: %s\nGrad-CAM: %s\nCandidates: %s\n\n', ...
    'Classical candidate evidence is provisional and not clinically validated\n', ...
    'lesion segmentation.\n\n', ...
    'Screening aid. Not a diagnosis. Requires clinician confirmation.'], ...
    localFieldText(screeningResult.reportMetadata, 'imageIdentifier'), ...
    localFieldText(screeningResult.reportMetadata, 'timestamp'), ...
    localQuality(screeningResult), localAdvice(screeningResult), ...
    localTextOrUnknown(screeningResult.predictedICDRLevel), ...
    localProbability(screeningResult.calibratedReferableProbability), ...
    localDecision(screeningResult), localAgreement(screeningResult), ...
    localEscalationReason(screeningResult), localCandidateCount(screeningResult), ...
    localQuadrantText(screeningResult), localGradCAMLayer(screeningResult), ...
    localGradCAMResolution(screeningResult), localRuleTrace(screeningResult), ...
    strjoin(localCellText(screeningResult, 'warnings'), '\n'), ...
    strjoin(localCellText(screeningResult, 'limitations'), '\n'), ...
    overlayPaths.original, overlayPaths.processed, overlayPaths.gradCAM, ...
    overlayPaths.candidates);
end

function value = localQuality(result)
if isfield(result, 'qualityResult') && isfield(result.qualityResult, 'class')
    value = char(result.qualityResult.class);
else
    value = 'unknown';
end
end

function value = localAdvice(result)
if isfield(result, 'qualityAdvice') && ~isempty(result.qualityAdvice)
    value = strjoin(localCell(result.qualityAdvice), '; ');
else
    value = 'None';
end
end

function value = localDecision(result)
if isfield(result, 'threeWayDecision') && ...
        isfield(result.threeWayDecision, 'decision')
    value = char(result.threeWayDecision.decision);
else
    value = 'unknown';
end
end

function value = localAgreement(result)
if isfield(result, 'agreementStatus')
    value = char(result.agreementStatus);
else
    value = 'not assessed';
end
end

function value = localEscalationReason(result)
if isfield(result, 'threeWayDecision') && ...
        isfield(result.threeWayDecision, 'decisionReason')
    value = char(result.threeWayDecision.decisionReason);
else
    value = 'not available';
end
end

function value = localCandidateCount(result)
if isfield(result, 'lesionCandidateEvidence') && ...
        isfield(result.lesionCandidateEvidence, 'candidateCoordinates')
    value = sprintf('%d', size(result.lesionCandidateEvidence.candidateCoordinates, 1));
else
    value = 'not generated';
end
end

function value = localQuadrantText(result)
if isfield(result, 'lesionCandidateEvidence') && ...
        isfield(result.lesionCandidateEvidence, 'quadrantCounts')
    counts = result.lesionCandidateEvidence.quadrantCounts;
    value = sprintf('[ST %d, IT %d, SN %d, IN %d]', counts.ST, counts.IT, ...
        counts.SN, counts.IN);
else
    value = 'not generated';
end
end

function value = localGradCAMLayer(result)
if isfield(result, 'gradCAMResult') && ...
        isfield(result.gradCAMResult, 'convolutionalLayerName')
    value = char(result.gradCAMResult.convolutionalLayerName);
else
    value = 'not generated';
end
end

function value = localGradCAMResolution(result)
if isfield(result, 'gradCAMResult') && ...
        isfield(result.gradCAMResult, 'rawHeatmapResolution')
    value = char(result.gradCAMResult.rawHeatmapResolution);
else
    value = 'not generated';
end
end

function value = localRuleTrace(result)
if isfield(result, 'icdrRuleResult') && ...
        isfield(result.icdrRuleResult, 'ruleTrace')
    value = char(result.icdrRuleResult.ruleTrace);
else
    value = 'not generated because the quality gate stopped inference.';
end
end

function value = localProbability(probability)
if isempty(probability) || ~isnumeric(probability) || ~isscalar(probability)
    value = 'not available';
else
    value = sprintf('%.6f', probability);
end
end

function value = localTextOrUnknown(input)
if isempty(input)
    value = 'not available';
elseif isnumeric(input) && isscalar(input)
    value = sprintf('%d', input);
else
    value = char(string(input));
end
end

function value = localFieldText(input, fieldName)
if isstruct(input) && isfield(input, fieldName) && ~isempty(input.(fieldName))
    value = char(string(input.(fieldName)));
else
    value = 'unknown';
end
end

function values = localCellText(result, fieldName)
if ~isfield(result, fieldName) || isempty(result.(fieldName))
    values = {'None'};
else
    values = localCell(result.(fieldName));
end
end

function values = localCell(input)
if ischar(input)
    values = {input};
elseif isstring(input)
    values = cellstr(input(:));
elseif iscell(input)
    values = cellfun(@(value) char(string(value)), input, 'UniformOutput', false);
else
    values = {char(string(input))};
end
end

function lines = localWrapText(input, width)
rawLines = strsplit(char(input), newline);
lines = {};
for lineIndex = 1:numel(rawLines)
    line = rawLines{lineIndex};
    if isempty(line)
        lines{end + 1} = ''; %#ok<AGROW>
        continue;
    end
    while strlength(line) > width
        splitAt = width;
        spaces = find(line(1:width) == ' ', 1, 'last');
        if ~isempty(spaces)
            splitAt = spaces;
        end
        lines{end + 1} = strtrim(line(1:splitAt)); %#ok<AGROW>
        line = strtrim(line(splitAt + 1:end));
    end
    lines{end + 1} = line; %#ok<AGROW>
end
end

function directory = localDatedDirectory(resultsRoot)
if ~isfolder(resultsRoot)
    mkdir(resultsRoot);
end
stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
for suffix = 0:999
    if suffix == 0
        directory = fullfile(resultsRoot, stamp);
    else
        directory = fullfile(resultsRoot, sprintf('%s_%02d', stamp, suffix));
    end
    if ~isfolder(directory)
        return;
    end
end
error('report:ResultsDirectory', 'Could not allocate a unique dated directory.');
end

function localWriteText(filename, content)
fileIdentifier = fopen(filename, 'w', 'n', 'UTF-8');
if fileIdentifier < 0
    error('report:ResultsWriteFailed', 'Could not write report text: %s', filename);
end
cleanup = onCleanup(@() fclose(fileIdentifier)); %#ok<NASGU>
fwrite(fileIdentifier, content, 'char');
end

function image = localDisplayImage(image)
if isempty(image)
    return;
end
if isinteger(image) || islogical(image)
    image = im2double(image);
else
    image = double(image);
end
if ndims(image) == 2
    image = repmat(image, 1, 1, 3);
elseif size(image, 3) == 1
    image = repmat(image, 1, 1, 3);
end
image = min(max(image, 0), 1);
end

function root = localProjectResultsRoot()
thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(fileparts(thisFile)));
root = fullfile(projectRoot, 'results');
end

function localRejectSealedPath(path)
normalizedPath = lower(strrep(char(path), '\\', '/'));
if contains(normalizedPath, '/data/sealed/') || endsWith(normalizedPath, '/data/sealed')
    error('report:SealedData', 'Report output cannot be inside data/sealed.');
end
end
