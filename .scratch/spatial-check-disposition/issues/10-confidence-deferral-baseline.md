# Measure the confidence-ranked deferral baseline (A14)

Status: resolved
Blocked by: 05

## Problem

Computing the equal-coverage veto for issue 06 surfaced something larger than the question it was asked to answer.

A deferral policy that ignores every channel this project built, and simply defers the cases where the calibrated probability sits closest to the frozen threshold, reaches **coverage 0.7255 with zero referable patients sent home** on the validation split.

The shipped A10 pipeline, with quality gating, lesion evidence, the ICDR rule trace, Grad-CAM and the full agreement check, reaches **coverage 0.3273 with zero**.

At equal safety, ranking on `abs(referableProbability - 0.40)` alone covers 2.2 times as many patients as the entire three-channel apparatus.

This is the obvious question a judge asks: why not just threshold on the calibrated confidence? Right now the project has no measured answer, and §11.6 contains no such baseline. A1 is the classifier at full coverage, and A4 defers on a different criterion; neither is this.

## The in-sample caveat, which is large

0.7255 is the highest coverage at which *this split* happens to carry zero misses. Selecting that operating point on the same data that measures it is selection on the evaluation set, which is the error this project is otherwise careful about. An honest number requires the coverage or the confidence cut to be committed in advance, on the calibration split, and then reported on validation.

The comparison must be run that way. The in-sample figure above is the reason to run it, not the result of it.

## Expected behaviour

Add **A14: confidence-ranked deferral**, a configuration that defers on `abs(referableProbability - autoClearThreshold)` alone, with no quality gate, no lesion evidence, no agreement check.

Select its coverage on the **calibration** split (n=365), then report it on **validation** (n=550) alongside every other configuration, with the equal-coverage veto applied to it like any other row.

Report the risk-coverage curves of A14 and the shipped configuration on one set of axes. The existing AURC for the classifier is 0.0222 against a base risk of 0.0564.

## Why this strengthens the project rather than undermining it

The pipeline's claim was never that it beats confidence thresholding on in-domain miss count. It is that a confidence score is not an explanation, and that a confidently wrong prediction keyed on a non-pathological image property ranks **high** in confidence and would be auto-decided by A14 with nothing to catch it. That is precisely the failure mode §8.6 is built around and §11.7 measures.

But that argument is currently unmeasured, and it points somewhere specific: the difference should appear under domain shift, not on the split the model was tuned on. The sealed Messidor-2 set (§10.4) is the only external read available and is therefore the experiment that decides this, which raises the stakes on the unseal considerably.

Recording the finding with its answer is much stronger than having a judge find it. The design document already records corrections after the fact, and this is one.

## Acceptance

- A14 implemented as an ablation configuration, coverage selected on calibration
- Reported on validation in the §11.6 table with the veto column applied
- Risk-coverage curves for A14 and the shipped configuration reported together
- §11.6 states the finding plainly, including that A14 dominates the pipeline on in-domain coverage at equal safety, and what the pipeline claims in exchange
- The claim that the pipeline holds up better out of domain is written down as the prediction the sealed-set read will test, before that read happens

## Resolution

Measured with `eval/confidenceDeferral.m`. The cut was selected on the calibration split (n=365) at a zero-miss budget, giving confidence >= 0.332877 and covering 0.7671 of that split with nobody sent home, then applied unchanged to validation.

| Cfg | Coverage | Referable sent home | clear / refer / escalate |
| --- | --- | --- | --- |
| A10 - the pipeline that ships | 0.3273 | 0 | 139 / 41 / 370 |
| A12 - the pipeline at its most permissive | 0.6636 | 2 | 244 / 121 / 185 |
| **A14 - calibrated probability alone** | **0.7527** | **1** | **219 / 195 / 136** |

A14 covers more of the caseload than any pipeline configuration measured, and beats A12 and A13 on both axes at once.

The veto is vacuous for A14 by construction, which the ticket did not anticipate: A14 is confidence-ranked truncation of the classifier, and that is exactly what ADR 0001 truncates to build its baseline, so A14 equals its own baseline at every coverage. It can be neither admitted nor rejected on that criterion. The comparison that means something is inverted, coverage at equal misses, and on that the pipeline loses.

The bound is structural rather than a matter of tuning. A gate can only escalate more, never less, so the most permissive the agreement check can be is the no-gate case, A12 at 0.6636 with two sent home. No setting of the two spatial constants lifts the pipeline past A14 on this split, which is why ADR 0002 records the D2 sweep as an optimisation within the pipeline rather than an answer to §11.6.

Two limits of the split are recorded with the result. It contains no ungradable image (511 gradable, 39 borderline), so the quality gate never rejects a frame and A14's lack of one costs it nothing measurable here. And the failure §8.6 exists to catch, a confident prediction keyed on a non-pathological image property, ranks high in A14's ordering and is auto-decided with nothing to stop it; that failure barely occurs in domain, which is why A14 wins here.

The prediction that the ordering reverses under domain shift is written into §11.6 before the sealed Messidor-2 set is opened, so it cannot be fitted to the result afterwards.

Written up in §11.6, the README status section, and ADR 0002.

### Correction, 4 September 2026

**The first acceptance criterion is not met and was signed off anyway.**

"A14 implemented as an ablation configuration, coverage selected on calibration" did not land as written.
The second half is satisfied: the cut is selected on calibration at a zero-miss budget and applied unchanged to validation, and `eval/confidenceDeferral.m` refuses with `eval:SelectionSplitReused` if selection and reporting name the same split.
The first half is not.
There is no `config/ablation_A14.json`, A14 is not a configuration the harness can run, and it appears in no row of `ablation_table.csv`.
It is a standalone tool whose numbers were transcribed into the §11.6 and README tables by hand.

The consequence is worth naming rather than hiding.
Every other row in those tables is reproduced by re-running the harness; the A14 row is not, and a transcription error in it would not be caught by any test.
Implementing A14 as an ablation configuration is the repair, and it is deliberately not being done before the configuration freeze: it would add a configuration to a study whose table is about to be frozen and read against the sealed set.
It is recorded here as owed.
