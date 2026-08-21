# Verification of Unverified Claims - SIH26038 Design Document

Verification of the claims registered in section 18.2 and Appendix A of `docs/SIH26038_design.html`, checked against primary sources.

**Date of verification:** 21 August 2026
**Scope:** U1, U2, U3, U4, U6, U7, U8, U9, U10, U12.
U5 (deletion/insertion AUC, Petsiuk et al.) and U11 (colour normalisation attribution) were not in scope for this pass and remain unverified.

**Standard applied.**
A primary source means the dataset's own paper or official distribution page, the official challenge documentation, the journal article itself, or the regulatory filing.
Secondary write-ups were not accepted as verification.
Every figure below was read from a source actually retrieved during verification, and the retrieval URL is given.
Where a source could not be reached, that is stated rather than papered over with a secondary source.

---

## Summary

| Ref | Claim | Verdict |
|---|---|---|
| U1 | IDx-DR 87.2% / 90.7% | **Correct** |
| U2 | EyeArt ~96% / ~88% | **Correct** |
| U3 | India ~101M adults with diabetes | **Partially correct** - figure correct, IDF rider unverifiable |
| U4 | Saliency sanity-check failures | **Correct in substance**, needs specifics and a version caveat |
| U6 | BagNet architecture reference | **Correct** - but do not conflate with sparse BagNet |
| U7 | Thailand deployment rejection rate | **Correct** - exact figure 21% |
| U8.1 | APTOS 3,662 train | **Correct** |
| U8.2 | IDRiD 516 graded, mask subset | **Partially correct** - "few dozen" MA masks understates |
| U8.3 | DRIVE 40, 20/20 split | **Correct** |
| U8.4 | Messidor-2 ~1,748 images with DR grades | **Partially correct** - official release ships no DR ground truth |
| U8.5 | IDRiD image 4288x2848 | **Correct** |
| U8.6 | APTOS roughly half Level 0 | **Correct** - exact distribution recovered |
| U8.7 | APTOS single-grader, no adjudication | **Partially correct** - adjudication never addressed by organisers |
| U9 | QWK is the APTOS metric | **Correct** |
| U10 | AUPR is the IDRiD lesion segmentation metric | **Correct** - sub-challenge 1 only |
| U12 | Non-pathological attribute prediction | **Correct** |

**Nothing on this list was found to be outright false.**
Three claims need rewording before they are safe to put in front of judges: the IDF rider on U3, the Messidor-2 grading claim in U8.4, and the adjudication half of U8.7.

---

## U8 - Dataset sizes and splits

### U8.1 APTOS 2019

**Claim:** "APTOS 2019 ~3,662 train", ICDR 0-4 image-level labels, Aravind Eye Hospital, India.

**Verdict:** Correct.

**Exact figures.**
Training set 3,662 images and 3,662 rows in `train.csv`.
Public test set 1,928 images.
Private test set approximately 13,000 images / 20 GB.

**Evidence.**
Kaggle's server-rendered metadata gives `train.zip` `totalFiles: 3662` and `train.csv` `rowCount: 3662`; `test.zip` `totalFiles: 1928`.
This cross-checks against the figure the live page still reports publicly, "5593 files": 3,662 + 1,928 + three CSVs = 5,593 exactly.
On the private set the live Data page states verbatim: "You can plan on the private test set consisting of 20GB of data across 13,000 images (approximately)."
Label scheme verbatim: "A clinician has rated each image for the severity of diabetic retinopathy on a scale of 0 to 4: 0 - No DR / 1 - Mild / 2 - Moderate / 3 - Severe / 4 - Proliferative DR."
This is the ICDR scale in substance, but Kaggle never names "ICDR"; it gives only the five level names.
Provenance verbatim from the Overview page: "Aravind Eye Hospital in India hopes to detect and prevent this disease among people living in rural areas where medical screening is difficult to conduct."

**Citation.**
Asia Pacific Tele-Ophthalmology Society, "APTOS 2019 Blindness Detection", Kaggle Featured Code Competition, 2019.
Overview: https://www.kaggle.com/competitions/aptos2019-blindness-detection/overview
Data: https://www.kaggle.com/competitions/aptos2019-blindness-detection/data
Kaggle's embedded file metadata, via Internet Archive capture 2019-07-17: https://web.archive.org/web/20190717130619id_/https://www.kaggle.com/c/aptos2019-blindness-detection/data

**Access note.**
Kaggle's per-folder file counts and CSV column statistics are gated behind competition-rules acceptance, and no Kaggle credentials were available.
The counts above come from an Internet Archive capture of the same Kaggle page whose HTML embeds Kaggle's own server-rendered JSON.
That is Kaggle's own data about its own files rather than a third-party restatement, and it arithmetically cross-checks against the figure that is still public today.

### U8.2 IDRiD

**Claim:** "IDRiD ~516 graded; smaller subset with masks", pixel masks for MA, HE, EX, SE, optic disc masks, fovea coordinates, Nanded, India.
Also: "IDRiD's segmentation subset provides on the order of a few dozen images with MA masks."

**Verdict:** Partially correct.
The 516 figure, the mask types, the optic disc masks, the fovea coordinates and the Nanded provenance are all correct.
The phrase "a few dozen images with MA masks" understates the data and should be replaced with exact numbers.

**Exact figures.**
Disease Grading (sub-challenge 2): **516 images, split 413 train / 103 test.**
Lesion Segmentation (sub-challenge 1): **81 images, split 54 train (Set-A) / 27 test (Set-B).**
Localisation (sub-challenge 3): all 516 images, also 413 / 103.

