function normalized = normalizeDecisionInput(input)
%NORMALIZEDECISIONINPUT Normalize aliases while preserving unknown evidence.

if ~isstruct(input) || ~isscalar(input)
    error('grade:InvalidDecisionInput', ...
        'Decision policy input must be one scalar structure.');
end

normalized = struct();
normalized.quality = localQuality(input);
normalized.cnn = localCNN(input);
normalized.rule = localRule(input);
normalized.explanation = localExplanation(input);
end

function quality = localQuality(input)
quality = struct('class', '', 'metadata', struct(), ...
    'enhancementApplied', false, 'enhancementKnown', false, ...
    'clearlyGradableAfterEnhancement', false, ...
    'enhancementOutcomeKnown', false);
if ~isfield(input, 'quality') || ~isstruct(input.quality) || ...
        ~isscalar(input.quality)
    return;
end
raw = input.quality;
quality.class = localText(localField(raw, ...
    {'class', 'qualityClass', 'quality_class'}, ''), '');
metadata = localField(raw, {'metadata', 'qualityMetadata', ...
    'quality_metadata'}, struct());
if isstruct(metadata) && isscalar(metadata)
    quality.metadata = metadata;
end
if isfield(raw, 'enhancementApplied')
    [quality.enhancementApplied, quality.enhancementKnown] = ...
        localLogical(raw.enhancementApplied);
elseif isfield(raw, 'enhancement_applied')
    [quality.enhancementApplied, quality.enhancementKnown] = ...
        localLogical(raw.enhancement_applied);
end

postClass = localField(quality.metadata, ...
    {'postEnhancementQualityClass', 'post_enhancement_quality_class', ...
    'enhancedQualityClass', 'enhanced_quality_class', ...
    'finalQualityClass', 'final_quality_class'}, '');
if ~isempty(postClass)
    quality.enhancementOutcomeKnown = true;
    quality.clearlyGradableAfterEnhancement = strcmpi( ...
        localText(postClass, ''), 'gradable');
elseif isfield(quality.metadata, 'clearlyGradable')
    [quality.clearlyGradableAfterEnhancement, ...
        quality.enhancementOutcomeKnown] = localLogical( ...
        quality.metadata.clearlyGradable);
elseif isfield(quality.metadata, 'clearly_gradable')
    [quality.clearlyGradableAfterEnhancement, ...
        quality.enhancementOutcomeKnown] = localLogical( ...
        quality.metadata.clearly_gradable);
end
end

function cnn = localCNN(input)
cnn = struct('predictedLevel', NaN, 'predictedLevelKnown', false, ...
    'calibratedProbability', NaN, 'calibratedProbabilityKnown', false, ...
    'uncertaintyScore', NaN, 'uncertaintyKnown', false, ...
    'classProbabilitiesPresent', false);
if ~isfield(input, 'cnn') || ~isstruct(input.cnn) || ~isscalar(input.cnn)
    return;
end
raw = input.cnn;
[cnn.predictedLevel, cnn.predictedLevelKnown] = localNumber(localField(raw, ...
    {'predictedLevel', 'predictedICDRLevel', 'predicted_icdr_level', ...
    'cnnPredictedLevel', 'cnn_predicted_level'}, NaN));
probability = localField(raw, {'calibratedReferableProbability', ...
    'calibratedProbability', 'calibrated_referable_probability'}, NaN);
[cnn.calibratedProbability, cnn.calibratedProbabilityKnown] = ...
    localNumber(probability);
if isfield(raw, 'classProbabilities') || isfield(raw, 'class_probabilities')
    cnn.classProbabilitiesPresent = true;
end
[cnn.uncertaintyScore, cnn.uncertaintyKnown] = localNumber(localField(raw, ...
    {'uncertaintyScore', 'uncertainty_score'}, NaN));
end

function rule = localRule(input)
rule = struct('present', false, 'level', NaN, 'levelKnown', false, ...
    'referable', false, 'referableKnown', false, 'unknownEvidence', false, ...
    'unknownFields', {{}}, 'unknownNeovascularisation', false, ...
    'escalationRecommended', false, 'candidateEvidence', false, ...
    'candidateWarning', '', 'evidenceSource', '', ...
    'clinicalValidationStatus', '');
