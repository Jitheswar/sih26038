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

## Comments

### Preliminary finding, 1 September 2026: the veto rejects A12, and it rejects A5

The veto can be computed ahead of the tooling, because `results/20260824_035401_full_metrics_validation/full_metrics.json` already carries per-case calibrated referable probabilities and reference labels for all 550 validation cases.
Reconstructing the CNN-only baseline from them gives 304 auto-clear, 246 refer and 4 referable sent home, which matches the harness's own A1 row in `results/20260824_132627_ablation_A1_A5/ablation_table.csv` exactly.
So the baseline used below is the harness's A1, not an approximation of it.

Ranking by the established confidence definition, `abs(referableProbability - 0.40)`, and truncating to each configuration's coverage:

| Cfg | Coverage | n autonomous | Cfg sends home | A1 sends home at same coverage | Admissible |
| --- | --- | --- | --- | --- | --- |
| A5 - classical, shipped until 31 Aug | 0.2745 | 151 | 1 | 0 | **No** |
| A9 - learned, hard exudates | 0.0691 | 38 | 0 | 0 | Yes |
| A10 - learned, endpoint levels, shipped | 0.3273 | 180 | 0 | 0 | **Yes** |
| A11 - learned, spatial advisory | 0.2436 | 134 | 2 | 0 | No |
| A12 - learned, both repairs | 0.6636 | 365 | 2 | 0 | **No** |
| A13 - classical, both repairs | 0.7382 | 406 | 4 | 1 | No |

The reason is that the classifier's four misses are all deep in its own low-confidence tail, at confidence ranks 400, 502, 512 and 542 of 550. A1 restricted to its most confident 66.4 per cent of cases sends nobody home. So the comparison that made A12 look safer than the classifier, 2 out of 365 against 4 out of 550, was comparing A12's misses against a baseline that included exactly the cases A12 declined to decide.

Tie-break independent: at every truncation boundary only one case sits on the cut, and no tie-breaking rule changes any verdict.

**A12 is inadmissible.** The clinical judgement it was parked on never has to be adjudicated, and the §12 dependency dissolves, which is what ADR 0001 anticipated.

**A5 is also inadmissible**, which is a retroactive finding about the configuration this project shipped until 31 August: its single miss at coverage 0.2745 is worse than the classifier alone deciding the same number of cases. A10 replaced it for unrelated reasons and happens to be the only non-trivial admissible configuration measured.

Caveats, all of which stand: these are small counts and the veto reads point estimates, so it separates these configurations by direction rather than decisively; the split is validation, which selected the training epoch; and this Python reconstruction is a preliminary finding, not a result. It is not a result until `missesAtCoverage.m` reproduces it through the harness on the real code path. That is what this ticket delivers.
