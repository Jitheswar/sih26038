# Re-run the ablation with per-case output and the veto column

Status: ready-for-agent
Blocked by: 04, 05

## Problem

The A1-A13 table needs re-reporting under ADR 0001, and the 2 patients A12 sends home need identifying.

## Expected behaviour

Run `eval/ablationHarness.m` over the validation split for A1, A5, A9, A10, A11, A12, A13, producing `per_case.csv`, the equal-coverage baseline column and the `admissible` verdict for every row.

Then answer, from `per_case.csv`:

1. Which patients does each configuration send home? Reference grade, calibrated probability, CNN level, rule level, spatial statistic.
2. Is A12 admissible under the veto?
3. Is A13's rejection re-derived, or does it change?
4. For the patients the gate catches, where does the spatial statistic sit relative to the 0.35 cut? Near it means the gate caught them marginally; far means the constants are doing real work.

Question 4 is the direct evidence for whether the gate carries a safety property the mandatory under-detected check does not.

## Notes

About 8.3 s/image on the cached pass, roughly 76 minutes for 550 images, then the per-configuration replays are cheap.
Results to a dated directory with the full config alongside, never overwritten.

## Acceptance

- Dated results directory with `ablation_table.csv`, `per_case.csv` and configs
- The four questions answered in writing against the data, appended to this issue
- Every missed-referable patient named with their grade and spatial statistic
