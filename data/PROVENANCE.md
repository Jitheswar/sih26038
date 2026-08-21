# Dataset provenance

Recorded 2026-08-22 from the downloaded archives in `data/raw/`.
The download date is the local filesystem creation date because no downloader log was retained.
File counts exclude directory entries inside ZIP files.
`Archive size` is the exact ZIP byte count; `uncompressed size` is the sum of the member file sizes reported by `unzip -l`.
Hashes are SHA-256 values of the ZIP files themselves.
No image pixels were modified before extraction or use.

## Archives

| Archive | Dataset / role | Source URL | Download date | Licence / terms | Files | Archive size | Uncompressed size | SHA-256 |
|---|---|---|---|---|---:|---:|---:|---|
| `aptos2019-blindness-detection.zip` | APTOS 2019 Blindness Detection; 3,662 labelled training images, 1,928 public test images, and CSV metadata | [Kaggle competition data page](https://www.kaggle.com/competitions/aptos2019-blindness-detection/data) | 2026-08-22 | Kaggle lists the data as **Subject to Competition Rules**; no standalone licence file is present in the archive. Use is limited to the accepted competition terms. | 5,593 | 10,215,289,875 bytes | 10,216,919,325 bytes | `18036845ab76b68d305d6e2dbbaaaf5cd23926be740e1297a8972ac1c6360976` |
| `A. Segmentation.zip` | IDRiD lesion segmentation data, including original images, lesion masks, optic-disc masks, and licence text | [IDRiD official data page](https://idrid.grand-challenge.org/Data/) and [IEEE DataPort record](https://ieee-dataport.org/open-access/indian-diabetic-retinopathy-image-dataset-idrid) | 2026-08-22 | **CC BY 4.0**, stated in the included `LICENSE.txt` and `CC-BY-4.0.txt`; retain attribution and the licence notice. | 446 | 584,315,841 bytes | 584,181,727 bytes | `f9a7fc0f7d228e326ca8ba61cfc99d54de689c52e44f52bde9917c78b07a1eaf` |
| `B. Disease Grading.zip` | IDRiD disease-grading data, including 516 image-level labels and DME risk labels | [IDRiD official data page](https://idrid.grand-challenge.org/Data/) and [IEEE DataPort record](https://ieee-dataport.org/open-access/indian-diabetic-retinopathy-image-dataset-idrid) | 2026-08-22 | **CC BY 4.0**, stated in the included `LICENSE.txt` and `CC-BY-4.0.txt`; retain attribution and the licence notice. | 520 | 212,405,123 bytes | 212,276,527 bytes | `8a9f4752b35d74cc35ff48b21ad44f295a6f800110ec218fc2d1c264803e4d8c` |
| `C. Localization.zip` | IDRiD optic-disc and fovea localisation data, including coordinate markups and licence text | [IDRiD official data page](https://idrid.grand-challenge.org/Data/) and [IEEE DataPort record](https://ieee-dataport.org/open-access/indian-diabetic-retinopathy-image-dataset-idrid) | 2026-08-22 | **CC BY 4.0**, stated in the included `LICENSE.txt` and `CC-BY-4.0.txt`; retain attribution and the licence notice. | 522 | 212,510,246 bytes | 212,383,600 bytes | `b80f37a470848c83e9486797d23e453aa0521ec2376966150aef7730fc673e0d` |
| `training.zip` | DRIVE training split, 20 retinal images and manual vessel annotations | [DRIVE official dataset page](https://drive.grand-challenge.org/DRIVE/) | 2026-08-22 | The official page describes the database as a research benchmarking resource but does not state an SPDX-style licence; the archive contains no licence file. Treat it as research-use data, preserve attribution to Staal et al. (2004), and do not redistribute without confirming the source terms. | 60 | 14,772,347 bytes | 15,094,739 bytes | `7101e19598e2b7aacdbd5e6e7575057b9154a4aaec043e0f4e28902bf4e2e209` |
| `test.zip` | DRIVE test split, 20 retinal images, masks, and circulated manual vessel annotations | [DRIVE official dataset page](https://drive.grand-challenge.org/DRIVE/) | 2026-08-22 | The official page describes the database as a research benchmarking resource but does not state an SPDX-style licence; the archive contains no licence file. Treat it as research-use data, preserve attribution to Staal et al. (2004), and do not redistribute without confirming the source terms. | 40 | 14,571,523 bytes | 14,883,946 bytes | `d76c95c98a0353487ffb63b3bb2663c00ed1fde7d8fdfd8c3282c6e310a02731` |
| `messidor2-dr-grades.zip` | MESSIDOR-2 DR Grades; adjudicated ICDR grades, DME grades, and gradability for the 1,748-image MESSIDOR-2 image set | [Kaggle data card](https://www.kaggle.com/datasets/google-brain/messidor2-dr-grades) | 2026-08-22 | Kaggle lists this grade-set data card as **CC0: Public Domain**. The archive also includes the required Krause et al. citation and documents that ungradable images have no DR/DME grade. This is a grade set, not the official MESSIDOR-2 image release. | 2 | 7,531 bytes | 49,964 bytes | `84809fc59541313be6cf57ed9209516eaf5a1514949669eed72dc9561917021d` |

## APTOS class distribution

The counts below were recomputed from `data/raw/aptos2019/train.csv` with the `diagnosis` column, not copied from a web summary.
The exact total is 3,662 rows.

| ICDR level | Label | Count | Exact share | Rounded share |
|---:|---|---:|---:|---:|
| 0 | No DR | 1,805 | 1805 / 3662 = 49.29000546% | 49.29% |
| 1 | Mild | 370 | 370 / 3662 = 10.10376843% | 10.10% |
| 2 | Moderate | 999 | 999 / 3662 = 27.28017477% | 27.28% |
| 3 | Severe | 193 | 193 / 3662 = 5.27034407% | 5.27% |
| 4 | Proliferative DR | 295 | 295 / 3662 = 8.05570726% | 8.06% |
| **Total** |  | **3,662** | **100%** | **100%** |

The five counts sum to 3,662 and are the values recorded in §7.4 of `docs/SIH26038_design.html`.

## Reproduction commands

```bash
awk -F, 'NR>1 {count[$2]++} END {for (i=0;i<=4;i++) print i, count[i]+0; print "total", NR-1}' data/raw/aptos2019/train.csv
sha256sum data/raw/*.zip
```

The extracted directories are working copies of the archive contents.
No resizing, relabelling, image enhancement, or other preprocessing was applied while creating this provenance record.
