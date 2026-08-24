function answer = evidenceSupportsCNN(predictedLevel, detection, rule)
%EVIDENCESUPPORTSCNN Does the lesion channel back the classifier's call?
%   For a referable prediction the test is the under-detected check of the
%   design's agreement table: a Level 2+ call with no lesion evidence behind
%   it is the case a human must see, because either the detector missed
%   findings or the classifier is keying on something that is not disease.
%
%   For a non-referable prediction the test is whether the rule engine also
%   reads the evidence as non-referable.  Requiring zero candidates would
%   contradict the ICDR scale itself, where Level 1 is defined as
%   microaneurysms only: a Level 1 image is supposed to carry candidates, so
%   counting them as evidence against a Level 1 call is backwards.
%
%   Shared by app.runScreeningCase and eval/ablationHarness.m so the
%   ablation cannot drift from the deployed pipeline.

if predictedLevel >= 2
    answer = detection.candidateCount > 0 || rule.referable;
else
    answer = ~rule.referable;
end
end
