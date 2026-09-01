# Record the Grad-CAM statistic behind the spatial check, not just its verdict

Status: claimed
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
