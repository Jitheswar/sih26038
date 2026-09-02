function result = equalCoverageVeto(metricsPath, ablationPath, varargin)
%EQUALCOVERAGEVETO Apply the ADR 0001 safety veto to an ablation table.
%   RESULT = equalCoverageVeto(METRICSPATH, ABLATIONPATH) reads a full
%   metric report and an ablation table over the same split, and reports
%   for every ablated configuration how many referable patients it sent
%   home against how many the classifier alone sends home when truncated
%   to that configuration's coverage.
%
%   METRICSPATH is a results directory or a full_metrics.json written by
%   eval/fullMetricReport.m; ABLATIONPATH is a results directory or an
%   ablation_table.csv written by eval/ablationHarness.m.
%
%   Why this exists.  Configurations that decide different fractions of
%   the caseload cannot be compared on raw miss counts.  A deferral
%   pipeline sheds exactly the low-confidence cases where a classifier's
%   errors concentrate, so its count over a self-selected subset flatters
%   it against a classifier's count over everything.  The A13 rejection of
%   31 August made that comparison, and eval/metrics/riskCoverage.m had
%   already been written to prevent it: its own documentation names the
%   comparison §11.6 asks for, and ablationHarness prints "Compare A5 with
%   A1 at equal coverage" at the foot of every run.
%
%   The baseline is the classifier's own ranking, using the definitions of
%   eval/fullMetricReport.m unchanged: correctness is agreement on the
%   referable endpoint, confidence is distance from the frozen threshold.
%   Counting is false negatives only, by missesAtCoverage, because the
%   veto's subject is the patient who goes home undiagnosed.
%
%   The verdict is admissibility and nothing more.  Passing does not mean
%   adopting; above the veto a configuration is argued for from several
%   measures moving together, never from coverage, which is the reading
%   that would have selected A13.  At these magnitudes the intervals on
%   1, 2 and 4 misses overlap heavily, so the veto separates configurations
%   by direction rather than decisively, and RESULT.discriminationWarning
%   says so wherever this is reported.

rng(42, 'twister');

options = localOptions(varargin{:});
metrics = localReadMetrics(metricsPath);
table = localReadAblation(ablationPath);

if metrics.n ~= table.n(1)
    error('eval:SplitMismatch', ...
        ['The metric report covers %d cases and the ablation table %d. ' ...
        'The veto compares a configuration against the classifier over ' ...
        'the same split; two splits cannot be compared.'], ...
        metrics.n, table.n(1));
end

% The classifier alone: auto-clear below the frozen threshold, refer at or
% above it.  This reconstructs the A1 baseline rather than reading it from
% the ablation table, because the truncation needs a per-case ranking and
% the table carries only aggregates.  localVerifyBaseline checks the
% reconstruction against the table's own A1 row when it has one.
predictedReferable = metrics.referableProbability >= metrics.threshold;
truthReferable = metrics.referableLabels;
confidence = abs(metrics.referableProbability - metrics.threshold);

coverage = table.coverage;
baseline = missesAtCoverage(truthReferable, predictedReferable, ...
    confidence, coverage);

admissible = table.missed_referable <= baseline.misses;

result = struct();
result.split = metrics.split;
result.n = metrics.n;
result.threshold = metrics.threshold;
result.config = table.config;
result.coverage = coverage;
result.retainedByBaseline = baseline.retained;
result.configMisses = table.missed_referable;
result.baselineMisses = baseline.misses;
result.admissible = admissible;
result.totalBaselineMisses = baseline.totalMisses;
result.curve = baseline.curve;
result.discriminationWarning = ['Counts, not rates. The Wilson intervals ' ...
    'on these miss counts overlap heavily, so the veto separates ' ...
    'configurations by direction rather than decisively (§11.1).'];
result.baselineCheck = localVerifyBaseline(table, baseline, ...
    truthReferable, predictedReferable);

if options.print
    localPrint(result);
end
if ~isempty(options.resultsDirectory)
    localWrite(options.resultsDirectory, result, metricsPath, ablationPath);
end
end

% ------------------------------------------------------------------ reading

function options = localOptions(varargin)
parser = inputParser();
parser.addParameter('Print', true, @(v) islogical(v) && isscalar(v));
parser.addParameter('ResultsDirectory', '', @(v) ischar(v) || isstring(v));
parser.parse(varargin{:});
options = struct( ...
    'print', parser.Results.Print, ...
    'resultsDirectory', char(parser.Results.ResultsDirectory));
end

function metrics = localReadMetrics(path)
path = char(path);
if isfolder(path)
    path = fullfile(path, 'full_metrics.json');
end
if ~isfile(path)
    error('eval:MetricsNotFound', 'No full metric report at %s.', path);
