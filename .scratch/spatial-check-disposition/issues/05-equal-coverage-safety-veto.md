# Add the equal-coverage safety veto metric

Status: resolved
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

## Resolution

Landed in cfff805 (metric) and d53cb83 (application). missesAtCoverage counts false negatives only and drops tied groups at the boundary, erring toward vetoing. equalCoverageVeto applies it to an ablation table and refuses to run if its reconstructed classifier disagrees with the harness A1 row.

### Correction, 4 September 2026

**One acceptance criterion is not met and was signed off anyway.**

"Ablation table carries the baseline column and the `admissible` verdict for every configuration" did not land.
`eval/ablationHarness.m` gained neither `baseline_misses_at_equal_coverage` nor `admissible`, and `ablation_table.csv` carries neither column.
The veto lives entirely in the standalone `eval/equalCoverageVeto.m`, which reads a finished ablation table and applies the metric to it.

That is arguably the better design and it is the reason to record the deviation rather than retrofit it four days from the configuration freeze.
The veto needs the A1 classifier row, which only exists after a full run, and `equalCoverageVeto` refuses to run when its reconstructed classifier disagrees with that row.
Putting the veto inside the harness would make the harness depend on a comparison that is only meaningful once every configuration in the study has finished, and would change the schema of an output the sealed read consumes.

So the criterion is superseded, not satisfied.
The number it asked for is published, in the veto table in §11.6 and the README, from a separate tool.
