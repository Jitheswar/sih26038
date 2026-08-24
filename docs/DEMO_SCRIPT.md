# Demo script: SIH26038, Explainable AI for DR Screening

A presenter's walkthrough of the live demo.
Everything below is driven from `./start.sh` at the repository root.
Target length is 8 minutes of demo plus questions.

---

## 0. Before the judges arrive

Run the preflight, from the repository root:

```bash
./start.sh check
```

It verifies MATLAB is on `PATH`, that the frozen checkpoint and the calibration directory named in `config/default.json` actually exist, that the APTOS images are present, and that `data/sealed/` is present but untouched.
If any line comes back red, fix it before you present, because the GUI will fail at the same point.

Then do one warm run of the GUI and screen one image, and close it.
The first MATLAB launch loads the ResNet-50 checkpoint and takes noticeably longer than the second, and you do not want that pause to be the first thing the judges see.

Have these open in other windows as backup:

- `docs/SIH26038_design.html`, the design document, for any "why did you choose that" question.
- `results/20260824_132627_ablation_A1_A5/ablation_table.csv`, the ablation table.
- `results/20260823_213652_639_E2_sensitivity_versus_workload/sensitivity_versus_grader_hours.png`, the Simulink workload curve.

Pick your demo images in advance from the validation split, and know their true grades:

| Purpose | Image | True ICDR grade |
| --- | --- | --- |
| Healthy retina, expect auto-clear | `data/raw/aptos2019/train_images/0097f532ac9f.png` | 0 |
| Moderate DR, expect refer or escalate | `data/raw/aptos2019/train_images/000c1434d8d7.png` | 2 |
| Proliferative DR, always escalates | `data/raw/aptos2019/train_images/03a7f4a5786f.png` | 4 |

Run all three once during your warm-up so you know exactly what verdict each produces, and adjust the order so your story matches what the model actually does.
Never demo an image you have not run before.

---

## 1. Opening line, 30 seconds

> Diabetic retinopathy is screened by photographing the retina, and the bottleneck is not the camera, it is the ophthalmologist who has to read every image.
> This system reads them first, sends home only the eyes it can justify sending home, and shows its reasoning for every case.
> It is a screening aid, not a diagnosis.

Say the last sentence.
It is the difference between a project that understands clinical deployment and one that does not.

---

## 2. Launch the app

```bash
./start.sh
```

A dark window titled **Retinal Screening Aid** opens.
Closing the window returns the terminal, and Ctrl+C in the terminal also stops the demo cleanly.
Do not click anything yet.
Point at the two badges in the top right first, because they answer the two questions a technical judge asks first.

**Badge 1, "Operating point 0.40, frozen 2026-08-23".**

> The decision threshold was frozen on that date and has not moved since.
> It is read live from the config file, so this badge cannot drift away from the model that produced our numbers.

**Badge 2, "Sealed external set: not opened".**

> Messidor-2 is sitting in `data/sealed/` and no code path in this demo touches it.
> It gets opened once, by a human key holder, after the operating point is frozen.
> That is what makes it an external validation rather than another tuning set.

---

## 3. Tour the screen, 60 seconds

Give the judges the map before you make anything move.

**Left rail, top to bottom:**

- **CASE**, the selected image, with the `Select fundus image` button.
- **`Run screening`**, the main action, also bound to the Enter key.
- **`Export report`**, greyed out until a case has been run.
- **Run status and processing time.**
- **Frozen model paths**, the exact checkpoint and calibration directory in use.
- **Validation numbers**, sensitivity and specificity, read from the config, not typed in.
- **Pipeline stages**, six dots: Quality gate, Preprocessing, CNN grading, Grad-CAM, Lesion evidence, ICDR rules.

> The stage dots are set from what the pipeline returned, not assumed.
> If the quality gate stops a case, the later dots stay unlit, and you can see it.

**Workspace, right side:**

- **Verdict strip** across the top: the decision, the calibrated probability, the predicted ICDR level, and the image quality class.
- **Four image panels**: Original fundus, Preprocessed, Grad-CAM, Lesion candidates.
- **Evidence panel and rule trace** underneath.

---

## 4. Case one, the healthy eye

Click `Select fundus image`, choose the grade 0 image, then click `Run screening`.

While the progress dialog spins, narrate:

> Quality gate first, then the shared preprocessing function, then the ResNet-50 grader at 448 by 448, then Grad-CAM, then a classical lesion detector, then the rule layer that turns all of it into one of three decisions.

When the result reveals, work the verdict strip left to right.

**The decision.**
One of three words: **AUTO-CLEAR**, **REFER**, **ESCALATE**.

