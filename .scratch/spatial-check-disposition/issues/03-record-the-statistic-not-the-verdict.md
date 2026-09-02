# Record the Grad-CAM statistic behind the spatial check, not just its verdict

Status: resolved
Blocked by: 02

## Problem

`eval/ablationHarness.m` caches `features.spatiallyAgree(index)` as a boolean.
The continuous quantity behind it, the Grad-CAM values at the candidate points, is discarded.

That makes the constants un-sweepable. Answering "can these two constants discriminate at all" currently costs a fresh GPU pass over every image for every candidate pair, when one pass could answer it for all pairs at once.

## Expected behaviour

Cache the vector of normalized Grad-CAM values at the candidate points for each image, for both evidence channels, alongside the existing boolean.

Store enough to reconstruct `mean(values >= cut) >= fraction` for any `(cut, fraction)` offline. The full vector is preferable; if per-image storage is a concern, a fixed quantile grid of the values is acceptable provided the reconstruction error is stated. 550 images times a few hundred candidate points is small.

The boolean stays, computed from the configured constants, so nothing downstream changes.

## Notes

This is what turns issue 07's sweep from a repeated GPU job into an offline computation over one cached pass.

## Acceptance

- Cache carries the per-image candidate-point value vectors for both channels
- The existing boolean is unchanged and still drives decisions
- A test reconstructs the boolean from the cached values for a known case and gets the same answer

## Resolution

Landed in 0cfaef9 and 27130e9. The test is split into `grade.spatialEvidence`, which extracts the normalized Grad-CAM values at the candidate points and is free of the constants, and `grade.spatialVerdict`, which applies them. The harness caches the evidence once per image and takes the verdict per configuration at composition time, so a sweep over (cut, fraction) is an offline computation rather than a Grad-CAM pass per pair. The statistic reaches `per_case.csv`, which is what let issue 06 see that two of the four missed patients sit at exactly 0.0000 rather than near the cut.
