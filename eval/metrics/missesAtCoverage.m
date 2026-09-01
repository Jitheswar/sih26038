function result = missesAtCoverage(truthReferable, predictedReferable, confidence, coverage)
%MISSESATCOVERAGE Referable patients sent home by the classifier alone.
%   RESULT = missesAtCoverage(TRUTHREFERABLE, PREDICTEDREFERABLE,
%   CONFIDENCE, COVERAGE) returns how many referable patients the
%   classifier auto-clears once its queue is ranked by confidence and
%   truncated to COVERAGE.  COVERAGE may be a vector, in which case every
%   count in RESULT is a vector of the same length, read off one ranking.
%
%   This is the equal-coverage baseline the safety veto of ADR 0001 reads.
%   Configurations that decide different fractions of the caseload cannot
%   be compared on raw miss counts: a deferral pipeline sheds exactly the
%   low-confidence cases where a classifier's errors concentrate, so its
%   count over a self-selected subset flatters it against a classifier's
%   count over everything.  The matched comparison is the classifier's own
%   best COVERAGE of cases, and this returns it.
%
%   It counts false negatives only.  riskCoverage scores a false positive
%   and a false negative identically, which is right for accuracy and
%   wrong here: the veto's whole subject is the patient who goes home
%   undiagnosed, and a patient referred unnecessarily is a different and
%   recoverable event (§3).  SYMMETRICERRORS reports the symmetric count
%   off the same ranking, so the two are visible side by side, but the
%   veto reads MISSES.
%
%   The definitions are those of eval/fullMetricReport.m, unchanged:
%   correctness is agreement on the referable endpoint (§11.2), and
%   confidence is distance from the frozen threshold, since a case sitting
%   on the threshold is the one to hand to a human.
%
%   Ties at the truncation boundary drop the whole tied group.  A boundary
%   that falls inside a run of equal confidences has no ranked answer, so
%   the alternatives are to keep the group, to drop it, or to break the tie
%   on input order.  Input order is the row order of a split CSV, which
%   would make a safety verdict depend on how the file was sorted, so it is
%   not used.  Keeping the group would hand the baseline extra cases and so
%   extra misses, making the baseline easier for a candidate configuration
%   to beat; dropping it errs the other way, toward vetoing.  For a safety
%   veto that is the correct direction, so the group is dropped.  RETAINED
%   and ACHIEVEDCOVERAGE report what was actually scored, which can be less
%   than COVERAGE asked for.  Full coverage has no boundary to cut and is
%   therefore never affected: at COVERAGE 1 the answer is the classifier's
%   own miss count.
%
%   Counts, not rates (§11.1).  At these magnitudes the Wilson intervals on
%   1, 2 and 4 misses overlap heavily, so a rate would imply a precision
%   the interval does not support, and the veto's inability to discriminate
%   finely is to be stated wherever it is applied rather than dressed up.

rng(42);

truthReferable = logical(truthReferable(:));
predictedReferable = logical(predictedReferable(:));
confidence = double(confidence(:));
if numel(truthReferable) ~= numel(predictedReferable) || ...
        numel(truthReferable) ~= numel(confidence)
    error('eval:LengthMismatch', ...
        'Truth, prediction and confidence must have the same number of elements.');
end
if ~all(isfinite(confidence))
    error('eval:InvalidConfidence', ...
        'Confidence must be finite; an unrankable case cannot be truncated on.');
end

coverage = double(coverage(:));
if isempty(coverage) || ~isreal(coverage) || ~all(isfinite(coverage)) || ...
        any(coverage < 0) || any(coverage > 1)
    error('eval:InvalidCoverage', ...
        'Coverage must be finite and between zero and one.');
end

n = numel(truthReferable);
if n == 0
    result = struct('requestedCoverage', coverage, ...
        'retained', zeros(size(coverage)), ...
        'achievedCoverage', nan(size(coverage)), ...
        'misses', nan(size(coverage)), ...
        'symmetricErrors', nan(size(coverage)), ...
        'totalMisses', NaN, 'n', 0, ...
        'curve', struct('retained', [], 'coverage', [], 'misses', [], ...
            'symmetricErrors', []));
    return;
end

% A miss is a referable patient the classifier auto-cleared.  A symmetric
% error is any disagreement on the endpoint, which is what riskCoverage
% counts and what the veto deliberately does not read.
missed = truthReferable & ~predictedReferable;
errored = predictedReferable ~= truthReferable;

[sortedConfidence, order] = sort(confidence, 'descend');
cumulativeMisses = cumsum(missed(order));
cumulativeErrors = cumsum(errored(order));

% The truncations the ranking can actually resolve are the ends of the
% tied groups, plus the empty prefix.  Every other cut falls inside a
% group and is answered by the group below it.
groupEnd = [sortedConfidence(1:end - 1) > sortedConfidence(2:end); true];
curveRetained = [0; find(groupEnd)];
curveMisses = [0; cumulativeMisses(groupEnd)];
curveErrors = [0; cumulativeErrors(groupEnd)];

% Cases asked for, floored to whole patients.  The tolerance absorbs the
% rounding in COVERAGE * N when COVERAGE was itself computed as a case
% count divided by N, where 140/550*550 can land just below 140.
scaled = coverage * n;
requested = floor(scaled + 1e-9 * max(1, scaled));

% The last resolvable truncation at or below what was asked for.
selected = sum(curveRetained' <= requested, 2);
retained = curveRetained(selected);

result = struct( ...
    'requestedCoverage', coverage, ...
    'retained', retained, ...
    'achievedCoverage', retained / n, ...
    'misses', curveMisses(selected), ...
    'symmetricErrors', curveErrors(selected), ...
    'totalMisses', cumulativeMisses(end), ...
    'n', n, ...
    'curve', struct( ...
        'retained', curveRetained, ...
        'coverage', curveRetained / n, ...
        'misses', curveMisses, ...
        'symmetricErrors', curveErrors));
end
