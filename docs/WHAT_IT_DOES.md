# What this program does, in plain English

This is the "what is it" document.

---

## The problem

Diabetes damages the blood vessels at the back of the eye.
This is called diabetic retinopathy, and if it is caught early it can be treated, and if it is not, the person goes blind.

Catching it early means photographing the retina of every diabetic person, regularly.
Taking the photo is easy and cheap.
The hard part is that an eye doctor has to look at every single photo, and there are far more photos than there are eye doctors.

Most of those photos are of healthy eyes.
The doctor's time is being spent confirming that nothing is wrong.

## What we built

A program that looks at each retina photo first, and sorts it into one of three piles:

- **Auto-clear.** The eye looks healthy, and the program is willing to say so without a doctor.
- **Refer.** There is disease here, send this person to a doctor.
- **Escalate.** The program is not sure, so a human has to look.

The third pile is the important one.
A system with only two answers has to guess when it does not know, and guessing about a patient is the wrong thing to do.
Our system is allowed to say "I don't know", and it says so out loud.

It is a screening aid, not a diagnosis.
It decides who needs a doctor's attention, not what is wrong with them.

## The "explainable" part

A program that just prints "refer" is not usable in a clinic, because nobody can check it.
So for every case, this one also shows its working:

- **A heat map** showing which parts of the image the neural network was actually looking at when it decided.
- **A lesion map** from a second, separate model that marks the damaged spots it can find.
- **A written reason** in the report, saying in words why the case got the answer it got.

The two maps are produced by different methods that do not talk to each other.
When they point at the same place, that is real support for the answer.
When they point at different places, the case gets escalated to a human instead of being decided.
That disagreement check is the core safety idea of the whole system.

## How a single image flows through it

Six steps, in this order:

1. **Quality gate.** Is this photo even readable?
   A blurred or badly lit photo is stopped here, before any model is trusted with it, and the operator is told what to fix.
2. **Preprocessing.** The image is cleaned and resized to a standard form.
   The exact same code does this during training and during use, which matters more than it sounds like it does.
3. **CNN grading.** A ResNet-50 neural network reads the image and grades it 0 to 4 on the standard ICDR scale.
4. **Grad-CAM.** The heat map of where that network looked.
5. **Lesion evidence.** A separate segmentation network marks hard exudates, which are one of the visible signs of the disease.
6. **ICDR rules.** A plain rule layer takes all of the above and produces one of the three decisions.

The last step is ordinary rules, not a model.
That is on purpose.
The part of the system that makes the final call about a patient is the part you can read and argue with.

## How well it works

On 550 validation images, at the decision threshold we froze on 23 August 2026:

- **Sensitivity 0.982.** Of the people who genuinely needed referral, it caught 98.2 percent.
- **Specificity 0.917.** Of the healthy people, it correctly left 91.7 percent alone.

Sensitivity is the number that matters most, because the cost of missing sick people is much higher than the cost of sending a healthy person for a second look.

We do not report "accuracy", ever.
About 40 percent of these images are referable, so a program that blindly answers "healthy" to everything scores 60 percent accuracy while being completely useless.
Accuracy hides that.
Sensitivity and specificity do not.

There is also a Simulink model of a whole district screening programme, with an image queue and a pool of human graders.
It answers the question a health administrator actually asks, which is not "what is your AUC" but "how many grader hours a year do I have to pay for".

## The things we are careful to say

**The external test set has not been opened.**
There is a second dataset, Messidor-2, sealed in the repository.
No code touches it.
It gets opened once, by a person, after the settings were locked in and dated.
If you tune your system while looking at a test set, that test set has stopped being a test.

**The lesion evidence is provisional.**
It is a helpful cross-check, not a clinically validated lesion detector, and the report says so on every case.

**Some disease signs have no detector at all.**
The most severe grade involves new blood vessel growth, and we have no detector for it, so the rule layer can never reach that grade from evidence alone.
It is written down as a known gap rather than quietly ignored.

**Escalation is a feature, not a failure.**
Currently the system decides about a third of cases on its own and hands the rest to a human.
That is a real limitation and we report it as one, rather than loosening the safety checks until the number looks better.

## How it is built

MATLAB, run headlessly, with a small App Designer window for the demo.
The full reasoning behind every design decision is in `docs/SIH26038_design.html`, which is the source of truth for this project.

Some rules the code follows, because each one exists to prevent a specific silent failure:

- Turning parts of the pipeline on and off is done by editing a config file, never by editing code.
  Thirteen different experiment configurations run through one single code path.
- Every run writes its results into a new dated folder with a copy of the config that produced it.
  Nothing is ever overwritten.
- Every entry point sets a fixed random seed, so any result can be reproduced.
- The train, validation, calibration and test splits are split by patient, not by image, and are committed as files.
  A test asserts that no patient appears in two of them.
- Every training run prints the recall for each class separately.
  A model that has collapsed into always answering "healthy" produces a beautiful loss curve and no error message, and per-class recall is the cheapest way to catch it.
  This happened to us during development, and there is now a test for it.
