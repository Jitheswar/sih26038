function configuration = decisionConfiguration(inputConfiguration)
%DECISIONCONFIGURATION Validate the configured three-way policy thresholds.

if ~isstruct(inputConfiguration) || ~isscalar(inputConfiguration)
    error('grade:InvalidDecisionConfiguration', ...
        'Decision policy configuration must be one scalar structure.');
end

policy = inputConfiguration;
if isfield(inputConfiguration, 'decisionPolicy')
    policy = inputConfiguration.decisionPolicy;
elseif isfield(inputConfiguration, 'decision_policy')
    policy = inputConfiguration.decision_policy;
end
if ~isstruct(policy) || ~isscalar(policy)
    error('grade:InvalidDecisionConfiguration', ...
        'decisionPolicy must be one scalar structure.');
end

configuration = struct();
configuration.referableThreshold = localRequiredNumber(policy, ...
    {'referableThreshold', 'referable_threshold'}, 'referable threshold');
configuration.autoClearThreshold = localRequiredNumber(policy, ...
    {'autoClearThreshold', 'auto_clear_threshold'}, 'auto-clear threshold');
configuration.uncertaintyThreshold = localRequiredNumber(policy, ...
    {'uncertaintyThreshold', 'uncertainty_threshold'}, ...
    'uncertainty threshold');
configuration.requireEvidenceForAutoClear = localRequiredLogical(policy, ...
    {'requireEvidenceForAutoClear', 'require_evidence_for_auto_clear'}, ...
    'requireEvidenceForAutoClear');
configuration.alwaysEscalateLevel4 = localRequiredLogical(policy, ...
    {'alwaysEscalateLevel4', 'always_escalate_level4'}, ...
    'alwaysEscalateLevel4');
configuration.escalateOnUnknownEvidence = localRequiredLogical(policy, ...
    {'escalateOnUnknownEvidence', 'escalate_on_unknown_evidence'}, ...
    'escalateOnUnknownEvidence');
configuration.escalateOnExplanationDisagreement = localRequiredLogical( ...
    policy, {'escalateOnExplanationDisagreement', ...
    'escalate_on_explanation_disagreement'}, ...
    'escalateOnExplanationDisagreement');

% Not a safety invariant, and deliberately not required.  escalateOnUnknown-
% Evidence above governs case-level unknowns, where a detector owns a field
% and could not determine it; that stays locked on.  This flag governs
% capability gaps, where no detector exists at all, so the field is unknown
% on every image.  Escalating on those refuses every case and yields a
% pipeline with zero autonomous coverage, which is a defensible policy but
% must be chosen rather than arrived at by accident.
configuration.escalateOnCapabilityGap = localOptionalLogical(policy, ...
    {'escalateOnCapabilityGap', 'escalate_on_capability_gap'}, ...
    'escalateOnCapabilityGap', false);

