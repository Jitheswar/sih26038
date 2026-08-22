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

if configuration.autoClearThreshold >= configuration.referableThreshold
    error('grade:InvalidDecisionConfiguration', ...
        'The auto-clear threshold must be below the referral threshold.');
end

% These are safety invariants, not tunable accuracy settings.
if ~configuration.requireEvidenceForAutoClear || ...
        ~configuration.alwaysEscalateLevel4 || ...
        ~configuration.escalateOnUnknownEvidence || ...
        ~configuration.escalateOnExplanationDisagreement
    error('grade:UnsafeDecisionConfiguration', ...
        ['Safety flags require evidence for auto-clear, Level 4 escalation, ', ...
        'unknown-evidence escalation, and explanation-disagreement escalation.']);
end
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
