# ResNet-50 VRAM Spike

Date: 2026-08-22.

This is a throwaway feasibility experiment and is not production training code.

## Question

Can this machine fine-tune ResNet-50 on 448x448 images with the batch sizes required by the design document?

The relevant design decision in §7.1 is ResNet-50 at 448x448 minimum, with batch sizes 8-16 tuned for the 6 GB RTX 3050.

The fallback resolutions were only to be tested if 448x448 failed at every reasonable batch size.

## Environment

- GPU: NVIDIA GeForce RTX 3050 6GB Laptop GPU.
- CUDA compute capability: 8.6.
- MATLAB: R2026a Update 4, version 26.1.0.3312084.
- Deep Learning Toolbox: 26.1.
- Parallel Computing Toolbox: 26.1.
- Host memory: 16 GB, as supplied for this experiment.

The three §14.3 smoke tests passed.

The CUDA smoke test reported the RTX 3050, compute capability 8.6, and 1.084464 seconds for the 4096-by-4096 GPU matrix multiplication.

`imagePretrainedNetwork('resnet50')` resolved and printed `DLT ok`.

`simevents` reached `SimEvents ok` and exited cleanly when followed by `close all force`.

SimEvents emitted fontconfig warnings under the Arch environment, but they did not prevent the smoke test from completing.

## Method

Each batch-size measurement ran in a fresh `matlab -batch` process so CUDA state from one run could not affect the next run.

Each run used `rng(42, "twister")`, a synthetic two-class dataset with three mini-batches, and one epoch.

The network was loaded with `imagePretrainedNetwork("resnet50", NumClasses=2)` and trained with `trainnet` using SGDM and `ExecutionEnvironment="gpu"`.

The images were single-precision arrays with shape `resolution x resolution x 3 x (3*batchSize)`.

The reported seconds per iteration are the elapsed training time divided by the three optimizer updates.

The GPU memory values are the `gpuDevice.AvailableMemory` readings from inside the run and after the run, not a separate peak-allocation profiler.

## Results at 448x448

| Batch size | Result | Optimizer updates | Seconds per iteration | Available before | Minimum available during callbacks | Available after |
| ---: | :--- | ---: | ---: | ---: | ---: | ---: |
| 16 | Success | 3 | 2.098490 | 5.989 GB | 5.614 GB | 5.898 GB |
| 8 | Success | 3 | 1.758833 | 5.989 GB | 5.603 GB | 5.862 GB |
| 4 | Success | 3 | 1.577591 | 5.989 GB | 5.530 GB | 5.753 GB |
| 2 | Success | 3 | 1.497033 | 5.989 GB | 5.563 GB | 5.751 GB |

The GPU reported 6.086 GB total memory at the start of each fresh process.

No run produced a GPU out-of-memory error or another training failure.

## Answer

- GPU training works on this machine.
- The largest tested and usable batch size is 16 at 448x448.
- 448x448 fits for every requested batch size: 16, 8, 4, and 2.
- The measured short-run cost is approximately 1.50-2.10 seconds per optimizer iteration, depending on batch size.
- Gradient accumulation is not required to make 448x448 training fit at the tested batch sizes.
- A batch size of 16 is a viable starting point for the full training path, subject to confirmation with the real preprocessing pipeline and dataset loader.
- The 384x384 and 320x320 fallback tests were not run because the required 448x448 configuration succeeded at every tested batch size.

## Incomplete work and limits

This spike used synthetic data and only three optimizer updates per batch size, so it establishes GPU feasibility and approximate iteration cost rather than model quality or end-to-end training throughput.

Batch sizes larger than 16 were not part of the requested matrix and were not used to claim the absolute hardware maximum.

The benchmark did not exercise the project's shared preprocessing function or real patient-level data splits.

No files under `data/sealed/` were accessed or modified.
