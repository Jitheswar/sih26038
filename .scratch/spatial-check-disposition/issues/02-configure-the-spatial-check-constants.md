# Move the spatial check's constants into configuration

Status: claimed
Blocked by: 01

## Problem

`localSpatialAgreement` in `src/+app/runScreeningCase.m` is `mean(heatmap(candidatePoints) >= 0.35) >= 0.25`.
Neither constant is in configuration.
§13.3 requires every pipeline mechanism to switch from `config/*.json` rather than by editing code, and §11.6 records this as the one §8.6 state that cannot be switched from configuration.

`eval/ablationHarness.m` holds its own copy of the same function. The two must stay in step; `TestAblationHarness` pins the harness against the deployed pipeline case for case.

## Expected behaviour

Two new keys under `decision_policy`, defaulting to today's values so no shipped behaviour changes:

- `spatialAttentionCut`: 0.35, the fraction-of-peak attention a candidate point must reach
- `spatialAgreementFraction`: 0.25, the fraction of candidate points that must reach it

Validated by `decisionConfiguration` the same way the existing thresholds are: finite, real, in [0, 1].

Extract the shared implementation to one function, `grade.spatialAgreement`, called by both `runScreeningCase` and `ablationHarness`, in the same way `grade.evidenceSupportsCNN` is already shared between them. Two copies of a safety test is the defect that `e734add` fixed for evidence construction and it should not be reintroduced here.

## Notes

This ships regardless of which disposition wins for the check itself. It is a §13.3 compliance fix, not a policy change.

## Acceptance

- Both constants read from configuration, defaults unchanged
- One shared `grade.spatialAgreement`, no second copy anywhere
- `TestAblationHarness` drift pin still passes
- Full suite green with no numeric expectation changed