| Lesion | Images with masks | Set-A (train) | Set-B (test) |
|---|---|---|---|
| MA (microaneurysms) | 81 | 54 | 27 |
| EX (hard exudates) | 81 | 54 | 27 |
| HE (haemorrhages) | 80 | 53 | 27 |
| SE (soft exudates) | 40 | 26 | 14 |
| Optic disc | 81 | 54 | 27 |

**Evidence.**
Official IDRiD Data page verbatim: "From the thousands of examinations available, we have extracted 516 images to form our dataset."
And: "This dataset consists of 81 color fundus images with signs of DR... Number of images (some images contain multiple lesions) with binary masks available for particular lesion is given as follows: MA - 81 / EX - 81 / HE - 80 / SE - 40."
And: "In addition to all the abnormalities, binary masks for the optic disc region are provided for all 81 images."
And: "The fundus images in IDRiD were captured by a retinal specialist at an Eye Clinic located in Nanded, Maharashtra, India."
The MDPI *Data* descriptor states the grading split verbatim: "The dataset is divided into training and testing set comprising of 413 (80%) and 103 (20%) images respectively by maintaining appropriate mixture of disease stratification."
The MDPI descriptor does not state the segmentation split.
The *Medical Image Analysis* 2020 challenge paper does, verbatim: "the data was separated as 2/3 for training (Set-A) and 1/3 for testing (Set-B) (See Table 3)", with Table 3 giving MA 54/27, HE 53/27, SE 26/14, EX 54/27.
IEEE DataPort independently confirms the grading split: "Original color fundus images (516 images divided into train set (413 images) and test set (103 images) - JPG Files)".

On the doc's phrasing: 81 images carry MA masks in total, 54 of them in the training split.
81 is closer to seven dozen than "a few dozen".

**Citation.**
Porwal P, Pachade S, Kamble R, Kokare M, Deshmukh G, Sahasrabuddhe V, Meriaudeau F.
"Indian Diabetic Retinopathy Image Dataset (IDRiD): A Database for Diabetic Retinopathy Screening Research."
*Data* 2018, 3(3), 25. DOI 10.3390/data3030025. https://www.mdpi.com/2306-5729/3/3/25

Porwal P, Pachade S, Kokare M, Deshmukh G, Son J, Bae W, Liu L, Wang J, Liu X, Gao L, et al.
"IDRiD: Diabetic Retinopathy - Segmentation and Grading Challenge."
*Medical Image Analysis* 2020, 59, 101561. DOI 10.1016/j.media.2019.101561.

Official Data page: https://idrid.grand-challenge.org/Data/
IEEE DataPort: https://ieee-dataport.org/open-access/indian-diabetic-retinopathy-image-dataset-idrid (DOI 10.21227/H25W98)

**Access note.**
The *Medical Image Analysis* version of record is paywalled on ScienceDirect (HTTP 403) and the OpenReview mirror is behind a bot check.
Table 3 was read from the author accepted manuscript deposited in the University of Debrecen institutional repository, identified as the open-access copy of the DOI via OpenAlex and Semantic Scholar: https://dea.lib.unideb.hu/dea/bitstream/2437/274207/1/FILE_UP_1_MEDIA-D-19-00049R1_rev1.pdf
The IDRiD grand-challenge sub-pages `/Segmentation/`, `/Grading/` and `/Localisation/` now return HTTP 403 to anonymous users; the `/Data/` page is public.

### U8.3 DRIVE

**Claim:** "DRIVE, 40 images with expert vessel annotations, conventionally split 20 train / 20 test", Netherlands.

**Verdict:** Correct.

**Evidence.**
Official DRIVE site verbatim: "The photographs for the DRIVE database were obtained from a diabetic retinopathy screening program in The Netherlands. The screening population consisted of 400 diabetic subjects between 25-90 years of age. Forty photographs have been randomly selected, 33 do not show any sign of diabetic retinopathy and 7 show signs of mild early diabetic retinopathy."
And: "The set of 40 images has been divided into a training and a test set, both containing 20 images."
And: "All human observers that manually segmented the vasculature were instructed and trained by an experienced ophthalmologist. They were asked to mark all pixels for which they were for at least 70% certain that they were vessel."

**One caveat for the design.**
The 20/20 split is the dataset's own defined split, not merely a convention, so the doc's wording is if anything too weak.
But the official challenge site withholds test-set annotations and expects online submission, whereas the commonly circulated DRIVE archive ships first- and second-observer manual segmentations for the test images.
If the project scores test annotations locally, that provenance should be stated explicitly rather than implied by the challenge page.

**Citation.**
Staal J, Abramoff MD, Niemeijer M, Viergever MA, van Ginneken B.
"Ridge-based vessel segmentation in color images of the retina."
*IEEE Transactions on Medical Imaging* 2004, 23(4), 501-509. DOI 10.1109/TMI.2004.825627. PMID 15084075.
Official site: https://drive.grand-challenge.org/

### U8.4 Messidor-2

**Claim:** "Messidor-2 ~1,748 images", DR grades, France.

**Verdict:** Partially correct.
The image count and the French provenance are correct.
**The implication that Messidor-2 ships DR grades is incorrect for the official release.**

**Exact figures.**
1,748 images, corresponding to 874 examinations (two images per examination, one per eye).
Composition: Messidor-Original contributes 529 examinations (1,058 images, PNG); Messidor-Extension contributes 345 examinations (690 images, JPG).

**Evidence.**
ADCIS Messidor-2 page verbatim: "Overall, Messidor-2 contains 874 examinations (1748 images)."
On grading, the same page states explicitly: "It does not contain annotations such as a diabetic retinopathy 'ground truth'. However, some third-parties proposed such annotations, but these are independent from the official Messidor-2 database, and therefore not handled by our services."
The Messidor-Extension images were "collected from Brest University Hospital between October 2009 and September 2010 using a Topcon TRC NW6 non-mydriatic fundus camera with 45-degree field of view."

