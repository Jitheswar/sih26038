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

The sealed external test set (Messidor-2, `data/sealed/`) has not been opened. All development to date - architecture, hyperparameters, thresholds, calibration - used only the train / validation / calibration splits. It is opened once, by the human key-holder, after the operating point is frozen and dated, and any result from it is reported alongside the internal numbers rather than replacing them.
IDRiD Set-B is not the sealed set; it is an ordinary held-out split, never trained on and never used to select an epoch.

This is a screening aid and research prototype, not a medical device or a clinical diagnosis.

## Repository layout

```
config/    default.json (frozen run configuration) and ablation_A1..A9.json
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
