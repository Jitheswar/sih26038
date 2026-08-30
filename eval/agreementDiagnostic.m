function result = agreementDiagnostic(varargin)
%AGREEMENTDIAGNOSTIC Why does the full pipeline escalate most of its caseload?
%   RESULT = agreementDiagnostic() runs the ablation configurations that
%   carry the agreement check and counts, per escalated case, which of the
%   §8.6 agreement states caused the escalation.
%
%   This is a read-only measurement.  It selects nothing, changes no
%   threshold, and writes no configuration.  It exists because the headline
%   ablation numbers say the full pipeline escalates 399 of 550 cases (A5)
%   and 512 of 550 (A9) without saying which mechanism did it, and the
%   reason-code string alone cannot separate the two routes to
%   "insufficient evidence": a missing input, versus an exact ICDR level
%   mismatch between two channels that both call the case referable.
%
%   Name-value options:
%     'Configs'     Ablation configuration filenames (default A5, A7, A9).
%     'Split'       Committed split name (default "validation").
%     'Limit'       Evaluate only the first N images.  Pilot runs only.
%     'ResultsRoot' Root for the dated result directory.
%
%   What it reports, per configuration:
%
%     Escalation cause
%         Every escalated case attributed to exactly one cause, taken as
%         the first mandatory reason code the policy raised.  A case with
%         several causes is counted once, under the first, so the column
%         sums to the escalation count rather than over-counting.
%
%     Insufficient-evidence split
%         The "insufficient evidence" state separated into its two routes.
%         Missing-input cases lack a channel.  Level-mismatch cases have
%         both channels present and disagreeing on the exact ICDR level,
%         including cases where both channels call the image referable and
%         differ only on how severe it is.  The screening endpoint is
%         binary (§11.2), so a Level 2 versus Level 3 disagreement escalates
%         a case on which both channels already agree about the decision
%         the system exists to make.
%
%     Spatial-check share
%         How many escalations fired the Grad-CAM spatial check.  §8.3
%         records that a 448x448 input gives a 14x14 Grad-CAM map, so one
%         cell covers about 32x32 pixels and the method "physically cannot
%         localise a microaneurysm".  §8.6 accordingly specifies the
%         spatially-inconsistent state as a report flag with escalation to
%         be *considered*, not a mandatory gate.  Whether the implemented
%         gate matches that intent is a design question this measurement
%         informs but does not settle, so the number is reported as a lower
%         bound on what relaxing the gate could return: it counts cases
%         escalated solely by that code, and those cases would still have to
%         pass the remaining agreement states to be handled autonomously.

rng(42, 'twister');

options = localOptions(varargin{:});
projectRoot = localProjectRoot();

harnessArguments = {'Configs', options.configs, 'Split', options.split, ...
    'ResultsRoot', options.resultsRoot};
if ~isempty(options.limit)
    harnessArguments = [harnessArguments, {'Limit', options.limit}];
end

fprintf('Agreement diagnostic over %s.\n\n', strjoin(options.configs, ' '));
harnessResult = ablationHarness(harnessArguments{:});

resultsDirectory = localDatedDirectory( ...
    fullfile(projectRoot, options.resultsRoot), 'agreement_diagnostic');

perConfig = harnessResult.metrics;
reports = cell(numel(perConfig), 1);
for index = 1:numel(perConfig)
    reports{index} = localDiagnose(perConfig(index));
    localPrintReport(reports{index});
end

localWriteOutputs(resultsDirectory, reports, options, harnessResult);

result = struct();
result.status = "completed";
result.split = string(options.split);
result.reports = reports;
result.resultsDirectory = string(resultsDirectory);
fprintf('\nDiagnostic written to %s\n', resultsDirectory);
end

% ------------------------------------------------------------- diagnosis

function report = localDiagnose(metrics)
%LOCALDIAGNOSE Attribute every escalated case to one cause.

decisions = metrics.decisions;
escalated = strcmp(decisions.decision, "escalate");

report = struct();
report.id = metrics.id;
report.label = metrics.label;
report.n = numel(escalated);
report.escalated = sum(escalated);
report.coverage = metrics.coverage;

