# SIH26038: Explainable AI for Diabetic Retinopathy Screening

Smart India Hackathon 2026, problem statement 26038. A screening pipeline for diabetic retinopathy (DR) in rural India, built in MATLAB.

Give it a photo of the back of the eye (a fundus photo) and it answers **clear**, **refer** or **escalate to a human**. It shows its work:

- a DR grade (ICDR scale) from a ResNet-50, with calibrated probabilities
- a Grad-CAM heatmap of where the model looked, mapped back onto the original image
- a check of that heatmap against lesion evidence from two independent sources: a trained segmentation network for microaneurysms, haemorrhages and exudates, and a classic image-processing detector that needs no training data
- a rule-based decision policy that escalates when the image quality is poor, when the evidence disagrees, or when there isn't enough evidence, instead of trusting the classifier alone

A Simulink/SimEvents model (`simulink/`) simulates screening capacity and referral load for a district. A MATLAB App Designer app (`app/`) walks through one case from start to finish.

`docs/SIH26038_design.html` is the source of truth. Every design decision in it has its reason attached, including corrections made later. Read it before changing anything.

This is a research prototype and screening aid. It is not a medical device and does not diagnose.

## Where it stands

The operating point is frozen (23 August 2026): refer when the calibrated probability is 0.40 or higher.

| Split | Sensitivity | Specificity |
|---|---|---|
| Validation | 0.9821 | 0.9174 |
| Internal test | 0.9600 | 0.9167 |

Intervals are 95% Wilson and are in the design doc. Bare accuracy is never reported.

The lesion segmentation network (a U-Net trained on IDRiD Set-A) scores a mean AUPR of 0.3732 on the held-out IDRiD Set-B (27 images). Each AUPR is reported next to how common that lesion is, because an AUPR only means something against that baseline.

| Lesion | AUPR | How common | AUPR / how common |
|---|---|---|---|
| Microaneurysms | 0.4340 | 0.00098 | 442x |
| Haemorrhages | 0.2060 | 0.01066 | 19x |
| Hard exudates | 0.7550 | 0.01085 | 70x |
| Soft exudates | 0.0980 | 0.00181 | 54x |

Getting the segmentation network to help the whole pipeline took several findings, all written up in the design doc:

- Its default thresholds refer every image on APTOS (specificity 0.0000), so the pipeline now trusts only the hard-exudate head at threshold 0.99. That gives sensitivity 0.8072 and specificity 0.8257 on validation.
- Even then, the check comparing the heatmap and the evidence was escalating too much. It compared exact ICDR levels, so it escalated cases where both sides already agreed the patient needed no referral. Comparing only the refer/don't-refer outcome fixed this (configuration A10). It handles more cases on its own (180 against 151) and sends fewer referable patients home (0 against 1).
- A12 (also relaxing the Grad-CAM check) handled more still, but sent 2 referable patients home where the classifier alone sent none at the same coverage. It was rejected under the rule in `docs/adr/0001-equal-coverage-safety-veto.md`. The Grad-CAM check stays on (`docs/adr/0002-keep-the-grad-cam-spatial-gate.md`).

`config/default.json` now matches A10.

The sealed external test set (Messidor-2, `data/sealed/`) has never been opened. Everything so far used only the train, validation and calibration splits. The human key-holder opens it once, after the operating point is frozen.

## Running it

Everything runs headless through `matlab -batch`. This is a MATLAB-only project, so there's no npm and no node.

```bash
# train the grading model
matlab -batch "addpath(genpath('src')); grade.train('config/default.json')"

# train lesion segmentation on IDRiD Set-A
matlab -batch "addpath(genpath('src')); segment.trainLesionSegmentation('config/default.json')"

# train vessel segmentation on DRIVE
matlab -batch "addpath(genpath('src')); segment.trainVesselSegmentation('config/default.json')"

# score a lesion checkpoint on IDRiD Set-B
matlab -batch "addpath(genpath('src')); addpath(genpath('eval')); lesionSegmentationEvaluation('results/<run>/best_lesion_model.mat')"

# score a vessel checkpoint on the held-out DRIVE split
matlab -batch "addpath(genpath('src')); addpath('eval'); vesselSegmentationEvaluation('Split','test')"

# re-pick lesion thresholds on APTOS and run the head-subset study
matlab -batch "addpath(genpath('src')); addpath(genpath('eval')); lesionThresholdTransfer()"

# run all tests
matlab -batch "assertSuccess(runtests('tests','IncludeSubfolders',true))"

# district capacity experiments E1 to E6
matlab -batch "addpath('simulink'); sweep_experiments()"

# demo app
./start.sh
```

Source is in `src/` as MATLAB packages, so calls look like `common.preprocess(...)`, `quality.assess(...)` and `explain.gradcam(...)`.

You need these MATLAB toolboxes: Image Processing, Computer Vision, Deep Learning, Medical Imaging, Statistics and Machine Learning, Simulink and SimEvents, and Parallel Computing.

## Demo cases

Twelve real validation cases, one for each behavior the pipeline can show, each with its full annotated report. They're chosen by what the pipeline actually did, not by how they look, and each one is run through the same code path the demo app uses.

```bash
matlab -batch "addpath(genpath('src')); addpath('eval'); selectDemoCases(); buildDemoPack()"
```

One thing that never happens: with `decision_policy.alwaysEscalateLevel4` on, no case is ever auto-referred at ICDR Level 4. Advanced disease always goes to a human.

## Folders

```
config/      default.json (frozen settings) and ablation_A1..A13.json
data/        PROVENANCE.md, patient-level splits (data/splits/), sealed set (data/sealed/, not read)
src/         MATLAB packages: +quality +segment +grade +explain +report +common +data
simulink/    district_model.slx and the capacity experiments
eval/        eval/harness.m and metrics in eval/metrics/
app/         ScreeningApp.m, the demo app
tests/       matlab.unittest test classes
docs/        SIH26038_design.html, technical design PDF, research notes
results/     dated run outputs, never overwritten (gitignored)
```

## Rules to know before changing things

- Per-class recall and the full confusion matrix print every validation epoch. A model that collapses to the majority class shows a healthy loss curve, and this is the cheap way to catch it.
- There is exactly one preprocessing function (`common.preprocess`), used in both training and inference.
- Splits come from the committed CSVs in `data/splits/`. They're never regenerated at run time.
- `data/sealed/` is never read or evaluated against during development.
- Pipeline stages are switched on and off in `config/*.json`, not by editing or commenting out code.
- `rng(seed)` is set at the top of every entry point. A result you can't reproduce isn't a result.
- Results go to a new dated folder under `results/` with the config next to them. Nothing is overwritten.
- Input is at least 448x448. At 224x224 the microaneurysms disappear.
- Lesion segmentation trains on full-resolution crops, never a resized image, for the same reason.
- The lesion loss punishes missed lesions more than false alarms, and the config refuses to start otherwise. Lesions are 0.1 to 1.0 percent of an image, so a balanced loss can score well by predicting nothing.
- A head the network was trained on isn't automatically one to trust. Which heads supply evidence, and at what thresholds, is set in `config/default.json` as `lesion_segmentation.evidence_heads` and `evidence_thresholds`.
- Vessel metrics are scored inside the camera's field of view only. About 31 percent of a DRIVE image is black corners that would give free specificity.

The reasoning for every rule is in `docs/SIH26038_design.html`. `CONTEXT.md` is the glossary, `docs/adr/` holds the decisions that are hard to reverse, and `CLAUDE.md` points coding agents at both.

## License

MIT, see `LICENSE`.
