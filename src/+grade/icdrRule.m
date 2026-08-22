function result = icdrRule(inputEvidence)
%ICDRRULE Apply deterministic ICDR 0-4 rules to structured evidence.
%   RESULT = grade.icdrRule(EVIDENCE) evaluates candidate or clinical
%   evidence independently of any neural network.
%
%   Each clinical field in EVIDENCE is a structure with VALUE and KNOWN.
%   Unknown evidence uses KNOWN=false and VALUE=[].  Candidate evidence is
%   never described as clinically confirmed by this function.

evidence = validateICDREvidence(inputEvidence);

unknownFields = localUnknownFields(evidence);
hasUnknown = ~isempty(unknownFields);

proliferativeCriteria = {};
if evidence.neovascularisation.known && evidence.neovascularisation.value
    proliferativeCriteria{end + 1} = 'neovascularisation'; %#ok<AGROW>
end
if evidence.vitreousOrPreretinalHaemorrhage.known && ...
        evidence.vitreousOrPreretinalHaemorrhage.value
    proliferativeCriteria{end + 1} = ...
        'vitreous-or-preretinal-haemorrhage'; %#ok<AGROW>
end

severeCriteria = {};
haemorrhageCriterionEvaluated = evidence.haemorrhageCountPerQuadrant.known;
haemorrhageCriterionFired = haemorrhageCriterionEvaluated && ...
    all(evidence.haemorrhageCountPerQuadrant.value > 20);
if haemorrhageCriterionFired
    severeCriteria{end + 1} = ...
        'more-than-20-haemorrhages-in-each-of-four-quadrants'; %#ok<AGROW>
end

beadingCriterionEvaluated = evidence.venousBeadingPerQuadrant.known;
beadingCriterionFired = beadingCriterionEvaluated && ...
    sum(evidence.venousBeadingPerQuadrant.value) >= 2;
if beadingCriterionFired
    severeCriteria{end + 1} = 'venous-beading-in-two-or-more-quadrants'; %#ok<AGROW>
end

irmaCriterionEvaluated = evidence.irmaPerQuadrant.known;
irmaCriterionFired = irmaCriterionEvaluated && ...
    any(evidence.irmaPerQuadrant.value);
if irmaCriterionFired
    severeCriteria{end + 1} = 'prominent-IRMA-in-one-or-more-quadrants'; %#ok<AGROW>
end

knownPositive = localKnownPositive(evidence);
microaneurysmsOnly = evidence.microaneurysmCount.known && ...
    evidence.microaneurysmCount.value > 0 && ...
    ~any(knownPositive(2:end));

if ~isempty(proliferativeCriteria)
    level = 4;
    firedCriterion = localJoin(proliferativeCriteria, ' plus ');
elseif ~isempty(severeCriteria)
    level = 3;
    firedCriterion = localJoin(severeCriteria, ' plus ');
elseif any(knownPositive(2:end))
    level = 2;
    firedCriterion = 'more-than-microaneurysms-without-severe-or-proliferative-criteria';
elseif microaneurysmsOnly
    level = 1;
    firedCriterion = 'microaneurysms-only';
elseif any(knownPositive)
    level = 2;
    firedCriterion = 'non-microaneurysm-evidence-present';
else
    level = 0;
    firedCriterion = 'no-apparent-retinopathy';
end

referable = level >= 2;
humanEscalation = hasUnknown || level == 4 || ...
    localIsCandidateEvidence(evidence);

result = struct();
result.icdrLevel = level;
result.level = level;
result.referable = referable;
result.firedCriterion = firedCriterion;
result.evidenceSummary = localEvidenceSummary(evidence, unknownFields);
result.uncertaintyWarning = localUncertaintyWarning(unknownFields);
result.escalationRecommendation = localEscalationRecommendation( ...
    humanEscalation, level, hasUnknown);
result.humanEscalationRecommended = humanEscalation;
result.uncertain = hasUnknown;
result.missingEvidenceFields = unknownFields;
result.evidenceSource = evidence.evidenceSource;
result.clinicalValidationStatus = evidence.clinicalValidationStatus;
result.ruleTrace = localRuleTrace(evidence, level, referable, ...
    firedCriterion, unknownFields, humanEscalation, ...
    haemorrhageCriterionEvaluated, haemorrhageCriterionFired, ...
    beadingCriterionEvaluated, beadingCriterionFired, ...
    irmaCriterionEvaluated, irmaCriterionFired, proliferativeCriteria);
