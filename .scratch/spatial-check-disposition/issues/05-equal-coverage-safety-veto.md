# Add the equal-coverage safety veto metric

Status: ready-for-agent
Blocked by: none

## Problem

Configurations that decide different fractions of the caseload are being compared on raw miss counts. A13's rejection compares its 4 misses across the 406 cases it chose to decide against A1's 4 across all 550. Those are different denominators over different case mixes, and a deferral pipeline sheds exactly the low-confidence cases where a classifier's errors concentrate.

`eval/metrics/riskCoverage.m` exists and its own documentation says "§11.6 asks for exactly this comparison: A5 against A1 at equal coverage". The harness prints "Compare A5 with A1 at equal coverage" at the foot of every run. It was never done.

See [ADR 0001](../../docs/adr/0001-equal-coverage-safety-veto.md) for the decision this implements.

## Expected behaviour

A new metric, `eval/metrics/missesAtCoverage.m`, returning how many referable patients the classifier alone sends home when truncated to a given coverage.

Reuse the established definitions from `eval/fullMetricReport.m` verbatim: correctness is agreement on the referable endpoint, confidence is `abs(referableProbability - frozen.referable_threshold)`. Rank by confidence descending, truncate to the requested coverage, count auto-cleared referable cases among the retained.

Critically the risk curve counts **false negatives only**, not symmetric correctness. `riskCoverage` as written scores a false positive and a false negative identically; the veto's subject is the patient sent home. Report the symmetric curve alongside, off the same ranking, but the veto reads the false-negative curve.

`ablationHarness` gains a `baseline_misses_at_equal_coverage` column and an `admissible` boolean per configuration.

## Notes

Ties in confidence at the truncation boundary need a stated, deterministic rule; document whichever is chosen.
Expect the veto to be unable to discriminate finely at these counts. That is stated wherever it is applied, not hidden.

## Acceptance

- `missesAtCoverage` with hand-computed unit tests, in the style of the other files in `eval/metrics/`
- Ablation table carries the baseline column and the `admissible` verdict for every configuration
- A test covers the boundary case where coverage is 1.0 and the answer must equal the classifier's own miss count