% The causes, in attribution priority order.
%
% Build-level disclosures ('evidence-capability-gap',
% 'unknown-neovascularisation-status', 'candidate-evidence-provisional') are
% deliberately absent.  The policy appends them to every case's reason codes
% without their forcing escalation, and its own comment says why: they are
% true of every image and therefore cannot discriminate between cases.
% Counting them as causes would attribute every escalation to the build
% rather than to the image.
%
% The two ready-to-decide codes come last.  They are raised only when no
% mandatory safety code fired at all, so they carry real information -
% the case cleared every safety check and still failed the positive
% conditions for refer or auto-clear - but any mandatory cause present
% alongside them is the better explanation.
causes = { ...
    'missing-quality-input', ...
    'quality-ungradable', ...
    'borderline-quality-not-clearly-gradable', ...
    'invalid-quality-class', ...
    'missing-cnn-prediction', ...
    'missing-calibrated-probability', ...
    'invalid-calibrated-probability', ...
    'high-uncertainty', ...
    'missing-rule-evidence', ...
    'required-evidence-unknown', ...
    'explanation-disagreement', ...
    'cnn-referable-evidence-unsupported', ...
    'evidence-referable-cnn-nonreferable', ...
    'insufficient-explanation-evidence', ...
    'cnn-level-4', ...
    'rule-engine-recommends-escalation', ...
    'referable-case-not-ready-to-refer', ...
    'case-not-ready-to-auto-clear'};

counts = zeros(numel(causes), 1);
soleCause = zeros(numel(causes), 1);
attributed = false(report.n, 1);
indices = find(escalated);
for position = 1:numel(indices)
    index = indices(position);
    codes = strsplit(decisions.reason(index), ',');
    present = ismember(causes, codes);
    if ~any(present)
        continue;
    end
    first = find(present, 1);
    counts(first) = counts(first) + 1;
    attributed(index) = true;
    if sum(present) == 1
        soleCause(first) = soleCause(first) + 1;
    end
end

report.causes = causes(:);
report.causeCounts = counts;
report.causeSoleCounts = soleCause;
report.unattributed = report.escalated - sum(counts);

% The two routes to "insufficient evidence", separated.  A missing input is
% a real gap in what the pipeline could observe.  A level mismatch is two
% present channels disagreeing on severity, which for a binary screening
% endpoint may or may not be a disagreement that matters.
insufficient = escalated & strcmp(decisions.agreementStatus, "insufficient evidence");
fullScale = contains(decisions.agreementBasis, "full scale");
levelKnown = ~isnan(decisions.ruleLevel) & ~isnan(decisions.predictedLevel);
mismatch = insufficient & fullScale & levelKnown & ...
    decisions.ruleLevel ~= decisions.predictedLevel;
missingInput = insufficient & ~mismatch;

report.insufficientTotal = sum(insufficient);
report.insufficientLevelMismatch = sum(mismatch);
report.insufficientMissingInput = sum(missingInput);

% Of the level mismatches, how many are disagreements about severity only,
% both channels already agreeing on the referable/not-referable endpoint
% that §11.2 names as primary?
bothReferable = mismatch & decisions.ruleLevel >= 2 & decisions.predictedLevel >= 2;
bothNonReferable = mismatch & decisions.ruleLevel < 2 & decisions.predictedLevel < 2;
report.mismatchAgreeOnReferable = sum(bothReferable | bothNonReferable);
report.mismatchDisagreeOnReferable = report.insufficientLevelMismatch - ...
    report.mismatchAgreeOnReferable;

% Level cross-tabulation over the mismatching cases, CNN level by rule
% level, so the shape of the disagreement is visible and not just its size.
crossTab = zeros(5, 5);
mismatchIndices = find(mismatch);
for position = 1:numel(mismatchIndices)
    index = mismatchIndices(position);
    row = decisions.predictedLevel(index) + 1;
    column = decisions.ruleLevel(index) + 1;
    if row >= 1 && row <= 5 && column >= 1 && column <= 5
        crossTab(row, column) = crossTab(row, column) + 1;
    end
end
report.levelCrossTab = crossTab;

spatialIndex = find(strcmp(causes, 'explanation-disagreement'), 1);
report.spatialEscalations = counts(spatialIndex);
report.spatialSoleCause = soleCause(spatialIndex);

% Cases that cleared every mandatory safety check and still escalated,
% broken down by which positive condition for refer they failed.  Without
% this the ready-to-refer code says only that something was not satisfied.
%
% The comparison is against the policy's own referral gate, not against
% frozen.threshold.  Those are different numbers with different jobs: 0.40
% is the operating point the reported sensitivity and specificity are
% measured at, while the policy refers only at referableThreshold and
% clears only below autoClearThreshold.  A case between the two escalates
% because the policy was asked to defer it, which is the deferral band
% working, not a failure of the agreement check.
referralGate = decisions.policyReferableThreshold;
clearGate = decisions.policyAutoClearThreshold;
report.referralGate = referralGate;
report.autoClearGate = clearGate;

readyToRefer = escalated & contains(decisions.reason, "referable-case-not-ready-to-refer");
report.notReadyToRefer = sum(readyToRefer);
report.notReadyBelowThreshold = sum(readyToRefer & ...
    decisions.referableProbability < referralGate);
