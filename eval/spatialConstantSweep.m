function result = spatialConstantSweep(runDirectory, varargin)
%SPATIALCONSTANTSWEEP What the §8.6 spatial gate's two constants are worth.
%   RESULT = spatialConstantSweep(RUNDIRECTORY) sweeps
%   spatialAttentionCut and spatialAgreementFraction over the cached
%   evidence of an ablation run and reports, for every pair, whether the
%   gate still escalates the patients the classifier sends home.
%
%   RUNDIRECTORY must hold spatial_evidence.mat, per_case.csv and
%   ablation_summary.json from eval/ablationHarness.m.  The split and the
%   frozen threshold are read from the summary rather than assumed, so the
%   patients the gate has to catch are defined by the run's own operating
%   point and the answer records which split chose the pair.
%
%   The verdict itself comes from grade.spatialVerdict.  This function
%   mirrored it once and drifted: the copy scored candidates that all land
%   off the map as vacuous agreement, where the deployed gate escalates
%   them.  See tests/TestSpatialConstantSweep.m.
%
%   Why this is scored on a constraint before an objective.  The gate is
%   the only mechanism in the pipeline that escalates d1a24527a15d, a
%   proliferative patient the classifier calls Level 1 at 0.0593, and its
%   cleared fraction there is 0.0000.  Moving these constants to buy
%   coverage moves the cut on exactly the statistic that separates that
%   patient from the rest.  So a pair that stops escalating any of the
%   classifier's missed patients is rejected whatever it does to coverage,
%   and coverage is only read among the pairs that survive.
%
%   Neither constant was ever selected against data, so this is the first
%   time either has been.  That is also the reason to be careful with it:
%   selecting a safety gate on the split that measures it is the error
%   §10.4 and §11.1 exist to prevent, so a pair chosen here is a candidate
%   to confirm on calibration, never a value to ship off this run alone.
%
%   Name-value options:
%     'Cuts'        Attention cuts to sweep (default 0.05:0.05:0.95).
%     'Fractions'   Agreement fractions to sweep (default 0.05:0.05:0.95).
%     'Config'      Ablation id whose rows are read (default A10).
%     'ResultsRoot' Root for the dated result directory.

rng(42, 'twister');

options = localOptions(varargin{:});
runDirectory = char(runDirectory);

evidencePath = fullfile(runDirectory, 'spatial_evidence.mat');
perCasePath = fullfile(runDirectory, 'per_case.csv');
if ~isfile(evidencePath)
    error('eval:MissingSpatialEvidence', ...
        ['No spatial_evidence.mat in %s. Runs before that export carry ' ...
        'only the cleared fraction at the configured cut, which sweeps ' ...
        'the agreement fraction and cannot sweep the attention cut.'], ...
        runDirectory);
end
if ~isfile(perCasePath)
    error('eval:MissingPerCase', 'No per_case.csv in %s.', runDirectory);
end
summaryPath = fullfile(runDirectory, 'ablation_summary.json');
if ~isfile(summaryPath)
    error('eval:MissingAblationSummary', ...
        ['No ablation_summary.json in %s. The sweep reads the split and ' ...
        'the frozen threshold from it rather than assuming either, so a ' ...
        'run that does not name them cannot be swept.'], runDirectory);
end
summary = jsondecode(fileread(summaryPath));
split = string(summary.split);
threshold = summary.frozenOperatingPoint.threshold;

loaded = load(evidencePath, 'evidence');
% Pick the record for the configuration being swept. The classical and
% learned channels produce different candidates and therefore different
% evidence, so sweeping one against the other's values would measure
% nothing.
match = find(strcmp(string({loaded.evidence.config}), string(options.config)), 1);
if isempty(match)
    error('eval:EvidenceConfigMissing', ...
        'No spatial evidence recorded for %s in %s. Recorded: %s.', ...
        options.config, runDirectory, ...
        strjoin(string({loaded.evidence.config}), ', '));
end
evidence = loaded.evidence(match);
rows = readtable(perCasePath, 'TextType', 'string');
rows = rows(rows.config == string(options.config), :);
if isempty(rows)
    error('eval:ConfigNotInRun', 'No %s rows in %s.', options.config, runDirectory);
end

% Align the cached evidence to the per-case rows by image id, rather than
% assuming both are in the same order.
[found, where] = ismember(rows.image_id, evidence.imageIds);
if ~all(found)
    error('eval:EvidenceMisaligned', ...
        '%d per-case rows have no cached evidence.', sum(~found));
end
values = evidence.values(where);

% The patients the classifier sends home: truth referable, probability
% below the frozen threshold. These are what the gate has to keep catching.
mustCatch = rows.truth_referable == 1 & rows.calibrated_probability < threshold;
fprintf('%s on the %s split (n=%d): %d cases, %d of them sent home by the classifier alone.\n', ...
    options.config, split, summary.n, height(rows), sum(mustCatch));