end
raw = jsondecode(fileread(path));
calibrated = raw.calibration.calibrated;
metrics = struct( ...
    'split', raw.split, ...
    'n', raw.n, ...
    'threshold', raw.threshold, ...
    'referableProbability', calibrated.referableProbability(:), ...
    'referableLabels', logical(calibrated.referableLabels(:)));
end

function table = localReadAblation(path)
path = char(path);
if isfolder(path)
    path = fullfile(path, 'ablation_table.csv');
end
if ~isfile(path)
    error('eval:AblationNotFound', 'No ablation table at %s.', path);
end
table = readtable(path, 'TextType', 'string');
required = {'config', 'n', 'coverage', 'missed_referable'};
for index = 1:numel(required)
    if ~ismember(required{index}, table.Properties.VariableNames)
        error('eval:AblationTableIncomplete', ...
            'The ablation table has no %s column.', required{index});
    end
end
end

% ------------------------------------------------------------------ checking

function check = localVerifyBaseline(table, baseline, truth, predicted)
%LOCALVERIFYBASELINE Does the reconstructed classifier match the harness?
%   The baseline is rebuilt from per-case probabilities rather than read
%   from the table, so where the table happens to carry the CNN-only row
%   the two must agree.  A silent disagreement would mean the veto is
%   scoring against a classifier the harness never ran.
check = struct('compared', false, 'tableMisses', NaN, ...
    'reconstructedMisses', baseline.totalMisses, 'agrees', NaN);
row = find(strcmpi(string(table.config), "A1"), 1);
if isempty(row)
    return;
end
check.compared = true;
check.tableMisses = table.missed_referable(row);
check.agrees = check.tableMisses == baseline.totalMisses;
if ~check.agrees
    error('eval:BaselineMismatch', ...
        ['The reconstructed classifier sends %d referable patients home ' ...
        'and the harness A1 row records %d. The veto would be scoring ' ...
        'against a classifier the harness never ran.'], ...
        baseline.totalMisses, check.tableMisses);
end
% Sanity, not a tautology: the reconstruction must also route the same way.
if isnumeric(table.auto_clear(row)) && ...
        table.auto_clear(row) ~= sum(~predicted)
    error('eval:BaselineMismatch', ...
        ['The reconstructed classifier auto-clears %d cases and the ' ...
        'harness A1 row records %d.'], sum(~predicted), table.auto_clear(row));
end
end

% ------------------------------------------------------------------ output

function localPrint(result)
fprintf('\nEqual-coverage safety veto (ADR 0001)\n');
fprintf('Split %s, n %d, frozen threshold %.2f\n', ...
    result.split, result.n, result.threshold);
fprintf('The classifier alone sends %d referable patients home at full coverage.\n\n', ...
    result.totalBaselineMisses);
fprintf('%-6s %10s %8s %14s %14s %12s\n', ...
    'Cfg', 'Coverage', 'n auto', 'Sends home', 'A1 at same n', 'Admissible');
for index = 1:numel(result.coverage)
    fprintf('%-6s %10.4f %8d %14d %14d %12s\n', ...
        result.config(index), result.coverage(index), ...
        result.retainedByBaseline(index), result.configMisses(index), ...
        result.baselineMisses(index), localYesNo(result.admissible(index)));
end
fprintf('\n%s\n', result.discriminationWarning);
fprintf(['Admissibility only. Passing is not adopting: above the veto a ' ...
    'configuration\nis argued from several measures moving together, ' ...
    'never from coverage.\n\n']);
end

function text = localYesNo(value)
if value
    text = 'yes';
else
    text = 'NO';
end
end

function localWrite(directory, result, metricsPath, ablationPath)
if ~isfolder(directory)
    mkdir(directory);
end
rows = table(result.config(:), result.coverage(:), ...
    result.retainedByBaseline(:), result.configMisses(:), ...
    result.baselineMisses(:), result.admissible(:), ...
    'VariableNames', {'config', 'coverage', 'baseline_n', ...
    'config_misses', 'baseline_misses_at_equal_coverage', 'admissible'});
writetable(rows, fullfile(directory, 'equal_coverage_veto.csv'));
provenance = struct( ...
    'metricsSource', char(metricsPath), ...
    'ablationSource', char(ablationPath), ...
    'split', result.split, 'n', result.n, ...
    'threshold', result.threshold, ...
    'totalBaselineMisses', result.totalBaselineMisses, ...
    'discriminationWarning', result.discriminationWarning);
fid = fopen(fullfile(directory, 'veto_provenance.json'), 'w');
fprintf(fid, '%s', jsonencode(provenance, 'PrettyPrint', true));
fclose(fid);
end
