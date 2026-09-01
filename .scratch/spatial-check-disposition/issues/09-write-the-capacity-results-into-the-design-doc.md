# Write the capacity experiment results into the design document

Status: ready-for-agent
Blocked by: none

## Problem

§9.5 specifies six capacity experiments for R5.2. `simulink/sweep_experiments.m` implements all six and all six have been run, on 22 and 23 August.

**Correction, 2 September 2026.** This ticket was originally written on the premise that only E1 had ever been run and that five sixths of R5.2 was outstanding. That was wrong: the search that produced it matched the literal string `E1` and so missed `E2_sensitivity_versus_workload` and its four siblings, which have existed since 22 August. The premise is withdrawn.

What was actually outstanding is narrower and still worth doing. The experiments had been run but §9.5 of the design document carried no measured numbers from them, so the results existed only as CSVs in `results/` and nothing had been read off them or written down.

## Expected behaviour

Run E2 to E6 via `sweep_experiments`, each to its own dated results directory with its configuration alongside.

Re-run E1 as well so the whole set is reported from one consistent run of the current model rather than partly from 23 August.

Then write the §9.5 results into the design document: what each experiment establishes, the numbers, and the scaling statement that `docs/simulation_assumptions.md` requires alongside any annualised figure.

## Notes

Entirely independent of the spatial check work. CPU and SimEvents only, no GPU, no model, no dataset. Start it immediately and let it run in parallel.

Sweep points are short steady-state windows at the full configured arrival rate, scaled to annual figures. The scaling must be stated with every annual number reported.

## Acceptance

- Dated results directories for E1 through E6 from one consistent run, with the reproduction against the August runs stated
- §9.5 populated with the measured numbers and the scaling statement
- Any annualised figure carries the statement of how it was scaled