raw = [];
if isfield(input, 'ruleEngine') && isstruct(input.ruleEngine) && ...
        isscalar(input.ruleEngine)
    raw = input.ruleEngine;
elseif isfield(input, 'icdrRuleResult') && isstruct(input.icdrRuleResult) && ...
        isscalar(input.icdrRuleResult)
    raw = input.icdrRuleResult;
end
if isempty(raw)
    return;
end
if isfield(raw, 'result') && isstruct(raw.result) && isscalar(raw.result)
    raw = raw.result;
elseif isfield(raw, 'icdrRuleResult') && isstruct(raw.icdrRuleResult) && ...
        isscalar(raw.icdrRuleResult)
    raw = raw.icdrRuleResult;
elseif isfield(raw, 'ruleResult') && isstruct(raw.ruleResult) && ...
        isscalar(raw.ruleResult)
    raw = raw.ruleResult;
end
rule.present = ~isempty(fieldnames(raw));
[rule.level, rule.levelKnown] = localNumber(localField(raw, ...
    {'icdrLevel', 'ruleLevel', 'level', 'icdr_rule_level'}, NaN));
level = rule.level;
if rule.levelKnown && (~isfinite(level) || level ~= floor(level) || ...
        level < 0 || level > 4)
    rule.levelKnown = false;
    rule.level = NaN;
end
if isfield(raw, 'referable')
    [rule.referable, rule.referableKnown] = localLogical(raw.referable);
elseif rule.levelKnown
    rule.referable = rule.level >= 2;
    rule.referableKnown = true;
end
unknown = localField(raw, {'missingEvidenceFields', ...
    'missing_evidence_fields'}, {});
if ischar(unknown)
    unknown = {unknown};
elseif isstring(unknown)
    unknown = cellstr(unknown(:));
elseif ~iscell(unknown)
    unknown = {};
end
rule.unknownFields = unknown;
unknownStatus = localField(raw, {'evidenceKnownStatus', ...
    'evidence_known_status'}, '');
unknownStatus = lower(localText(unknownStatus, ''));
[unknownFlag, unknownFlagKnown] = localLogical(localField(raw, ...
    {'uncertain', 'unknownEvidence', 'evidenceUnknown', ...
    'evidence_unknown'}, false));
if isfield(raw, 'evidenceKnown') || isfield(raw, 'evidence_known')
    [evidenceKnown, evidenceKnownIsValid] = localLogical(localField(raw, ...
        {'evidenceKnown', 'evidence_known'}, true));
else
    evidenceKnown = true;
    evidenceKnownIsValid = true;
end
rule.unknownEvidence = (unknownFlagKnown && unknownFlag) || ...
    ~evidenceKnownIsValid || ~evidenceKnown;
rule.unknownEvidence = rule.unknownEvidence || ~isempty(unknown) || ...
    any(strcmp(unknownStatus, {'unknown', 'insufficient', 'not-known'}));
rule.unknownNeovascularisation = localContainsUnknown(unknown, ...
    {'neovascularisation', 'neovascularization', 'nv'}) || ...
    (contains(unknownStatus, 'unknown') && contains(unknownStatus, 'neovascular'));
[rule.escalationRecommended, ~] = localLogical(localField(raw, ...
    {'humanEscalationRecommended', 'escalationRecommended', ...
    'human_escalation_recommended'}, false));
recommendation = lower(localText(localField(raw, ...
    {'escalationRecommendation', 'escalation_recommendation'}, ''), ''));
negativeRecommendation = contains(recommendation, 'no escalation') || ...
    contains(recommendation, 'no additional human escalation') || ...
    contains(recommendation, 'not recommended');
rule.escalationRecommended = rule.escalationRecommended || ...
    ((contains(recommendation, 'escalat') || ...
    contains(recommendation, 'human review')) && ...
    ~negativeRecommendation);
rule.evidenceSource = localText(localField(raw, {'evidenceSource', ...
    'evidence_source'}, ''), '');
