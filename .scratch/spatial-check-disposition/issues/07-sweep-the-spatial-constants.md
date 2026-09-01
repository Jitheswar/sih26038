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

## Comments

### Objective sharpened, 1 September 2026

The preliminary veto computation in issue 06 rejects A11 and A12, so demoting the gate is dead and D2 is now the only remaining route to coverage above A10's 0.3273.

That sharpens what the sweep is looking for. It is not "do these constants discriminate" in the abstract. It is:

**Does any (cut, fraction) pair raise coverage above 0.3273 while keeping referable-sent-home at or below the classifier's count at that same coverage?**

Note the baseline moves as coverage rises: A1 sends nobody home up to coverage 0.700, one patient at 0.738, and four at 1.000. So a recalibrated gate reaching coverage 0.70 must still send nobody home to remain admissible, while one reaching 0.74 is allowed a single miss.

If no pair clears that bar, the finding is that the gate cannot be tuned into admissibility and A10 stands as shipped. That is a perfectly good answer and it should be reported as one rather than treated as a failed experiment.
