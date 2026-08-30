# SIH26038 - Explainable AI for DR Screening

MATLAB project, built by several Codex sessions working in parallel.
`docs/SIH26038_design.html` is the single source of truth: every decision in it carries the reason it was made.
Before changing anything a rule below governs, read the section that rule cites.
Reading paths by role are in §0.1.

## Running code

Everything runs headlessly through `matlab -batch`, which logs to stdout/stderr and exits non-zero on failure.

```
matlab -batch "addpath(genpath('src')); grade.train('config/default.json')"
matlab -batch "assertSuccess(runtests('tests','IncludeSubfolders',true))"
```

Tests are `matlab.unittest` classes under `tests/`.
This is not a JS project: no npm, no jest, no node.
Source lives in `src/` as MATLAB package folders (§13.1), so calls are namespaced: `common.preprocess(...)`, `quality.assess(...)`, `explain.gradcam(...)`.

```
config/  default.json, ablation_A1..A13.json
data/    PROVENANCE.md, splits/, sealed/
src/     +quality +segment +grade +explain +report +common
simulink/  district_model.slx, sweep_experiments.m
eval/    harness.m, metrics/
app/     ScreeningApp.mlapp
tests/   results/  docs/
```

`eval/harness.m` is built before any model (§11).
A harness written after the fact gets written to flatter whatever the model already does.

GUI work (App Designer, SimEvents) needs the Arch workarounds in §14.2.
Environment not yet verified? Run the three smoke tests in §14.3 first.

## Hard rules

**Per-class recall and the full confusion matrix print at every validation epoch, in every training run** (§7.4, §13.4).
A model that collapses to the majority class raises no error and shows a healthy loss curve; per-class recall is the only cheap signal that catches it.
A unit test asserts no class has zero recall on a smoke run.

**Exactly one preprocessing function, in `+common`, called from both the training and the inference path** (§5.4, §7.2).
Enhancement applied at inference but not at training is self-inflicted domain shift, and no metric will name it.
Extend that function; a second one is the bug.

**Splits are read from the committed CSVs in `data/splits/`** (§10.2).
They are patient-level, four-way (train / validation / calibration / test), stratified by grade, generated once with a fixed seed and committed.
Regenerating a split at run time is a bug, whatever the seed.
A unit test asserts no patient ID appears in two splits.

**`data/sealed/` is the sealed external test set (Messidor-2).**
Do not read, load, extract, or evaluate against it (§10.4).
All development - architecture, hyperparameters, thresholds, calibration - uses train / validation / calibration only.
It is opened once, by the human key-holder, after the operating point is frozen and dated.
If a task appears to need it, stop and say so.

**Pipeline stages switch on and off from `config/*.json`, never by editing or commenting out code** (§11.6, §13.3).
Ablations A1-A13 are thirteen config files over one code path.
SimEvents parameters are named variables in a config file, never numbers typed into a block dialog (§9.4).

**`rng(seed)` at the top of every entry point** (§13.2).
A result you cannot reproduce is not a result.

**Results go to a dated directory under `results/`, never overwritten, with the full config written alongside them** (§13.2).

**Stay inside the declared toolbox set** (§4.4): Image Processing, Computer Vision, Deep Learning, Medical Imaging, Statistics and Machine Learning, Simulink + SimEvents, Parallel Computing.
Report Generator is not among them, so compose the report with `exportgraphics` (§8.7).

**Input resolution is 448x448 minimum** (§7.1).
224x224 destroys microaneurysm evidence (§3.2).
Under VRAM pressure, reduce batch size, not resolution.

## Reporting results

Never report bare accuracy (§11.1).
Report sensitivity and specificity at the frozen operating point with 95% Wilson intervals, and state n.
Select the best epoch on validation; the test split is touched once.
Softmax output is not confidence: report temperature-scaled probabilities with ECE and a reliability diagram (§7.6).
Every headline number appears twice, internal and external, side by side (§11.4).
The full metric set is §11.3; explanation-quality metrics are §11.7.

Report what was measured, including results that miss the targets (§10.5, §11.4).
A low external number that is reported and analysed is the stronger submission; a number tuned after the seal is opened is not an external validation result at all (§10.4).

## Editing the design doc

Claims carry `Verified`, `Established`, or `Unverified` tags (§0.2); keep tagging new ones.
§10.4 and §11.2 are frozen after the freeze date, and changes there are recorded with a reason in §0.3.