end

function unknownFields = localUnknownFields(evidence)
names = { ...
    'microaneurysmCount', ...
    'haemorrhageCountPerQuadrant', ...
    'hardExudateCount', ...
    'softExudateCount', ...
    'venousBeadingPerQuadrant', ...
    'irmaPerQuadrant', ...
    'neovascularisation', ...
    'vitreousOrPreretinalHaemorrhage'};
unknownFields = {};
for index = 1:numel(names)
    if ~evidence.(names{index}).known
        unknownFields{end + 1} = names{index}; %#ok<AGROW>
    end
end
end

function positive = localKnownPositive(evidence)
positive = false(8, 1);
positive(1) = evidence.microaneurysmCount.known && ...
    evidence.microaneurysmCount.value > 0;
positive(2) = evidence.haemorrhageCountPerQuadrant.known && ...
    any(evidence.haemorrhageCountPerQuadrant.value > 0);
positive(3) = evidence.hardExudateCount.known && ...
    evidence.hardExudateCount.value > 0;
positive(4) = evidence.softExudateCount.known && ...
    evidence.softExudateCount.value > 0;
positive(5) = evidence.venousBeadingPerQuadrant.known && ...
    any(evidence.venousBeadingPerQuadrant.value);
positive(6) = evidence.irmaPerQuadrant.known && ...
    any(evidence.irmaPerQuadrant.value);
positive(7) = evidence.neovascularisation.known && ...
    evidence.neovascularisation.value;
positive(8) = evidence.vitreousOrPreretinalHaemorrhage.known && ...
    evidence.vitreousOrPreretinalHaemorrhage.value;
end

function answer = localIsCandidateEvidence(evidence)
source = lower(evidence.evidenceSource);
status = lower(evidence.clinicalValidationStatus);
answer = contains(source, 'candidate') || contains(status, 'not clinically');
end

function text = localEvidenceSummary(evidence, unknownFields)
text = sprintf(['Evidence source: %s.\n', ...
    'Clinical validation status: %s. Candidate findings are not confirmed lesions.\n', ...
    'Microaneurysm count: %s.\n', ...
    'Intraretinal haemorrhages by quadrant (ST, IT, SN, IN): %s.\n', ...
    'Hard exudate count: %s.\n', ...
    'Soft exudate count: %s.\n', ...
    'Venous beading by quadrant (ST, IT, SN, IN): %s.\n', ...
    'IRMA by quadrant (ST, IT, SN, IN): %s.\n', ...
    'Neovascularisation: %s.\n', ...
    'Vitreous or preretinal haemorrhage: %s.'], ...
    evidence.evidenceSource, evidence.clinicalValidationStatus, ...
    localCountText(evidence.microaneurysmCount), ...
    localCountVectorText(evidence.haemorrhageCountPerQuadrant), ...
    localCountText(evidence.hardExudateCount), ...
    localCountText(evidence.softExudateCount), ...
    localLogicalVectorText(evidence.venousBeadingPerQuadrant), ...
    localLogicalVectorText(evidence.irmaPerQuadrant), ...
    localLogicalText(evidence.neovascularisation), ...
    localLogicalText(evidence.vitreousOrPreretinalHaemorrhage));
if ~isempty(unknownFields)
    text = sprintf('%s\nUnknown fields: %s.', text, strjoin(unknownFields, ', '));
end
end

function text = localUncertaintyWarning(unknownFields)
if isempty(unknownFields)
    text = 'No missing evidence detected; all required evidence fields were known.';
else
    text = sprintf(['Uncertainty warning: evidence is unknown for %s. ', ...
        'Unknown evidence was not treated as zero and may conceal a more severe ICDR level.'], ...
        strjoin(unknownFields, ', '));
end
end

function text = localEscalationRecommendation(humanEscalation, level, hasUnknown)
if hasUnknown
    text = ['Escalate to human clinical review because missing evidence could affect ', ...
        'the safety of the screening result.'];
elseif level == 4
    text = ['Escalate every Level 4 result to a human reviewer because ', ...
        'neovascularisation has no validated pixel-level ground truth in this project.'];
elseif humanEscalation
    text = ['Human confirmation is recommended because this result uses ', ...
        'candidate evidence that is not clinically validated.'];
else
    text = 'No additional human escalation was triggered by the rule engine.';
