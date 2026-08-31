# Demo script: what to click, and what everything on screen is

This is the presenting document.
For the plain-English explanation of what the program is and how it works, see `docs/WHAT_IT_DOES.md`.

Everything runs from `./start.sh` in the project root.
Plan for about 8 minutes of demo, plus questions.

---

## Part 0. Before you present

### Check the machine

```bash
./start.sh check
```

Every line should be green.
It confirms MATLAB is installed, the frozen model file exists, the images exist, and the sealed test set is present but untouched.
If a line is red, fix it now, because the app will fail in exactly the same place in front of the judges.

### Do one warm-up run

Launch the app once, screen one image, and close it.
The first launch has to load the neural network from disk and is noticeably slower than the second.
Do not let that pause be the first thing anyone sees.

### Know your images

Twelve real cases are already prepared in `~/sih-demo-cases`, one for each behaviour the system can show.
Each folder has the image, the four panels, and the exported PDF report from a real run.
Open `~/sih-demo-cases/README.md` to see the table of all twelve.

For a live demo, use these three.
They are in `data/raw/aptos2019/train_images/`:

| Order | File | What happens | Why show it |
| --- | --- | --- | --- |
| 1 | `143db89c11c8.png` | AUTO-CLEAR, risk 2.0% | A healthy eye handled without a doctor |
| 2 | `3b185ac445d0.png` | REFER, risk 99.2% | Severe disease, caught and referred |
| 3 | `9df31421cdd2.png` | ESCALATE | The quality gate stopping a bad photo |

Never demo an image you have not run yourself first.

### Have these open in other windows

- `docs/SIH26038_design.html` for any "why did you choose that" question.
- `~/sih-demo-cases/README.md` for the twelve-case table.
- `results/20260830_232525_ablation_A1_A5/ablation_table.csv` for the experiment table.

---

## Part 1. Opening line, 30 seconds

Say this before you touch anything:

> Diabetic retinopathy is screened by photographing the retina.
> The bottleneck is not the camera, it is the eye doctor who has to read every single photo, and most of the photos are of healthy eyes.
> This system reads them first, sends home only the eyes it can justify sending home, shows its reasoning every time, and hands anything it is unsure about back to a human.
> It is a screening aid, not a diagnosis.

Say that last sentence.
It is the line that separates a project that has thought about real clinical use from one that has not.

---

## Part 2. Launch the app

```bash
./start.sh
```

A dark window opens, titled **Retinal Screening Aid**.
Closing the window gives you the terminal back, and Ctrl+C in the terminal also stops it cleanly.

**Do not click anything yet.**
Point at the two badges in the top right corner first, because they answer the two questions a technical judge asks first.

**Badge 1: "Operating point 0.40, frozen 2026-08-23".**

> That is the decision threshold, and it was locked on that date.
> The badge is read live out of the config file, so it cannot drift away from the model that produced our numbers.

**Badge 2: "Sealed external set: not opened".**

> There is a second dataset sitting in `data/sealed/` and nothing in this demo touches it.
> It gets opened once, by a person, now that the threshold is frozen.
> That is what makes it a real external test instead of another tuning set.

---

## Part 3. Tour the screen, 60 seconds

Give them the map before you make anything move.

### The left rail, top to bottom

| Item | What it is |
| --- | --- |
| **CASE** | The image you picked, with the `Select fundus image` button |
| **`Run screening`** | The main button. The Enter key does the same thing |
| **`Export report`** | Greyed out until a case has been run |
| **Status and time** | Whether it ran, and how long it took |
| **Model paths** | The exact checkpoint and calibration files in use |
| **Validation numbers** | Sensitivity and specificity, read from config, not typed in |
| **Pipeline stages** | Six dots: Quality gate, Preprocessing, CNN grading, Grad-CAM, Lesion evidence, ICDR rules |

Say this about the dots:

> The dots are set from what the pipeline actually returned, not assumed.
> If the quality gate stops a case, the later dots stay dark, and you can see exactly where it stopped.

### The right side, top to bottom

**The verdict strip**, four big tiles across the top:

- **DECISION.** One of AUTO-CLEAR, REFER, ESCALATE.
- **REFERABLE RISK.** The calibrated probability that this patient needs referral.
- **ICDR GRADE.** The 0 to 4 severity grade the network predicted.
- **IMAGE QUALITY.** Whether the photo was good enough, and what to fix if not.

**The four image panels** underneath:

- **Original fundus**, the photo as captured.
- **Preprocessed**, the cleaned version the network actually sees.
- **Grad-CAM**, where the network looked.
- **Lesion candidates**, damaged spots found by a separate model.

**The evidence panel and rule trace** at the bottom, which is the written explanation of the verdict.

---

## Part 4. Case one, the healthy eye

