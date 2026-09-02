# Name the three finding kinds, and split the disclosure bucket

Status: resolved
Blocked by: none

## Problem

`grade.decisionPolicy` collects findings into two buckets, `codes` and `disclosures`.
`disclosures` currently holds two different concepts:

- **capability gaps**, which are build-level and true of every image (`evidence-capability-gap`, `unknown-neovascularisation-status` when no detector exists), and
- **per-case findings that simply do not force the decision** (`explanation-spatially-inconsistent` when the spatial check is advisory, `candidate-evidence-provisional`).

These are not the same thing. A capability gap discriminates between no cases; an advisory finding is image-dependent and says something about this patient. Merging them means a reader of the output cannot tell "this image's attention was odd" from "this build has no neovascularisation detector".

The documentation compounds it by using a third word: §11.6 and the ablation configs call the demoted spatial state "advisory", while the code calls it a disclosure.

## Expected behaviour

Three named kinds, per `CONTEXT.md`:

- **safety exception**: per-case, forces escalation
- **advisory finding**: per-case, image-dependent, reported, does not force the decision
- **capability gap**: build-level, true of every image, reported, does not force the decision

`result.reasonCodes` keeps its current contents and current order, so nothing downstream changes.
Add `result.findingKinds`, a cell array parallel to `reasonCodes`, naming each entry's kind.
The report and the app read `reasonCodes` as they do today.

`escalateOnCapabilityGap` continues to promote capability gaps to safety exceptions and must not promote advisory findings; those are separately governed by `escalateOnExplanationDisagreement`.

## Notes

Behaviour-preserving refactor plus one new output field. No decision may change.
`TestDecisionPolicy` and `TestRunScreeningCase` pin current behaviour; they must still pass unchanged except for additions covering `findingKinds`.

## Acceptance

- `grade.decisionPolicy` returns `findingKinds` parallel to `reasonCodes`
- Every existing test passes with no expectation edited except to add coverage
- New tests assert an advisory finding and a capability gap are distinguishable in the output, and that `escalateOnCapabilityGap` promotes only the latter

## Resolution

Landed in a19048d. decisionPolicy now collects safety exceptions, capability gaps and advisory findings separately and returns findingKinds parallel to reasonCodes. Reason-code order preserved.
