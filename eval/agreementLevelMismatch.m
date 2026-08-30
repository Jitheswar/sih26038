function result = agreementLevelMismatch(varargin)
%AGREEMENTLEVELMISMATCH Why the agreement check escalates, from saved runs.
%   RESULT = agreementLevelMismatch(RUNPATH) reads an existing
%   ablation_results.mat and reports, for each escalating pipeline
%   configuration, which §8.6 agreement state caused each escalation and how
%   the two channels' ICDR levels were distributed when they disagreed.
%
%   It reads saved results only.  No model, no image, no GPU, no split: it
%   answers in seconds what a re-run of the harness answers in hours.
%
%   The trick that makes this possible is that the ablation study already
%   runs each lesion channel twice.  A "rules only, no CNN" configuration
%   records the rule engine's own ICDR level in decisions.predictedLevel,
%   and the full-pipeline configuration built on the same channel records
%   the CNN's level in the same field, over the same split in the same
%   order and from the same feature pass.  Pairing them recovers both
%   levels per case without recomputing either.
%
%   Name-value options:
%     'Run'       Path to an ablation_results.mat (required).
%     'Pairs'     Cell array of {ruleOnlyId, fullPipelineId} pairs.  The
%                 default covers the three pairs the study defines:
%                 A3/A5 classical, A6/A7 four-head learned, A8/A9
%                 hard-exudate learned.  Pairs absent from the file are
%                 skipped rather than raising.
%     'ResultsRoot' Root for the dated result directory.
%
%   What the numbers mean.  §11.2 names the primary endpoint as referable
%   versus not referable, a binary decision.  localAgreementStatus compares
%   the two channels for exact ICDR level equality whenever the rule engine
%   can reach Level 2, and calls any difference "insufficient evidence".
%   The mismatch table therefore separates two very different cases:
%
%     Severity-only    Both channels place the patient on the same side of
%                      the referral decision and differ on how severe the
%                      disease is.  The pipeline escalates a case on which
%                      both channels already agree about what to do.
%
%     Endpoint         The channels disagree about referral itself.  This
%                      is the disagreement §8.6 was written to catch.
%
%   The rule engine's observed ceiling is reported alongside, because a
%   ceiling below 4 makes some mismatches unreachable rather than unlikely:
%   with hard-exudate evidence only the ceiling is Level 2, so every CNN
%   prediction of Level 3 or 4 mismatches by construction.

rng(42, 'twister');

options = localOptions(varargin{:});
if isempty(options.run)
    error('eval:MissingRun', ...
        'Pass the path to an ablation_results.mat with ''Run''.');
end
if ~isfile(options.run)
    error('eval:MissingRun', 'No such results file: %s', options.run);
end

loaded = load(options.run, 'perConfig');
perConfig = loaded.perConfig;
identifiers = arrayfun(@(entry) string(entry.id), perConfig);

fprintf('Agreement level mismatch, from %s\n', options.run);

reports = {};
for index = 1:size(options.pairs, 1)
    ruleId = string(options.pairs{index, 1});
    fullId = string(options.pairs{index, 2});
    ruleAt = find(identifiers == ruleId, 1);
    fullAt = find(identifiers == fullId, 1);
    if isempty(ruleAt) || isempty(fullAt)
        continue;
    end
    report = localAnalyse(perConfig(ruleAt), perConfig(fullAt));
    localPrintReport(report);
    reports{end + 1} = report; %#ok<AGROW>
end

if isempty(reports)
    error('eval:NoPairs', ...
        'None of the requested configuration pairs are in %s.', options.run);
end

resultsDirectory = localDatedDirectory(fullfile(localProjectRoot(), ...
    options.resultsRoot), 'agreement_level_mismatch');
localWriteOutputs(resultsDirectory, reports, options);

result = struct();
result.status = "completed";
result.reports = reports;
result.resultsDirectory = string(resultsDirectory);
fprintf('\nWritten to %s\n', resultsDirectory);
end

% -------------------------------------------------------------- analysis

function report = localAnalyse(ruleConfig, fullConfig)
ruleDecisions = ruleConfig.decisions;
fullDecisions = fullConfig.decisions;

ruleLevel = ruleDecisions.predictedLevel;
cnnLevel = fullDecisions.predictedLevel;
escalated = strcmp(fullDecisions.decision, "escalate");

report = struct();
report.ruleId = ruleConfig.id;
report.fullId = fullConfig.id;
report.label = fullConfig.label;
report.n = numel(escalated);
report.escalated = sum(escalated);
report.coverage = fullConfig.coverage;