end
end

function text = localRuleTrace(evidence, level, referable, firedCriterion, ...
        unknownFields, humanEscalation, haemorrhageEvaluated, haemorrhageFired, ...
        beadingEvaluated, beadingFired, irmaEvaluated, irmaFired, ...
        proliferativeCriteria)
text = sprintf(['ICDR RULE TRACE\n', ...
    'Received evidence source: %s.\n', ...
    'Received evidence status: %s.\n', ...
    'Candidate counts/statuses are evidence candidates, not clinically confirmed lesions.\n', ...
    'Microaneurysm count: %s.\n', ...
    'Haemorrhage counts (ST, IT, SN, IN): %s.\n', ...
    'Hard exudates: %s; soft exudates: %s.\n', ...
    'Venous beading (ST, IT, SN, IN): %s.\n', ...
    'IRMA (ST, IT, SN, IN): %s.\n', ...
    'Neovascularisation: %s.\n', ...
    'Vitreous/preretinal haemorrhage: %s.\n', ...
    'Threshold check - haemorrhage criterion requires strictly >20 in each of all four quadrants: %s (%s).\n', ...
    'Threshold check - venous beading criterion requires at least 2 quadrants: %s (%s).\n', ...
    'Threshold check - prominent IRMA criterion requires at least 1 quadrant: %s (%s).\n', ...
    'Level 4 criteria checked first: %s.\n', ...
    'Criterion fired: %s.\n', ...
    'Final ICDR level: %d.\n', ...
    'Referable DR: %s because referable DR is ICDR level >= 2.\n', ...
    'Human escalation recommended: %s.'], ...
    evidence.evidenceSource, evidence.clinicalValidationStatus, ...
    localCountText(evidence.microaneurysmCount), ...
    localCountVectorText(evidence.haemorrhageCountPerQuadrant), ...
    localCountText(evidence.hardExudateCount), ...
    localCountText(evidence.softExudateCount), ...
    localLogicalVectorText(evidence.venousBeadingPerQuadrant), ...
    localLogicalVectorText(evidence.irmaPerQuadrant), ...
    localLogicalText(evidence.neovascularisation), ...
    localLogicalText(evidence.vitreousOrPreretinalHaemorrhage), ...
    localEvaluatedText(haemorrhageEvaluated), localFiredText(haemorrhageFired), ...
    localEvaluatedText(beadingEvaluated), localFiredText(beadingFired), ...
    localEvaluatedText(irmaEvaluated), localFiredText(irmaFired), ...
    localCriteriaText(proliferativeCriteria), firedCriterion, level, ...
    localBooleanText(referable), localBooleanText(humanEscalation));
if isempty(unknownFields)
    text = sprintf('%s\nNo evidence fields were unknown.', text);
else
    text = sprintf('%s\nMissing/unknown evidence requiring caution: %s.', ...
        text, strjoin(unknownFields, ', '));
    text = sprintf('%s\nUnknown evidence was not treated as zero.', text);
end
end

function text = localCountText(item)
if item.known
    text = sprintf('%g (known)', item.value);
else
    text = 'unknown';
end
end

function text = localCountVectorText(item)
if item.known
    text = sprintf('[%g %g %g %g] (known)', item.value);
else
    text = 'unknown';
end
end

function text = localLogicalText(item)
if item.known
    text = localBooleanText(item.value);
else
    text = 'unknown';
end
end

function text = localLogicalVectorText(item)
if item.known
    text = sprintf('[%s %s %s %s] (known)', ...
        localBooleanText(item.value(1)), localBooleanText(item.value(2)), ...
        localBooleanText(item.value(3)), localBooleanText(item.value(4)));
else
    text = 'unknown';
end
end

function text = localBooleanText(value)
if value
    text = 'true';
else
    text = 'false';
end
end

function text = localEvaluatedText(value)
if value
    text = 'evaluated';
else
    text = 'not evaluated because evidence is unknown';
end
end

function text = localFiredText(value)
if value
    text = 'FIRED';
else
    text = 'not fired';
end
end

function text = localCriteriaText(criteria)
if isempty(criteria)
    text = 'none';
else
    text = localJoin(criteria, ', ');
end
end

function text = localJoin(values, delimiter)
text = values{1};
for index = 2:numel(values)
    text = [text, delimiter, values{index}]; %#ok<AGROW>
end
end
