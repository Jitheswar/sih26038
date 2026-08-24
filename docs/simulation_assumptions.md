# District screening capacity simulation assumptions

This document describes the inputs to the SimEvents capacity-planning model.
Simulation outputs are operational planning results conditional on these assumptions.
They are not clinical outcomes, clinical validation, or evidence of patient benefit.

## Model boundary

The model represents one district screening workflow from patient arrival through report issuance.
It contains a real discrete-event model in `simulink/district_model.slx`.
The model uses SimEvents Entity Generator, Queue, Server, Entity Output Switch, Entity Input Switch, Resource Pool, Resource Acquirer, Resource Releaser, and Entity Terminator blocks.
The experiment runner loads named values from `simulink/district_config.json` into the model workspace.
No experiment parameter is typed as a numeric constant into a block dialog.

The sealed external test set is not used by this model or its experiments.
The model is not a substitute for the evaluation harness and does not establish sensitivity, specificity, safety, or clinical effectiveness.

## Parameter status

The JSON configuration keeps required parameters as numeric or string fields so they can be validated and swept.
`parameterMetadata.<field>.assumed` is the authoritative marker for whether a value is measured.
Values marked `assumed: true` must not be presented as measured project values.

Currently measured project values: none of the required capacity-model inputs have been frozen from the quality-gate evaluation, actual screening-pipeline benchmark, evaluation harness, decision-policy risk-coverage curve, or reader study.
The annual volume and simulation horizon are planning inputs from R5.2 and are not clinical measurements.

The quality rejection rate of `0.21` is a clearly labelled placeholder.
The 21 percent field result described in the design document is external context and is not treated as a measurement from this project.

Inference time is a placeholder until the actual screening pipeline is benchmarked on target hardware.
Model sensitivity and specificity are placeholders until the evaluation harness produces a frozen operating point.
Deferral rate has now been measured, and the configured value is deliberately not the measured one.

Measured over the full validation split on 24 August 2026 with `eval/ablationHarness.m` configuration A5 at the frozen operating point, autonomous coverage is 0 of 550 cases.
Every case escalates to human review, so the measured deferral rate is `1.00`, recorded as `measuredDeferralRate` in the district config.
`grade.decisionPolicy` raises `required-evidence-unknown`, `unknown-neovascularisation-status`, `candidate-evidence-provisional` and `rule-engine-recommends-escalation` on every image while the only evidence source is classical microaneurysm candidate detection, and those codes force escalation before any threshold is consulted.
The configured `deferralRate` of `0.10` is retained as a scenario value describing a decision policy that can act autonomously.
The current pipeline is not that policy, so any sweep run at `0.10` models a hypothetical improved system and must be labelled that way whenever its numbers are quoted.
Grader service time is a placeholder until the reader study reports service time.
Capture time, quality-gate time, image size, bandwidth, connectivity availability, retry interval, PHC count, prevalence, camp multiplier, and the turnaround target are scenario assumptions.

`maximumRecaptureAttempts` is a project policy value of two.
`arrivalRate` is derived from annual volume and the simulation horizon.
The default burst multiplier uses one high-volume camp day in a seven-day cycle and reduces the off-camp rate so the weekly expected volume remains equal to the configured annual rate.
Smooth arrivals use the configured rate deterministically.
Bursty arrivals use the same deterministic event calendar with camp-day and off-camp rates, while quality, routing, and service outcomes remain stochastic under `randomSeed`.

## Service and routing assumptions

PHC capture is a shared finite-capacity server with capacity equal to the configured number of PHCs.
The quality gate is served in parallel with capture capacity and rejects an independent Bernoulli fraction of attempts when enabled.
Rejected attempts return to the PHC capture queue until the configured maximum is reached.
After the maximum, the default route is escalation into the upload and human-review path.
The total-attempt attribute is retained on the entity and is reported by the logger.

The AI decision is sampled using the configured sensitivity and specificity against the configured referable prevalence.
Non-deferred true-positive and false-positive cases are referred.
Deferred cases are escalated and require human review.
Auto-clear cases leave the model without upload or grader service.
This is a capacity abstraction of the three-way policy, not a clinical decision engine.

Upload service time is `imageSizeMegabytes * 8 / bandwidthMegabitsPerSecond` seconds.
Connectivity is represented as a repeating availability window with period `connectivityCycleSeconds`.
When an upload starts during the unavailable portion, the entity waits in the upload server until the next available window, implementing store-and-forward behavior.
The upload queue is a real SimEvents Queue and therefore responds to both file size and connectivity.

The grader path uses a SimEvents Resource Pool named `Graders`.
The pool amount is configurable, the Resource Acquirer waits for a grader, and the Resource Releaser returns it after the grader server completes.
The default grader service time is deterministic because no reader-study distribution is currently available.
Grader-hours are measured directly from simulated grader busy time, not estimated analytically.

`failedCaptureRouting` is a configured field for a future routing choice between escalating or referring exhausted-recapture cases.
The current model always escalates them; the field is not yet read by the build script.
This is recorded here so it is not mistaken for wired behaviour.

The logger distinguishes two kinds of escalation.
`totalEscalated` is every case sent to human review outside the normal referral path: both quality-exhausted recaptures and AI-deferred cases.
`totalDeferralEscalations` is the safety-related subset caused only by the AI deferral policy, reported separately by E3.

## Interpreting results

Queue lengths are time-series statistics from the SimEvents queues.
Turnaround is measured from entity generation to completed report output for entities that complete before the simulation stop time.
The 95th percentile is calculated over completed entities only.
The percentage meeting the turnaround target is `100 * count(turnaround <= target) / completed`.
Incomplete entities at the stop time remain in the event model and are not counted as completed reports.

Every experiment saves a dated directory containing the exact JSON configuration, result structure, CSV summary, and MATLAB plots.
Existing results are never overwritten.

## Sampling window for experiments E1-E4

A full 365-day, 100,000-entity run of every sweep point in E1-E4 is wall-clock expensive (tens of minutes per run).
`sweep_experiments.m` instead simulates a shorter window (`windowDays`, 14 by default) while holding the arrival rate at the true annual pace: it passes an explicit `ArrivalRate` override (`annualVolume / (365*86400)`) together with a shorter `SimulationDurationDays`, rather than deriving the rate from the short window.
This yields steady-state queueing statistics — arrivals, service times, and routing decisions are unaffected by the window length — without the cost of simulating a full year.
Annualised figures (grader-hours per year, minimum graders for a stated annual volume) are the short-window measurement scaled by `365 / windowDays`, and every such figure is labelled as extrapolated where it is reported.
This window length is itself an assumption, traded for wall-clock feasibility; a longer window narrows sampling noise at proportionally higher run cost.
