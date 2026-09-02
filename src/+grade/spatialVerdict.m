function [agree, clearedFraction] = spatialVerdict(evidence, configuration)
%SPATIALVERDICT Take the §8.6 spatial test from cached evidence.
%   [AGREE, CLEAREDFRACTION] = grade.spatialVerdict(EVIDENCE, CONFIGURATION)
%   applies the two constants to evidence from grade.spatialEvidence.
%
%   The test: of the normalized Grad-CAM values at the candidate points,
%   the fraction reaching CONFIGURATION.spatialAttentionCut must be at
%   least CONFIGURATION.spatialAgreementFraction.
%
%   Both constants come from configuration and default to the values that
%   have always shipped, so moving them here changes no deployed
%   behaviour.  They were magic numbers in two separate copies of this
%   test until now, which §13.3 forbids and which §11.6 recorded as the
%   one §8.6 state that could not be switched from configuration.  Neither
%   was ever selected against data.
%
%   This is the only place the rule lives.  Both the deployed pipeline and
%   the ablation harness reach it, because two copies of an evidence rule
%   is how an evaluation path diverges from the deployed one while still
%   passing its own tests.

if nargin < 2 || isempty(configuration)
    configuration = struct();
end
cut = localConstant(configuration, ...
    {'spatialAttentionCut', 'spatial_attention_cut'}, 0.35);
fraction = localConstant(configuration, ...
    {'spatialAgreementFraction', 'spatial_agreement_fraction'}, 0.25);

clearedFraction = NaN;
if ~isstruct(evidence) || ~isfield(evidence, 'known') || ~evidence.known
    % No usable heatmap.  Not a disagreement between channels, but the
    % test cannot be passed on absent evidence either.
    agree = false;
    return;
end
if evidence.candidatesScored == 0
    if isfield(evidence, 'outOfFrame') && evidence.outOfFrame
        % Candidates exist and none land on the map: a real failure to
        % correspond, not the vacuous case.
        agree = false;
        return;
    end
    % The lesion channel found nothing, so no candidate can fall outside
    % the attention and there is nothing to disagree about.
    agree = true;
    return;
end

clearedFraction = mean(evidence.values >= cut);
agree = clearedFraction >= fraction;
end

function value = localConstant(configuration, names, defaultValue)
value = defaultValue;
for index = 1:numel(names)
    if isfield(configuration, names{index})
        candidate = configuration.(names{index});
        if ~isnumeric(candidate) || ~isscalar(candidate) || ...
                ~isreal(candidate) || ~isfinite(candidate) || ...
                candidate < 0 || candidate > 1
            error('grade:InvalidSpatialConstant', ...
                '%s must be a finite number between zero and one.', ...
                names{index});
        end
        value = double(candidate);
        return;
    end
end
end