The DR grades practitioners actually use with Messidor-2 are a third-party artefact.
The most widely used set is Google Brain's "MESSIDOR-2 DR Grades", whose data card states: "The grades were adjudicated by a panel of three Retina Specialists", citing Krause et al., *Ophthalmology* 2018.

**This matters for the project.**
Section 10.4 seals Messidor-2 as the external test set and section 11.4 reports referable-DR metrics against it.
Both depend on grades that are not part of the official distribution.
**The team must obtain the third-party grade set separately, and must say in the submission which grade set was used.**
This is a second access dependency on top of the ADCIS licence, and it is not currently tracked in the risk register (R03 covers only the ADCIS licence).

**Citation.**
ADCIS, "Messidor-2" official distribution page: https://www.adcis.net/en/third-party/messidor2/
Google Brain, "MESSIDOR-2 DR Grades": https://www.kaggle.com/datasets/google-brain/messidor2-dr-grades
Krause J, et al. "Grader variability and the importance of reference standards for evaluating machine learning models for diabetic retinopathy." *Ophthalmology* 2018. DOI 10.1016/j.ophtha.2018.01.034
Decenciere E, et al. "Feedback on a publicly distributed image database: the Messidor database." *Image Analysis & Stereology* 2014, 33(3), 231-234. DOI 10.5566/ias.1155

### U8.5 IDRiD native resolution

**Claim:** "An IDRiD image is 4288x2848."

**Verdict:** Correct.

**Evidence.**
Official IDRiD Data page verbatim: "Images were acquired using a Kowa VX-10 alpha digital fundus camera with 50-degree field of view (FOV), and all are centered near to the macula. The images have a resolution of 4288x2848 pixels and are stored in jpg file format. The size of each image is about 800 KB."
The MDPI *Data* descriptor states the same in its "Fundus Camera Specifications" section.

**Citation.**
https://idrid.grand-challenge.org/Data/ and Porwal et al., *Data* 2018, 3(3), 25.

### U8.6 APTOS class distribution

**Claim:** "In APTOS, roughly half the images are Level 0" and "APTOS is markedly imbalanced, with Level 0 the dominant class and Levels 3 and 4 sparse."

**Verdict:** Correct, and the exact distribution is now available.

**Exact figures.** APTOS 2019 training set, `train.csv`, n = 3,662:

| Grade | Name | Count | Share |
|---|---|---|---|
| 0 | No DR | 1,805 | 49.29% |
| 1 | Mild | 370 | 10.10% |
| 2 | Moderate | 999 | 27.28% |
| 3 | Severe | 193 | 5.27% |
| 4 | Proliferative DR | 295 | 8.06% |
| | **Total** | **3,662** | 100% |

**Evidence.**
These are Kaggle's own column statistics for the `diagnosis` column, embedded in the server-rendered page HTML.
Kaggle reports the column as integer-valued on 0..4 with `finiteCount: 3662` and `mean: 1.1269797924631348`, plus a 10-bucket histogram.
Because the column is integer-valued on 0..4, each non-empty bucket maps to exactly one grade.
Two independent arithmetic checks confirm the mapping.
The counts sum to 3,662, matching Kaggle's stated `rowCount` exactly.
And the implied mean, (0x1805 + 1x370 + 2x999 + 3x193 + 4x295) / 3662 = 4127 / 3662 = 1.12697979..., reproduces Kaggle's reported mean to every published digit.

**One nuance the doc misses.**
Grade 4 (295) is only slightly smaller than grade 1 (370).
Grade 1 is therefore nearly as sparse as the grades the doc calls sparse, and it sits directly on the referral threshold discussed in section 11.6.

**Citation.**
https://web.archive.org/web/20190717130619id_/https://www.kaggle.com/c/aptos2019-blindness-detection/data
No peer-reviewed dataset paper for APTOS 2019 states the distribution; there does not appear to be one.

### U8.7 APTOS single-grader

**Claim:** "APTOS grades are single-grader" without adjudication.

**Verdict:** Partially correct.
The single-grader half is directly supported.
The "without adjudication" half is an inference, because the organisers never address adjudication either way.

**Evidence.**
Kaggle's Data page says verbatim: "A clinician has rated each image for the severity of diabetic retinopathy on a scale of 0 to 4."
The singular "A clinician" is the only statement Kaggle makes about the grading process.
Kaggle nowhere describes a second reader, a consensus step or an adjudication panel, and nowhere states that none occurred.
Kaggle does independently warn about label quality, verbatim: "Like any real-world data set, you will encounter noise in both the images and labels."

The doc is on solid ground saying the labels are single-clinician and noisy.
It over-claims if it asserts as fact that no adjudication took place.
**Safe framing:** "the organisers describe a single clinician rating per image, document no adjudication process, and explicitly warn of label noise."

**Citation.**
https://www.kaggle.com/competitions/aptos2019-blindness-detection/data

---

## U9 - Quadratic weighted kappa as the APTOS 2019 metric

**Claim:** "Quadratic weighted kappa ... the APTOS competition metric."

**Verdict:** Correct.
Kaggle names the metric exactly "quadratic weighted kappa".

**Evidence.**
The Evaluation section states verbatim: "Submissions are scored based on the quadratic weighted kappa, which measures the agreement between two ratings. This metric typically varies from 0 (random agreement between raters) to 1 (complete agreement between raters). In the event that there is less agreement between the raters than expected by chance, this metric may go below 0. The quadratic weighted kappa is calculated between the scores assigned by the human rater and the predicted scores."
It then specifies the construction: an N x N observed histogram matrix O, a quadratic weight matrix w based on the difference between raters' scores, and an expected matrix E formed as the outer product of the two raters' histogram vectors, normalised so E and O have the same sum.

