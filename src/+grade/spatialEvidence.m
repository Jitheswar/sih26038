function evidence = spatialEvidence(gradCAMResult, detection)
%SPATIALEVIDENCE The normalized Grad-CAM values at the lesion candidates.
%   EVIDENCE = grade.spatialEvidence(GRADCAMRESULT, DETECTION) extracts the
%   quantity the §8.6 spatially-inconsistent test is taken from, without
%   taking the test.  It is deliberately free of the two constants, because
%   this half is expensive and the verdict half is not: one pass over a
%   split caches EVIDENCE, and grade.spatialVerdict then answers any
%   (cut, fraction) pair offline.
%
%   Fields.  VALUES are the normalized Grad-CAM values at the candidate
%   points.  KNOWN is false when there was no usable heatmap, which is not
%   the same as a candidate falling outside the attention.
%   CANDIDATESSCORED is zero when the lesion channel found nothing, which
%   is the vacuous case: no candidate can fall outside the attention, so
%   there is nothing to disagree about.  Those two zero-length cases mean
%   opposite things and are kept distinguishable here so a sweep cannot
%   silently average them together.
%
%   The cut this feeds is a fraction of peak attention and is meaningful
%   only on the normalized map.  Applying it to the unnormalized response,
%   whose scale is arbitrary and in practice tiny, made the check fire on
%   every image; that was the §8.6 defect fixed on 24 August, which is why
%   this reads normalizedHeatmap and nothing else.

evidence = struct('values', zeros(0, 1), 'known', false, ...
    'candidatesScored', 0);

if isempty(detection) || ~isstruct(gradCAMResult) ...
        || ~isfield(gradCAMResult, 'normalizedHeatmap') ...
        || isempty(gradCAMResult.normalizedHeatmap)
    % An absent detection reaches here from a configuration that runs
    % Grad-CAM without the lesion channel.  The harness copies this
    % function replaced both guarded it and returned "not agreement", so
    % the case escalated.  Without the guard it throws instead, and the
    % harness try/catch marks the image failed, which drops it from the
    % denominators rather than escalating it.  Dropping a case silently is
    % worse than escalating it, so the guard stays.
    return;
end

if detection.candidateCount == 0
    evidence.known = true;
    return;
end

heatmap = double(gradCAMResult.normalizedHeatmap);
coordinates = detection.candidateCoordinates;
valid = coordinates(:, 1) >= 1 & coordinates(:, 1) <= size(heatmap, 2) & ...
    coordinates(:, 2) >= 1 & coordinates(:, 2) <= size(heatmap, 1);
coordinates = round(coordinates(valid, :));
if isempty(coordinates)
    % Candidates exist but none land on the map.  Not vacuous and not
    % unknown: the channels genuinely fail to correspond.
    evidence.known = true;
    evidence.candidatesScored = 0;
    evidence.values = zeros(0, 1);
    evidence.outOfFrame = true;
    return;
end

linear = sub2ind(size(heatmap), coordinates(:, 2), coordinates(:, 1));
evidence.values = double(heatmap(linear));
evidence.values = evidence.values(:);
evidence.known = true;
evidence.candidatesScored = numel(evidence.values);
end
