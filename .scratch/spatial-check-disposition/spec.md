# Spatial check disposition

## Why

The Grad-CAM spatial check is the largest single cause of escalation in every measured configuration: 335 of 399 escalations in A5, 340 of 525 in A7, 314 of 512 in A9.
§8.6 specifies the state it raises as "Flag in the report as reduced explanation confidence. Consider escalation", which is an advisory with escalation to be considered.
The implementation raises it as a mandatory reason code that forces escalation.

Its test is `mean(heatmap(candidatePoints) >= 0.35) >= 0.25`.
Neither constant is in configuration and neither was selected against data, which contradicts §13.3.
§8.3 records that at 448x448 the Grad-CAM map is 14x14, one cell covers roughly 32x32 input pixels, and the method physically cannot localise a microaneurysm; a gate requiring candidates to sit on attention peaks asks the channel for precision the design says it does not have.
The check has already produced a total-escalation defect once, when the cut was applied to the unnormalized map.

A12 measures *removing* the gate and reaches 0.6636 coverage against A10's 0.3273.
Nobody has measured *tuning* it.
The decision was parked awaiting the §12 clinician review; §12 has not started, has no participant, and §12.5 already documents the fallback for nobody responding.

## What this delivers

A disposition for the spatial check, decided on evidence, recorded, and either shipped or explicitly rejected before the configuration freeze.

Five candidate dispositions were considered:

- **D1** demote to advisory (measured, A12)
- **D2** keep as a gate, constants recalibrated against data (unmeasured)
- **D3** re-specify at the regional resolution §8.3 says Grad-CAM has (out of scope, see below)
- **D4** keep exactly as-is
- **D5** move the constants into configuration with no value change

D5 ships unconditionally: it is a §13.3 defect independent of which disposition wins.
D1 and D2 are measured from cached passes and the winner is chosen against the safety veto.
D3 is descoped: it is new design and new code, and it is only justified if D2's sweep shows that no constant pair separates the classes.

## Constraints

**The safety veto governs admissibility.** See [ADR 0001](../../docs/adr/0001-equal-coverage-safety-veto.md). A configuration is inadmissible if it sends more referable patients home than the classifier alone does at equal coverage. Passing the veto does not mean adopting; above the veto the argument is from several measures moving together, never from coverage.

**No clinician is assumed.** The disposition must be decidable from measurement and from §8.6's own wording. If a clinician becomes available, the reader study is better spent on R4.5 and the misleading-explanation flag than on ratifying a configuration flag.

**The frozen operating point is untouched.** Threshold 0.40, temperature 2.1414, checkpoint `results/20260823_184930/epoch_08.mat`. Nothing here re-selects any metric behind them.

**The sealed set stays sealed until the configuration is settled.** §10.4 opens it once. That puts this work on the critical path: configuration frozen 8 September, unseal about 10 September, finale 15 September.

**Selection split discipline.** The D2 sweep selects on the calibration split (n=365), following the precedent set when the lesion evidence thresholds were re-selected in `636f803`, and reports on validation (n=550). Validation already selected the training epoch and carries every ablation number; it is not also used to select these constants.

**The sweep does not select for coverage.** D2 characterises whether the constants can discriminate at all. If no pair separates the missed-referable cases from the rest, that is the finding, and it retires the gate on evidence rather than on wording alone.

## Out of scope

- D3, the regional re-specification.
- The §12 clinician reader study. Recorded as descoped, not as pending.
- Any change to the operating point, the checkpoint, the temperature or the trusted lesion heads.
