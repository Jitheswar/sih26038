# SIH26038 - Explainable AI for Diabetic Retinopathy Screening

Smart India Hackathon 2026, Problem Statement 26038: an explainable AI pipeline for diabetic retinopathy (DR) screening in rural India, built for MathWorks/MATLAB.

The pipeline takes a fundus photograph and produces a screening decision (clear / refer / escalate) backed by:

- a calibrated ICDR grade prediction (ResNet-50 backbone, temperature-scaled probabilities),
- Grad-CAM explanation evidence, spatially mapped back into the original image frame,
- lesion evidence that the model's explanation is checked against, from two independent channels: a trained multi-label segmentation network over microaneurysms, haemorrhages and exudates, and a classical morphological candidate detector that needs no training data and cannot fail with it, and
- a rule-based decision policy that escalates on low image quality, evidence disagreement, or unknown/insufficient evidence rather than trusting the classifier alone.

A Simulink/SimEvents model (`simulink/`) simulates district-level screening capacity and referral load. A MATLAB App Designer UI (`app/`) demonstrates the end-to-end pipeline on a single case.

`docs/SIH26038_design.html` is the single source of truth for this project: every design decision in it carries the reason it was made, including corrections recorded after the fact. Read it before changing anything a rule in this README touches.

## Status

The operating point is frozen (2026-08-23): a calibrated referable-probability threshold of 0.40, giving validation sensitivity 0.9821 / specificity 0.9174 and internal test sensitivity 0.9600 / specificity 0.9167 (both with 95% Wilson intervals reported alongside, per `docs/SIH26038_design.html` §11).

Lesion segmentation (Track B, §6.4-§6.5) is trained.
A multi-label U-Net over microaneurysms, haemorrhages, hard exudates and soft exudates, trained on native-resolution 512x512 crops from IDRiD Set-A.
On the held-out IDRiD Set-B benchmark split (n = 27 frames), AUPR at 33 equally spaced thresholds over pooled pixels:

| Lesion | AUPR | Prevalence | AUPR / prevalence |
| --- | --- | --- | --- |
| Microaneurysms | 0.4340 | 0.00098 | 442x |
| Haemorrhages | 0.2060 | 0.01066 | 19x |
| Hard exudates | 0.7550 | 0.01085 | 70x |
| Soft exudates | 0.0980 | 0.00181 | 54x |
| **Mean** | **0.3732** | | |

Every AUPR is reported beside the prevalence of its lesion type, because an AUPR is only interpretable against the precision a detector answering positive everywhere would reach.
Validation mean AUPR was 0.3829 at the selected epoch, so validation and test agree and the epoch selection did not overfit.

This matters because it fixes the measured weak point of the pipeline.
The classical candidate channel scored a pointing-game lift of 0.96x (chance) in §11.7 and 0.0000 sensitivity in the §11.6 A3 ablation, because counting microaneurysms can never satisfy an ICDR criterion above Level 1.
The learned channel takes ICDR evidence coverage from one of eight fields to four, which makes Levels 2 and 3 reachable from evidence alone.

The learned channel's operating thresholds have been re-selected against APTOS, and the result changed which heads the pipeline trusts.
The thresholds shipped in the checkpoint maximise pixel F1 on IDRiD, and on APTOS they call every frame referable: specificity 0.0000 on the validation split, n = 550.
Sweeping all fourteen thresholds per head over the calibration split (n = 365) showed that no threshold set rescues the four-head channel, and the separation diagnostic showed why.
ICDR Level 2 fires on the presence of any non-microaneurysm finding, so the channel ORs its heads together and its specificity is bounded by whichever head most often reports something on a healthy eye.
That head is soft exudates, which clears under 2 per cent of eyes graded 0 at every threshold up to 0.975.

Restricting the evidence to the hard-exudate head at threshold 0.99 gives, on the held-out validation split with the thresholds fixed and no search:

