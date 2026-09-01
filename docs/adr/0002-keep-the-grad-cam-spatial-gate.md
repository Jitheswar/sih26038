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

The gate is kept without a measurement showing it catches anything the mandatory under-detected check does not. That question is not answered by this ADR. What the veto establishes is that removing it costs two patients and buys coverage the project cannot bank, which is sufficient to keep it and not sufficient to justify it. Identifying the patients each configuration sends home, which no artefact currently records, is the evidence that would settle it, and it is tracked separately.