**Implication worth carrying into section 11.3.**
The metric measures agreement against a single human rater's grade, so the achievable ceiling is bounded by that rater's own reliability.
This connects directly to the label-noise limitation the doc already acknowledges.

**Citation.**
https://www.kaggle.com/competitions/aptos2019-blindness-detection/overview/evaluation

---

## U10 - AUPR as the IDRiD lesion segmentation metric

**Claim:** "AUPR is the metric used for the IDRiD lesion segmentation benchmark."

**Verdict:** Correct, with an important scope limit.

**Exact.**
Area under the precision-recall curve, computed **per lesion type** (separate MA, HE, SE and EX scores), over the 27-image Set-B, from grayscale probability maps thresholded at 33 equally spaced levels.
**AUPR applies to sub-challenge 1 only.**
The other sub-challenges use different metrics, so the doc must not generalise AUPR to "the IDRiD benchmark" as a whole.

**Evidence.**
The challenge paper's Section 6 states verbatim: "As in the lesion segmentation task(s) background overwhelms foreground, a highly imbalanced scenario, the performance of this task was measured using area under precision (a.k.a. Positive Predictive Value (PPV)) recall (a.k.a. Sensitivity (SN)) curve (AUPR) (Saito and Rehmsmeier, 2015)."
And: "The curve was obtained by thresholding the results at 33 equally spaced instances i.e. [0, 8, 16, ..., 256] in gray levels or [0, 0.03125, 0.0625 ... , 1] in probabilities. The AUPR provides a single-figure measure (a.k.a. mean average precision (mAP)), computed over the Set-B, was used to rank the participating methods."
And on the rationale: "The AUPR measure is more realistic (Boyd et al., 2013; Saito and Rehmsmeier, 2015) for the lesion segmentation performance over the Area under Receiver Operating Characteristics (ROC)."
This directly supports the doc's own justification for preferring AUPR under class imbalance.

Independently confirmed by the official challenge leaderboard, which carries separate "MA Score", "HE Score", "SE Score" and "EX Score" columns with the footnote: "Ranking of the teams for Subchallenge-1 is done based on the single score computed by finding the area under the Positive Predictive Value (Precision) and Sensitivity (Recall) curve using the test data of apparent retinopathy."

**The other sub-challenges, so the claim is not over-extended.**
Sub-challenge 2 (DR and DME grading) is scored by accuracy over the 103 test images, specifically a joint accuracy requiring both the DR grade and the DME grade to match.
Sub-challenge 3 uses Euclidean distance for optic disc and fovea centre localisation, and the Jaccard index for optic disc segmentation.

**Citation.**
Porwal P, et al. "IDRiD: Diabetic Retinopathy - Segmentation and Grading Challenge." *Medical Image Analysis* 2020, 59, 101561. DOI 10.1016/j.media.2019.101561.
Section 6A, author accepted manuscript: https://dea.lib.unideb.hu/dea/bitstream/2437/274207/1/FILE_UP_1_MEDIA-D-19-00049R1_rev1.pdf
Official leaderboard, Internet Archive capture 2019-07-16: https://web.archive.org/web/20190716212450/https://idrid.grand-challenge.org/leaderboard/

---

## U1 - IDx-DR pivotal trial

**Claim:** "IDx-DR (pivotal trial) 87.2% sensitivity / 90.7% specificity. First FDA De Novo authorised autonomous DR system (2018)."

**Verdict:** Correct.

**Exact figures.**
Sensitivity 87.2% (95% CI 81.8-91.2), specificity 90.7% (95% CI 88.3-92.7), imageability 96.1%, n = 819 analysable participants.
Endpoint is more-than-mild DR (mtmDR), defined as ETDRS level 35 or higher and/or diabetic macular oedema, in at least one eye.

**One qualification worth carrying.**
87.2% / 90.7% are the **enrichment-corrected** values against the fundus-photography mtmDR reference standard.
The **observed** (uncorrected) values in the same trial were sensitivity 87.4% and specificity 89.5%, and those are the numbers the FDA quoted in its Decision Summary.
The FDA's headline block reads: "Sensitivity - 87% / Specificity - 90% / Imageability - 96% / PPV - 73% / NPV - 96%".

**De Novo authorisation confirmed.**
FDA De Novo database record DEN180001, device name IDx-DR, requester IDx LLC, date received 12 January 2018, **decision date 11 April 2018**, decision "granted (DENG)", regulation 21 CFR 886.1100, product code PIB, Class II, "Retinal diagnostic software device".
The doc's year of 2018 is correct.

The paper's own claim of primacy, verbatim: "FDA authorized the system for use by health care providers to detect more than mild DR and diabetic macular edema, making it, the first FDA authorized autonomous AI diagnostic system in any field of medicine".

**Citation.**
Abramoff MD, Lavin PT, Birch M, Shah N, Folk JC.
"Pivotal trial of an autonomous AI-based diagnostic system for detection of diabetic retinopathy in primary care offices."
*npj Digital Medicine* 1:39 (2018). DOI 10.1038/s41746-018-0040-6.
Full text: https://pmc.ncbi.nlm.nih.gov/articles/PMC6550188/
US FDA, De Novo Decision Summary DEN180001: https://www.accessdata.fda.gov/cdrh_docs/reviews/DEN180001.pdf
US FDA, De Novo database record: https://www.accessdata.fda.gov/scripts/cdrh/cfdocs/cfPMN/denovo.cfm?ID=DEN180001

