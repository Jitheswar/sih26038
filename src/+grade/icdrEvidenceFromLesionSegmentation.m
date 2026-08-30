function evidence = icdrEvidenceFromLesionSegmentation(lesionEvidence, ...
    detection, evidenceHeads)
%ICDREVIDENCEFROMLESIONSEGMENTATION Build ICDR evidence from the learned net.
%   EVIDENCE = grade.icdrEvidenceFromLesionSegmentation(LESIONEVIDENCE)
%   turns the measurements from segment.lesionEvidence into the structured
%   evidence grade.icdrRule consumes.
%   EVIDENCE = grade.icdrEvidenceFromLesionSegmentation(LESIONEVIDENCE,
%   DETECTION) additionally accepts the classical Track A detection, which
%   supplies the microaneurysm count when the learned net was not trained
%   with an MA head.
%
%   EVIDENCE = grade.icdrEvidenceFromLesionSegmentation(LESIONEVIDENCE,
%   DETECTION, EVIDENCEHEADS) restricts the evidence to the named heads and
%   declares the rest as capability gaps.  A head the network was trained
%   for is not automatically a head its output can be trusted from: §11.7
%   measured the soft-exudate head at 0.0980 AUPR on 21 training frames,
%   and on APTOS it reports a median of 46 lesions on eyes graded 0.  Since
%   ICDR Level 2 fires on the PRESENCE of any non-microaneurysm finding,
%   the channel ORs its heads together and its specificity is bounded by
%   the worst of them, so one untrustworthy head caps the whole channel
%   whatever the others do.  Restricting the heads is therefore a
%   correctness control, not a tuning knob, and it belongs in
%   configuration rather than in this file (§13.3).
%
%   What this changes, against grade.icdrEvidenceFromDetection:
%
%   The classical channel owns exactly one of the eight evidence fields, so
%   the highest ICDR level it can reach is Level 1, microaneurysms-only.
%   That is the direct cause of the 0.0000 sensitivity the A3 ablation
%   measured for the evidence channel (§11.6): the channel was not
%   mis-tuned, it was structurally incapable of satisfying any criterion
%   above Level 1.  A haemorrhage or exudate head moves three more fields
%   from unknown to known, which makes Level 2 reachable at all and Level 3
%   reachable through the 4-2-1 haemorrhage criterion (§3.3).
%
%   Four fields stay unknown, and stay declared as capability gaps rather
%   than as facts about the patient: venous beading, IRMA,
%   neovascularisation and vitreous or preretinal haemorrhage.  IDRiD
%   carries no masks for any of them, so Level 4 remains unreachable from
%   evidence alone - the declared data gap of §6.6, whose stated mitigation
%   is that a Level 4 CNN prediction always escalates to a human.
%
%   Marking those four as capability gaps is what keeps the decision layer
%   working.  grade.icdrRule escalates on a case-level unknown, so
%   presenting a permanent, every-image gap as a per-case unknown would
%   escalate every patient and silently disable the triage the system
%   exists to perform.

if nargin < 2
    detection = [];
end
if nargin < 3
    evidenceHeads = {};
end
if ~isstruct(lesionEvidence) || ~isscalar(lesionEvidence) || ...
        ~isfield(lesionEvidence, 'counts')
    error('grade:InvalidLesionEvidence', ...
        ['Lesion evidence must be the scalar structure returned by ' ...
        'segment.lesionEvidence.']);
end

lesionTypes = lesionEvidence.lesionTypes;
counts = lesionEvidence.counts;

% A head that is not trusted is dropped from lesionTypes rather than
% reported with an unknown value. That distinction is load-bearing:
% grade.icdrRule escalates on a case-level unknown, so presenting a
% permanent, every-image restriction as a per-case unknown would escalate
% every patient and disable the triage the system exists to perform.
if ~isempty(evidenceHeads)
    if ischar(evidenceHeads)
        evidenceHeads = {evidenceHeads};
    end
    trusted = ismember(lesionTypes, evidenceHeads);
    if ~any(trusted)
        error('grade:NoTrustedLesionHeads', ...
            ['None of the configured evidence heads (%s) are present in ' ...
            'the lesion evidence (%s).'], strjoin(evidenceHeads, ', '), ...
            strjoin(lesionTypes(:)', ', '));
    end
    lesionTypes = lesionTypes(trusted);
end

unknownLogical = struct('value', [], 'known', false);

[microaneurysm, microaneurysmKnown, microaneurysmSource] = ...
    localMicroaneurysmCount(lesionTypes, counts, detection);

haemorrhage = struct('value', [], 'known', false);
if any(strcmp('HE', lesionTypes))
    if ~isfield(lesionEvidence, 'haemorrhageQuadrantCounts')
        error('grade:MissingQuadrantCounts', ...
            ['Lesion evidence carries a haemorrhage head but no quadrant ' ...
            'counts; the Level 3 criterion is per quadrant and cannot be ' ...
            'evaluated from a total.']);
    end
    quadrantCounts = lesionEvidence.haemorrhageQuadrantCounts;
    haemorrhage = struct('value', ...
        [quadrantCounts.ST, quadrantCounts.IT, ...
        quadrantCounts.SN, quadrantCounts.IN], 'known', true);
end

hardExudate = localOptionalCount(lesionTypes, counts, 'EX');
softExudate = localOptionalCount(lesionTypes, counts, 'SE');

coverage = struct( ...
    'microaneurysmCount', microaneurysmKnown, ...
    'haemorrhageCountPerQuadrant', haemorrhage.known, ...
    'hardExudateCount', hardExudate.known, ...
    'softExudateCount', softExudate.known, ...
    'venousBeadingPerQuadrant', false, ...
    'irmaPerQuadrant', false, ...
    'neovascularisation', false, ...
    'vitreousOrPreretinalHaemorrhage', false);

evidence = struct( ...
    'microaneurysmCount', struct('value', microaneurysm, ...
        'known', microaneurysmKnown), ...
    'haemorrhageCountPerQuadrant', haemorrhage, ...
    'hardExudateCount', hardExudate, ...
    'softExudateCount', softExudate, ...
    'venousBeadingPerQuadrant', unknownLogical, ...
    'irmaPerQuadrant', unknownLogical, ...
    'neovascularisation', unknownLogical, ...
    'vitreousOrPreretinalHaemorrhage', unknownLogical, ...
    'evidenceFieldCoverage', coverage, ...
    'evidenceSource', sprintf('learned lesion segmentation (%s)', ...
        strjoin(lesionTypes(:)', '+')), ...
    'microaneurysmSource', microaneurysmSource, ...
    'clinicalValidationStatus', ...
        'not clinically validated lesion segmentation');
end

function [value, known, source] = localMicroaneurysmCount(lesionTypes, ...
    counts, detection)
%LOCALMICROANEURYSMCOUNT Prefer the learned MA head, fall back to Track A.
%   §6.4 predicts the microaneurysm head is the one most likely to fail, and
%   Track A exists precisely so that failure cannot leave the field empty.

if any(strcmp('MA', lesionTypes))
    value = double(counts.MA);
    known = true;
    source = 'learned lesion segmentation';
    return;
end
if ~isempty(detection) && isstruct(detection) && ...
        isfield(detection, 'candidateCount')
    value = double(detection.candidateCount);
    known = true;
    source = 'classical candidate evidence';
    return;
end
value = [];
known = false;
source = 'unavailable';
end

function item = localOptionalCount(lesionTypes, counts, lesionType)
if any(strcmp(lesionType, lesionTypes))
    item = struct('value', double(counts.(lesionType)), 'known', true);
else
    item = struct('value', [], 'known', false);
end
end