cuts = options.cuts(:);
fractions = options.fractions(:);
gateFires = false(height(rows), numel(cuts), numel(fractions));
for cutIndex = 1:numel(cuts)
    for fractionIndex = 1:numel(fractions)
        % Ask the deployed rule rather than re-deriving it here.  A sweep
        % that mirrors the verdict is how the evaluation path drifts from
        % the pipeline while still passing its own tests, and the two
        % zero-candidate cases grade.spatialEvidence keeps distinguishable
        % are exactly what a mirror flattens: no candidates at all is
        % vacuous agreement, candidates that all land off the map is a real
        % failure to correspond that escalates at every fraction.
        configuration = struct( ...
            'spatialAttentionCut', cuts(cutIndex), ...
            'spatialAgreementFraction', fractions(fractionIndex));
        gateFires(:, cutIndex, fractionIndex) = ...
            ~cellfun(@(v) grade.spatialVerdict(v, configuration), values);
    end
end

caught = squeeze(sum(gateFires(mustCatch, :, :), 1));
fired = squeeze(sum(gateFires, 1));
required = sum(mustCatch);
admissible = caught == required;

result = struct();
result.config = string(options.config);
result.runDirectory = string(runDirectory);
result.split = split;
result.n = summary.n;
result.threshold = threshold;
result.cuts = cuts;
result.fractions = fractions;
result.mustCatch = rows.image_id(mustCatch);
result.caughtOfRequired = caught;
result.escalationLoad = fired / height(rows);
result.admissible = admissible;
result.shipped = localShippedPair();

localPrint(result, required);

if ~isempty(options.resultsRoot)
    result.resultsDirectory = localWrite(options.resultsRoot, result, required);
end
end

function shipped = localShippedPair()
%LOCALSHIPPEDPAIR The pair config/default.json actually ships.
%   Read rather than written down, so the row this sweep labels "shipped"
%   cannot go stale behind the configuration it claims to describe.  That
%   is the whole point of moving these two constants into configuration.
policy = jsondecode(fileread(fullfile(localProjectRoot(), 'config', ...
    'default.json'))).decision_policy;
shipped = struct('cut', policy.spatialAttentionCut, ...
    'fraction', policy.spatialAgreementFraction);
end

function options = localOptions(varargin)
parser = inputParser();
parser.addParameter('Cuts', 0.05:0.05:0.95);
parser.addParameter('Fractions', 0.05:0.05:0.95);
parser.addParameter('Config', 'A10');
parser.addParameter('ResultsRoot', fullfile(localProjectRoot(), 'results'));
parser.parse(varargin{:});
options = struct( ...
    'cuts', parser.Results.Cuts, ...
    'fractions', parser.Results.Fractions, ...
    'config', char(string(parser.Results.Config)), ...
    'resultsRoot', char(string(parser.Results.ResultsRoot)));
end

function localPrint(result, required)
fprintf('\nSweeping %d cuts x %d fractions.\n', ...
    numel(result.cuts), numel(result.fractions));
survivors = sum(result.admissible(:));
fprintf('%d of %d pairs still escalate all %d.\n\n', survivors, ...
    numel(result.admissible), required);

if survivors == 0
    fprintf(['No pair keeps every patient the classifier sends home. The\n' ...
        'constants cannot be tuned into something safer than they are,\n' ...
        'and the shipped pair stays.\n']);
    return;
end

load = result.escalationLoad;
load(~result.admissible) = Inf;
[best, index] = min(load(:));
[cutIndex, fractionIndex] = ind2sub(size(load), index);
shippedLoad = localLoadAt(result, result.shipped.cut, result.shipped.fraction);

fprintf('%-34s %8s %8s %16s\n', '', 'cut', 'fraction', 'escalation load');
fprintf('%-34s %8.2f %8.2f %15.1f%%\n', 'shipped', result.shipped.cut, ...
    result.shipped.fraction, 100 * shippedLoad);
fprintf('%-34s %8.2f %8.2f %15.1f%%\n', 'lowest load still catching all', ...
    result.cuts(cutIndex), result.fractions(fractionIndex), 100 * best);
fprintf(['\nSwept on the %s split. A pair chosen here is a candidate to\n' ...
    'confirm on a split that did not pick it, not a value to ship: a\n' ...
    'safety constant selected on the split that measures it will find\n' ...
    'savings bought by a patient the gate was there to catch.\n'], ...
    result.split);
end

function value = localLoadAt(result, cut, fraction)
[~, cutIndex] = min(abs(result.cuts - cut));
[~, fractionIndex] = min(abs(result.fractions - fraction));
value = result.escalationLoad(cutIndex, fractionIndex);
end

function directory = localWrite(resultsRoot, result, required)
directory = fullfile(resultsRoot, sprintf('%s_spatial_constant_sweep', ...
    char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'))));
mkdir(directory);
[cutGrid, fractionGrid] = ndgrid(result.cuts, result.fractions);
table_ = table(cutGrid(:), fractionGrid(:), result.caughtOfRequired(:), ...
    repmat(required, numel(cutGrid), 1), result.escalationLoad(:), ...
    result.admissible(:), 'VariableNames', {'attention_cut', ...
    'agreement_fraction', 'missed_patients_caught', 'missed_patients_total', ...
    'escalation_load', 'catches_all'});
writetable(table_, fullfile(directory, 'sweep.csv'));
fid = fopen(fullfile(directory, 'must_catch.txt'), 'w');
fprintf(fid, '%s\n', result.mustCatch);
fclose(fid);
fprintf('\nSweep written to %s\n', directory);
end

function root = localProjectRoot()
root = fileparts(fileparts(mfilename('fullpath')));
end
