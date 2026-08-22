function result = decisionPolicy(input, config)
%DECISIONPOLICY Apply the conservative three-way DR screening policy.
%   RESULT = grade.decisionPolicy(INPUT, CONFIG) returns exactly one of
%   auto-clear, refer, or escalate.  Calibrated probability must be
%   supplied explicitly; class softmax probabilities are never a fallback.

rng(42, 'twister');
if nargin < 2
    error('grade:MissingDecisionConfiguration', ...
        'A decision policy configuration is required.');
end

configuration = decisionConfiguration(config);
normalized = normalizeDecisionInput(input);
codes = {};

quality = normalized.quality;
if isempty(quality.class)
    codes{end + 1} = 'missing-quality-input'; %#ok<AGROW>
elseif strcmpi(quality.class, 'ungradable')
    codes{end + 1} = 'quality-ungradable'; %#ok<AGROW>
elseif strcmpi(quality.class, 'borderline')
    if ~(quality.enhancementKnown && quality.enhancementApplied && ...
            quality.enhancementOutcomeKnown && ...
            quality.clearlyGradableAfterEnhancement)
        codes{end + 1} = 'borderline-quality-not-clearly-gradable'; %#ok<AGROW>
    end
elseif ~strcmpi(quality.class, 'gradable')
    codes{end + 1} = 'invalid-quality-class'; %#ok<AGROW>
elseif ~quality.enhancementKnown
    codes{end + 1} = 'missing-quality-input'; %#ok<AGROW>
end

cnn = normalized.cnn;
if ~cnn.predictedLevelKnown
    codes{end + 1} = 'missing-cnn-prediction'; %#ok<AGROW>
end
if ~cnn.calibratedProbabilityKnown
    codes{end + 1} = 'missing-calibrated-probability'; %#ok<AGROW>
elseif cnn.calibratedProbability < 0 || cnn.calibratedProbability > 1
    codes{end + 1} = 'invalid-calibrated-probability'; %#ok<AGROW>
end

if cnn.uncertaintyKnown
    if cnn.uncertaintyScore < 0 || cnn.uncertaintyScore > 1
        codes{end + 1} = 'invalid-uncertainty-score'; %#ok<AGROW>
        uncertaintyStatus = 'unknown';
    elseif cnn.uncertaintyScore > configuration.uncertaintyThreshold
        codes{end + 1} = 'high-uncertainty'; %#ok<AGROW>
        uncertaintyStatus = 'high';
    else
        uncertaintyStatus = 'low';
    end
else
    uncertaintyStatus = 'not_available_for_prototype';
end

rule = normalized.rule;
if ~rule.present || ~rule.levelKnown || ~rule.referableKnown
    codes{end + 1} = 'missing-rule-evidence'; %#ok<AGROW>
end
if rule.unknownEvidence
    codes{end + 1} = 'required-evidence-unknown'; %#ok<AGROW>
end
if rule.unknownNeovascularisation
    codes{end + 1} = 'unknown-neovascularisation-status'; %#ok<AGROW>
end

agreementStatus = localAgreementStatus(normalized);
if strcmp(agreementStatus, 'spatially inconsistent')
    codes{end + 1} = 'explanation-disagreement'; %#ok<AGROW>
elseif strcmp(agreementStatus, 'CNN referable but evidence unsupported')
    codes{end + 1} = 'cnn-referable-evidence-unsupported'; %#ok<AGROW>
elseif strcmp(agreementStatus, 'evidence referable but CNN non-referable')
    codes{end + 1} = 'evidence-referable-cnn-nonreferable'; %#ok<AGROW>
elseif strcmp(agreementStatus, 'insufficient evidence')
    codes{end + 1} = 'insufficient-explanation-evidence'; %#ok<AGROW>
end
if rule.candidateEvidence
    codes{end + 1} = 'candidate-evidence-provisional'; %#ok<AGROW>
end
if cnn.predictedLevelKnown && cnn.predictedLevel == 4
    codes{end + 1} = 'cnn-level-4'; %#ok<AGROW>
end
if rule.escalationRecommended
    codes{end + 1} = 'rule-engine-recommends-escalation'; %#ok<AGROW>
end

mandatoryCodes = codes;
if isempty(mandatoryCodes)
    if cnn.predictedLevel >= 2
        canRefer = cnn.calibratedProbability >= ...
            configuration.referableThreshold && ...
            normalized.explanation.supportKnown && ...
            normalized.explanation.supportsCNN && ...
            strcmp(agreementStatus, 'concordant') && rule.referable;
        if canRefer
            decision = 'refer';
        else
            codes{end + 1} = 'referable-case-not-ready-to-refer'; %#ok<AGROW>
            decision = 'escalate';
        end
    else
        canAutoClear = cnn.calibratedProbability < ...
            configuration.autoClearThreshold && ...
            (~configuration.requireEvidenceForAutoClear || ...
            (rule.present && rule.referableKnown && ~rule.referable && ...
            ~rule.unknownEvidence)) && ...
            strcmp(agreementStatus, 'concordant') && ...
            (~cnn.uncertaintyKnown || strcmp(uncertaintyStatus, 'low'));
        if canAutoClear
            decision = 'auto-clear';
        else
            codes{end + 1} = 'case-not-ready-to-auto-clear'; %#ok<AGROW>
            decision = 'escalate';
        end
    end
