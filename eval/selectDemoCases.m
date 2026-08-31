function result = selectDemoCases(varargin)
%SELECTDEMOCASES Choose twelve real validation cases that demo distinct states.
%   RESULT = selectDemoCases() reads a saved ablation run and picks twelve
%   images from the validation split, one for each behaviour the screening
%   pipeline can show, and writes a manifest.
%
%   Name-value options:
%     'Run'        Path to an ablation_results.mat (default: the 30 August
%                  A1-A13 run).
%     'ConfigId'   Ablation id standing in for the deployed pipeline
%                  (default A10, which config/default.json now equals).
%     'OutputDir'  Where the manifest is written (default ~/sih-demo-cases).
%
%   Why the cases are selected from a saved run rather than hand-picked.
%   A demo case whose behaviour was assumed rather than measured will
%   eventually be shown to a judge who asks what the pipeline actually did
%   with it, and the honest answer has to already exist.  Every case below
%   is chosen by querying the recorded per-case decision of a run that is
%   already reported in §11.6, so the manifest states what the pipeline did
%   and the demo can be checked against it.
%
%   The A5 pairing.  The same run holds A5, the configuration that shipped
%   before the agreement check was repaired.  Cases where A5 escalated and
%   A10 does not are what the repair bought, and one is selected
%   deliberately, because a reviewer's first question about a change in
%   screening behaviour is which patients it moved.
%
%   Validation split only.  The test split is touched once (§11.1) and the
%   sealed set is not touched at all (§10.4), so neither may supply a demo
%   image.

rng(42, 'twister');

options = localOptions(varargin{:});
projectRoot = localProjectRoot();

runPath = options.run;
if isempty(runPath)
    runPath = fullfile(projectRoot, 'results', ...
        '20260830_232525_ablation_A1_A5', 'ablation_results.mat');
end
if ~isfile(runPath)
    error('eval:MissingAblationRun', ...
        'Ablation results do not exist: %s', runPath);
end

loaded = load(runPath, 'perConfig');
perConfig = loaded.perConfig;
deployed = localFindConfig(perConfig, options.configId);
previous = localFindConfig(perConfig, 'A5');

splitTable = readtable(fullfile(projectRoot, 'data', 'splits', ...
    'validation.csv'), 'TextType', 'string');
decisions = deployed.decisions;
caseCount = numel(decisions.decision);
if height(splitTable) ~= caseCount
    error('eval:SplitMismatch', ...
        ['The saved run covers %d cases and validation.csv holds %d rows. ' ...
        'The harness records decisions in split order, so they must ' ...
        'match for a row index to name an image.'], caseCount, ...
        height(splitTable));
end

scenarios = localScenarios();
used = false(caseCount, 1);
rows = cell(numel(scenarios), 1);

for index = 1:numel(scenarios)
    scenario = scenarios(index);
    matches = scenario.predicate(decisions, previous.decisions, splitTable);
    matches = matches(:) & ~used;

    candidates = find(matches);
    if isempty(candidates)
        rows{index} = localMissingRow(scenario);
        continue;
    end

    % Deterministic pick: the candidate whose referable probability sits
    % closest to the scenario's illustrative point, so re-running selects
    % the same image rather than whichever the split happened to order
    % first.
    [~, order] = min(abs(decisions.referableProbability(candidates) - ...
        scenario.illustrativeProbability));
    chosen = candidates(order);
    used(chosen) = true;
    rows{index} = localCaseRow(scenario, chosen, decisions, ...
        previous.decisions, splitTable);
end

manifest = vertcat(rows{:});

if ~isfolder(options.outputDir)
    mkdir(options.outputDir);
end
manifestPath = fullfile(options.outputDir, 'demo_cases.csv');
writetable(manifest, manifestPath, 'QuoteStrings', true);

result = struct();
result.manifest = manifest;
result.manifestPath = string(manifestPath);
result.runPath = string(runPath);
result.configId = string(options.configId);
result.foundCount = sum(manifest.found);

fprintf('Demo case selection from %s (%s).\n', ...
    options.configId, runPath);
