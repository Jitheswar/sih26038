# APTOS split integrity audit

Audit date: 2026-08-22.

The audit checks the fixed CSV files in `data/splits/` against §10.2 of `docs/SIH26038_design.html`.

## Result

The split files pass the implemented integrity checks.

All 3,662 labelled APTOS images appear exactly once across the four files.

No image ID appears in more than one split.

No value in the CSV `patient_id` field appears in more than one split.

Every file has the exact header `image_id,patient_id,grade,relative_path`.

Every grade is an integer from 0 through 4.

The files are reproducible with the project generator and fixed seed 42.

All four split files are tracked by Git.

## Counts and grade distributions

The grade columns were counted directly from the committed CSV files.

| Split | Total | Grade 0 | Grade 1 | Grade 2 | Grade 3 | Grade 4 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| train | 2,564 | 1,264 | 259 | 699 | 135 | 207 |
| validation | 550 | 271 | 56 | 150 | 29 | 44 |
| calibration | 365 | 180 | 37 | 100 | 19 | 29 |
| test | 183 | 90 | 18 | 50 | 10 | 15 |
| **Total** | **3,662** | **1,805** | **370** | **999** | **193** | **295** |

The total distribution matches the APTOS labelled training set recorded in `data/PROVENANCE.md`.

## Reproducibility and Git tracking

Two temporary split directories were generated with `data.createSplits(labelsFile, outputDir, 42)`.

Each generated CSV matched the other generated CSV byte-for-byte.

Each generated CSV also matched the committed CSV byte-for-byte.

The four paths `data/splits/train.csv`, `data/splits/validation.csv`, `data/splits/calibration.csv`, and `data/splits/test.csv` are returned by `git ls-files`.

The split generator uses `rng(42, 'twister')`, stratifies each grade, and sorts each output by `image_id`.

## Important APTOS patient-identifier limitation

APTOS does not provide a separate patient or examination identifier in its supplied training metadata.

The source metadata contains only `id_code` and `diagnosis`.

The split files therefore set `patient_id` equal to `image_id` as a conservative surrogate.

The audit proves that all supplied image IDs, and therefore all surrogate `patient_id` values, are disjoint across splits.

It does not prove true patient-level separation.

The dataset does not provide the independent patient IDs needed to detect whether two different image IDs belong to the same patient, including possible left-eye and right-eye pairs.

Project documentation and results must not claim true patient-level separation for APTOS unless independent patient metadata is obtained.

This limitation means the image-level split integrity result passes, while the stronger §10.2 patient-level guarantee remains unverified for APTOS.

## Test

The checks are implemented in `tests/TestSplitIntegrity.m`.

Run them with:

```text
matlab -batch "results = runtests('tests','IncludeSubfolders',true); assertSuccess(results)"
```
