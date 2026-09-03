# ADR 0002: The Grad-CAM spatial check stays a gate, and its constants become configurable

Date: 2026-09-02

Status: Accepted

Supersedes the "recommendation awaiting the §12 review" recorded in §11.6 on 31 August 2026.

## Context

The Grad-CAM spatial check is the largest single cause of escalation in every measured configuration: 335 of 399 escalations in A5, 340 of 525 in A7, 314 of 512 in A9.

Three things were true of it and pulled in opposite directions.

§8.6 specifies the spatially-inconsistent state as "Flag in the report as reduced explanation confidence. Consider escalation", which is an advisory with escalation to be considered, while the implementation raised it as a mandatory reason code. §8.3 records that at 448x448 the Grad-CAM map is 14x14, one cell covering roughly 32x32 input pixels, and that the method cannot localise a microaneurysm, so a test demanding that candidate points coincide with attention peaks asks the channel for precision the design says it lacks. Both argue for demotion.

Against that, A12 measured demotion and reached coverage 0.6636 against A10's 0.3273, a 9.6-fold increase over A9, for two referable patients sent home. The decision was parked as a clinical judgement awaiting the §12 reader study.

Four dispositions were considered: **D1** demote to advisory, **D2** keep as a gate with constants recalibrated against data, **D3** re-specify at the regional resolution §8.3 says Grad-CAM has, **D4** keep as-is, and **D5** move the constants into configuration with no value change.

## Decision

**D1 is rejected on evidence.** Under the ADR 0001 equal-coverage veto, A12 sends two referable patients home where the classifier, deciding the same number of cases, sends none, and is inadmissible. A11, which isolates the demotion alone, is inadmissible for the same reason. The clinical judgement the decision was parked on does not have to be adjudicated, and `escalateOnExplanationDisagreement` stays `true` because the measurement says so rather than because no reviewer was available.

**D5 ships, independently of the above.** Both constants now live in `config/*.json` under `decision_policy` as `spatialAttentionCut` and `spatialAgreementFraction`, defaulting to the 0.35 and 0.25 that have always shipped, so no deployed behaviour changes. This is a §13.3 defect repair and was owed regardless of which disposition won: §11.6 had recorded this as the one §8.6 state that could not be switched from configuration, and the test existed as two separate copies each carrying the constants inline.

**D4 stands for now, and D2 remains open** as an optimisation within the pipeline rather than as an answer to §11.6's central table. The implementation is prepared for it: the test is split into `grade.spatialEvidence`, which is expensive and free of the constants, and `grade.spatialVerdict`, which is cheap and applies them, so one cached pass over a split answers any (cut, fraction) pair offline.

**D3 is descoped**, and would only be justified if a D2 sweep showed that no constant pair separates the classes.

**The §12 reader study is recorded as descoped rather than pending.** It has no participant and has not started, §12.5 already provides for its absence, and no decision now depends on it. If a clinician does become available, the study is better spent on R4.5 and the misleading-explanation flag than on ratifying a configuration flag.

## Consequences

The shipped configuration is unchanged in behaviour. `config/default.json` keeps `escalateOnExplanationDisagreement: true` and `levelComparison: endpoint`, and gains the two spatial constants at their historical values. The operating point frozen on 23 August is untouched.

**A recalibrated gate cannot rescue the pipeline's coverage, and this bounds how much D2 is worth.** A gate can only escalate more, never less, so the highest coverage the agreement check can reach with the learned channel is the no-gate case: A12, at 0.6636 with two sent home. A14, deferring on the calibrated probability alone, reaches 0.7527 with one. No setting of these two constants lifts the pipeline past that baseline on this split, so D2 is worth doing to improve A10 and not worth doing to win the comparison in §11.6.

## Addendum, 2 September 2026: the gate is now justified, not merely kept

This ADR was written saying the gate was kept without any measurement showing it catches something the mandatory under-detected check does not, and that identifying the patients each configuration sends home would settle it. That evidence now exists and it settles it in the gate's favour.

`d1a24527a15d` is graded 4, proliferative. The classifier calls it Level 1 at a calibrated referable probability of 0.0593, and the rule engine also reads Level 1, so the channels agree and the status is concordant. The under-detected check does not fire, because it runs on a referable prediction. `alwaysEscalateLevel4` does not fire, because it reads the predicted level and not the reference grade. In A10 the gate is the only mechanism that escalates this patient, and it fires with zero of the candidates reaching the attention cut. A11, A12 and A13 all auto-clear the case.

