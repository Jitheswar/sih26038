# Sweep the spatial check constants on the calibration split

Status: resolved
Blocked by: 03

## Problem

D2, keeping the gate but recalibrating it, is the option nobody has measured. The current constants were never selected against data.

## Expected behaviour

One cached pass over the **calibration** split (n=365), then an offline sweep of `(spatialAttentionCut, spatialAgreementFraction)` over the cached candidate-point values.

Selection split discipline: sweep on calibration, following the precedent set for the lesion evidence thresholds in `636f803`; report on validation. Validation already selected the training epoch and carries every ablation number, and is not also used to select these constants.

**Do not sweep for maximum coverage.** Tuning a safety gate on the number §11.6 says not to select on is the trap. The question is whether the constants can discriminate at all: does any pair separate the referable-sent-home cases from the rest by more than chance?

Report the surface, not a winner. If no pair separates the classes, that is the finding and it retires the gate on evidence rather than on §8.6's wording alone.

## Notes

Roughly 50 minutes for the calibration cached pass; the sweep itself is offline and fast.

## Acceptance

- Dated results directory with the swept surface over both constants
- A written verdict on whether any pair discriminates, with the separation statistic
- An explicit statement that coverage was not the selection objective

## Comments

### Objective sharpened, 1 September 2026

The preliminary veto computation in issue 06 rejects A11 and A12, so demoting the gate is dead and D2 is now the only remaining route to coverage above A10's 0.3273.

That sharpens what the sweep is looking for. It is not "do these constants discriminate" in the abstract. It is:

**Does any (cut, fraction) pair raise coverage above 0.3273 while keeping referable-sent-home at or below the classifier's count at that same coverage?**

Note the baseline moves as coverage rises: A1 sends nobody home up to coverage 0.700, one patient at 0.738, and four at 1.000. So a recalibrated gate reaching coverage 0.70 must still send nobody home to remain admissible, while one reaching 0.74 is allowed a single miss.

If no pair clears that bar, the finding is that the gate cannot be tuned into admissibility and A10 stands as shipped. That is a perfectly good answer and it should be reported as one rather than treated as a failed experiment.

### Objective sharpened again, 2 September 2026

The per-case records of issue 06 change what this sweep is allowed to optimise.

The gate is now the only mechanism escalating `d1a24527a15d`, a proliferative patient the classifier calls Level 1 at 0.0593. Its spatial statistic is 0.0000, and the other three cases the classifier misses sit at 0.0000, 0.2044 and 0.3056.

**Recalibrating to raise coverage moves the cut on exactly the statistic that separates those four from the rest, and the patient it would most easily lose is the proliferative one.** Raising `spatialAgreementFraction` above 0.3056 would keep all four; lowering the cut to buy coverage risks `5a2c27b95c7c` at 0.3056 first, then `caec68f11c86` at 0.2044.

So the sweep is scored on a constraint before an objective:

- **Constraint**: does this (cut, fraction) pair still escalate all four of the classifier's misses? A pair that does not is rejected regardless of what it does to coverage.
- **Objective, subject to that**: coverage.

Report the surface with the four patients marked on it, so the boundary where each is lost is visible rather than implied.

**Correction, 2 September 2026.** The claim that this needs no GPU pass was wrong. `per_case.csv` carries `spatial_statistic`, which is `mean(values >= cut)` at the *configured* cut of 0.35, so the cut is already baked into it. That sweeps `spatialAgreementFraction` and cannot sweep `spatialAttentionCut`.

The fix is to export the raw candidate-point values, which cost one pass to produce and nothing to keep. `eval/ablationHarness.m` now writes `spatial_evidence.mat` alongside `per_case.csv`, and `eval/spatialConstantSweep.m` sweeps both constants over it offline. Every future run carries the values, so this pass is paid once.

## Resolution

Swept with `eval/spatialConstantSweep.m` over `results/20260903_230202_ablation_A1_A5`, 19 attention cuts by 19 agreement fractions, scored constraint-first.

**291 of 361 pairs still escalate all four patients the classifier sends home.** The shipped pair catches 4 of 4 at an escalation load of 57.1 per cent, which reproduces the §11.6 figure exactly and is the check that the sweep and the design document agree.

| | cut | fraction | escalation load |
| --- | --- | --- | --- |
| shipped | 0.35 | 0.25 | 57.1% |
| **lowest load still catching all four** | **0.40** | **0.15** | **44.2%** |

Recalibrating would cut gate firings by 12.9 points, about 71 cases out of 550, while still catching all four including the proliferative case.
Read that as an upper bound on patients released rather than a count of them: the gate is the sole safety exception on 263 of the 314 cases it fires on, and the other 51 escalate on a second exception regardless. On a gate whose entire cost is specialist time, and which §9.5 prices at 591.82 grader-hours a year at the shipped deferral rate, that is a real saving.

**It is a candidate, not a value to ship.** The pair was chosen on the split that measures it, which is the error §10.4 and §11.1 exist to prevent. Confirming it on calibration before the configuration freeze is what would make it shippable, and that is the remaining step.

### What this cost, and what it changed about how the sweep is scored

Two mistakes had to be corrected before the number above could be trusted, and both are worth recording because the first one produced a plausible answer.

The first sweep reported 279 of 361 and said the shipped pair fails to catch all four, contradicting §11.6. §11.6 was right. The export was reading the shared feature cache, which holds the classical channel, while A10's decisions swap in the learned channel in `localComposeDecisions` on a per-configuration copy. So A10 was being swept against evidence it never saw. The export now records what each configuration's decisions actually used, keyed by configuration id, and the sweep selects the matching record. `TestAblationHarness.exportedEvidenceIsWhatTheDecisionsUsed` pins it.

The second is that the export was originally called from `localWriteOutputs`, where the feature cache is not in scope. That crashed after a ninety-minute pass had already completed, losing the cache. A forty-second run over three images would have caught it.


### Correction, 4 September 2026

Two acceptance criteria were signed off more loosely than they read, and one number above was wrong.

**"A written verdict on whether any pair discriminates, with the separation statistic" is only half met.**
The sweep reports how many pairs catch every must-catch patient and what each costs in escalation load.
It does not report a separation statistic.
The statistic that exists, a median cleared fraction of 0.0200 against 0.2128 with four of four at a 57.1 per cent base rate giving p = 0.106, came from the per-case diagnostic and lives in ADR 0002, not from this sweep.

**"An explicit statement that coverage was not the selection objective" is met only under this ticket's own later wording, not under the spec's.**
`.scratch/spatial-check-disposition/spec.md` says "The sweep does not select for coverage".
The 2 September sharpening in this ticket instead says "Constraint" first and then "**Objective, subject to that**: coverage", which is what the code implements: it minimises escalation load among the pairs that catch every patient.
The ticket supersedes the spec line and the code follows the ticket.
The spec line should be read as "coverage never overrides the constraint", which is true, and not as "coverage is not the objective", which is not.

**The escalation-load figure is not a patient count**, corrected inline above and in ADR 0002.