---

## U2 - EyeArt pivotal trial

**Claim:** "EyeArt (pivotal) ~96% sensitivity / ~88% specificity. FDA 510(k), 2020."

**Verdict:** Correct.

**Exact figures.**
The doc's "~96% / ~88%" matches the published paper's own rounded headline exactly.
Unrounded: sensitivity 95.5% (95% CI 92.9-97.7) and specificity 87.8% (95% CI 86.3-89.5), for mtmDR, enrichment-corrected, under the dilate-if-needed protocol.
For vision-threatening DR: sensitivity 97.0% (91.2-100), specificity 90.1% (89.4-91.5).
Imageability 87.4% undilated, rising to 97.4% under dilate-if-needed.
Analysis population 893 participants (1,786 eyes) of 942 enrolled.

**Two things the doc should absorb.**
First, **the endpoint is per eye**, not per participant.
The IDx-DR trial reported per participant.
The section 3.5 table places the two side by side without noting this.

Second, **the 510(k) Summary itself contains no pooled 96% / 88% figure.**
It reports per-cohort, per-eye numbers instead: sequentially enrolled cohort mtmDR sensitivity 100.0% (11/11) at primary care and 94.9% (37/39) at ophthalmology sites; enrichment-permitted cohort 92.9% (92/99) and 96.6% (28/29).
**Cite the JAMA Network Open paper for those two values, not the clearance document.**

**Clearance confirmed.**
FDA clearance letter K200667 dated **3 August 2020**, Eyenuk Inc., regulation 21 CFR 886.1100, Class II, product code PIB.
openFDA record: decision_date 2020-08-03, decision_description "Substantially Equivalent", clearance_type "Traditional", date_received 2020-03-13.
Both the route and the year in the doc are correct.

**A detail worth using.**
The predicate device named in the 510(k) Summary is **IDx-DR, De Novo DEN180001**.
EyeArt was cleared as substantially equivalent to IDx-DR, which is why the De Novo came first and the 510(k) second.
EyeArt's cleared indication is also broader: it covers both mtmDR and vision-threatening DR.

**The paper draws the doc's own comparison.**
Verbatim: "The mtmDR findings reported on the IDx-DR system were 87.2% for sensitivity, 90.7% for specificity, and 96.1% for imageability rate after enrichment correction in a cohort of 819 participants. Using the EyeArt system, we found sensitivity of 95.5%, specificity of 87.8%, and imageability rate of 97.7% for mtmDR after enrichment correction in a cohort of 893 patients."
The section 3.5 table is therefore exactly the comparison the EyeArt authors themselves drew, which is a defensible position to hold in front of judges.

**Citation.**
Ipp E, Liljenquist D, Bode B, Shah VN, Silverstein S, Regillo CD, Lim JI, Sadda S, Domalpally A, Gray G, Reddy S, Rees E, Aramanti T, Solanki K, et al. (Eyenuk EyeArt Study Group).
"Pivotal Evaluation of an Artificial Intelligence System for Autonomous Detection of Referrable and Vision-Threatening Diabetic Retinopathy."
*JAMA Network Open* 4(11):e2134254 (2021). DOI 10.1001/jamanetworkopen.2021.34254.
Full text: https://pmc.ncbi.nlm.nih.gov/articles/PMC8593763/
US FDA, 510(k) Summary K200667: https://www.accessdata.fda.gov/cdrh_docs/pdf20/K200667.pdf
openFDA: https://api.fda.gov/device/510k.json?search=k_number:%22K200667%22

**Note.** The full author string was not fully enumerated from the extracted text; confirm it from the DOI landing page before formal citation.

---

## U3 - India diabetes prevalence (ICMR-INDIAB)

**Claim:** "~101 million adults with diabetes in India (ICMR-INDIAB), *Lancet Diabetes Endocrinol*, 2023. Shows the PS's 77M figure is the older IDF estimate and the burden is larger still."

**Verdict:** Partially correct.
The 101 million figure is correct and verified.
**The attached assertion that "the PS's 77M figure is the older IDF estimate" is unverifiable from a primary source as written, and should be deleted or reworded.**

**Exact figures.**
101 million people with diabetes, as a **2021 national projection** derived from the survey.
Weighted prevalence 11.4% (95% CI 10.2-12.5) in adults aged 20 years and older.
Prediabetes 136 million, prevalence 15.3% (13.9-16.6).

**Evidence.**
Results verbatim: "Figure 4 presents the 2021 projections for cardiometabolic risk factors for the entire country. We estimated that in 2021, 101 million people had diabetes, and the number with prediabetes was 136 million."
Discussion verbatim: "Our estimates of the prevalence of diabetes and prediabetes in India (101 million and 136 million, respectively) are much higher than earlier reported figures,[32]"
Abstract Findings verbatim: "A total of 113 043 individuals (79 506 from rural areas and 33 537 from urban areas) participated in the ICMR-INDIAB study between Oct 18, 2008 and Dec 17, 2020. The overall weighted prevalence of diabetes was 11.4% (95% CI 10.2-12.5; 10 151 of 107 119 individuals)..."

**Two precision points the doc must absorb.**
First, 101 million is a **2021 projection**, not a directly measured 2023 count, and it does not appear in the abstract at all.
It is in the Results and Discussion.
Phrase it as "an estimated 101 million in 2021".
Second, the survey fieldwork ran from October 2008 to December 2020, a twelve-year window.
A judge who reads the paper could reasonably ask about that, so do not present the figure as a snapshot.