rule.clinicalValidationStatus = localText(localField(raw, ...
    {'clinicalValidationStatus', 'clinical_validation_status'}, ''), '');
rule.candidateWarning = localText(localField(raw, ...
    {'candidateEvidenceWarning', 'candidate_evidence_warning'}, ''), '');
candidateField = localField(raw, {'candidateEvidence', ...
    'candidate_evidence'}, false);
[candidateField, candidateFieldKnown] = localLogical(candidateField);
rule.candidateEvidence = (candidateFieldKnown && candidateField) || ...
    contains(lower(rule.evidenceSource), 'candidate') || ...
    contains(lower(rule.clinicalValidationStatus), 'not clinically') || ...
    ~isempty(rule.candidateWarning);
end

function explanation = localExplanation(input)
explanation = struct('spatialKnown', false, 'spatiallyAgree', false, ...
    'supportKnown', false, 'supportsCNN', false, 'evidenceReferableKnown', false, ...
    'evidenceReferable', false, 'evidenceKnown', true, 'gradCamAvailable', true);
if ~isfield(input, 'explanation') || ~isstruct(input.explanation) || ...
        ~isscalar(input.explanation)
    return;
end
raw = input.explanation;
[explanation.spatiallyAgree, explanation.spatialKnown] = localLogical(localField(raw, ...
    {'gradCamAndLesionEvidenceSpatiallyAgree', 'spatiallyAgree', ...
    'spatialAgreement', 'spatially_agree'}, NaN));
[explanation.supportsCNN, explanation.supportKnown] = localLogical(localField(raw, ...
    {'lesionEvidenceSupportsCNN', 'lesionEvidenceSupportsCnn', ...
    'lesion_evidence_supports_cnn'}, NaN));
metadata = localField(raw, {'lesionEvidenceMetadata', ...
    'lesion_evidence_metadata'}, struct());
if isstruct(metadata) && isscalar(metadata)
    [candidate, candidateKnown] = localLogical(localField(metadata, ...
        {'candidateEvidence', 'candidate_evidence'}, false));
    if candidateKnown && candidate
        explanation.evidenceKnown = true;
    end
    evidenceKnown = localField(metadata, {'evidenceKnown', ...
        'evidence_known'}, true);
    [explanation.evidenceKnown, evidenceKnownIsValid] = ...
        localLogical(evidenceKnown);
    if ~evidenceKnownIsValid
        explanation.evidenceKnown = false;
    end
    [explanation.evidenceReferable, explanation.evidenceReferableKnown] = ...
        localLogical(localField(metadata, {'referable', ...
        'pathologyIndicatesReferable', 'indicatesReferable', ...
        'isReferable'}, NaN));
end
gradCam = localField(raw, {'gradCamMetadata', 'gradcamMetadata', ...
    'grad_cam_metadata'}, struct());
if isstruct(gradCam) && isfield(gradCam, 'available')
    [explanation.gradCamAvailable, ~] = localLogical(gradCam.available);
end
end

function answer = localContainsUnknown(values, names)
answer = false;
for index = 1:numel(values)
    value = lower(localText(values{index}, ''));
    answer = answer || any(strcmp(value, names)) || ...
        contains(value, 'neovascular');
end
end

function value = localField(inputStruct, names, defaultValue)
value = defaultValue;
if ~isstruct(inputStruct) || ~isscalar(inputStruct)
    return;
end
for index = 1:numel(names)
    if isfield(inputStruct, names{index})
        value = inputStruct.(names{index});
        return;
    end
end
end

function text = localText(value, defaultValue)
if ischar(value) && isrow(value)
    text = value;
elseif isstring(value) && isscalar(value)
    text = char(value);
else
    text = defaultValue;
end
end

function [value, known] = localNumber(value)
known = isnumeric(value) && isscalar(value) && isreal(value) && isfinite(value);
if known
    value = double(value);
else
    value = NaN;
end
end

function [value, known] = localLogical(value)
known = (islogical(value) && isscalar(value)) || ...
    (isnumeric(value) && isscalar(value) && isreal(value) && ...
    isfinite(value) && ismember(value, [0, 1]));
if known
    value = logical(value);
else
    value = false;
end
end