report.notReadyInDeferralBand = sum(readyToRefer & ...
    decisions.referableProbability >= clearGate & ...
    decisions.referableProbability < referralGate);
report.notReadyEvidenceUnsupported = sum(readyToRefer & ~decisions.evidenceSupportsCNN);
report.notReadyNotConcordant = sum(readyToRefer & ...
    ~strcmp(decisions.agreementStatus, "concordant"));

notReadyToClear = escalated & contains(decisions.reason, "case-not-ready-to-auto-clear");
report.notReadyToClear = sum(notReadyToClear);
report.notReadyToClearAboveGate = sum(notReadyToClear & ...
    decisions.referableProbability >= clearGate);
report.notReadyToClearNotConcordant = sum(notReadyToClear & ...
    ~strcmp(decisions.agreementStatus, "concordant"));

% Agreement status over every case the policy actually evaluated, escalated
% or not.  The cause table says what escalated; this says how often each
% §8.6 state was reached at all, which is what a state's gate is worth.
evaluated = strlength(decisions.agreementStatus) > 0;
statuses = decisions.agreementStatus(evaluated);
[uniqueStatus, ~, group] = unique(statuses);
statusCounts = accumarray(group, 1);
[statusCounts, order] = sort(statusCounts, 'descend');
report.agreementStates = uniqueStatus(order);
report.agreementStateCounts = statusCounts;
report.agreementEvaluated = sum(evaluated);
end

% ------------------------------------------------------------- reporting

function localPrintReport(report)
fprintf('\n==== %s ====\n', report.id);
fprintf('%s\n', report.label);
fprintf('n = %d, escalated = %d (%.1f%%), autonomous coverage = %.3f\n\n', ...
    report.n, report.escalated, 100 * report.escalated / report.n, ...
    report.coverage);

fprintf('Escalation cause (each case counted once, under its first cause):\n');
[sorted, order] = sort(report.causeCounts, 'descend');
for index = 1:numel(sorted)
    if sorted(index) == 0
        continue;
    end
    fprintf('  %5d  %5.1f%%  %-45s (sole cause: %d)\n', sorted(index), ...
        100 * sorted(index) / report.escalated, report.causes{order(index)}, ...
        report.causeSoleCounts(order(index)));
end
if report.unattributed > 0
    fprintf('  %5d  unattributed\n', report.unattributed);
end

fprintf('\nInsufficient evidence, by route:\n');
fprintf('  %5d  total\n', report.insufficientTotal);
fprintf('  %5d  missing input (a channel was absent or unknown)\n', ...
    report.insufficientMissingInput);
fprintf('  %5d  exact ICDR level mismatch, both channels present\n', ...
    report.insufficientLevelMismatch);
fprintf('           of which %d agree on referable/not and differ only on severity\n', ...
    report.mismatchAgreeOnReferable);
fprintf('           of which %d genuinely disagree on the referable endpoint\n', ...
    report.mismatchDisagreeOnReferable);

if any(report.levelCrossTab(:))
    fprintf('\nLevel mismatch cross-tab (rows CNN level 0-4, columns rule level 0-4):\n');
    for row = 1:5
        fprintf('  %d |', row - 1);
        fprintf(' %4d', report.levelCrossTab(row, :));
        fprintf('\n');
    end
end

if report.notReadyToRefer > 0
    fprintf('\nCleared every safety check but still did not refer (%d cases):\n', ...
        report.notReadyToRefer);
    fprintf('  %5d  probability below the policy referral gate (%.2f)\n', ...
        report.notReadyBelowThreshold, report.referralGate);
    fprintf('  %5d  of those sit in the deferral band [%.2f, %.2f)\n', ...
        report.notReadyInDeferralBand, report.autoClearGate, report.referralGate);
    fprintf('  %5d  lesion evidence did not support the CNN\n', ...
        report.notReadyEvidenceUnsupported);
    fprintf('  %5d  agreement status was not concordant\n', ...
        report.notReadyNotConcordant);
end

if report.notReadyToClear > 0
    fprintf('\nCleared every safety check but still did not auto-clear (%d cases):\n', ...
        report.notReadyToClear);
    fprintf('  %5d  probability at or above the auto-clear gate (%.2f)\n', ...
        report.notReadyToClearAboveGate, report.autoClearGate);
    fprintf('  %5d  agreement status was not concordant\n', ...
        report.notReadyToClearNotConcordant);
end

fprintf('\nAgreement state reached, over all %d evaluated cases:\n', ...
    report.agreementEvaluated);
for index = 1:numel(report.agreementStates)
    fprintf('  %5d  %5.1f%%  %s\n', report.agreementStateCounts(index), ...
        100 * report.agreementStateCounts(index) / report.agreementEvaluated, ...
        report.agreementStates(index));
end