> Three outcomes, not two.
> Auto-clear means the system took responsibility for sending this patient home.
> Refer means a human grader looks at it.
> Escalate means the system is not confident enough to be useful and is explicitly handing the case over.

**The calibrated probability.**

> This is not a softmax score.
> Softmax outputs are overconfident, so we fit a temperature on a held-out calibration split, and this number is temperature scaled at T equals 2.14.
> When it says 8 percent, roughly 8 percent of cases that look like this are actually referable.

**The predicted ICDR level and the quality class.**

Now the four panels.

- **Original fundus**, as captured.
- **Preprocessed**, and say the important part: *this is the exact same function used during training.* Enhancement applied at inference but not at training is self-inflicted domain shift, and it is a common and invisible failure in this problem space.
- **Grad-CAM**, where the network looked. For a healthy eye the heat should be diffuse, with nothing lighting up.
- **Lesion candidates**, from a classical detector, completely independent of the CNN.

Finish on the evidence panel:

> The rule layer requires positive evidence before it will auto-clear.
> The network being confident is not enough on its own.

---

## 5. Case two, the disease case

Select the grade 2 or grade 4 image and run it.
This is the case that earns the project.

Point at the Grad-CAM panel and the Lesion candidates panel side by side.

> These two panels are produced by completely different methods.
> Grad-CAM is gradient attribution from the network, the candidate map is classical image processing looking for microaneurysms.
> When they point at the same quadrants, we have agreement, and that is the evidence line in the panel.
> When they disagree, the case escalates instead of being cleared.

Read the evidence panel aloud:

- **Agreement**, the status.
- **Reason**, the plain-language justification for the verdict.
- **Candidates**, the total count, then the per-quadrant split: ST, IT, SN, IN, meaning superior-temporal, inferior-temporal, superior-nasal, inferior-nasal.
- **Grad-CAM layer**, the actual convolutional layer the heatmap came from.

> That last line matters. We are not asking you to trust a picture, we are telling you which layer produced it.

Note the honest caveat printed on screen: **"Candidate evidence is provisional."**
Do not hide it, use it.

> The classical detector is a cross-check, not a validated lesion detector.
> We say so on screen rather than implying more than we measured.

---

## 6. Export the report

Click `Export report`.

The status line shows the exported filename, and hovering it shows the full path.
The report lands in a new dated directory under `results/`, containing `screening_report.pdf`, `screening_report.png`, `screening_report.txt`, the four-panel figure, and the individual overlays.

> Every run goes into its own dated directory, alongside the full config that produced it.
> Nothing is overwritten, and any result on this screen can be traced back to a config file.
> The report is composed with `exportgraphics`, because Report Generator is outside our declared toolbox set and we did not want a dependency the reviewers might not have.

---

## 7. The numbers, 90 seconds

Close the app, or switch to a second terminal, and run:

```bash
./start.sh numbers
```

The headline, on the validation split, n equals 550, at the frozen 0.40 threshold:

| Metric | Value | 95% Wilson CI | Target |
| --- | --- | --- | --- |
| Sensitivity, referable DR | 0.982 | 0.955 to 0.993 | > 0.90 |
| Specificity, referable DR | 0.917 | 0.883 to 0.943 | > 0.85 |

Supporting numbers from `results/20260824_035401_full_metrics_validation/full_metrics.json`:

- ROC AUC 0.985.
- PPV 0.890, NPV 0.987, at the observed prevalence of 0.405.
- 219 true positives, 4 false negatives, 300 true negatives, 27 false positives.

Say this out loud:

> Four missed referable cases out of 223.
> We report the misses, not just the rate.

And this:

> We never report bare accuracy.
> Sensitivity and specificity at a frozen operating point, with intervals, with n stated.
> Accuracy on an imbalanced screening set is a number that flatters a model that has learned nothing.

---

## 8. The ablation, and the finding that is worth more than the headline

Open `results/20260824_132627_ablation_A1_A5/ablation_table.csv`.
Five configurations, one code path, five config files.
No code was edited or commented out between them.

| Config | What it is | Sensitivity | Specificity | Coverage |
| --- | --- | --- | --- | --- |
| A1 | CNN only | 0.982 | 0.917 | 1.00 |
| A2 | CNN plus quality gate | 0.982 | 0.917 | 1.00 |
| A3 | Lesion rules only, no CNN | 0.000 | 1.000 | 1.00 |
| A4 | CNN, quality gate, deferral | 0.664 | 0.972 | 0.838 |
| A5 | Full pipeline | 0.049 | 1.000 | 0.275 |

Three things to say, and say all three.

**A3 proves the CNN is doing the work.**
The classical lesion rules on their own catch nothing, 0 sensitivity, 223 missed cases.
That is why the detector is a cross-check and not the grader.

**A5 is a negative result and we are reporting it.**

