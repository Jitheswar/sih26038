# Emit per-case rows from the ablation harness

Status: resolved
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

## Resolution

`ablation_table.csv` is now accompanied by `per_case.csv`, one row per image per configuration, written by the harness itself. Row counts reconcile with every aggregate the table reports, and that reconciliation is the test rather than an assertion about it.

The row carries the continuous spatial statistic as well as the boolean verdict, because a patient the gate caught just short of the cut and one it caught far short are different findings and the boolean cannot tell them apart.

Visible immediately on a four-image smoke run: image `000c1434d8d7`, reference grade 2, CNN level 2 at a calibrated probability of 0.909, rule level 2, 85 candidates, escalated on `spatially inconsistent` with a spatial statistic of 0.0588 against a required 0.25. Both channels agreed the patient was referable and the gate escalated anyway, on a channel §8.3 records as unable to localise a lesion at that resolution, and not marginally.