**On the "77M is the older IDF estimate" rider.**
Reference 32, the source the paper contrasts itself against, is the **IDF Diabetes Atlas 10th edition (2021)**, not the edition normally cited for a 77 million India figure.
Retrieval of the IDF Diabetes Atlas 9th edition (2019) was attempted from diabetesatlas.org and idf.org; every candidate PDF URL returned HTTP 404 and no IDF primary document could be obtained.
**Do not assert in the submission that the PS's 77M comes from IDF unless someone retrieves the IDF Atlas and confirms it.**
The fully sourced framing is: "ICMR-INDIAB (*Lancet Diabetes Endocrinol*, 2023) estimates 101 million people with diabetes in India in 2021, higher than the IDF Diabetes Atlas estimates the paper contrasts itself against."

**Citation.**
Anjana RM, Unnikrishnan R, Deepa M, Pradeepa R, Tandon N, Das AK, Joshi S, Bajaj S, Jabbar PK, Das HK, Kumar A, Dhandhania VK, Bhansali A, Rao PV, Desai A, Kalra S, Gupta A, Lakshmy R, Madhu SV, Elangovan N, Chowdhury S, Venkatesan U, Subashini R, Kaur T, Dhaliwal RS, Mohan V; ICMR-INDIAB Collaborative Study Group.
"Metabolic non-communicable disease health report of India: the ICMR-INDIAB national cross-sectional study (ICMR-INDIAB-17)."
*The Lancet Diabetes & Endocrinology* 11(7):474-489 (2023). DOI 10.1016/S2213-8587(23)00119-5.
Full text: https://www.thelancet.com/journals/landia/article/PIIS2213-8587(23)00119-5/fulltext

---

## U4 - Sanity Checks for Saliency Maps

**Claim:** section 11.7, "A number of widely used saliency methods fail this test in the published literature", citing Adebayo et al., NeurIPS 2018.

**Verdict:** Correct in substance, but the doc must be specific, and there is a version trap to avoid.

**Exact result of the model parameter randomization test.**

| Method | Result |
|---|---|
| Gradients (plain input gradient) | **Pass** |
| GradCAM | **Pass** |
| Guided BackProp | **Fail** - invariant to higher-layer parameters |
| Guided GradCAM | **Fail** - invariant to higher-layer parameters |
| Gradient-input | Middle case - see below |
| Integrated Gradients | Middle case - see below |

**Evidence.**
Contributions list item 3 verbatim: "Of the methods tested, Gradients & GradCAM pass the sanity checks, while Guided BackProp & Guided GradCAM are invariant to higher layer parameters; hence, fail."
Cascading randomization verbatim: "We find that the gradient map is, indeed, sensitive to model parameter randomization. Similarly, GradCAM is sensitive to model weights if the randomization is downstream of the last convolutional layer. However, Guided Backprop (along with Guided GradCAM) is invariant to higher layer weights."

**The middle case, which is the most useful part for section 11.7.**
Verbatim: "On visual inspection, we find that gradient input and integrated gradients show visual similarity to the original mask... However, re-initialization disrupts the sign of the map, so that the spearman rank correlation without absolute values goes to zero... almost as soon as the top layers are randomized. The observed visual perception versus ranking dichotomy indicates that naive visual inspection of the masks, in this setting, does not distinguish networks of similar structure but widely differing parameters."
These two methods change quantitatively but stay visually convincing.
That is precisely the failure mode the design document is worried about, and it is a stronger point to make than a pass/fail list.

**Version trap - important.**
arXiv v3 (November 2020) carries a footnote: "A previous version of this work noted that Guided Backprop was entirely invariant; however, this is not this case."
The arXiv comment field reads "Updating Guided Backprop experiments due to bug. The results and conclusions remain the same."
**The NeurIPS 2018 camera-ready therefore states a stronger claim than the corrected paper does.**
If the doc cites "NeurIPS 2018" and then says "Guided BackProp is entirely invariant to model weights", it will be quoting a claim the authors have since corrected.
Cite the venue as NeurIPS 2018 but state the finding as "invariant to higher-layer parameters".

**Direct relevance to this project.**
The design ships Grad-CAM.
**Grad-CAM is one of the two methods that passes.**
Section 11.7 currently under-sells this by saying only that "a number of widely used saliency methods fail".

**Data randomization test**, for completeness: gradients and SmoothGrad undergo substantial changes; GradCAM masks develop disconnected patches; Guided BackProp changes visually but still highlights plausible-looking regions; gradient-input and Integrated Gradients change in sign while retaining input structure.

**Methods evaluated:** Gradient, Gradient-input, Integrated Gradients, Guided Backpropagation, GradCAM, Guided GradCAM, SmoothGrad (as a wrapper), Integrated Gradients-SG.
**Models:** Inception v3 on ImageNet, CNN on Fashion-MNIST, CNN/MLP on MNIST.

**Citation.**
Adebayo J, Gilmer J, Muelly M, Goodfellow I, Hardt M, Kim B.
"Sanity Checks for Saliency Maps."
*Advances in Neural Information Processing Systems 31 (NeurIPS 2018)*.
arXiv:1810.03292 (v1 October 2018; v3 November 2020, corrected Guided BackProp experiments).
https://arxiv.org/abs/1810.03292
Proceedings: https://papers.nips.cc/paper_files/paper/2018/hash/294a8ed24b1ad22ec2e7efea049b8737-Abstract.html
Figures quoted from v3: https://arxiv.org/pdf/1810.03292v3

---

## U6 - BagNet

**Claim:** cites Brendel & Bethge, ICLR 2019, for the BagNet limited-receptive-field architecture.

**Verdict:** Correct on the citation.
The receptive-field description is correct in principle; the specific sizes need stating.

