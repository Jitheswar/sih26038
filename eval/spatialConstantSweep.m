function result = spatialConstantSweep(runDirectory, varargin)
%SPATIALCONSTANTSWEEP What the §8.6 spatial gate's two constants are worth.
%   RESULT = spatialConstantSweep(RUNDIRECTORY) sweeps
%   spatialAttentionCut and spatialAgreementFraction over the cached
%   evidence of an ablation run and reports, for every pair, whether the
%   gate still escalates the patients the classifier sends home.
%
%   RUNDIRECTORY must hold spatial_evidence.mat and per_case.csv from
%   eval/ablationHarness.m.
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
mustCatch = rows.truth_referable == 1 & rows.calibrated_probability < 0.40;
fprintf('%s: %d cases, %d of them sent home by the classifier alone.\n', ...
    options.config, height(rows), sum(mustCatch));

cuts = options.cuts(:);
fractions = options.fractions(:);
gateFires = false(height(rows), numel(cuts), numel(fractions));
for cutIndex = 1:numel(cuts)
    cleared = cellfun(@(v) localCleared(v, cuts(cutIndex)), values);
    for fractionIndex = 1:numel(fractions)
        % The gate fires (escalates) when the cleared fraction falls short.
        gateFires(:, cutIndex, fractionIndex) = ...
            cleared < fractions(fractionIndex);
    end
end

caught = squeeze(sum(gateFires(mustCatch, :, :), 1));
fired = squeeze(sum(gateFires, 1));
required = sum(mustCatch);
admissible = caught == required;

result = struct();
result.config = string(options.config);
result.runDirectory = string(runDirectory);
result.cuts = cuts;
result.fractions = fractions;
result.mustCatch = rows.image_id(mustCatch);
result.caughtOfRequired = caught;
result.escalationLoad = fired / height(rows);
result.admissible = admissible;
result.shipped = struct('cut', 0.35, 'fraction', 0.25);

localPrint(result, required);

if ~isempty(options.resultsRoot)
    result.resultsDirectory = localWrite(options.resultsRoot, result, required);
end
end

function cleared = localCleared(entry, cut)
%LOCALCLEARED The fraction of candidate points reaching CUT.
%   Mirrors grade.spatialVerdict: no usable heatmap is not agreement, and
%   no candidates at all is vacuous agreement, which is expressed here as a
%   cleared fraction of 1 so that no fraction threshold ever fires on it.
if isempty(entry) || ~entry.known
    cleared = 0;
    return;
end
if entry.candidatesScored == 0
    cleared = 1;
    return;
end
cleared = mean(entry.values >= cut);
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
fprintf(['\nA pair here is a candidate to confirm on calibration, not a\n' ...
    'value to ship: it was chosen on the split that measures it.\n']);
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