This also revises the reasoning above. D1 was already rejected by the veto, and the rejection now has a mechanism rather than only a count: the two patients A12 sends home include a proliferative case that no other check in the pipeline catches.

It further revises what §8.3 was taken to imply. §8.3 is right that a 14x14 map cannot localise a microaneurysm, and this ADR read that as the gate asking for precision the channel lacks. Across 548 cases the gate fires on 57.1% of cases the classifier gets right and on all four it sends home, whose median statistic is 0.0200 against 0.2128. Four of four at that base rate is p = 0.106, so the discrimination claim is a direction rather than a demonstration. But a channel too coarse to say *where* a lesion is can still say that attention and evidence are not in the same place at all, which is what this gate reads.

**D2's value is revised upward and its risk is now explicit.** Recalibrating the constants to raise coverage would move the cut on the very statistic that separates these four patients from the rest, and the patient it would most easily lose is the proliferative one. Any sweep must be scored on whether it still escalates all four, not on coverage.

## Addendum, 3 September 2026: D2 is measured, and it is worth about 71 patients

The sweep that addendum called for has run. `eval/spatialConstantSweep.m` over 19 attention cuts by 19 agreement fractions, scored constraint-first: a pair that stops escalating any of the four is rejected whatever it does to coverage.

**291 of 361 pairs still escalate all four.** The shipped pair catches 4 of 4 at an escalation load of 57.1 per cent, reproducing the §11.6 figure exactly. The lowest load among pairs that still catch all four is `spatialAttentionCut` 0.40 with `spatialAgreementFraction` 0.15, at 44.2 per cent.

That is 12.9 points, about 71 fewer patients sent to a human out of 550, at no measured cost in the patients the gate exists to catch. §9.5 prices the shipped deferral rate at 591.82 grader-hours a year against 214.65 at the scenario rate, so this is a saving denominated in the scarcest resource the district model has.

**It does not ship on this evidence.** The pair was selected on the validation split, which is the split that measures it, and this project does not get to select a safety constant that way after building `riskCoverage.m` to prevent exactly that class of error. Confirming it on the calibration split is the step that would make it shippable, and it is cheap now that the evidence export exists: one pass over calibration, then the sweep runs offline.

D4 therefore still stands as shipped, and D2 is now a costed proposal rather than an open question. If the calibration confirmation lands before the configuration freeze, D2 should be adopted; if it does not, the shipped pair is safe and the saving is deferred rather than lost.

The cost is unchanged and stated: the gate escalates 314 of 550 cases to catch four. §9.5 prices that at 591.82 grader-hours a year against 214.65 at the scenario deferral rate. Whether that exchange is acceptable is a service-capacity question and not a technical one, and it is the question the gate's defence now rests on.


## Addendum, 4 September 2026: D2 is rejected on the confirmation it asked for

The addendum above recorded 0.40 / 0.15 as a costed proposal worth about 71 fewer escalations, pending confirmation on calibration. That confirmation has run and it rejects the pair.

On calibration the classifier sends five referable patients home. The shipped pair catches all five at an escalation load of 56.7 per cent. The candidate catches four at 44.1 per cent, and the one it loses is `4ef0b485a7da`, reference grade 2, scored by the classifier at a calibrated referable probability of 0.0675: a confident error, which is the population the gate exists to catch.

The number that explains it is the patient's cleared fraction. At the shipped cut of 0.35 it is 0.2000, under the shipped fraction of 0.25, so the gate fires. At the candidate's cut of 0.40 it is 0.1875, over the candidate's fraction of 0.15, so it does not. The candidate's 12.6 points of saving are bought by lowering the bar past this patient specifically.

**D2 is rejected and D4 stands.** `config/default.json` keeps 0.35 and 0.25. Calibration's own best pair, 0.15 / 0.40 at 41.9 per cent, is also not adopted: selecting it would repeat one split over the error this confirmation existed to catch, and no third split remains to confirm it on.

The general finding is worth more than the specific rejection. The validation sweep was correct about validation and wrong about the world, and it was wrong in the direction that looks like an improvement: a 12.9 point gain in escalation load, with a referable patient quietly sent home to pay for it. A safety constant selected on one split and reported on the same split will find savings of exactly this kind, which is why §10.4 and `eval/metrics/riskCoverage.m` exist and why this project does not get to skip the confirmation.