**Exact figures.**
BagNet-q was trained and evaluated for **q in {9, 17, 33}**, that is receptive fields of 9x9, 17x17 and 33x33 pixels at the topmost convolutional layer, on 224x224 inputs.
17x17 reaches AlexNet-level performance (80.5% top-5); 33x33 reaches close to 87.6% top-5.

**Evidence.**
Architecture verbatim: "first, we infer a 2048 dimensional feature representation from each image patch of size q x q pixels using multiple stacked ResNet blocks and apply a linear classifier to infer the class evidence for each patch (heatmaps). We average the class evidence across all patches to infer the image-level class evidence (logits). This structure differs from other ResNets (He et al., 2015) only in the replacement of many 3 x 3 by 1 x 1 convolutions, thereby limiting the receptive field size of the topmost convolutional layer to q x q pixels... We denote the resulting architecture as BagNet-q and test q in [9, 17, 33]."
Accuracy verbatim: "Surprisingly, patch sizes as small as 17 x 17 pixels suffice to reach AlexNet (Krizhevsky et al., 2012) performance (80.5% top-5 performance) while patches sizes 33 x 33 pixels suffice to reach close to 87.6%."
Runtime: "Across all receptive field sizes BagNets reach around 155 images/s for BagNets compared to 570 images/s for ResNet-50", attributed to reduced downsampling.
Pretrained BagNet-9, BagNet-17 and BagNet-33 were released for PyTorch and Keras.
Venue confirmed from the PDF running header: "Published as a conference paper at ICLR 2019".

**One attribution point, and it matters for the pitch.**
The **sparse BagNet** the doc describes in section 1.3, and the 0.960 / 0.656 localisation numbers in reference V5, are **not** from Brendel & Bethge.
Brendel & Bethge introduced BagNet; the sparse variant with a sparsity-constrained linear head is the later PLOS Digital Health 2025 contribution.
The doc's own reference V5 attributes those numbers correctly, so this is only a risk if the two get conflated on a slide.
**Cite Brendel & Bethge for the limited-receptive-field architecture; cite the 2025 PLOS Digital Health paper for the sparse variant and its numbers.**

**Citation.**
Brendel W, Bethge M.
"Approximating CNNs with Bag-of-local-Features models works surprisingly well on ImageNet."
*Seventh International Conference on Learning Representations (ICLR 2019)*.
arXiv:1904.00760. https://arxiv.org/abs/1904.00760

---

## U7 - Beede et al., CHI 2020, Thailand deployment

**Claim:** section 5.1, "A deployed Google DR screening system in Thai clinics had a substantial fraction of images rejected for quality in field conditions."

**Verdict:** Correct, and the exact figure is now available.

**Exact figure.**
**393 of 1,838 images (21%)** were rejected by the algorithm as not meeting its grading standard, over the first six months of usage.

**Evidence.**
Verbatim: "After clinics 2, 4, and 5 all reported issues with gradability, we reviewed system logs to determine how many images were rejected by the algorithm. Out of 1838 images that were put through the system (in the first six months of usage), 393 (21%) didn't meet the system's high standards for grading. Through our observations and interviews, we found that low-quality images were caused by fundus photos being taken in a non-darkened environment, as observed in our pre-deployment findings, or from a camera that needed repair. In addition, clinics in Patham Thani were not using dilation drops on patients, which could have aided in capturing a quality image."

Gradability threshold verbatim: "The deep learning system has stringent guidelines regarding the images it will assess. For patient safety reasons, it was designed to decrease the chance that it would make an incorrect assessment, and therefore only assesses the highest-quality images. If an image has a bit of blur or a dark area, for instance, the system will reject it, even if it could make a strong prediction."

Consequence verbatim: "In the case of an ungradable image, the system notifies the nurse and recommends the patient be referred to an ophthalmologist... This immediate gradability feedback is something that the nurses did not have before, and turned out to be frustrating as images they felt were human-readable were rejected by the system."

**Exact context - get this right, because it is easy to overstate.**
The fieldwork covered 11 clinics across Pathum Thani and Chiang Mai (five and six respectively), visited in November 2018, April 2019 and August 2019.
The deep learning system was **initially deployed in three clinics within Pathum Thani** as part of a larger prospective study of 7,600 patients.
The 21% is a log-derived rejection rate over the deployed sites, not a rate across all 11 clinics studied.

**Safe phrasing for the submission.**
"In a CHI 2020 human-centred evaluation of a deployed deep learning DR screening system in Thailand, 21% of 1,838 images (393) put through the system in the first six months were rejected as not meeting the model's image-quality standard, largely because of non-darkened rooms, cameras needing repair, and non-use of dilation drops."

