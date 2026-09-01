# ADR 0001: A configuration is vetoed on referable-sent-home at equal coverage

Date: 2026-09-01

Status: Accepted

## Context

The §11.6 ablation study compares pipeline configurations that decide different fractions of the caseload.
A5 decides 27.5 per cent of cases, A12 decides 66.4 per cent, A1 decides all of them.
Each is scored on how many referable patients it auto-cleared.

Until now those counts were compared directly.
A13 was rejected on 31 August because it "sends 4 referable patients home out of 406 autonomous cases, a per-case miss rate of 0.99 per cent, worse than using the classifier alone", where the classifier alone means A1 at 4 misses out of 550.

That comparison is unmatched.
A13's 4 misses are drawn from the 406 cases it chose to decide; A1's 4 are drawn from all 550, including the hard cases A13 handed away.
A deferral pipeline exists precisely to hand away the cases it is least sure of, so comparing its error rate on a self-selected subset against a classifier's error rate on everything flatters the pipeline by construction.
The size of that flattery is unknown and is not small: a classifier's errors concentrate in its low-confidence tail, which is the part a deferral pipeline sheds first.

The repository already contains the correct comparison and already says to use it.
`eval/metrics/riskCoverage.m` exists, is unit-tested, and its own documentation states: "§11.6 asks for exactly this comparison: A5 against A1 at equal coverage."
The ablation harness prints "Compare A5 with A1 at equal coverage" at the foot of every run.
Neither the A1-A5 table nor the A10-A13 table did so.

## Decision

A configuration is **inadmissible** if it sends more referable patients home than the classifier alone sends home **at the same coverage**.

The equal-coverage baseline is constructed from the classifier's own confidence ranking, using the definitions already established in `eval/fullMetricReport.m`: correctness is agreement with the reference standard on the referable endpoint, and confidence is distance from the frozen threshold, since a case sitting on the threshold is the one to hand to a human.
The baseline is A1 truncated to the candidate configuration's coverage.

Three further points fix how the veto is read.

**It counts what it vetoes.** The risk-coverage curve behind the veto counts referable-sent-home only, not symmetric accuracy. A false positive and a false negative are not the same event here, and the veto's whole subject is the patient who goes home undiagnosed. The symmetric accuracy curve is reported alongside it, off the same ranking, but the veto does not read it.

**It reads the point estimate.** At these magnitudes the Wilson intervals on 1, 2 and 4 misses overlap heavily. A veto stated on intervals would discriminate between nothing and would have failed to reject A13 too. The point estimate is used, and the fact that it cannot discriminate finely is stated wherever the veto is applied rather than hidden by it.

**It is a veto and never a ranking.** Passing does not mean adopting. Above the veto, a configuration is argued for from several independent measures moving in the same direction, never from any single count, and never from coverage. A13 is the configuration that reading the coverage column alone would have selected, and it is the wrong one.

The criterion applies retroactively. The whole A1-A13 table is re-reported with an equal-coverage safety column, because a table whose safety column means one thing for early rows and another for later rows is worse than either convention alone.

## Consequences

A13's rejection is re-derived under this criterion rather than resting on the comparison this ADR supersedes. The conclusion is expected to stand and is not assumed to.

A12's case is re-examined and may not survive. Its argument rests on 2 misses across 365 autonomous cases reading as safer than A1's 4 across 550. Under equal coverage the baseline is A1's best 365 cases by confidence, which will contain fewer than 4 misses and may contain fewer than 2. If the veto rejects A12, the question of whether relaxing the Grad-CAM spatial gate is clinically acceptable never has to be adjudicated, and the §12 dependency dissolves.

A10, already shipped, is unaffected. It sends zero referable patients home, which passes any veto, and it reaches higher coverage than A5 at fewer misses, so its dominance claim needs no equal-coverage correction.

The veto constrains admissibility only. It deliberately says nothing about how much coverage is worth buying, because that question is not answerable from these splits and is not the question the veto exists to settle.