| Configuration | Sensitivity (95% Wilson) | Specificity (95% Wilson) |
| --- | --- | --- |
| IDRiD-selected, all four heads | 1.0000 (0.9831-1.0000) | 0.0000 (0.0000-0.0116) |
| APTOS-selected, hard exudates only | 0.8072 (0.7504-0.8536) | 0.8257 (0.7809-0.8630) |

Sensitivity falls because the old number was not a capability: a channel that refers every frame scores 1.0000 by construction and can never withhold an alarm.
The new channel misses 43 of 223 referable frames, which is a real cost and is accounted for at pipeline level by ablations A8 and A9 rather than by this table.
Which heads are trusted and at what thresholds is now named in `config/default.json` as `lesion_segmentation.evidence_heads` and `evidence_thresholds`, not taken from the checkpoint.

Fixing the evidence channel did not fix the pipeline, and that is the more important result.
At pipeline level (ablations A8 and A9, validation split, n = 550) the restricted channel raises autonomous coverage only from 4.6 per cent to 6.9 per cent, because the agreement check still cannot reconcile the learned evidence with the CNN and escalates 512 of 550 frames.
The classical channel (A5) still handles 27.5 per cent of the caseload autonomously, so at the time of this measurement it remained the best measured pipeline on the number the system exists to move, and `pipeline.learned_lesion_evidence` stayed `false`.
The A10-A13 results below reverse that conclusion and the setting: once the agreement check stops penalising a channel for reaching Level 2, the learned channel is ahead at equal policy.
The next question is about the agreement check and the CNN, not about lesion thresholds.

That question has now been measured, and the answer is that the agreement check is escalating for two reasons the design did not ask for.
Every escalation on the validation split was attributed to the §8.6 state that caused it (`eval/agreementLevelMismatch.m`, results in `results/20260830_200447_agreement_level_mismatch` and `results/20260830_200454_agreement_level_mismatch`).

The Grad-CAM spatial check is the largest single cause in every configuration: 335 of 399 escalations in A5, 340 of 525 in A7, 314 of 512 in A9.
§8.6 specifies that state as a report flag with escalation to be considered; the code raises it as a mandatory reason code, and `decisionConfiguration` refuses to start if it is switched off.
Its test is `mean(heatmap(candidatePoints) >= 0.35) >= 0.25`, two constants that are not in configuration and were not selected against data, applied to a channel §8.3 records as unable to localise a microaneurysm.

The exact ICDR level comparison is the second cause.
All 174 insufficient-evidence escalations in A9 are level mismatches, and 163 of them (93.7 per cent) place the patient on the same side of the referral decision and differ only on severity.
The largest single cell is 142 cases where the CNN says Level 0 and the rule engine says Level 1: both below the referral threshold, both agreeing the patient does not need referral, escalated anyway.

The two compose, and together they explain why the better lesion channel lowered coverage.
The comparison runs only when the rule engine can reach Level 2.
The classical channel's ceiling is Level 1, so in A5 it never runs; the restricted learned channel's ceiling is Level 2, so in A9 it runs and adds 174 escalations that did not previously exist.
`eval/agreementCheckCases.m` reproduces this with no model and no image: the same CNN prediction is referred against a channel capped at Level 1 and escalated against a channel reaching Level 2.
So the drop from 27.5 to 6.9 per cent coverage is the agreement check penalising the evidence channel for expressing more of the scale, not the learned channel performing worse.

Both repairs have now been measured, as ablations A10 to A13 (validation split, n = 550, results in `results/20260830_232525_ablation_A1_A5`).
Each differs from its base configuration in `decision_policy` alone, so the measured difference is attributable to the agreement check and nothing else.

| Cfg | Levels | Spatial check | Coverage | Auto accuracy | Referable sent home |
| --- | --- | --- | --- | --- | --- |
| A5 - classical, shipped | exact | gate | 0.2745 | 0.9934 | 1 |
| A9 - learned, hard exudates | exact | gate | 0.0691 | 0.9474 | 0 |
| A10 - learned, endpoint levels | endpoint | gate | 0.3273 | 0.9889 | **0** |
| A11 - learned, spatial advisory | exact | advisory | 0.2436 | 0.9552 | 2 |
| **A12 - learned, both repairs** | endpoint | advisory | **0.6636** | **0.9836** | **2** |
| A13 - classical, both repairs | endpoint | advisory | 0.7382 | 0.9704 | 4 |