% How the two channels' ICDR levels are compared once the rule engine can
% reach Level 2.
%
%   'exact'     Levels must be equal.  The original behaviour and the
%               default, so a configuration that does not mention this gets
%               exactly what it got before.
%   'endpoint'  The levels are compared on referable versus not referable,
%               which is the primary endpoint of §11.2 and the only thing
%               the three-way decision acts on.
%
% The measurement that motivates the option is the §11.6 entry of 30 August:
% under 'exact', 163 of A9's 174 level-mismatch escalations put the patient
% on the same side of the referral decision and differ only on severity.
% Exact equality is also unreachable above the rule engine's own ceiling,
% which is Level 2 when hard exudates are the only trusted head, so every
% CNN prediction of Level 3 or 4 mismatches by construction.  Neither the
% endpoint disagreements nor the under-detected case are given up by
% 'endpoint': those are caught by the dedicated states above it.
% The two constants of the §8.6 spatial test, defaulting to the values
% that have always shipped so a configuration that does not mention them
% behaves exactly as before.  They were magic numbers inside two copies of
% the test until now, which §13.3 forbids ("every stage must be switchable
% from configuration") and which §11.6 recorded as the one §8.6 state that
% could not be switched from configuration at all.
%
% Neither was ever selected against data, and §8.3 records that the
% Grad-CAM map at 448x448 is 14x14, one cell covering roughly 32x32 input
% pixels, so the channel cannot localise a microaneurysm.  Naming them here
% does not endorse them; it makes them measurable, which is what deciding
% between keeping this gate and recalibrating it requires.
configuration.spatialAttentionCut = localOptionalNumber(policy, ...
    {'spatialAttentionCut', 'spatial_attention_cut'}, ...
    'spatialAttentionCut', 0.35);
configuration.spatialAgreementFraction = localOptionalNumber(policy, ...
    {'spatialAgreementFraction', 'spatial_agreement_fraction'}, ...
    'spatialAgreementFraction', 0.25);

configuration.levelComparison = localOptionalChoice(policy, ...
    {'levelComparison', 'level_comparison'}, 'levelComparison', ...
    'exact', {'exact', 'endpoint'});

if configuration.autoClearThreshold >= configuration.referableThreshold
    error('grade:InvalidDecisionConfiguration', ...
        'The auto-clear threshold must be below the referral threshold.');
end

% These are safety invariants, not tunable accuracy settings.
%
% escalateOnExplanationDisagreement was on this list and is no longer.  It
% governs the Grad-CAM spatial check, and §8.6 specifies that state as
% "Flag in the report as reduced explanation confidence. Consider
% escalation." - an annotation with escalation to be considered, not a
% mandatory gate.  Refusing to start unless it was true made the one §8.6
% state the document describes as advisory the only one that could not be
% switched from configuration, which also contradicts §11.6 and §13.3.  It
% still defaults to true and is true in every shipped configuration, so no
% deployed behaviour changes; it is now measurable, which is what the
% ablation study needs in order to say what it costs.
%
% The other three stay locked.  Auto-clear without evidence, an unescalated
% Level 4, and an unescalated case-level unknown are all failures to refer a
% patient who may need referral.  A spatial-attention mismatch is not: the
% under-detected check below it, which is mandatory, is what carries the
% "the classifier is keying on something that is not disease" safety
% property that §8.6 is built around.
if ~configuration.requireEvidenceForAutoClear || ...
        ~configuration.alwaysEscalateLevel4 || ...
        ~configuration.escalateOnUnknownEvidence
    error('grade:UnsafeDecisionConfiguration', ...
        ['Safety flags require evidence for auto-clear, Level 4 escalation, ', ...
        'and unknown-evidence escalation.']);
end
end

function value = localOptionalChoice(policy, names, label, defaultValue, allowed)
value = localField(policy, names, []);
if isempty(value)
    value = defaultValue;
    return;
end
if isstring(value) && isscalar(value)
    value = char(value);
end
if ~ischar(value) || ~ismember(value, allowed)
    error('grade:InvalidDecisionConfiguration', ...
        '%s must be one of: %s.', label, strjoin(allowed, ', '));
end
end

function value = localOptionalNumber(policy, names, label, defaultValue)
if ~any(cellfun(@(name) isfield(policy, name), names))
    value = defaultValue;
    return;
end
value = localRequiredNumber(policy, names, label);
end

function value = localRequiredNumber(policy, names, label)
value = localField(policy, names, []);
if ~isnumeric(value) || ~isscalar(value) || ~isreal(value) || ...
        ~isfinite(value) || value < 0 || value > 1
    error('grade:InvalidDecisionConfiguration', ...
        '%s must be a finite number between zero and one.', label);
end
value = double(value);
end

function value = localOptionalLogical(policy, names, label, defaultValue)
if ~any(cellfun(@(name) isfield(policy, name), names))
    value = defaultValue;
    return;
end
value = localRequiredLogical(policy, names, label);
end

function value = localRequiredLogical(policy, names, label)
value = localField(policy, names, []);
if islogical(value) && isscalar(value)
    return;
end
if isnumeric(value) && isscalar(value) && isreal(value) && ...
        isfinite(value) && ismember(value, [0, 1])
    value = logical(value);
    return;
end
error('grade:InvalidDecisionConfiguration', ...
    '%s must be a logical scalar.', label);
end

function value = localField(inputStruct, names, defaultValue)
value = defaultValue;
for index = 1:numel(names)
    if isfield(inputStruct, names{index})
        value = inputStruct.(names{index});
        return;
    end
end
end
