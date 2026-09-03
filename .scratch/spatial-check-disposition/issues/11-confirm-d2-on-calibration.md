# Confirm the recalibrated spatial constants on the calibration split

Status: ready-for-agent
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
