function result = decisionPolicy(input, config)
%DECISIONPOLICY Apply the conservative three-way DR screening policy.
%   RESULT = grade.decisionPolicy(INPUT, CONFIG) returns exactly one of
%   auto-clear, refer, or escalate.  Calibrated probability must be
%   supplied explicitly; class softmax probabilities are never a fallback.
%
%   RESULT.reasonCodes lists every finding the policy raised, and
%   RESULT.findingKinds names what each of them is, entry for entry.  The
%   three kinds are the ones CONTEXT.md defines; see localKindNames below.

rng(42, 'twister');
if nargin < 2
    error('grade:MissingDecisionConfiguration', ...
        'A decision policy configuration is required.');
end

configuration = decisionConfiguration(config);
normalized = normalizeDecisionInput(input);
kindNames = localKindNames();

% The three kinds are collected separately because they are three different
% statements about the case, not one bucket of caveats.
%
%   codes         safety exceptions: per-case findings that force escalation.
%   gaps          capability gaps: fields no detector in this build produces,
%                 and therefore unknown on every image.  They discriminate
%                 between no cases, so escalating on one escalates the whole
%                 caseload; they are reported and do not force the decision.
%   advisories    advisory findings: per-case and image-dependent like a
%                 safety exception, reported, but not treated as
%                 disqualifying.
%
% All three reach reasonCodes, in that order, exactly as before.  Only the
% first is consulted when the decision is made.
codes = {};
gaps = {};
advisories = {};

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
if rule.caseUnknownEvidence
    codes{end + 1} = 'required-evidence-unknown'; %#ok<AGROW>
elseif rule.unknownEvidence
    gaps{end + 1} = 'evidence-capability-gap'; %#ok<AGROW>
end
if rule.unknownNeovascularisation
    if localIsCapabilityGap(rule, {'neovascularisation', ...
            'neovascularization', 'nv'})
        % Per the declared data gap, no dataset in this project carries
        % neovascularisation masks, so this is unknown on every image.  The
        % committed mitigation is escalating every predicted Level 4, which
        % alwaysEscalateLevel4 does below, not escalating every case.
        gaps{end + 1} = 'unknown-neovascularisation-status'; %#ok<AGROW>
    else
        codes{end + 1} = 'unknown-neovascularisation-status'; %#ok<AGROW>
    end
end

agreementStatus = localAgreementStatus(normalized, configuration);
agreementBasis = localAgreementBasis(normalized);
% When the spatial check is advisory the state is still computed and still
% reported; it simply does not force the decision.  Reporting it as an
% advisory finding rather than dropping it keeps §8.6's "flag in the report
% as reduced explanation confidence" true of the output.
if ~configuration.escalateOnExplanationDisagreement && ...
        localSpatiallyInconsistent(normalized)
    advisories{end + 1} = 'explanation-spatially-inconsistent'; %#ok<AGROW>
end
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
    advisories{end + 1} = 'candidate-evidence-provisional'; %#ok<AGROW>
end
if cnn.predictedLevelKnown && cnn.predictedLevel == 4
    codes{end + 1} = 'cnn-level-4'; %#ok<AGROW>
end
if rule.escalationRecommended
    codes{end + 1} = 'rule-engine-recommends-escalation'; %#ok<AGROW>
end

if configuration.escalateOnCapabilityGap
    % The maximally conservative policy: refuse to decide anything while any
    % evidence field lacks a detector.  This is what the pipeline did before
    % the distinction existed, kept reachable from configuration so the
    % ablation can measure both policies over one code path.
    %
    % Capability gaps only.  Whether an advisory finding escalates is a
    % different question with its own flag - the spatial check's is
    % escalateOnExplanationDisagreement - and promoting advisories here
    % would answer that question behind the other flag's back.
    codes = [codes, gaps];
    gaps = {};
end
mandatoryCodes = codes;
if isempty(mandatoryCodes)
    if cnn.predictedLevel >= 2
        % The rule engine confirms referability where it can reach Level 2;
        % where a capability gap caps it below Level 2 it cannot confirm or
        % deny, so requiring confirmation would require the impossible.  The
        % under-detected safety check is carried by supportsCNN, which is
        % still evaluated: a referable prediction with no lesion evidence
        % behind it escalates rather than referring.
        ruleDoesNotContradict = rule.referable || ~rule.referableLevelReachable;
        canRefer = cnn.calibratedProbability >= ...
            configuration.referableThreshold && ...
            normalized.explanation.supportKnown && ...
            normalized.explanation.supportsCNN && ...
            strcmp(agreementStatus, 'concordant') && ruleDoesNotContradict;
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
            ~rule.caseUnknownEvidence)) && ...
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

% Everything collected in codes up to here either forced the escalation or
% records why the positive path was not taken, so all of it is a per-case
% safety exception.  Capability gaps promoted above are safety exceptions
% too, by the configured choice to treat them that way.
kinds = repmat({kindNames.safetyException}, 1, numel(codes));

if isempty(mandatoryCodes) && strcmp(agreementStatus, 'concordant')
    % Not a finding against the case but a finding about it: reported,
    % image-dependent, and it does not force the decision.  That is what an
    % advisory finding is, and it is the only kind it can honestly carry.
    codes = [{'concordant'}, codes];
    kinds = [{kindNames.advisoryFinding}, kinds];
end

% The other two kinds are reported alongside the safety exceptions so
% nothing the policy saw is hidden from the report; they simply did not
% drive the decision.
codes = [codes, gaps, advisories];
kinds = [kinds, repmat({kindNames.capabilityGap}, 1, numel(gaps)), ...
    repmat({kindNames.advisoryFinding}, 1, numel(advisories))];