Comparing the channels on the referable endpoint instead of on exact ICDR equality (A10) costs nothing: coverage rises from 0.0691 to 0.3273, zero referable patients are sent home, and autonomous accuracy rises from 0.9474 to 0.9889.
It beats the shipped A5 on both axes at once, more coverage at fewer patients sent home, so it reads as a defect repair rather than a trade-off.

Both repairs together (A12) take coverage from 0.0691 to 0.6636, a 9.6-fold increase, for two referable patients sent home out of 223.
The A1 CNN-only baseline sends 4 home out of 550 autonomous cases, 0.73 per cent; A12 sends 2 out of 365, 0.55 per cent.
So the deferral pipeline is now safer per case it decides than the classifier alone and hands the remaining third to a human, which is what §4.2 claims for it and what it was not doing before.

This reverses the conclusion recorded above: with the agreement check no longer penalising a channel for reaching Level 2, the learned channel is ahead of the classical one at equal policy.
A13 has the highest coverage of any configuration, 0.7382, and is not the best one: it sends 4 referable patients home out of 406 autonomous cases, a per-case miss rate of 0.99 per cent, worse than using the classifier alone.
Coverage is the number the system exists to move and it is not the number to select on.

Sensitivity in the ablation table counts an escalated referable case as not referred, so A12's 0.5247 does not mean it misses 47 per cent of referable patients.
Of 223 referable frames it auto-refers 117, escalates 104 to a human who sees them, and auto-clears 2.

A10 was adopted on 31 August 2026; A12 was not.
`config/default.json` now sets `decision_policy.levelComparison` to `endpoint` and `pipeline.learned_lesion_evidence` to `true`, which together make the shipped configuration identical to A10.
Both were needed: the level comparison runs only when the rule engine can reach Level 2, so with the classical channel capped at Level 1 the `endpoint` setting alone would have changed nothing.

A10 was adopted because it is a defect repair rather than a trade-off.
It dominates the shipped A5 on both axes at once, more autonomous cases (180 against 151) at fewer referable patients sent home (0 against 1), and it gives up nothing: the endpoint disagreement and under-detection checks above the level comparison are unchanged and still mandatory.
Exact ICDR equality was only ever adding escalations on cases where both channels already agreed about referral, and above the rule engine's ceiling it was adding escalations no improvement to either channel could have removed.

A12 was not adopted.
Its second repair demotes the Grad-CAM spatial check from a gate to an advisory flag, and relaxing a safety gate is a clinical judgement rather than only a technical one, so it stays recorded in §11.6 as a recommendation awaiting the §12 review.
`escalateOnExplanationDisagreement` therefore still defaults to `true`.

The operating point frozen on 23 August is untouched: the threshold of 0.40, the temperature and the checkpoint are unchanged, and no metric behind them was re-selected.

Configurations are now compared against the classifier at equal coverage, and that changes which of them are admissible.

The A10-A13 table above compares configurations that decide different fractions of the caseload on raw miss counts.
A deferral pipeline sheds exactly the low-confidence cases where a classifier's errors concentrate, so its count over a self-selected subset is not comparable to the classifier's count over everything.
`docs/adr/0001-equal-coverage-safety-veto.md` states the criterion: a configuration is inadmissible if it sends more referable patients home than the classifier alone does at the same coverage.
It counts false negatives only, reads the point estimate because these intervals overlap heavily, and is a veto rather than a ranking.

| Cfg | Coverage | Sends home | Classifier at same coverage | Admissible |
| --- | --- | --- | --- | --- |
| A5 - classical, shipped until 31 Aug | 0.2745 | 1 | 0 | No |
| **A10 - learned, endpoint levels, shipped** | **0.3273** | **0** | **0** | **Yes** |
| A11 - learned, spatial advisory | 0.2436 | 2 | 0 | No |
| A12 - learned, both repairs | 0.6636 | 2 | 0 | No |
| A13 - classical, both repairs | 0.7382 | 4 | 1 | No |

