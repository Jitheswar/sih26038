function [agree, evidence] = spatialAgreement(gradCAMResult, detection, configuration)
%SPATIALAGREEMENT Do the lesion candidates sit where the model is looking?
%   [AGREE, EVIDENCE] = grade.spatialAgreement(GRADCAMRESULT, DETECTION,
%   CONFIGURATION) is the §8.6 spatially-inconsistent test, for callers
%   that want the verdict in one step.  It is grade.spatialVerdict applied
%   to grade.spatialEvidence and holds no rule of its own.
%
%   Callers that evaluate many configurations over one split should use
%   the two separately: the evidence half is the expensive one and does
%   not depend on the constants, so it is computed once per image and the
%   verdict is then free for every (cut, fraction) pair.
%
%   §8.3 records that at 448x448 the Grad-CAM map is 14x14, one cell
%   covering roughly 32x32 input pixels, so the method cannot localise a
%   microaneurysm and is to be read as regional attention.  A test asking
%   whether candidate points coincide with attention peaks asks that
%   channel for precision §8.3 says it does not have.  The split above
%   exists so that claim can be measured rather than argued.

evidence = grade.spatialEvidence(gradCAMResult, detection);
if nargin < 3
    configuration = struct();
end
[agree, clearedFraction] = grade.spatialVerdict(evidence, configuration);
evidence.clearedFraction = clearedFraction;
end
