# Measure the confidence-ranked deferral baseline (A14)

Status: ready-for-agent
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