% The reason codes are the policy's own record of which state fired.
report.spatial = sum(escalated & ...
    contains(fullDecisions.reason, "explanation-disagreement"));
report.insufficient = sum(escalated & ...
    contains(fullDecisions.reason, "insufficient-explanation-evidence"));
report.evidenceUnsupported = sum(escalated & ...
    contains(fullDecisions.reason, "cnn-referable-evidence-unsupported"));
report.evidenceOverDetected = sum(escalated & ...
    contains(fullDecisions.reason, "evidence-referable-cnn-nonreferable"));

insufficient = escalated & ...
    contains(fullDecisions.reason, "insufficient-explanation-evidence");
known = ~isnan(ruleLevel) & ~isnan(cnnLevel);
mismatch = insufficient & known & ruleLevel ~= cnnLevel;

report.insufficientLevelsKnown = sum(insufficient & known);
report.insufficientMismatch = sum(mismatch);
report.insufficientLevelsEqual = sum(insufficient & known & ruleLevel == cnnLevel);

severityOnly = mismatch & ((ruleLevel >= 2 & cnnLevel >= 2) | ...
    (ruleLevel < 2 & cnnLevel < 2));
report.severityOnly = sum(severityOnly);
report.endpointDisagreement = report.insufficientMismatch - report.severityOnly;

crossTab = zeros(5, 5);
mismatchAt = find(mismatch);
for position = 1:numel(mismatchAt)
    row = cnnLevel(mismatchAt(position)) + 1;
    column = ruleLevel(mismatchAt(position)) + 1;
    if row >= 1 && row <= 5 && column >= 1 && column <= 5
        crossTab(row, column) = crossTab(row, column) + 1;
    end
end
report.crossTab = crossTab;

observed = ruleLevel(~isnan(ruleLevel));
if isempty(observed)
    report.ruleCeiling = NaN;
else
    report.ruleCeiling = max(observed);
end

% Mismatches the ceiling makes unreachable: the rule engine has no way to
% return a level above its ceiling, so a CNN prediction above it can never
% be matched however good either channel becomes.
report.unreachableAboveCeiling = sum(mismatch & cnnLevel > report.ruleCeiling);
end

% ------------------------------------------------------------- reporting

function localPrintReport(report)
fprintf('\n==== %s (rule levels from %s) ====\n', report.fullId, report.ruleId);
fprintf('%s\n', report.label);
fprintf('n = %d, escalated = %d (%.1f%%), autonomous coverage = %.3f\n', ...
    report.n, report.escalated, 100 * report.escalated / report.n, ...
    report.coverage);
fprintf('Rule engine ICDR ceiling observed on this split: Level %d\n\n', ...
    report.ruleCeiling);

fprintf('Escalations by agreement state:\n');
fprintf('  %5d  %5.1f%%  spatial check (Grad-CAM vs lesions)\n', ...
    report.spatial, 100 * report.spatial / max(report.escalated, 1));
fprintf('  %5d  %5.1f%%  insufficient evidence\n', ...
    report.insufficient, 100 * report.insufficient / max(report.escalated, 1));
fprintf('  %5d  %5.1f%%  CNN referable, evidence unsupported\n', ...
    report.evidenceUnsupported, ...
    100 * report.evidenceUnsupported / max(report.escalated, 1));
fprintf('  %5d  %5.1f%%  evidence referable, CNN non-referable\n', ...
    report.evidenceOverDetected, ...
    100 * report.evidenceOverDetected / max(report.escalated, 1));

if report.insufficient == 0
    fprintf(['\nNo insufficient-evidence escalations: the rule engine ', ...
        'ceiling is Level %d,\nso referableLevelReachable is false and ', ...
        'the exact-level comparison never runs.\n'], report.ruleCeiling);
    return;
end

fprintf('\nOf the %d insufficient-evidence escalations:\n', report.insufficient);
fprintf('  %5d  differ on exact ICDR level\n', report.insufficientMismatch);
fprintf('  %5d  have equal levels (escalated for another reason)\n', ...
    report.insufficientLevelsEqual);

fprintf('\nOf the %d exact-level mismatches:\n', report.insufficientMismatch);
fprintf(['  %5d  %5.1f%%  agree on the referable endpoint, differ only ', ...
    'on severity\n'], report.severityOnly, ...
    100 * report.severityOnly / max(report.insufficientMismatch, 1));
fprintf('  %5d  %5.1f%%  genuinely disagree on the referable endpoint\n', ...
    report.endpointDisagreement, ...
    100 * report.endpointDisagreement / max(report.insufficientMismatch, 1));
