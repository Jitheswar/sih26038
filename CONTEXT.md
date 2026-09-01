# Context

The shared vocabulary of this project.
This file is a glossary and nothing else: no implementation detail, no specifications, no scratch notes.
Where a term has a decision behind it, the decision lives in `docs/adr/`.

## The decision layer

### Screening decision

One of exactly three outcomes the pipeline may produce for a case: **auto-clear**, **refer**, or **escalate**.
Escalate is a first-class output, not a failure: it means the system declines to decide and hands the case to a human.

### Coverage

The fraction of cases the pipeline decides without a human, that is auto-clear plus refer.
Coverage is the number the system exists to move.
It is never the number a configuration is selected on: a configuration can raise coverage by deciding cases it should have handed over.

### Autonomous accuracy

Accuracy measured only over the cases inside coverage.
Accuracy over all cases is not reported, because it credits a deferral pipeline for cases it declined to decide.

### Referable sent home

A patient whose reference grade is referable and whom the pipeline auto-cleared.
This is the harm the system is built to avoid, and it is reported in counts rather than rates, because at these magnitudes a rate implies a precision the interval does not support.

### Safety veto

The rule that a configuration is inadmissible if it sends more referable patients home than the classifier alone does at the same coverage.
A veto, never a ranking: above it, configurations are argued from several measures moving together, never from a single count.
See [ADR 0001](docs/adr/0001-equal-coverage-safety-veto.md).

## Evidence and disagreement

### Evidence channel

A source of lesion findings that the classifier's output is checked against, independent of the classifier.
Two exist: the **classical channel**, a morphological candidate detector that needs no training data, and the **learned channel**, a multi-label segmentation network.

### Trusted head

An output of the learned channel that is permitted to supply ICDR evidence.
A head the network was trained for is not automatically a head its output can be trusted from.
Which heads are trusted, and at what thresholds, is named in configuration, never taken from the checkpoint.

### Agreement check

The comparison between what the classifier concluded and what the evidence channel found.
Its states are named in the design document; three of them force escalation and one does not.

### Safety exception

A finding about **this case** that forces escalation.
A missing input, a case-level unknown, a predicted Level 4, an evidence channel contradicting the classifier.

### Advisory finding

A finding about **this case** that is reported but does not force the decision.
Per-case and image-dependent, like a safety exception; it simply is not treated as disqualifying.
Distinct from a capability gap, which is not about the case at all.

### Capability gap

A field no detector in this build produces, and which is therefore unknown on **every** image.
A capability gap discriminates between no cases, so escalating on one escalates the entire caseload and disables the decision layer rather than guarding it.
It is disclosed in the report and never presented as a per-case unknown.

### Case-level unknown

A field some detector owns but could not determine on **this** image.
Unlike a capability gap this is a fact about the case, so it is a safety exception and escalates.

## Scale and endpoint

### ICDR level

The five-point international severity scale, 0 to 4, that both the classifier and the rule engine report on.

### Referable

ICDR Level 2 or above.
The primary endpoint: it is what the three-way decision acts on, and the only distinction the system takes an action on.

### Endpoint comparison

Comparing the two channels on referable versus not referable, rather than on exact ICDR equality.
Exact equality escalates cases where both channels agree about referral and differ only on severity, and is unreachable above the rule engine's own ceiling.

### Reachable level

The highest ICDR level the rule engine can reach given which evidence fields this build has detectors for.
Below that ceiling the rule engine's "not referable" is silence, not a denial, and cannot be read as contradicting the classifier.

## Data discipline

### Frozen operating point

The threshold, temperature and checkpoint fixed on a recorded date, after which no metric behind them is re-selected.

### Sealed set

The external dataset opened exactly once, after the configuration is settled, under a recorded unseal with a named operator.
It is the only external read this project gets.
