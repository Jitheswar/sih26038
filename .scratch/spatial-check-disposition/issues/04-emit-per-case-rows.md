# Emit per-case rows from the ablation harness

Status: ready-for-agent
Blocked by: 03

## Problem

`results/<run>/ablation_table.csv` reports `missed_referable` as an integer: 1 for A5, 2 for A12, 4 for A13.
Nothing anywhere records *which* patients those are.

The entire safety cost of the spatial check decision is 2 patients whose grades, IDs and images nobody has looked at. `eval/agreementLevelMismatch.m` did per-case attribution for escalations and nothing does it for misses, which is why the escalation column got explained and the safety column did not.

The harness already holds everything needed. `split.imageIds` is carried at line 169 and `localComposeDecisions` replays `grade.decisionPolicy` per configuration at line 557 with the full decision input in hand.

## Expected behaviour

Every ablation run writes `per_case.csv` alongside `ablation_table.csv`, one row per image per configuration:

`config, image_id, truth_grade, truth_referable, decision, calibrated_probability, cnn_level, rule_level, agreement_status, agreement_basis, spatially_agree, spatial_statistic, reason_codes, finding_kinds, missed_referable`

`missed_referable` is the boolean identifying exactly the patients the safety column counts.

Write it from the harness itself, not a separate script. The harness is where the numbers are produced, so it should emit the rows behind every column it reports.

## Notes

`reason_codes` and `finding_kinds` are joined with a separator that survives CSV quoting.
This outlives the current decision: every future ablation gets an inspectable safety column.

## Acceptance

- `per_case.csv` written for every run, one row per image per configuration
- Row counts reconcile exactly with every aggregate in `ablation_table.csv`
- A test asserts the per-case rows reproduce the aggregate row for at least one configuration