The classifier's four misses all sit deep in its own low-confidence tail, at confidence ranks 400, 502, 512 and 542 of 550, so restricted to its most confident two thirds of cases it sends nobody home.
The comparison that made A12 look safer than the classifier was measuring it against a baseline that included exactly the cases A12 declined to decide.

A12 is therefore inadmissible and the clinical judgement it was parked on never has to be adjudicated.
`escalateOnExplanationDisagreement` stays `true` on the evidence rather than on the absence of a reviewer, and the §12 reader study is recorded as descoped rather than pending.
See `docs/adr/0002-keep-the-grad-cam-spatial-gate.md`.
A5, which shipped until 31 August, is also inadmissible; A10 is the only non-trivial configuration in the study that passes.

Deferring on the calibrated probability alone beats the pipeline on this split, and that is stated here rather than left for a judge to find.

Configuration A14 ranks cases by distance from the frozen threshold and hands the least confident to a human, with no quality gate, no lesion evidence, no ICDR rule trace, no Grad-CAM and no agreement check.
Its cut is selected on the calibration split at a zero-miss budget and applied to validation, never selected on the split that reports it.

| Cfg | Coverage | Referable sent home |
| --- | --- | --- |
| A10 - the pipeline that ships | 0.3273 | 0 |
| **A14 - calibrated probability alone** | **0.7527** | **1** |

The bound is structural rather than a matter of tuning: a gate can only escalate more, so the most permissive the agreement check can be is the no-gate case, A12 at 0.6636 with two sent home, and no setting of the spatial constants lifts the pipeline past A14 on this split.

That reading was corrected the same day, and the correction goes against it.

Per-case records now name the patients each configuration sends home (`results/20260902_052342_ablation_A1_A5/per_case.csv`, 3,300 rows, every configuration reproducing its 30 August numbers exactly).
The classifier's four misses are three graded 2 and one graded **4, proliferative**.

That patient, `d1a24527a15d`, is called Level 1 by the classifier at a calibrated referable probability of 0.0593: confident, and badly wrong.
The rule engine also reads Level 1, so the channels agree and the agreement status is concordant.
The under-detected check does not fire, because it runs on a referable prediction and this prediction is Level 1.
`alwaysEscalateLevel4` does not fire, because it reads the predicted level and not the reference grade.
**The Grad-CAM spatial gate is the only mechanism that escalates this patient**, and it fires at full strength: zero of the candidates reach the attention cut.

Demote the gate and the patient goes home. A11, A12 and A13 all auto-clear the case as concordant.
So does A14, whose confidence of `|0.0593 - 0.40| = 0.3407` sits above its calibration-selected cut of 0.332877.
**A14's single miss is the proliferative patient**, so its coverage advantage is bought with the worst case in the split.

Across the 548 A10 rows carrying a spatial statistic, the gate fires on 57.1% of cases the classifier gets right, 55.6% of those it over-refers, and 100% of the four it sends home, whose median statistic is 0.0200 against 0.2128.
Four of four at a 57.1% base rate would happen by chance with probability 0.106, so this is a direction and not a demonstration.
What it does settle is narrower and enough for the disposition: on this split, removing the gate sends a proliferative patient home and nothing else in the pipeline catches it.

The cost is stated plainly rather than argued away: the gate escalates 314 of 550 cases to catch four.
§9.5 prices that at 591.82 grader-hours a year against 214.65 at the scenario deferral rate.

The earlier claim that this failure "barely occurs in domain" was wrong, and the prediction built on it - that the ordering only reverses under domain shift - is withdrawn.
It reverses in domain, on this split.
A14 remains not a competing deliverable: R4.1 to R4.5 require an explanation, lesion-level evidence, an ICDR trace and an annotated report, and a confidence score is none of those.
One limit of the split still stands: it contains no ungradable image, so the quality gate never fires and A14's lack of one costs it nothing measurable here.

