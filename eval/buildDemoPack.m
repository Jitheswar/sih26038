function result = buildDemoPack(varargin)
%BUILDDEMOPACK Run the deployed pipeline over the demo cases and export them.
%   RESULT = buildDemoPack() reads the manifest written by selectDemoCases,
%   runs app.runScreeningCase over every case with the frozen operating
%   point, exports each one's annotated report, and writes an index.
%
%   Name-value options:
%     'OutputDir'  Demo root (default ~/sih-demo-cases).
%     'Limit'      Build only the first N cases.  Pilot runs only.
%
%   This runs the same entry point the demo UI runs, `app.runScreeningCase`,
%   rather than the ablation harness.  The harness composes the modules
%   itself (§11.6) and the point of the pack is to show what the deployed
%   path does, so anything it produces has to come from the deployed path.
%   The manifest records what the harness measured for each case, and the
%   index below reports both, so a disagreement between them is visible
%   rather than hidden.

rng(42, 'twister');

options = localOptions(varargin{:});
projectRoot = localProjectRoot();

manifestPath = fullfile(options.outputDir, 'demo_cases.csv');
if ~isfile(manifestPath)
    error('eval:MissingDemoManifest', ...
        ['Demo manifest does not exist: %s. Run selectDemoCases first.'], ...
        manifestPath);
end
manifest = readtable(manifestPath, 'TextType', 'string', ...
    'Delimiter', ',', 'ReadVariableNames', true);

configPath = fullfile(projectRoot, 'config', 'default.json');
config = jsondecode(fileread(configPath));
checkpointPath = fullfile(projectRoot, config.operating_point.model);
temperature = config.operating_point.temperature;

% The case folders sit directly in the demo folder rather than under a
% further 'cases' level, so the folder a presenter opens is the folder that
% holds the twelve cases.
caseRoot = options.outputDir;
if ~isfolder(caseRoot)
    mkdir(caseRoot);
end

caseCount = height(manifest);
if options.limit > 0
    caseCount = min(caseCount, options.limit);
end

fprintf('Demo pack over %d cases.\n', caseCount);
fprintf('Frozen operating point: threshold %.2f on calibrated P(ICDR>=2), temperature %.4f.\n', ...
    config.decision_policy.autoClearThreshold, temperature);
fprintf('Checkpoint: %s\n\n', config.operating_point.model);

records = cell(caseCount, 1);
for index = 1:caseCount
    row = manifest(index, :);
    if ~row.found
        fprintf('[%2d/%2d] %-34s skipped, no case matched\n', index, ...
            caseCount, row.scenario);
        continue;
    end

    slug = localSlug(row.scenario);
    caseDir = fullfile(caseRoot, sprintf('%02d_%s', index, slug));
    if ~isfolder(caseDir)
        mkdir(caseDir);
    end

    imagePath = fullfile(projectRoot, char(row.relative_path));
    started = tic;
    screening = app.runScreeningCase(imagePath, checkpointPath, ...
        temperature, configPath);
    elapsed = toc(started);

    reportResult = report.generate(screening, 'ResultsRoot', caseDir);

    record = struct();
    record.index = index;
    record.scenario = row.scenario;
    record.note = row.note;
    record.imageId = row.image_id;
    record.trueGrade = row.true_grade;
    record.harnessDecision = row.decision;
    record.previousDecision = row.previous_decision;
    record.deployedDecision = string(screening.threeWayDecision.decision);
    record.agreementStatus = string(screening.agreementStatus);
    record.cnnLevel = screening.predictedICDRLevel;
    record.ruleLevel = screening.icdrRuleResult.level;
    record.referableProbability = screening.calibratedReferableProbability;
    record.evidenceSource = string(screening.icdrRuleResult.evidenceSource);
    record.seconds = elapsed;
    record.caseDir = string(caseDir);
    record.reportDir = string(reportResult.resultsDirectory);
    record.agrees = record.deployedDecision == record.harnessDecision;
    records{index} = record;

    localWriteText(fullfile(caseDir, 'case.json'), ...
        jsonencode(record, 'PrettyPrint', true));

    flag = "";
    if ~record.agrees
        flag = "  <-- differs from the harness";
    end
    fprintf('[%2d/%2d] %-34s %-11s %4.1fs%s\n', index, caseCount, ...
        row.scenario, record.deployedDecision, elapsed, flag);
end

records = records(~cellfun(@isempty, records));
built = vertcat(records{:});

localWriteIndex(options.outputDir, built, config);
localWriteReadme(options.outputDir, built, config);

result = struct();
result.records = built;
result.outputDir = string(options.outputDir);
result.builtCount = numel(built);
result.disagreementCount = sum(~[built.agrees]);

fprintf('\n%d cases built into %s\n', result.builtCount, options.outputDir);
if result.disagreementCount > 0
    fprintf(['%d of them decided differently from the saved harness run. ' ...
        'That is a drift signal, not a demo problem: investigate before ' ...
        'showing it.\n'], result.disagreementCount);
else
    fprintf(['Every case matched the decision the saved harness run ' ...
        'recorded for it.\n']);
end
end

function localWriteIndex(outputDir, built, config) %#ok<INUSD>
%LOCALWRITEINDEX A machine-readable summary beside the human one.
rows = table();
rows.no = [built.index]';
rows.scenario = [built.scenario]';
rows.image_id = [built.imageId]';
rows.true_grade = [built.trueGrade]';
rows.decision = [built.deployedDecision]';
rows.harness_decision = [built.harnessDecision]';
rows.agrees = [built.agrees]';
rows.cnn_level = [built.cnnLevel]';
rows.rule_level = [built.ruleLevel]';
rows.referable_probability = [built.referableProbability]';
rows.agreement_status = [built.agreementStatus]';
rows.evidence_source = [built.evidenceSource]';
rows.seconds = [built.seconds]';
writetable(rows, fullfile(outputDir, 'demo_index.csv'), 'QuoteStrings', true);
end