**Citation.**
Beede E, Baylor E, Hersch F, Iurchenko A, Wilcox L, Ruamviboonsuk P, Vardoulakis LM.
"A Human-Centered Evaluation of a Deep Learning System Deployed in Clinics for the Detection of Diabetic Retinopathy."
*Proceedings of the 2020 CHI Conference on Human Factors in Computing Systems (CHI '20)*, Honolulu, HI, April 2020.
DOI 10.1145/3313831.3376718.
Full text (gold open access): https://dl.acm.org/doi/fullHtml/10.1145/3313831.3376718

---

## U12 - Poplin et al., attributes predicted from fundus photographs

**Claim:** "Retinal models can predict non-pathological attributes from fundus images", supporting section 8.6's point that "Retinal classifiers are known to be able to exploit non-pathological image properties".

**Verdict:** Correct.
The doc's use of the paper is sound.

**Attributes predicted, with performance.**
From Table 2. UK Biobank validation set n = 12,026; EyePACS-2K validation set n = 999.
Baseline means predicting the population mean (continuous) or chance (binary).

| Attribute (metric) | UK Biobank (95% CI) | UKB baseline | EyePACS-2K (95% CI) | EyePACS-2K baseline |
|---|---|---|---|---|
| Age (MAE, years) | 3.26 (3.22-3.31) | 7.06 | 3.42 (3.23-3.61) | 8.48 |
| Age (R-squared) | 0.74 (0.73-0.75) | 0.00 | 0.82 (0.79-0.84) | 0.00 |
| Gender (AUC) | 0.97 (0.966-0.971) | 0.50 | 0.97 (0.96-0.98) | 0.50 |
| Current smoker (AUC) | 0.71 (0.70-0.73) | 0.50 | n/a | n/a |
| HbA1c (MAE, %) | n/a | n/a | 1.39 (1.29-1.50) | 1.67 |
| Systolic BP (MAE, mmHg) | 11.35 (11.18-11.51) | 14.57 | n/a | n/a |
| Diastolic BP (MAE, mmHg) | 6.42 (6.33-6.52) | 7.83 | n/a | n/a |
| BMI (MAE) | 3.29 (3.24-3.34) | 3.62 | n/a | n/a |

Additionally **ethnicity** was inferred, kappa 0.60 (0.58-0.63) on UK Biobank and 0.75 (0.70-0.79) on EyePACS-2K.
**Major adverse cardiac events within 5 years:** AUC 0.70 (0.648-0.740) from fundus images alone, against 0.72 (0.67-0.76) for the European SCORE risk calculator.

**Published abstract verbatim:** "we predicted cardiovascular risk factors not previously thought to be present or quantifiable in retinal images, such as age (mean absolute error within 3.26 years), gender (area under the receiver operating characteristic curve (AUC) = 0.97), smoking status (AUC = 0.71), systolic blood pressure (mean absolute error within 11.23 mmHg) and major adverse cardiac events (AUC = 0.70). We also show that the trained deep-learning models used anatomical features, such as the optic disc or blood vessels, to generate each prediction."

**Two discrepancies to be aware of before quoting.**
1. Systolic BP: the arXiv Table 2 gives MAE **11.35** mmHg on UK Biobank, whereas both the arXiv abstract and the published Nature BME abstract say "within **11.23** mmHg".
The Nature BME full text is paywalled and only the published abstract could be read, so which value appears in the published Table 2 is unconfirmed.
**If the doc quotes an SBP number, quote 11.23 mmHg and attribute it to the published abstract.**
2. The published Nature BME abstract **omits HbA1c**; the arXiv preprint abstract includes it.
If HbA1c is quoted, attribute it to Table 2 / the preprint, not to the published abstract.

**Relevance to section 8.6.**
The paper reports that models trained to predict HbA1c tended to highlight the vessels, while attention masks for diastolic blood pressure and BMI were more diffuse.
The published abstract confirms the models "used anatomical features, such as the optic disc or blood vessels, to generate each prediction."
This supports the doc's concern that a model can learn non-lesion signal and still produce a plausible-looking heatmap.

**Citation.**
Poplin R, Varadarajan AV, Blumer K, Liu Y, McConnell MV, Corrado GS, Peng L, Webster DR.
"Prediction of cardiovascular risk factors from retinal fundus photographs via deep learning."
*Nature Biomedical Engineering* 2(3):158-164 (2018). DOI 10.1038/s41551-018-0195-0.
Published abstract: https://www.nature.com/articles/s41551-018-0195-0 (full text paywalled)
Table 2 figures from the preprint, arXiv:1708.09843: https://arxiv.org/pdf/1708.09843
Note the preprint title differs from the published title.

---

## Actions the design document needs

Ordered by how much damage the claim would do if a judge checked it.

1. **U8.4, Messidor-2 grades.** Section 10.1 lists Messidor-2 as supplying "DR grades". The official ADCIS release does not. Correct the table, and add the third-party grade set as a tracked dependency alongside R03.
2. **U3, the IDF rider.** Delete "Shows the PS's 77M figure is the older IDF estimate". It could not be verified. Keep the 101 million figure, reworded as a 2021 projection.
3. **U8.7, adjudication.** Reword to "the organisers describe a single clinician rating per image and document no adjudication process".
4. **U4, saliency specifics.** Name the methods, and state that Grad-CAM passes. Use the corrected "invariant to higher-layer parameters" wording, not the 2018 camera-ready's stronger claim.
5. **U8.2, MA mask counts.** Replace "a few dozen" with 81 images total, 54 train / 27 test.
6. **U10, AUPR scope.** Say "IDRiD sub-challenge 1" rather than implying AUPR scores the whole benchmark.
7. **U2, endpoint mismatch.** Note in section 3.5 that the EyeArt figures are per eye and the IDx-DR figures per participant.
8. **U6, sparse BagNet attribution.** Keep Brendel & Bethge and the PLOS Digital Health 2025 paper separate.

## Still unverified

- **U5** - deletion / insertion AUC as a saliency faithfulness metric (Petsiuk et al., RISE). Not checked in this pass.
- **U11** - local colour normalisation attribution. Not checked in this pass. The existing instruction stands: describe the method, do not attribute it to a named individual without checking.
- **The IDF Diabetes Atlas source for the 77 million figure.** No IDF primary document could be retrieved; every candidate PDF URL on diabetesatlas.org and idf.org returned HTTP 404.
- **Poplin published Table 2 systolic BP value.** Nature BME full text is paywalled; only the abstract value of 11.23 mmHg is confirmed.
- **SIH judging theme bucket for PS 26038.** Out of scope for this pass; still open in Appendix A.