Vessel segmentation (§6.3, R2.2) is trained.
A patch-based U-Net on the CLAHE-equalised green channel, trained on DRIVE at 128x128 crops, selected on validation AUC at epoch 8 of 16 before early stopping.

| Split | n frames | Sensitivity (95% Wilson) | Specificity (95% Wilson) | ROC AUC |
| --- | --- | --- | --- | --- |
| Validation | 3 | 0.8388 (0.8363-0.8413) | 0.9722 (0.9718-0.9726) | 0.9718 |
| Test, held out | 3 | 0.7723 (0.7695-0.7751) | 0.9804 (0.9801-0.9808) | 0.9621 |

Every pixel is scored inside the field-of-view mask.
A DRIVE frame is 31 per cent black corner outside the camera aperture and every one of those pixels is a true negative, so scoring the whole frame would add a third of a frame of free specificity.

Read the intervals with care, and the frame count more carefully.
The Wilson intervals above are over pooled pixels, and a frame holds a few hundred thousand of them, so they describe sampling error over pixels rather than over eyes.
The honest spread is frame to frame: sensitivity runs 0.6866 to 0.8454 across the three test frames, an order of magnitude wider than the pixel interval suggests.
Test sensitivity sits below validation, which is what three frames and one weak frame (DRIVE_25, the densest in the split) produce.

Two provenance points, because §6.3 asks for them explicitly.
The archive this project holds ships DRIVE's test half without vessel annotations: `data/raw/test` has images and field-of-view masks only, verified against the SHA-256 in `data/PROVENANCE.md`.
So DRIVE's own 20/20 division cannot be scored locally, and the twenty annotated training frames are split 14/3/3 instead, stratified by vessel fraction (`data/splits/vessel_*.csv`).
These numbers are therefore a held-out result and **not** the DRIVE benchmark, and they are not comparable to published DRIVE figures the way §6.3 anticipated under R6.1.

Nothing downstream consumes the vessel network yet.
§6.3 names three uses - venous beading for the 4-2-1 rule, vessel masking to suppress false haemorrhage detections, and neovascularisation features - and none are wired into the screening pipeline.
Claiming the downstream benefit before it is measured is exactly what §11.1 exists to prevent.

The SimEvents district capacity model (§9, R5.1 and R5.2) has been run end to end.
All six optimisation experiments E1 to E6 come from one seeded invocation of `simulink/sweep_experiments.m` on 1 September 2026, each writing a dated results directory with the configuration it used.
Every sweep point is a 14-day window held at the full annual arrival rate for 100,000 screenings a year, and every annual figure here is that window multiplied by 365/14 = 26.07 rather than a simulated year.
The six reproduce the 23 August run of the same model to eight significant figures.

At 100,000 screenings a year the district's human-review workload is 214.65 grader-hours, and the minimum grader count that meets the 24-hour turnaround target is one, at 2.45 per cent utilisation, unchanged at 50,000 and at 150,000 screenings a year.
Read the headcount as a statement about the placeholder rather than about a district.
Grader service time is the 30-second R4.5 target standing in until the §12 reader study reports a distribution, and the model's grader pool is available around the clock.
Five minutes a case on an eight-hour day would multiply that utilisation by thirty; the workload figure scales with the service time and the headcount does not survive changing it.

That 214.65 is also at the configured deferral rate of 0.10, which is a scenario value no measured configuration reaches.
E3 therefore sweeps the rate the shipped pipeline actually defers at, 0.6727 from ablation A10, reading it from the configuration so the experiment cannot go stale behind the pipeline.
At that rate the workload is 591.82 grader-hours a year, 2.76 times the scenario figure, and that is the number that describes what ships today.

Connectivity availability, not bandwidth, is the binding infrastructure constraint.
A twentyfold bandwidth increase moves mean turnaround by 3.1 per cent at 30 per cent connectivity availability, while raising availability from 30 to 90 per cent cuts it by about 97.5 per cent.
At 8 MB a case the transfer takes seconds and the wait for the next connectivity window takes hours, which is the quantified case for keeping inference local rather than shipping every image out for it.
Camp-day bunching quadruples the peak queue, 29 to 117, while moving mean turnaround by 11.8 per cent and p95 turnaround not at all, so the cost of a camp day is patients waiting on site rather than reports arriving late.