Click `Select fundus image`, pick `143db89c11c8.png`, then click `Run screening`.

While the progress bar spins, narrate the pipeline:

> Quality check first, then the shared preprocessing, then the ResNet-50 grader at 448 by 448 pixels, then the heat map, then the lesion model, then the rule layer that turns all of it into one decision.

When the result appears, work the verdict strip from left to right.

**DECISION: AUTO-CLEAR.**

> Three possible answers, not two.
> Auto-clear means the system is taking responsibility for sending this patient home.
> Refer means send them to a doctor.
> Escalate means the system is not confident enough to be useful, and is explicitly handing the case over rather than guessing.

**REFERABLE RISK: 2.0%.**

> This is not the raw network output.
> Raw neural network scores are overconfident, so we fitted a correction on a separate held-out set of images.
> When this says 2 percent, it means roughly 2 out of 100 cases that look like this really do need referral.

**ICDR GRADE and IMAGE QUALITY.** Read them off, they are self-explanatory.

Now the four panels.
Spend your words on two of them:

**Preprocessed.**

> This is the exact same function that ran during training.
> If you clean the image at use time but not at training time, you have created a mismatch that no metric will ever name, and it is a common and invisible failure in this problem.

**Grad-CAM.**

> This is where the network was looking.
> On a healthy eye the heat should be spread out with nothing lighting up, and that is what you see.

Finish on the evidence panel:

> The rules require positive evidence before they will auto-clear anyone.
> The network being confident is not on its own enough to send a patient home.

---

## Part 5. Case two, the disease case

Select `3b185ac445d0.png` and run it.
This is the case that earns the project.

DECISION comes back **REFER**, risk **99.2%**, grade 3.

Now put your finger on the Grad-CAM panel and the Lesion candidates panel, side by side:

> These two pictures are made by two completely different methods that never talk to each other.
> The left one is the classifier telling us where it looked.
> The right one is a separate segmentation network marking the actual damaged tissue it can find.
> When they agree, we have real support for the answer.
> When they disagree, the case escalates to a human instead of being decided.

Read the evidence panel out loud:

- **Agreement**, whether the two channels lined up.
- **Reason**, the plain-language justification for this verdict.
- **Candidates**, how much evidence was found and in which quadrant of the eye.
- **Grad-CAM layer**, the exact network layer the heat map came from.

> That last line matters.
> We are not asking you to trust a pretty picture, we are telling you which layer produced it.

There is a line on screen saying the candidate evidence is **provisional**.
Do not hide it, use it:

> It is a cross-check, not a clinically validated lesion detector.
> We say so on screen rather than implying more than we measured.

---

## Part 6. Case three, the bad photo

Select `9df31421cdd2.png` and run it.

DECISION comes back **ESCALATE**, and the IMAGE QUALITY tile says the photo is not clearly gradable.

> This is the first stage of the pipeline, and it runs before any model is trusted.
> A rural camera operator gets told what to fix and can retake the photo on the spot, rather than the patient getting a confident answer computed from an unreadable image.

Point at the stage dots on the left rail while you say it.
You can see where it stopped.

---

## Part 7. Export the report

Click `Export report`.

The status line shows the filename, and hovering over it shows the full path.

> Every run goes into its own new dated folder, with a copy of the config that produced it.
> Nothing is ever overwritten, so any number on this screen can be traced back to the exact settings that made it.

The folder contains the PDF report, the PNG version, a plain text version, the four-panel figure, and each overlay on its own.
Open the PDF if you have time.

---

## Part 8. The numbers, 90 seconds

Close the app, or switch to a second terminal:

```bash
./start.sh numbers
```

On 550 validation images, at the frozen 0.40 threshold:

| Metric | Value | Target |
| --- | --- | --- |
| Sensitivity, referable disease | 0.982 | above 0.90 |
| Specificity, referable disease | 0.917 | above 0.85 |

Say both of these out loud:

> Four missed referable cases out of 223.
> We report the misses, not just the rate.

> We never report accuracy on this problem.
> At 40 percent prevalence, a program that answers "healthy" to everything scores 60 percent accuracy while being useless.
> So we report sensitivity and specificity at a frozen threshold, with confidence intervals, with the number of cases stated.

---

## Part 9. The experiment table, and the honest finding

Open `results/20260830_232525_ablation_A1_A5/ablation_table.csv`.
Thirteen configurations, one code path, thirteen config files.
No code was edited or commented out between any of them.

Three things to say, and say all three.

**The lesion rules alone catch nothing.**
Run on their own with no network, sensitivity is 0.000.
That is why the lesion model is a cross-check and not the grader.

**Our best explanation model was, at first, useless as evidence.**