function localWriteReadme(outputDir, built, config)
%LOCALWRITEREADME The page a presenter actually reads before demoing.

lines = strings(0, 1);
lines(end + 1) = "# SIH26038 demo pack";
lines(end + 1) = "";
lines(end + 1) = "Twelve real cases from the APTOS validation split, one for " + ...
    "each behaviour the screening pipeline can show.";
lines(end + 1) = "";
lines(end + 1) = "Generated by `eval/buildDemoPack.m` from the case list " + ...
    "`eval/selectDemoCases.m` chose. Every case was picked by querying " + ...
    "the recorded per-case decision of the ablation run reported in " + ...
    "§11.6, so what each one demonstrates is measured rather than assumed.";
lines(end + 1) = "";
lines(end + 1) = "## What is frozen here";
lines(end + 1) = "";
lines(end + 1) = sprintf("- Checkpoint: `%s`", config.operating_point.model);
lines(end + 1) = sprintf("- Temperature: %.4f", config.operating_point.temperature);
lines(end + 1) = sprintf("- Auto-clear threshold: %.2f on calibrated P(ICDR>=2)", ...
    config.decision_policy.autoClearThreshold);
lines(end + 1) = sprintf("- Level comparison: `%s`", ...
    config.decision_policy.levelComparison);
lines(end + 1) = sprintf("- Learned lesion evidence: `%d`", ...
    config.pipeline.learned_lesion_evidence);
lines(end + 1) = "";
lines(end + 1) = "No image here comes from the test split or the sealed " + ...
    "external set. The test split is touched once (§11.1) and the sealed " + ...
    "set is not opened during development at all (§10.4).";
lines(end + 1) = "";
lines(end + 1) = "## The cases";
lines(end + 1) = "";
lines(end + 1) = "| # | Scenario | Decision | CNN / rule level | P(referable) | True grade |";
lines(end + 1) = "| --- | --- | --- | --- | --- | --- |";
for index = 1:numel(built)
    record = built(index);
    lines(end + 1) = sprintf("| %d | %s | %s | %d / %d | %.4f | %d |", ...
        record.index, record.scenario, record.deployedDecision, ...
        record.cnnLevel, record.ruleLevel, record.referableProbability, ...
        record.trueGrade); %#ok<AGROW>
end
lines(end + 1) = "";
lines(end + 1) = "### What each one is for";
lines(end + 1) = "";
for index = 1:numel(built)
    record = built(index);
    lines(end + 1) = sprintf("%d. **%s** (`%s`) - %s", record.index, ...
        record.scenario, record.imageId, record.note); %#ok<AGROW>
end
lines(end + 1) = "";
lines(end + 1) = "## Honesty notes for the presenter";
lines(end + 1) = "";
lines(end + 1) = "- The lesion evidence is provisional. It is candidate " + ...
    "evidence, not clinically validated segmentation, and the report says " + ...
    "so on every case. Say it before a judge asks.";
lines(end + 1) = "- Six of the eight ICDR evidence fields have no detector " + ...
    "in this build. The rule engine declares that a capability gap rather " + ...
    "than a per-case unknown, because a permanent restriction presented " + ...
    "as a per-case unknown would escalate every patient.";
lines(end + 1) = "- Escalation is a designed output, not a failure. Case " + ...
    "12 is a referable patient the pipeline declined to decide, and that " + ...
    "is the safe failure the three-way policy exists to produce (§4.2).";
lines(end + 1) = "- Neovascularisation has no detector at all (§6.6, a " + ...
    "declared data gap), so ICDR Level 4 can never be reached from " + ...
    "evidence alone.";
lines(end + 1) = "- This is a screening aid and research prototype, not a " + ...
    "medical device and not a clinical diagnosis.";
lines(end + 1) = "";
lines(end + 1) = "## Rerunning";
lines(end + 1) = "";
lines(end + 1) = "```bash";
lines(end + 1) = "matlab -batch ""addpath(genpath('src')); " + ...
    "addpath('eval'); selectDemoCases(); buildDemoPack()""";
lines(end + 1) = "```";
lines(end + 1) = "";

localWriteText(fullfile(outputDir, 'README.md'), ...
    strjoin(lines, newline) + newline);
end

function slug = localSlug(text)
slug = lower(char(text));
slug = regexprep(slug, '[^a-z0-9]+', '_');
slug = regexprep(slug, '^_+|_+$', '');
end

function localWriteText(path, text)
fileId = fopen(path, 'w');
if fileId == -1
    error('eval:CannotWrite', 'Could not open %s for writing.', path);
end
cleanup = onCleanup(@() fclose(fileId)); %#ok<NASGU>
fwrite(fileId, char(text), 'char');
end

function options = localOptions(varargin)
parser = inputParser();
parser.addParameter('OutputDir', fullfile(getenv('HOME'), 'sih-demo-cases'));
parser.addParameter('Limit', 0);
parser.parse(varargin{:});

options = struct();
options.outputDir = char(parser.Results.OutputDir);
options.limit = double(parser.Results.Limit);
end

function projectRoot = localProjectRoot()
thisFile = mfilename('fullpath');
projectRoot = fileparts(fileparts(thisFile));
end
