# Dataset provenance

Recorded on 2026-08-22 from the archives and extracted files present in `data/raw/`.

The actual download time was not recorded, so the date below is the local filesystem creation date of each archive.

Archive file counts exclude directory entries and count only archive members that are files.

Archive size is the exact byte size of the archive, and SHA-256 is computed over the archive itself.

No image pixels were modified before extraction or use.

## APTOS 2019 Blindness Detection

- Source URL: [Kaggle competition data page](https://www.kaggle.com/competitions/aptos2019-blindness-detection/data).
- Download date: 2026-08-22 based on local filesystem metadata; the original download log is unavailable.
- Licence or usage conditions: Kaggle marks the data as subject to the competition rules, and the archive contains no standalone licence file.
- Number of files: 5,593 archive files, comprising 3,662 labelled training images, 1,928 public test images, and three CSV files.
- Archive size: 10,215,289,875 bytes.
- SHA-256: `18036845ab76b68d305d6e2dbbaaaf5cd23926be740e1297a8972ac1c6360976`.
- Labels available: `train.csv` provides image-level severity labels 0 to 4, named No DR, Mild, Moderate, Severe, and Proliferative DR; the public test images are unlabelled.
- Intended project role: Primary training, validation, calibration, and internal test data because it is an Indian dataset and the closest available proxy for the intended deployment setting.
- Patient identifier note: The supplied metadata has only `id_code` and `diagnosis`, with no patient or examination identifier.

The fixed split files therefore use each unique APTOS `id_code` as a conservative `patient_id` surrogate.

This proves separation of all supplied identifiers, but a stronger bilateral-eye patient guarantee would require patient metadata from the dataset provider.

## IDRiD segmentation package

- Source URL: [IDRiD official data page](https://idrid.grand-challenge.org/Data/) and [IEEE DataPort record](https://ieee-dataport.org/open-access/indian-diabetic-retinopathy-image-dataset-idrid).
- Download date: 2026-08-22 based on local filesystem metadata; the original download log is unavailable.
- Licence or usage conditions: Creative Commons Attribution 4.0 International, stated in the included `LICENSE.txt` and `CC-BY-4.0.txt`; retain attribution and the licence notice.
- Number of files: 446 archive files.
- Archive size: 584,315,841 bytes.
- SHA-256: `f9a7fc0f7d228e326ca8ba61cfc99d54de689c52e44f52bde9917c78b07a1eaf`.
- Labels available: 81 original fundus images, pixel masks for microaneurysms, haemorrhages, hard exudates, and soft exudates, plus optic-disc masks.
- Intended project role: Lesion supervision and explanation-quality ground truth, not part of the APTOS development split files.

## IDRiD disease-grading package

- Source URL: [IDRiD official data page](https://idrid.grand-challenge.org/Data/) and [IEEE DataPort record](https://ieee-dataport.org/open-access/indian-diabetic-retinopathy-image-dataset-idrid).
- Download date: 2026-08-22 based on local filesystem metadata; the original download log is unavailable.
- Licence or usage conditions: Creative Commons Attribution 4.0 International, stated in the included `LICENSE.txt` and `CC-BY-4.0.txt`; retain attribution and the licence notice.
- Number of files: 520 archive files.
- Archive size: 212,405,123 bytes.
- SHA-256: `8a9f4752b35d74cc35ff48b21ad44f295a6f800110ec218fc2d1c264803e4d8c`.
- Labels available: 516 image-level ICDR disease grades and diabetic macular oedema risk labels, split by the dataset into 413 training and 103 testing images.
- Intended project role: Secondary grading reference and future lesion or explanation analysis, not part of the APTOS development split files.

## IDRiD localisation package

- Source URL: [IDRiD official data page](https://idrid.grand-challenge.org/Data/) and [IEEE DataPort record](https://ieee-dataport.org/open-access/indian-diabetic-retinopathy-image-dataset-idrid).
- Download date: 2026-08-22 based on local filesystem metadata; the original download log is unavailable.
- Licence or usage conditions: Creative Commons Attribution 4.0 International, stated in the included `LICENSE.txt` and `CC-BY-4.0.txt`; retain attribution and the licence notice.
- Number of files: 522 archive files.
- Archive size: 212,510,246 bytes.
- SHA-256: `b80f37a470848c83e9486797d23e453aa0521ec2376966150aef7730fc673e0d`.
- Labels available: Optic-disc centre and fovea centre coordinate markups for the IDRiD image sets.
- Intended project role: Anatomical localisation supervision and future preprocessing or explanation analysis, not part of the APTOS development split files.

## DRIVE training split

- Source URL: [DRIVE official dataset page](https://drive.grand-challenge.org/DRIVE/).
- Download date: 2026-08-22 based on local filesystem metadata; the original download log is unavailable.
- Licence or usage conditions: The official page describes DRIVE as a research benchmarking resource but does not state an SPDX-style licence, and the archive contains no licence file.
- Number of files: 60 archive files, comprising 20 retinal images and their manual vessel annotations and masks.
- Archive size: 14,772,347 bytes.
- SHA-256: `7101e19598e2b7aacdbd5e6e7575057b9154a4aaec043e0f4e28902bf4e2e209`.
- Labels available: Pixel-level retinal vessel annotations and field-of-view masks; no ICDR grading labels.
- Intended project role: Vessel segmentation training and benchmarking using the dataset's official training split.

## DRIVE test split

- Source URL: [DRIVE official dataset page](https://drive.grand-challenge.org/DRIVE/).
- Download date: 2026-08-22 based on local filesystem metadata; the original download log is unavailable.
- Licence or usage conditions: The official page describes DRIVE as a research benchmarking resource but does not state an SPDX-style licence, and the archive contains no licence file.
- Number of files: 40 archive files, comprising 20 retinal images, masks, and circulated manual vessel annotations.
- Archive size: 14,571,523 bytes.
- SHA-256: `d76c95c98a0353487ffb63b3bb2663c00ed1fde7d8fdfd8c3282c6e310a02731`.
- Labels available: Pixel-level retinal vessel annotations and field-of-view masks; no ICDR grading labels.
- Intended project role: Vessel segmentation benchmarking using DRIVE's official test split, not part of the APTOS development split files.

## MESSIDOR-2 DR Grades metadata

- Source URL: [Google Brain MESSIDOR-2 DR Grades data card](https://www.kaggle.com/datasets/google-brain/messidor2-dr-grades).
- Download date: 2026-08-22 based on local filesystem metadata; the original download log is unavailable.
- Licence or usage conditions: The Kaggle data card lists the grade metadata as CC0 Public Domain and the included README requests citation of Krause et al. (2018).
- Number of files: 2 archive files, `messidor_data.csv` and `messidor_readme.txt`.
- Archive size: 7,531 bytes.
- SHA-256: `84809fc59541313be6cf57ed9209516eaf5a1514949669eed72dc9561917021d`.
- Labels available: Adjudicated five-point ICDR grades, referable DME grades, and gradability flags for the MESSIDOR-2 image identifiers.
- Intended project role: Metadata for the sealed external evaluation only.

This archive contains grade metadata, not the official MESSIDOR-2 image release.

It is excluded from all development split files, and no contents of the grade CSV were read while cataloguing or moving this archive.

### Move under seal, recorded 2026-08-22

This archive and its extracted contents were downloaded to `data/raw/messidor2-dr-grades.zip` and `data/raw/messidor2_grades/` (unsealed), where they had been sitting exposed to the working tree rather than access-controlled as §10.4 requires.

On 2026-08-22 the following were moved, unread, to bring them under the seal:

- `data/raw/messidor2-dr-grades.zip` &rarr; `data/sealed/messidor2-dr-grades.zip`
- `data/raw/messidor2_grades/messidor_data.csv` &rarr; `data/sealed/messidor2_grades/messidor_data.csv`
- `data/raw/messidor2_grades/messidor_readme.txt` &rarr; `data/sealed/messidor2_grades/messidor_readme.txt`

The grade CSV's contents were not read or opened as part of this move, consistent with §10.4: development uses train / validation / calibration only, and the sealed set is opened once, by the named key-holder, after the operating point is frozen and dated.

`data/raw/` no longer contains any Messidor-2 material.

A regression test, `tests/TestSealedDataProtection.m`, asserts this and asserts that the pipeline's existing sealed-path guards (in `app.runScreeningCase`, `explain.gradcam`, `grade.fitTemperature`, and `report.generate`) reject paths under `data/sealed/`.

## APTOS class distribution

The counts below were independently recomputed from `data/raw/aptos2019/train.csv` with MATLAB using the `diagnosis` column.

The exact total is 3,662 labelled training images.

| ICDR level | Label | Count | Exact share | Rounded share |
|---:|---|---:|---:|---:|
| 0 | No DR | 1,805 | 1805 / 3662 = 49.29000546% | 49.29% |
| 1 | Mild | 370 | 370 / 3662 = 10.10376843% | 10.10% |
| 2 | Moderate | 999 | 999 / 3662 = 27.28017477% | 27.28% |
| 3 | Severe | 193 | 193 / 3662 = 5.27034407% | 5.27% |
| 4 | Proliferative DR | 295 | 295 / 3662 = 8.05570726% | 8.06% |
| **Total** |  | **3,662** | **100%** | **100%** |

The five counts sum to 3,662.

## Reproduction commands

```bash
sha256sum data/raw/*.zip
```

The extracted directories are working copies of the archive contents.

No resizing, relabelling, image enhancement, or other preprocessing was applied while creating this provenance record.