Two experiments returned less than §9.5 expected of them, and both are recorded as such rather than reported as wins.
E2 sweeps sensitivity with specificity held fixed, so it prices the extra true positives and not the extra false positives, and the sensitivity-against-grader-hours Pareto curve §9.5 calls for is not yet the curve §9.5 specifies.
E5 shows the quality gate lowering grader load rather than raising it, because an image that exhausts its recaptures is routed to human review while the model samples the AI decision from a fixed sensitivity and specificity irrespective of image quality, so this model has no way to price what the gate is actually for.

## Demo pack

`~/sih-demo-cases` holds twelve real validation cases, one for each behaviour the pipeline can show, with the full annotated report exported for each.
The cases are chosen by `eval/selectDemoCases.m`, which queries the recorded per-case decision of the ablation run reported in §11.6, so what each case demonstrates is measured rather than assumed.
`eval/buildDemoPack.m` then runs each one through `app.runScreeningCase`, the same entry point the demo UI uses, and reports where the deployed path and the harness disagree.
On the current build all twelve agree.

```bash
matlab -batch "addpath(genpath('src')); addpath('eval'); selectDemoCases(); buildDemoPack()"
```

The twelve are chosen to be mechanically distinct rather than merely to look different, and the list is matched on the reason code the policy raised, because that is what the report prints and what a judge asks about.
The quality gate is among them: it is the first stage of the pipeline and the one a rural capture actually stresses, and an earlier version of this list ran twelve cases without showing it once.

One scenario in that list is unreachable and worth knowing about: `decision_policy.alwaysEscalateLevel4` means no case can ever be auto-referred at ICDR Level 4, because proliferative disease always goes to a human.

The sealed external test set (Messidor-2, `data/sealed/`) has not been opened. All development to date - architecture, hyperparameters, thresholds, calibration - used only the train / validation / calibration splits. It is opened once, by the human key-holder, after the operating point is frozen and dated, and any result from it is reported alongside the internal numbers rather than replacing them.
IDRiD Set-B is not the sealed set; it is an ordinary held-out split, never trained on and never used to select an epoch.

This is a screening aid and research prototype, not a medical device or a clinical diagnosis.

## Repository layout

```
config/    default.json (frozen run configuration) and ablation_A1..A13.json
data/      PROVENANCE.md, patient-level splits plus IDRiD lesion and DRIVE vessel splits (data/splits/), sealed external set (data/sealed/, not read)
src/       MATLAB packages: +quality +segment +grade +explain +report +common +data
simulink/  district_model.slx and the capacity sweep experiments
eval/      eval/harness.m and the metrics under eval/metrics/
app/       ScreeningApp.m, an App Designer-compatible demo UI
tests/     matlab.unittest test classes
docs/      SIH26038_design.html (source of truth), technical design PDF, research notes
results/   dated, never-overwritten run outputs (gitignored)
```

## Running

Everything runs headlessly through `matlab -batch`, which logs to stdout/stderr and exits non-zero on failure. No npm, no jest, no node - this is a MATLAB-only project.

Train the grading model with the frozen configuration:

```bash
matlab -batch "addpath(genpath('src')); grade.train('config/default.json')"
```

Train the lesion segmentation network on IDRiD Set-A:

```bash
matlab -batch "addpath(genpath('src')); segment.trainLesionSegmentation('config/default.json')"
```

Train the vessel segmentation network on DRIVE:

```bash
matlab -batch "addpath(genpath('src')); segment.trainVesselSegmentation('config/default.json')"
```

Score a vessel checkpoint on the held-out DRIVE split:

```bash
matlab -batch "addpath(genpath('src')); addpath('eval'); vesselSegmentationEvaluation('Split','test')"
```

Re-select the lesion evidence thresholds against APTOS on the calibration split, and run the head-subset study:

```bash
matlab -batch "addpath(genpath('src')); addpath(genpath('eval')); lesionThresholdTransfer()"
```