fprintf('%-4s %-34s %-12s %-9s %s\n', 'No', 'Scenario', 'Decision', ...
    'Image', 'Note');
for index = 1:height(manifest)
    fprintf('%-4d %-34s %-12s %-9s %s\n', index, ...
        manifest.scenario(index), manifest.decision(index), ...
        manifest.image_id(index), manifest.note(index));
end
fprintf('\n%d of %d scenarios matched a real case.\n', ...
    result.foundCount, height(manifest));
fprintf('Manifest written to %s\n', manifestPath);
end

function scenarios = localScenarios()
%LOCALSCENARIOS The twelve behaviours worth showing, and how to find one.
%   Each predicate reads the recorded per-case decision.  Nothing here
%   inspects an image: the scenario is defined by what the pipeline did.
%
%   Most predicates match on the reason code the policy raised rather than
%   on a derived flag, because the reason code is what the report prints
%   and what a judge will ask about.  The distinct codes over A10 and the
%   count of each are listed in the §11.6 entry; the scarce ones are
%   selected before the common ones so a plentiful scenario cannot consume
%   the only case a rare one had.

scenarios = struct('name', {}, 'note', {}, 'illustrativeProbability', {}, ...
    'predicate', {});

scenarios(end + 1) = localScenario( ...
    'Auto-clear, healthy eye', ...
    'Cleared without a human. The common case a screening programme needs.', ...
    0.02, @(d, ~, s) d.decision == "auto-clear" & s.grade == 0);

% Level 3, not Level 4.  decision_policy.alwaysEscalateLevel4 makes
% "auto-refer at Level 4" unreachable by construction: proliferative
% disease always goes to a human, so no case can ever match it.  Asking
% for one returned nothing, which is the policy working rather than a gap
% in the split, and the Level 4 scenario below is where it is demonstrated.
scenarios(end + 1) = localScenario( ...
    'Auto-refer, severe disease', ...
    'Referred without a human at high calibrated probability.', ...
    0.99, @(d, ~, ~) d.decision == "refer" & d.predictedLevel == 3);

scenarios(end + 1) = localScenario( ...
    'Auto-refer, moderate disease', ...
    'Referred at a mid ICDR level, not only the obvious end of the scale.', ...
    0.85, @(d, ~, ~) d.decision == "refer" & d.predictedLevel == 2);

% The quality gate is the pipeline's first module (§5, R1.1-R1.3) and was
% missing from the first version of this list, which is how a demo can run
% twelve cases without once showing the stage that runs before any model.
scenarios(end + 1) = localScenario( ...
    'Quality gate, borderline capture', ...
    ['The image is not clearly gradable, so the quality gate says so ' ...
    'before any model is trusted. This is the first stage of the ' ...
    'pipeline and the one a rural capture actually stresses.'], ...
    0.50, @(d, ~, ~) contains(d.reason, ...
        "borderline-quality-not-clearly-gradable"));

scenarios(end + 1) = localScenario( ...
    'Referable, held back from auto-refer', ...
    ['Both channels agree the patient is referable and the pipeline ' ...
    'still declines to refer on its own. The safe failure the three-way ' ...
    'policy exists to produce (§4.2).'], ...
    0.50, @(d, ~, ~) contains(d.reason, "referable-case-not-ready-to-refer"));

scenarios(end + 1) = localScenario( ...
    'Escalate, evidence refers and CNN does not', ...
    ['The lesion channel finds referable disease the classifier missed. ' ...
    'The disagreement runs this direction as well as the other, and this ' ...
    'is the direction that protects the patient.'], ...
    0.30, @(d, ~, ~) contains(d.reason, "evidence-referable-cnn-nonreferable"));

scenarios(end + 1) = localScenario( ...
    'Escalate, insufficient evidence', ...
    'The two channels disagree about referral itself, not about severity.', ...
    0.50, @(d, ~, ~) contains(d.reason, "insufficient-explanation-evidence"));