else
    decision = 'escalate';
end

if isempty(mandatoryCodes) && strcmp(agreementStatus, 'concordant')
    codes = [{'concordant'}, codes];
end

% The invariant is checked after all conditions so future edits cannot add
% a fourth primary outcome accidentally.
if ~ismember(decision, {'auto-clear', 'refer', 'escalate'})
    error('grade:InvalidDecision', 'The policy produced an invalid decision.');
end

if strcmp(decision, 'auto-clear')
    recommendedAction = 'Advise routine annual re-screening; no referral slip is required.';
    referralSlipRequired = false;
    humanReviewRequired = false;
elseif strcmp(decision, 'refer')
    recommendedAction = 'Print the referral slip and refer the patient for specialist review.';
    referralSlipRequired = true;
    humanReviewRequired = false;
else
    recommendedAction = 'Queue the image for human grading; do not make an automated disposition.';
    referralSlipRequired = false;
    humanReviewRequired = true;
end

candidateEvidenceStatus = 'not_present';
evidenceQualityStatus = 'known';
if ~rule.present
    evidenceQualityStatus = 'missing';
elseif rule.unknownEvidence
    evidenceQualityStatus = 'unknown';
end
if rule.candidateEvidence
    candidateEvidenceStatus = 'provisional_not_clinically_validated';
    evidenceQualityStatus = 'provisional_not_clinically_validated';
end

reasonText = localReasonText(codes);
decisionReason = sprintf('%s: %s.', localDecisionText(decision), reasonText);
explanation = sprintf(['Primary decision: %s. Quality: %s. Calibrated ', ...
    'referable probability: %s. CNN ICDR level: %s. ICDR rule level: %s. ', ...
    'Agreement: %s. Uncertainty: %s. Evidence quality: %s. ', ...
    'Reason codes: %s.'], ...
    decision, localTextOrUnknown(quality.class), ...
    localProbabilityText(cnn), localLevelText(cnn.predictedLevel), ...
    localLevelText(rule.level), agreementStatus, uncertaintyStatus, ...
    evidenceQualityStatus, strjoin(codes, ', '));
if rule.candidateEvidence
    warning = rule.candidateWarning;
    if isempty(warning)
        warning = 'Candidate evidence is provisional and not clinically validated.';
    end
    explanation = sprintf('%s %s', explanation, warning);
end

result = struct();
result.decision = decision;
result.decisionReason = decisionReason;
result.reasonCodes = codes;
result.recommendedAction = recommendedAction;
result.referralSlipRequired = referralSlipRequired;
result.humanReviewRequired = humanReviewRequired;
result.calibratedProbability = cnn.calibratedProbability;
result.cnnPredictedLevel = cnn.predictedLevel;
result.icdrRuleLevel = rule.level;
result.agreementStatus = agreementStatus;
result.uncertaintyStatus = uncertaintyStatus;
result.evidenceQualityStatus = evidenceQualityStatus;
result.candidateEvidenceStatus = candidateEvidenceStatus;
result.candidateEvidenceWarning = rule.candidateWarning;
result.explanation = explanation;
end

function status = localAgreementStatus(normalized)
cnn = normalized.cnn;
rule = normalized.rule;
explanation = normalized.explanation;
if explanation.spatialKnown && ~explanation.spatiallyAgree
    status = 'spatially inconsistent';
    return;
end
if cnn.predictedLevelKnown && cnn.predictedLevel >= 2 && ...
        explanation.supportKnown && ~explanation.supportsCNN
    status = 'CNN referable but evidence unsupported';
    return;
end
if cnn.predictedLevelKnown && cnn.predictedLevel < 2 && ...
        localEvidenceReferable(normalized)
    status = 'evidence referable but CNN non-referable';
    return;
end
if ~rule.present || ~rule.levelKnown || ~rule.referableKnown || ...
        ~explanation.spatialKnown || ~explanation.supportKnown || ...
        ~explanation.gradCamAvailable || ~explanation.evidenceKnown || ...
        rule.unknownEvidence
    status = 'insufficient evidence';
    return;
end
if cnn.predictedLevel ~= rule.level
    status = 'insufficient evidence';
    return;
end
status = 'concordant';
end

function answer = localEvidenceReferable(normalized)
if normalized.explanation.evidenceReferableKnown
    answer = normalized.explanation.evidenceReferable;
else
    answer = normalized.rule.referableKnown && normalized.rule.referable;
end
end

function text = localReasonText(codes)
if isempty(codes)
    text = 'No safety exception was detected';
else
    text = strjoin(codes, ', ');
end
end

function text = localDecisionText(decision)
if strcmp(decision, 'auto-clear')
    text = 'Auto-clear';
elseif strcmp(decision, 'refer')
    text = 'Refer';
else
    text = 'Escalate';
end
end

function text = localProbabilityText(cnn)
if cnn.calibratedProbabilityKnown
    text = sprintf('%.6f', cnn.calibratedProbability);
else
    text = 'unavailable';
end
end

function text = localLevelText(level)
if isfinite(level)
    text = sprintf('%d', level);
else
    text = 'unavailable';
end
end

function text = localTextOrUnknown(value)
if isempty(value)
    text = 'unknown';
else
    text = value;
end
end
