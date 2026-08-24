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
[capabilityGapFields, caseUnknownFields] = localPartitionUnknown(evidence, ...
    unknownFields);
hasCaseUnknown = ~isempty(caseUnknownFields);
maxReachableLevel = localMaxReachableLevel(evidence);

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

% Escalation must be discriminative.  A condition that holds on every image
% is a property of which detectors this build has, not a fact about this
% patient, so it cannot function as a per-case safety control; treating it
% as one silently disables the decision layer.  Capability gaps and the
% provisional status of candidate evidence are therefore disclosed rather
% than escalated.  Case-level unknowns - a field some detector owns but
% could not determine on this image - do escalate, and so does Level 4,
% which is the mitigation the design commits to for the neovascularisation
% data gap.
humanEscalation = hasCaseUnknown || level == 4;

result = struct();
result.icdrLevel = level;
result.level = level;
result.referable = referable;
result.firedCriterion = firedCriterion;
result.evidenceSummary = localEvidenceSummary(evidence, unknownFields);
result.uncertaintyWarning = localUncertaintyWarning(capabilityGapFields, ...
    caseUnknownFields);
result.escalationRecommendation = localEscalationRecommendation( ...
    humanEscalation, level, hasCaseUnknown);
result.humanEscalationRecommended = humanEscalation;
result.uncertain = hasUnknown;
result.caseUnknownEvidence = hasCaseUnknown;
result.missingEvidenceFields = unknownFields;
result.capabilityGapFields = capabilityGapFields;
result.caseUnknownFields = caseUnknownFields;
result.maxReachableLevel = maxReachableLevel;
result.referableLevelReachable = maxReachableLevel >= 2;
result.levelIsCapabilityCapped = maxReachableLevel < 4;
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

function text = localUncertaintyWarning(capabilityGapFields, caseUnknownFields)
parts = {};
if ~isempty(capabilityGapFields)
    parts{end + 1} = sprintf(['Capability gap: no detector in this build ', ...
        'produces %s, so these fields are unknown on every image. The rule ', ...
        'engine cannot rise above the levels those fields define.'], ...
        strjoin(capabilityGapFields, ', ')); %#ok<AGROW>
end
if ~isempty(caseUnknownFields)
    parts{end + 1} = sprintf(['Uncertainty warning: evidence is unknown for ', ...
        '%s on this image. Unknown evidence was not treated as zero and may ', ...
        'conceal a more severe ICDR level.'], ...
        strjoin(caseUnknownFields, ', ')); %#ok<AGROW>
end
if isempty(parts)
    text = 'No missing evidence detected; all required evidence fields were known.';
else
    text = strjoin(parts, ' ');
end
end

function text = localEscalationRecommendation(humanEscalation, level, hasCaseUnknown)
if hasCaseUnknown
    text = ['Escalate to human clinical review because a detector that owns ', ...
        'an evidence field could not determine it on this image, and the ', ...
        'missing value could affect the safety of the screening result.'];
elseif level == 4
    text = ['Escalate every Level 4 result to a human reviewer because ', ...
        'neovascularisation has no validated pixel-level ground truth in this project.'];
elseif humanEscalation
    text = 'Human confirmation is recommended by the rule engine.';
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

function [capabilityGapFields, caseUnknownFields] = ...
        localPartitionUnknown(evidence, unknownFields)
%LOCALPARTITIONUNKNOWN Split unknown fields by whether a detector owns them.
coverage = evidence.evidenceFieldCoverage;
capabilityGapFields = {};
caseUnknownFields = {};
for index = 1:numel(unknownFields)
    fieldName = unknownFields{index};
    if isfield(coverage, fieldName) && ~coverage.(fieldName)
        capabilityGapFields{end + 1} = fieldName; %#ok<AGROW>
    else
        caseUnknownFields{end + 1} = fieldName; %#ok<AGROW>
    end
end
end

function level = localMaxReachableLevel(evidence)
%LOCALMAXREACHABLELEVEL The highest ICDR level this evidence set can express.
%   With only microaneurysm counts covered the rule can never return more
%   than Level 1, so asking it to confirm referability is asking for the
%   impossible.  Callers use this to tell "the rule disagrees" apart from
%   "the rule cannot reach that far".
coverage = evidence.evidenceFieldCoverage;
covered = @(name) isfield(coverage, name) && coverage.(name);
if covered('neovascularisation') || covered('vitreousOrPreretinalHaemorrhage')
    level = 4;
elseif covered('haemorrhageCountPerQuadrant') || ...
        covered('venousBeadingPerQuadrant') || covered('irmaPerQuadrant')
    level = 3;
elseif covered('hardExudateCount') || covered('softExudateCount')
    level = 2;
elseif covered('microaneurysmCount')
    level = 1;
else
    level = 0;
end
end