scenarios(end + 1) = localScenario( ...
    'Escalate, Level 4 always to a human', ...
    'Proliferative disease is never auto-handled, whatever the confidence.', ...
    0.95, @(d, ~, ~) contains(d.reason, "cnn-level-4"));

scenarios(end + 1) = localScenario( ...
    'Escalate, explanation not spatial', ...
    'Grad-CAM did not land on the lesion evidence, so a human sees it.', ...
    0.50, @(d, ~, ~) contains(d.reason, "explanation-disagreement"));

scenarios(end + 1) = localScenario( ...
    'Escalate, borderline probability', ...
    'Sits near the frozen 0.40 operating point; deferral is the point.', ...
    0.40, @(d, ~, ~) d.decision == "escalate" & ...
        abs(d.referableProbability - 0.40) < 0.08);

scenarios(end + 1) = localScenario( ...
    'Rule engine reaches Level 2', ...
    ['Hard-exudate evidence lifts the rule ceiling off Level 1, which is ' ...
    'what the learned channel bought and what A10 stopped punishing.'], ...
    0.60, @(d, ~, ~) d.ruleLevel >= 2);

scenarios(end + 1) = localScenario( ...
    'The A10 repair, in one patient', ...
    'A5 escalated this; A10 does not. Same image, same model, same point.', ...
    0.20, @(d, p, ~) d.autonomous & ~p.autonomous);
end

function scenario = localScenario(name, note, illustrativeProbability, ...
    predicate)
scenario = struct('name', string(name), 'note', string(note), ...
    'illustrativeProbability', illustrativeProbability, ...
    'predicate', predicate);
end

function row = localCaseRow(scenario, index, decisions, previous, splitTable)
row = table();
row.scenario = scenario.name;
row.found = true;
row.image_id = splitTable.image_id(index);
row.relative_path = splitTable.relative_path(index);
row.true_grade = splitTable.grade(index);
row.decision = decisions.decision(index);
row.autonomous = decisions.autonomous(index);
row.cnn_level = decisions.predictedLevel(index);
row.rule_level = decisions.ruleLevel(index);
row.referable_probability = decisions.referableProbability(index);
row.agreement_status = decisions.agreementStatus(index);
row.spatially_agree = decisions.spatiallyAgree(index);
row.evidence_supports_cnn = decisions.evidenceSupportsCNN(index);
row.candidate_count = decisions.candidateCount(index);
row.previous_decision = previous.decision(index);
row.reason = decisions.reason(index);
row.note = scenario.note;
end

function row = localMissingRow(scenario)
%LOCALMISSINGROW Record a scenario no real case matched.
%   A scenario with no match is reported as unmatched rather than filled
%   with the nearest thing.  A demo case that does not do what its label
%   says is worse than a missing one, and which behaviours the validation
%   split does not contain is itself worth knowing.

row = table();
row.scenario = scenario.name;
row.found = false;
row.image_id = "";
row.relative_path = "";
row.true_grade = NaN;
row.decision = "";
row.autonomous = false;
row.cnn_level = NaN;
row.rule_level = NaN;
row.referable_probability = NaN;
row.agreement_status = "";
row.spatially_agree = false;
row.evidence_supports_cnn = false;
row.candidate_count = NaN;
row.previous_decision = "";
row.reason = "";
row.note = "No case in the validation split matched this scenario.";
end

function configEntry = localFindConfig(perConfig, configId)
index = find(arrayfun(@(x) string(x.id) == string(configId), perConfig), 1);
if isempty(index)
    error('eval:MissingConfiguration', ...
        'The saved run has no configuration %s.', configId);
end
configEntry = perConfig(index);
end

function options = localOptions(varargin)
parser = inputParser();
parser.addParameter('Run', '');
parser.addParameter('ConfigId', 'A10');
parser.addParameter('OutputDir', fullfile(getenv('HOME'), 'sih-demo-cases'));
parser.parse(varargin{:});

options = struct();
options.run = char(parser.Results.Run);
options.configId = char(parser.Results.ConfigId);
options.outputDir = char(parser.Results.OutputDir);
end

function projectRoot = localProjectRoot()
thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
end