fprintf('\nGrad-CAM spatial check (§8.3, §8.6):\n');
fprintf('  %5d  escalations fired explanation-disagreement (%.1f%% of escalations)\n', ...
    report.spatialEscalations, ...
    100 * report.spatialEscalations / max(report.escalated, 1));
fprintf('  %5d  of those had no other mandatory cause\n', report.spatialSoleCause);
end

% --------------------------------------------------------------- outputs

function localWriteOutputs(resultsDirectory, reports, options, harnessResult)
lines = {['config,label,n,escalated,coverage,spatial_escalations,', ...
    'spatial_sole_cause,insufficient_total,insufficient_missing_input,', ...
    'insufficient_level_mismatch,mismatch_agree_on_referable,', ...
    'mismatch_disagree_on_referable,referral_gate,auto_clear_gate,', ...
    'not_ready_to_refer,not_ready_below_gate,not_ready_in_deferral_band,', ...
    'not_ready_evidence_unsupported,not_ready_not_concordant,', ...
    'not_ready_to_clear,not_ready_to_clear_above_gate']};
for index = 1:numel(reports)
    r = reports{index};
    lines{end + 1} = sprintf( ...
        '%s,"%s",%d,%d,%.6f,%d,%d,%d,%d,%d,%d,%d,%.4f,%.4f,%d,%d,%d,%d,%d,%d,%d', ...
        r.id, r.label, r.n, r.escalated, r.coverage, r.spatialEscalations, ...
        r.spatialSoleCause, r.insufficientTotal, r.insufficientMissingInput, ...
        r.insufficientLevelMismatch, r.mismatchAgreeOnReferable, ...
        r.mismatchDisagreeOnReferable, r.referralGate, r.autoClearGate, ...
        r.notReadyToRefer, r.notReadyBelowThreshold, ...
        r.notReadyInDeferralBand, r.notReadyEvidenceUnsupported, ...
        r.notReadyNotConcordant, r.notReadyToClear, ...
        r.notReadyToClearAboveGate); %#ok<AGROW>
end

statusLines = {'config,agreement_state,count'};
for index = 1:numel(reports)
    r = reports{index};
    for stateIndex = 1:numel(r.agreementStates)
        statusLines{end + 1} = sprintf('%s,"%s",%d', r.id, ...
            r.agreementStates(stateIndex), ...
            r.agreementStateCounts(stateIndex)); %#ok<AGROW>
    end
end
localWriteText(fullfile(resultsDirectory, 'agreement_states.csv'), ...
    strjoin(statusLines, newline));
localWriteText(fullfile(resultsDirectory, 'agreement_summary.csv'), ...
    strjoin(lines, newline));

causeLines = {'config,cause,count,sole_cause_count'};
for index = 1:numel(reports)
    r = reports{index};
    for causeIndex = 1:numel(r.causes)
        if r.causeCounts(causeIndex) == 0
            continue;
        end
        causeLines{end + 1} = sprintf('%s,%s,%d,%d', r.id, ...
            r.causes{causeIndex}, r.causeCounts(causeIndex), ...
            r.causeSoleCounts(causeIndex)); %#ok<AGROW>
    end
end
localWriteText(fullfile(resultsDirectory, 'escalation_causes.csv'), ...
    strjoin(causeLines, newline));

save(fullfile(resultsDirectory, 'agreement_diagnostic.mat'), 'reports', '-v7.3');
localWriteText(fullfile(resultsDirectory, 'run_options.json'), ...
    jsonencode(options, 'PrettyPrint', true));
localWriteText(fullfile(resultsDirectory, 'harness_run.json'), ...
    jsonencode(rmfield(harnessResult, 'metrics'), 'PrettyPrint', true));
end

% --------------------------------------------------------------- helpers

function options = localOptions(varargin)
parser = inputParser();
% A5 is the shipped pipeline (pipeline.learned_lesion_evidence is false) and
% A9 is the best measured learned-channel pipeline.  A7 is deliberately not
% in the default set: its four-head channel refers every frame and was
% superseded on 30 August, so a pass over it costs a third of the run time
% to diagnose a configuration nothing would ship.  Pass it explicitly if the
% comparison is wanted.
parser.addParameter('Configs', {'ablation_A5.json', 'ablation_A9.json'}, ...
    @iscellstr);
parser.addParameter('Split', 'validation', @(value) ischar(value) || isstring(value));
parser.addParameter('Limit', [], @(value) isempty(value) || ...
    (isnumeric(value) && isscalar(value) && value > 0));
parser.addParameter('ResultsRoot', 'results', @(value) ischar(value) || isstring(value));
parser.parse(varargin{:});

options = struct();
options.configs = parser.Results.Configs;
options.split = char(parser.Results.Split);
options.limit = parser.Results.Limit;
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
