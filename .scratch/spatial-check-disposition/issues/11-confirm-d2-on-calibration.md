# Confirm the recalibrated spatial constants on the calibration split

Status: resolved
Blocked by: none

## Problem

The sweep of 3 September found that `spatialAttentionCut` 0.40 with `spatialAgreementFraction` 0.15 escalates all four patients the classifier sends home, at an escalation load of 44.2 per cent against the shipped pair's 57.1 per cent. That is about 71 fewer patients sent to a human out of 550, at no measured cost in the patients the gate exists to catch, and §9.5 prices it in grader-hours.

It cannot ship on that measurement. The pair was selected on the validation split, which is the split that reports it, and selecting a safety constant that way is the error `eval/metrics/riskCoverage.m` and §10.4 exist to prevent. ADR 0002's addendum records it as a costed proposal awaiting confirmation.

## Expected behaviour

One ablation pass over the **calibration** split (n = 365) with A10, which now exports `spatial_evidence.mat`, then `eval/spatialConstantSweep.m` offline against it.

The question is not "what is the best pair on calibration". It is narrower and pre-committed:

**Does the pair selected on validation, 0.40 and 0.15, still escalate every patient the classifier sends home on calibration, and at what load?**

Report the shipped pair's load on calibration alongside it, so the comparison is like for like on one split.

Selection discipline. The candidate pair is fixed before this runs and is not re-chosen here. If a different pair looks better on calibration, that is a finding to record and not a value to adopt, because adopting it would repeat on calibration exactly the error this ticket exists to correct.

## Decision rule

- If 0.40 / 0.15 catches every classifier miss on calibration and its load is materially below the shipped pair's, adopt it in `config/default.json` before the configuration freeze, and record the adoption with both splits' numbers.
- If it misses any of them, it does not ship, the shipped pair stays, and the finding is that the validation surface did not transfer.
- Either way the frozen operating point, the checkpoint and the temperature are untouched: this changes only how the §8.6 spatial state is decided.

## Acceptance

- Dated results directory for the calibration pass and the sweep
- A written verdict against the decision rule above, appended here
- §11.6 and ADR 0002 updated with the calibration numbers
- `config/default.json` changed only if the rule says adopt
- Full suite green

## Answer: it does not ship. The validation surface did not transfer.

Calibration pass `results/20260904_004923_ablation_A1_A5`, sweep `results/20260904_004930_spatial_constant_sweep`. On calibration the classifier sends **five** referable patients home, against four on validation.

| | catches | escalation load |
| --- | --- | --- |
| shipped, 0.35 / 0.25 | **5 of 5** | 56.7% |
| candidate, 0.40 / 0.15 | **4 of 5** | 44.1% |

The candidate loses `4ef0b485a7da`, reference grade 2, which the classifier scores at a calibrated referable probability of **0.0675**. That is not a borderline case the classifier was unsure about; it is one it was confidently wrong about, which is the exact population this gate exists to catch.

The mechanism is visible in one number. At the shipped attention cut of 0.35 the patient's cleared fraction is 0.2000, below the shipped agreement fraction of 0.25, so the gate fires and she is escalated. At the candidate's cut of 0.40 her cleared fraction is 0.1875, which is above the candidate's agreement fraction of 0.15, so the gate does not fire and she is auto-cleared. The candidate buys its 12.6 points of load by lowering the bar past exactly this patient.

**Decision rule fires on the second branch: it does not ship.** The shipped pair stays. `config/default.json` is unchanged.

Calibration's own best pair is 0.15 / 0.40 at 41.9 per cent, and it is deliberately not adopted either. Selecting it here would repeat on calibration precisely the error this ticket exists to correct, and there is no third split left to confirm it on.

### Why this ticket was worth running

The validation sweep was not wrong about validation: 0.40 / 0.15 genuinely catches all four there. It was wrong about the world. Adopting on that evidence alone would have shipped a gate that sends a confidently-mis-scored referable patient home, and the ablation table would have shown a 12.9 point improvement in escalation load while it did so.

The saving is not lost so much as shown to be unavailable: the load the shipped constants carry is buying the patients on the boundary, and the boundary is where the classifier's confident errors sit.
