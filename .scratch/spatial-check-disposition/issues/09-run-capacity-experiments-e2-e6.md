# Run the remaining capacity experiments E2 to E6

Status: ready-for-agent
Blocked by: none

## Problem

§9.5 specifies six capacity experiments for R5.2. `simulink/sweep_experiments.m` implements all six. `results/` contains only `E1_minimum_grader_count`, last run 23 August.

R5.1 and R5.2 are a fifth of the problem statement, and the design document calls §9 "the highest return-per-hour component in the entire problem statement". Five sixths of it is unrun.

## Expected behaviour

Run E2 to E6 via `sweep_experiments`, each to its own dated results directory with its configuration alongside.

Re-run E1 as well so the whole set is reported from one consistent run of the current model rather than partly from 23 August.

Then write the §9.5 results into the design document: what each experiment establishes, the numbers, and the scaling statement that `docs/simulation_assumptions.md` requires alongside any annualised figure.

## Notes

Entirely independent of the spatial check work. CPU and SimEvents only, no GPU, no model, no dataset. Start it immediately and let it run in parallel.

Sweep points are short steady-state windows at the full configured arrival rate, scaled to annual figures. The scaling must be stated with every annual number reported.

## Acceptance

- Dated results directories for E1 through E6 from one consistent run
- §9.5 populated with the measured numbers and the scaling statement
- Any annualised figure carries the statement of how it was scaled
