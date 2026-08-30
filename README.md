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
The classical channel (A5) still handles 27.5 per cent of the caseload autonomously, so it remains the best measured pipeline on the number the system exists to move, and `pipeline.learned_lesion_evidence` stays `false`.
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

Nothing has been adopted.
`config/default.json` is unchanged, `escalateOnExplanationDisagreement` still defaults to `true`, `levelComparison` still defaults to `exact`, `pipeline.learned_lesion_evidence` stays `false`, and the operating point frozen on 23 August is untouched.
These are validation-split numbers separated by small integer miss counts, and relaxing the spatial gate is a clinical judgement rather than only a technical one, so adoption is recorded in §11.6 as a recommendation awaiting that decision.

The sealed external test set (Messidor-2, `data/sealed/`) has not been opened. All development to date - architecture, hyperparameters, thresholds, calibration - used only the train / validation / calibration splits. It is opened once, by the human key-holder, after the operating point is frozen and dated, and any result from it is reported alongside the internal numbers rather than replacing them.
IDRiD Set-B is not the sealed set; it is an ordinary held-out split, never trained on and never used to select an epoch.

This is a screening aid and research prototype, not a medical device or a clinical diagnosis.

## Repository layout

```
config/    default.json (frozen run configuration) and ablation_A1..A13.json
data/      PROVENANCE.md, patient-level splits and IDRiD lesion splits (data/splits/), sealed external set (data/sealed/, not read)
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
- **Bare accuracy is never reported.** Sensitivity and specificity are reported at the frozen operating point with 95% Wilson intervals and stated n; softmax output is not confidence, so temperature-scaled probabilities are reported with ECE and a reliability diagram.

Full detail and rationale for every rule above is in `docs/SIH26038_design.html`; `AGENTS.md` has the equivalent guidance for agents working in this repository.

## License

No license has been chosen yet.