> We trained a lesion segmentation network, and by the measurements it is our best explanation channel by a wide distance.
> It points at real lesions 4.87 times better than chance, against 1.32 for Grad-CAM.
> It was also completely unusable as evidence, because it called all 550 images referable, including every healthy eye.
> Its thresholds had been picked to look good on the dataset it was trained on, and they did not survive the move to a different camera population.
> We reselected them on a set we had held back for exactly this, switched off the one detector head that was reporting 46 lesions on a healthy eye, and specificity went from 0.00 to 0.83.

**And then the interesting part.**

> Fixing the channel barely moved the pipeline.
> That told us the bottleneck was not the evidence at all, it was the agreement check, which was escalating cases just for reaching a moderate grade.
> We repaired that on 31 August, and the share of cases the system decides by itself went from 6.9 percent to 32.7 percent, with zero referable patients wrongly sent home.
> We predicted the cause, then measured it, and the measurement agreed.

If a judge pushes on the fact that the system still hands two thirds of cases to a human, that is a fair hit and the honest answer is that it is a real limitation, it is measured, it is in the repository, and the alternative was to loosen the safety checks until the number looked better.

---

## Part 10. The district simulation, 60 seconds

Open `results/20260823_213652_639_E2_sensitivity_versus_workload/sensitivity_versus_grader_hours.png`.

> This is a simulation of an entire district screening programme: an upload queue, a pool of human graders, realistic arrival patterns.
> It answers the question a health administrator actually asks, which is not "what is your AUC", it is "how many grader hours do I need to fund".

From the sweep, over 3835 arrivals:

- At sensitivity 0.90, about 209 grader hours a year.
- At sensitivity 0.97, about 215 grader hours a year.

> Buying the last 7 points of sensitivity costs about 6 extra grader hours a year.
> That is a cheap trade, and it is the argument for putting the threshold where we put it.

---

## Part 11. Engineering credibility, only if you have time

Do not run the test suite live, it takes about 8 minutes.
Say this instead:

> The suite covers every stage of the pipeline, from preprocessing through to the app's own render path.
> One test asserts that no class has zero recall on a smoke run, because a model that collapses into always answering "healthy" produces a healthy-looking loss curve and no error message.
> That actually happened to us during development, and the test exists because of it.
> Another asserts that no patient appears in two different data splits.

---

## Part 12. Questions you will get, with answers

**"What is your accuracy?"**
We do not report accuracy here, because at 40 percent prevalence, guessing one class scores 60 percent.
Sensitivity is 0.982 and specificity 0.917 at the frozen threshold, on 550 cases, with confidence intervals.

**"Why 448 by 448? That is expensive."**
Microaneurysms are a few pixels wide.
At 224 by 224 they are gone, and the earliest treatable stage becomes invisible.
When we run short of GPU memory we cut the batch size, never the resolution.

**"Have you tested on external data?"**
Not yet, on purpose.
Messidor-2 is sealed in the repository and gets opened once, now that the threshold is frozen and dated.
A number produced after peeking is not an external result.

**"Is the heat map actually meaningful?"**
We measured it instead of assuming.
Insertion score 0.81 and deletion score 0.33, which says the highlighted regions really do drive the prediction.
The overlap with annotated lesions is weak, 0.086 against a random baseline of 0.066, which says Grad-CAM shows what the network uses, not reliably what a clinician would circle.
We report both numbers, including the weak one.

**"Can this replace an eye doctor?"**
No, and it is not designed to.
It is a triage aid with a deliberate escalate path, and the experiments show exactly what fraction of cases it hands back.

**"What if the image is bad?"**
The quality gate runs first and stops the case before grading, and the app tells the operator what to fix.
Case three in this demo is exactly that.

**"Why does it escalate so much?"**
Because we would rather it says "I don't know" than guess about a patient.
It currently decides about a third of cases on its own, that number is measured and reported, and reducing it further is the next piece of work rather than something we hid.

---

## Part 13. If something breaks live

- **No window appears.** Press Ctrl+C in the terminal, which stops MATLAB and all its child processes, then run `./start.sh` again.
- **A case errors.** The status line turns red. Say "that is the error path doing its job", pick another image, move on. Do not debug in front of judges.
- **MATLAB is slow or stuck.** Fall back to `./start.sh demo`, which runs one image headlessly and prints the whole decision trace to the terminal.
- **MATLAB will not start at all.** Present from `~/sih-demo-cases` instead. All twelve cases are already exported there as PDFs with their panels, and they carry the entire story without the app.

---

## Part 14. Closing line

> Every number on that screen comes from a frozen model file and a dated config.
> The external test set has not been opened.
> The experiment showing our pipeline over-escalating is sitting in the repository right next to the one showing it working.
> We would rather show you the result we got than the result we wanted.