fprintf(['  %5d  are unreachable by construction: the CNN level exceeds ', ...
    'the rule ceiling\n'], report.unreachableAboveCeiling);

fprintf('\nMismatch cross-tab (rows CNN level, columns rule level):\n');
fprintf('         rule0  rule1  rule2  rule3  rule4\n');
for row = 1:5
    fprintf('  CNN%d |', row - 1);
    fprintf(' %6d', report.crossTab(row, :));
    fprintf('\n');
end
end

% --------------------------------------------------------------- outputs

function localWriteOutputs(resultsDirectory, reports, options)
lines = {['rule_config,full_config,label,n,escalated,coverage,rule_ceiling,', ...
    'spatial,insufficient,evidence_unsupported,evidence_over_detected,', ...
    'level_mismatch,severity_only,endpoint_disagreement,', ...
    'unreachable_above_ceiling']};
for index = 1:numel(reports)
    r = reports{index};
    lines{end + 1} = sprintf( ...
        '%s,%s,"%s",%d,%d,%.6f,%d,%d,%d,%d,%d,%d,%d,%d,%d', ...
        r.ruleId, r.fullId, r.label, r.n, r.escalated, r.coverage, ...
        r.ruleCeiling, r.spatial, r.insufficient, r.evidenceUnsupported, ...
        r.evidenceOverDetected, r.insufficientMismatch, r.severityOnly, ...
        r.endpointDisagreement, r.unreachableAboveCeiling); %#ok<AGROW>
end
localWriteText(fullfile(resultsDirectory, 'level_mismatch_summary.csv'), ...
    strjoin(lines, newline));

crossLines = {'full_config,cnn_level,rule_level,count'};
for index = 1:numel(reports)
    r = reports{index};
    for row = 1:5
        for column = 1:5
            if r.crossTab(row, column) == 0
                continue;
            end
            crossLines{end + 1} = sprintf('%s,%d,%d,%d', r.fullId, ...
                row - 1, column - 1, r.crossTab(row, column)); %#ok<AGROW>
        end
    end
end
localWriteText(fullfile(resultsDirectory, 'level_cross_tab.csv'), ...
    strjoin(crossLines, newline));

save(fullfile(resultsDirectory, 'level_mismatch.mat'), 'reports', '-v7.3');
localWriteText(fullfile(resultsDirectory, 'run_options.json'), ...
    jsonencode(options, 'PrettyPrint', true));
end

% --------------------------------------------------------------- helpers

function options = localOptions(varargin)
% A leading path is accepted positionally, which is how this is called by
% hand.  inputParser cannot express that alongside a 'Run' parameter of the
% same type without ambiguity, so the positional is peeled off first: a
% first argument that is not one of the parameter names is the run path.
positionalRun = '';
names = {'Run', 'Pairs', 'ResultsRoot'};
if ~isempty(varargin) && (ischar(varargin{1}) || isstring(varargin{1})) && ...
        ~any(strcmpi(char(varargin{1}), names))
    positionalRun = char(varargin{1});
    varargin(1) = [];
end

parser = inputParser();
parser.addParameter('Run', '', @(value) ischar(value) || isstring(value));
parser.addParameter('Pairs', {'A3', 'A5'; 'A6', 'A7'; 'A8', 'A9'}, @iscell);
parser.addParameter('ResultsRoot', 'results', @(value) ischar(value) || isstring(value));
parser.parse(varargin{:});

options = struct();
options.run = char(parser.Results.Run);
if isempty(options.run)
    options.run = positionalRun;
end
options.pairs = parser.Results.Pairs;
options.resultsRoot = char(parser.Results.ResultsRoot);
end

function root = localProjectRoot()
root = fileparts(fileparts(mfilename('fullpath')));
end

function directory = localDatedDirectory(resultsRoot, suffix)
if ~isfolder(resultsRoot)
    mkdir(resultsRoot);
end
stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
directory = fullfile(resultsRoot, [stamp '_' suffix]);
counter = 0;
while isfolder(directory)
    counter = counter + 1;
    directory = fullfile(resultsRoot, sprintf('%s_%s_%d', stamp, suffix, counter));
end
mkdir(directory);
end

function localWriteText(filename, text)
fileId = fopen(filename, 'w');
if fileId == -1
    error('eval:UnwritableFile', 'Could not write %s', filename);
end
cleanup = onCleanup(@() fclose(fileId));
fwrite(fileId, text, 'char');
end
