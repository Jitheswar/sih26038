# Decide the spatial check's disposition and record it

Status: resolved
Blocked by: 06, 07

## Problem

The disposition must be settled before the configuration freeze on 8 September, because §10.4 opens the sealed set once and only after the configuration is settled.

## Expected behaviour

Choose between D1 (demote to advisory), D2 (keep, recalibrated), D4 (keep as-is), on the evidence from issues 06 and 07, against the safety veto in ADR 0001.

The decision rules, in order:

1. If the veto rejects a candidate, it is inadmissible. No further argument.
2. Among admissible candidates, argue from several measures moving together: misses, autonomous accuracy, specificity. Never from coverage alone.
3. If issue 07 shows no constant pair discriminates, the gate is retired on evidence and D1 follows, with §8.6's wording as corroboration rather than as the argument.
4. If the gate does discriminate and its catches are not marginal, D2 follows and the recalibrated constants ship.

Record the outcome as an ADR, `docs/adr/0002-*`, and update §11.6 and the README to match. If the disposition changes `config/default.json`, the change and its measured basis are recorded together.

## Notes

Whatever is decided, record the §12 reader study as descoped rather than pending. It has no participant, has not started, and §12.5 already provides for its absence.

## Acceptance

- ADR 0002 written, with the evidence and the rejected alternatives
- `config/default.json` matches the decision
- §11.6, the README status section and `CONTEXT.md` updated
- Full test suite green

## Resolution

Recorded as `docs/adr/0002-keep-the-grad-cam-spatial-gate.md`.

D1 (demote to advisory) is rejected on evidence: A11 and A12 are both inadmissible under the ADR 0001 veto, so decision rule 1 of this ticket applies and no further argument is needed. The clinical judgement the decision was parked on never has to be adjudicated, and `escalateOnExplanationDisagreement` stays `true` because the measurement says so rather than because no reviewer was available.

D5 (constants into configuration) shipped in 0cfaef9, independently of the disposition, as the §13.3 defect repair it always was.

D4 stands. D2 remains open as an optimisation within the pipeline, and its value is now bounded: no setting of the two constants lifts the pipeline past A14 on this split, because a gate can only escalate more. D3 is descoped.

The §12 reader study is recorded as descoped rather than pending, per this ticket's note.

`config/default.json` is unchanged in behaviour and gains the two spatial constants at their historical values. The suite is green at 299 passed.

Not settled by this ADR, and said so in it: whether the gate catches anything the mandatory under-detected check does not. The veto establishes that removing it costs two patients and buys coverage the project cannot bank, which is enough to keep it and not enough to justify it. Issue 04, identifying the patients each configuration sends home, is the evidence that would settle it.