% findingKinds is only usable if it lines up entry for entry.
if numel(kinds) ~= numel(codes)
    error('grade:InvalidFindingKinds', ...
        'Every reason code must carry exactly one finding kind.');
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
    'Agreement: %s (basis: %s). Uncertainty: %s. Evidence quality: %s. ', ...
    'Reason codes: %s.'], ...
    decision, localTextOrUnknown(quality.class), ...
    localProbabilityText(cnn), localLevelText(cnn.predictedLevel), ...
    localLevelText(rule.level), agreementStatus, agreementBasis, ...
    uncertaintyStatus, evidenceQualityStatus, strjoin(codes, ', '));
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
result.findingKinds = kinds;
result.recommendedAction = recommendedAction;
result.referralSlipRequired = referralSlipRequired;
result.humanReviewRequired = humanReviewRequired;
result.calibratedProbability = cnn.calibratedProbability;
result.cnnPredictedLevel = cnn.predictedLevel;
result.icdrRuleLevel = rule.level;
result.agreementStatus = agreementStatus;
result.agreementBasis = agreementBasis;
result.uncertaintyStatus = uncertaintyStatus;
result.evidenceQualityStatus = evidenceQualityStatus;
result.candidateEvidenceStatus = candidateEvidenceStatus;
result.candidateEvidenceWarning = rule.candidateWarning;
result.explanation = explanation;
end

function names = localKindNames()
%LOCALKINDNAMES The three kinds of finding, named as CONTEXT.md names them.
%   safety exception   a finding about this case that forces escalation.
%   advisory finding   a finding about this case that is reported and does
%                      not force the decision.
%   capability gap     a field no detector in this build produces, unknown
%                      on every image, reported and never presented as a
%                      per-case unknown.
%
%   The distinction is not cosmetic.  A capability gap discriminates between
%   no cases, so a reader who cannot tell one from an advisory finding
%   cannot tell "this image's attention was odd" from "this build has no
%   neovascularisation detector".  §11.6 and the ablation configurations
%   already say "advisory" for the demoted spatial state; this is the code
%   using the same word.
names = struct( ...
    'safetyException', 'safety exception', ...
    'advisoryFinding', 'advisory finding', ...
    'capabilityGap', 'capability gap');
end

function answer = localSpatiallyInconsistent(normalized)
%LOCALSPATIALLYINCONSISTENT Did the Grad-CAM spatial check fail?
%   Separated from the status chain so the condition can be reported when
%   the check is advisory and the chain no longer short-circuits on it.
explanation = normalized.explanation;
answer = explanation.spatialKnown && ~explanation.spatiallyAgree;
end

function status = localAgreementStatus(normalized, configuration)
cnn = normalized.cnn;
rule = normalized.rule;
explanation = normalized.explanation;
% The spatial state short-circuits the chain only while it is a gate.  Left
% in place when advisory it would mask every state below it, so a case whose
% attention map disagrees would never be examined for the under-detected
% condition that actually carries the safety property.
if configuration.escalateOnExplanationDisagreement && ...
        localSpatiallyInconsistent(normalized)
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
        rule.caseUnknownEvidence
    status = 'insufficient evidence';
    return;
end
if rule.referableLevelReachable
    % Both channels can reach the referral boundary, so compare them.  How
    % is configuration.levelComparison: 'exact' requires equal ICDR levels,
    % 'endpoint' requires only that they place the patient on the same side
    % of the referral decision (§11.2), which is the whole of what the
    % three-way disposition acts on.
    %
    % 'exact' is unreachable above the rule engine's own ceiling.  With hard
    % exudates as the only trusted head that ceiling is Level 2, so a CNN
    % prediction of Level 3 or 4 mismatches however well either channel
    % performs, and the §11.6 entry of 30 August measured 163 of 174 such
    % mismatches as severity-only disagreements on cases where both channels
    % already agreed about referral.
    if strcmp(configuration.levelComparison, 'endpoint')
        if (cnn.predictedLevel >= 2) ~= localEvidenceReferable(normalized)
            status = 'insufficient evidence';
            return;
        end
    elseif cnn.predictedLevel ~= rule.level
        status = 'insufficient evidence';
        return;
    end
end
% When a capability gap caps the rule engine below Level 2 no comparison
% against its level is meaningful.  Its "not referable" is silence, not a
% denial: it lacks every field the Level 2+ criteria are written over, so it
% would contradict the classifier on every diseased image and agree with it
% on every healthy one for reasons that have nothing to do with the image.
% The under-detected and over-detected checks above are then the whole
% agreement test, and they run off the lesion-evidence channel, which does
% exist.  agreementBasis records which of the two situations produced this
% verdict so a concordant result is never read as more corroboration than it is.
status = 'concordant';
end

function basis = localAgreementBasis(normalized)
%LOCALAGREEMENTBASIS What the agreement verdict was actually able to check.
if normalized.rule.referableLevelReachable
    basis = 'CNN and ICDR rule engine compared on the full scale';
else
    basis = ['lesion evidence channel only; the ICDR rule engine is ', ...
        'capability-capped below Level 2 and cannot corroborate referability'];
end
end

function answer = localEvidenceReferable(normalized)
if normalized.explanation.evidenceReferableKnown
    answer = normalized.explanation.evidenceReferable;
else
    answer = normalized.rule.referableKnown && normalized.rule.referable;
end
end

function answer = localIsCapabilityGap(rule, names)
%LOCALISCAPABILITYGAP Is this field unknown because no detector produces it?
answer = false;
for index = 1:numel(rule.capabilityGapFields)
    value = lower(rule.capabilityGapFields{index});
    if any(strcmp(value, names)) || contains(value, 'neovascular')
        answer = true;
        return;
    end
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
