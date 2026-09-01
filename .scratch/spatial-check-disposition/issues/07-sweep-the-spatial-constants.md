# Sweep the spatial check constants on the calibration split

Status: ready-for-agent
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