Score a lesion checkpoint on the held-out IDRiD Set-B benchmark split:

```bash
matlab -batch "addpath(genpath('src')); addpath(genpath('eval')); lesionSegmentationEvaluation('results/<run>/best_lesion_model.mat')"
```

Run the full test suite:

```bash
matlab -batch "assertSuccess(runtests('tests','IncludeSubfolders',true))"
```

Run the district capacity experiments E1 to E6:

```bash
matlab -batch "addpath('simulink'); sweep_experiments()"
```

Launch the demo UI:

```bash
./start.sh
```

Source lives in `src/` as MATLAB package folders, so calls are namespaced, e.g. `common.preprocess(...)`, `quality.assess(...)`, `explain.gradcam(...)`.

## Required toolboxes

Image Processing, Computer Vision, Deep Learning, Medical Imaging, Statistics and Machine Learning, Simulink + SimEvents, Parallel Computing.

## Design rules worth knowing before contributing

- **Per-class recall and the full confusion matrix print at every validation epoch, in every training run.** A model that collapses to the majority class raises no error and shows a healthy loss curve; per-class recall is the only cheap signal that catches it.
- **Exactly one preprocessing function** (`common.preprocess`), called from both the training and the inference path. A second one is a bug, not a feature.
- **Splits are read from the committed CSVs in `data/splits/`**, never regenerated at run time. They are patient-level, four-way, stratified by grade, generated once with a fixed seed.
- **`data/sealed/` is never read, loaded, extracted, or evaluated against** during development. See "Status" above.
- **Pipeline stages switch on and off from `config/*.json`**, never by editing or commenting out code.
- **`rng(seed)` is set at the top of every entry point.** A result that cannot be reproduced is not a result.
- **Results go to a dated directory under `results/`**, never overwritten, with the full config written alongside them.
- **Input resolution is 448x448 minimum**; 224x224 destroys microaneurysm evidence.
- **Lesion segmentation trains on native-resolution crops and never on a resized frame.** The resize is exactly what removes the microaneurysms the network is being trained to find. At inference each frame is instead resampled so its field-of-view diameter matches the training scale, because capture scale differs between datasets by up to 3x.
- **The lesion loss weights false negatives above false positives** (Tversky, beta > alpha), and the configuration refuses to start otherwise. Lesion pixels are 0.1 to 1.0 per cent of a frame, so a symmetric objective reaches an excellent value by predicting all background.
- **A head the network was trained for is not automatically a head its output can be trusted from.** Which heads supply ICDR evidence, and at what thresholds, is named in `config/default.json`, because ICDR Level 2 fires on the presence of any non-microaneurysm finding and one untrustworthy head therefore caps the specificity of the whole evidence channel. An untrusted head is declared a capability gap, never reported as a per-case unknown, because the rule engine escalates on a per-case unknown and a permanent restriction presented as one would escalate every patient.
- **The vessel loss is symmetric and the lesion loss is not, on purpose.** Lesion pixels are 0.1 to 1.0 per cent of a frame, so that path requires Tversky with beta > alpha and refuses to start otherwise. Vessels are 12.5 per cent of the field of view, a hundred times the prevalence, where a recall-weighted objective buys thickened vessels and a worse specificity. `segment.vesselLoss` is a separate function from `segment.lesionLoss` for exactly this reason; unifying them would break one of the two.
- **Vessel metrics are scored inside the field-of-view mask only.** A DRIVE frame is 31 per cent black corner outside the camera aperture and every one of those pixels is a true negative, so whole-frame scoring hands the result a third of a frame of free specificity.
- **Bare accuracy is never reported.** Sensitivity and specificity are reported at the frozen operating point with 95% Wilson intervals and stated n; softmax output is not confidence, so temperature-scaled probabilities are reported with ECE and a reliability diagram.

Full detail and rationale for every rule above is in `docs/SIH26038_design.html`.
`CONTEXT.md` is the glossary, `docs/adr/` holds the decisions that were hard to reverse, and `CLAUDE.md` points agents at both.

## License

No license has been chosen yet.