> The full pipeline, with every safety rail on, only makes an autonomous decision on 27 percent of cases.
> It is nearly perfect on the ones it does decide, one miss and 99.3 percent autonomous accuracy, but it escalates 399 of 550 cases to a human.
> That is not a deployable operating point, it is a system tuned so conservatively that it barely reduces the grader's workload.
> A1 and A2 are the configuration that delivers the headline numbers.
> We measured this rather than shipping the full pipeline and calling the extra rails an improvement.

If a judge presses on it, that is a good thing.
The answer is that the agreement check between Grad-CAM and the classical detector is currently too strict, the escalation rate is the metric that shows it, and the fix is a calibrated agreement threshold rather than a binary one.

---

## 9. The Simulink district model, 60 seconds

Open `results/20260823_213652_639_E2_sensitivity_versus_workload/sensitivity_versus_grader_hours.png`.

> This is a SimEvents model of a district screening programme, one upload queue, a pool of graders, real arrival patterns.
> It answers the question a health administrator asks, which is not "what is your AUC", it is "how many grader hours do I need to fund".

From the sweep, over 3835 arrivals:

- At model sensitivity 0.90, roughly 209 grader hours per year.
- At sensitivity 0.97, roughly 215 grader hours.
- Mean turnaround stays near 1.09 hours, and p95 near 6.06 hours, across the whole range.

> Buying the last 7 points of sensitivity costs about 6 extra grader hours a year.
> That is a cheap trade, and it is the argument for setting the threshold where we set it.
> Every parameter in that model is a named variable in `simulink/district_config.json`, not a number typed into a block dialog.

Six sweeps exist: minimum grader count, sensitivity versus workload, deferral threshold, bandwidth, quality gate, and arrival pattern.
Show more only if asked.

---

## 10. Engineering credibility, 30 seconds, only if you have time

```bash
./start.sh tests
```

Takes about 8 minutes, so do not run it live unless a judge asks.
Say instead:

> 212 tests.
> One of them asserts that no class has zero recall on a smoke run, because a model that collapses to the majority class shows a perfectly healthy loss curve and raises no error.
> That actually happened to us during development, and the test exists because of it.
> Another asserts that no patient ID appears in two splits.
> The splits are patient-level, four-way, stratified, generated once with a fixed seed, and committed as CSVs.

---

## 11. Likely questions, with answers

**"What is your accuracy?"**
We do not report accuracy on this problem, because at 40 percent prevalence a model that guesses one class scores 60 percent.
Sensitivity is 0.982 and specificity is 0.917 at the frozen threshold, on 550 validation cases, with Wilson intervals.

**"Why 448 by 448, that is expensive?"**
Microaneurysms are a few pixels wide at native resolution.
At 224 they are gone, and the earliest referable grade becomes invisible.
Under VRAM pressure we reduce batch size, never resolution.

**"Have you tested on external data?"**
Not yet, deliberately.
Messidor-2 is sealed in the repository and will be opened once, after this operating point was frozen and dated.
A number produced after peeking is not an external validation result.

**"Is the Grad-CAM actually meaningful?"**
We measured it rather than assuming.
Insertion AUC is 0.81 and deletion AUC is 0.33 across 27 evaluated cases, which says the highlighted regions do drive the prediction.
The overlap with annotated lesion pixels is weak, mean hit rate 0.086 against a random baseline of 0.066, so Grad-CAM localises what the network uses, not reliably what a clinician would circle.
We report both numbers.

**"Can it replace an ophthalmologist?"**
No, and the design does not try to.
It is a triage aid with a deliberate escalate path, and the ablation shows exactly what fraction of cases it hands back.

**"What if the image is bad?"**
The quality gate runs first and can stop the case before grading, and the app returns recapture advice telling the operator what to fix.
You can see it in the pipeline stage dots, the later stages stay unlit.

---

## 12. If something breaks live

- **The window does not appear.** Wayland issue, `start.sh` already exports the workarounds. Press Ctrl+C in the terminal, which stops MATLAB and all its child processes, then rerun `./start.sh`.
- **A case errors.** The status line turns red with the message. Say "that is the error path doing its job", select a different image, and move on. Do not debug in front of judges.
- **MATLAB is slow or hangs.** Fall back to `./start.sh demo`, which is the headless single-image run and prints the full decision trace to the terminal.
- **MATLAB will not start at all.** Present from `results/` directly: the exported PDF report, the ablation table, and the Simulink figure carry the whole story without the GUI.

---

## 13. Closing line

> Every number on that screen comes from a frozen checkpoint and a dated config, the external set has not been opened, and the ablation that shows our full pipeline over-escalating is in the repository next to the ablation that shows it working.
> We would rather show you the result we got than the result we wanted.
