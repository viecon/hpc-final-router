# VM CUDA Optimization Log

Date: 2026-06-04

## Objective

Evaluate whether the CUDA side can improve real NTHU-Route runtime on the VM,
including:

- single-GPU latency for the existing CUDA costed-maze path
- one process with two GPUs visible
- opt-in two-GPU dogleg preselection splitting
- two independent router processes pinned to separate GPUs for throughput only

Benchmarks must run only on the VM.

## Code Changes

The original router in `external/nthu-route-original` is kept unchanged.

CUDA changes are limited to the optimized router in `external/nthu-route`:

- `CudaDogleg.cu` now has an opt-in `NTHU_CUDA_DOGLEG_MULTI_GPU=1` path that
  partitions dogleg preselect inputs across visible GPUs.
- The multi-GPU path is disabled by default and only affects runs that set the
  env flag.
- Redundant explicit `cudaDeviceSynchronize()` calls were removed where the
  immediately following blocking `cudaMemcpy()` already synchronizes.

## VM Runner

`scripts/run_vm_cuda_utilization.sh` builds the CUDA-enabled NTHU router and
records:

- `summary.csv`: runtime and legality per scenario/benchmark
- `gpu_summary.csv`: average/max GPU utilization, memory utilization, memory used,
  and power per GPU
- `profile_breakdown.csv`: NTHU phase/profile counters including CUDA prepare and
  CUDA maze time
- `strategy_index.csv`: scenario definitions
- `environment.txt`: git, CPU, memory, GPU, and toolchain details

Default scenarios:

- `single_costed`
- `dual_visible_costed`
- `single_preselect`
- `dual_multigpu_preselect`
- `dual_parallel_costed`

## Interpretation Rules

- `dual_visible_costed` is a single-process test. If GPU 1 stays idle, the current
  code does not use both GPUs for one testcase.
- `dual_multigpu_preselect` tests only the opt-in dogleg preselect split. It is
  useful only if it improves runtime or meaningfully raises utilization.
- `dual_parallel_costed` is throughput, not single-testcase latency. It can justify
  using both GPUs to run different benchmarks concurrently, but not a per-benchmark
  speedup claim.
- If dual-GPU scenarios do not improve latency, CUDA tuning should focus on the
  single-GPU path and on future collision-aware batching rather than device count.

## Results

VM run:

```text
/home/ubuntu/hpc-final-router/results/vm_cuda_utilization/cuda_a3_single_dual_20260604T000000Z
commit=6c369f9
host GPUs=2x Tesla V100-SXM2-32GB
```

All measured rows were legal (`total_overflow=0`, `max_overflow=0`).

| Scenario | Benchmark | Seconds | GPU0 Avg/Max Util | GPU1 Avg/Max Util | Notes |
|---|---:|---:|---:|---:|---|
| `single_costed` | adaptec3 | 194.907488 | 0.122% / 8% | 0% / 0% | Existing CUDA costed-maze path on one GPU. |
| `dual_visible_costed` | adaptec3 | 191.291393 | 0.158% / 8% | 0% / 0% | Single process sees both GPUs, but only GPU0 does work. |
| `single_preselect` | adaptec3 | 197.495564 | 0.080% / 5% | 0% / 0% | Dogleg preselect enabled on one GPU. |
| `dual_multigpu_preselect` | adaptec3 | 199.862087 | 0.171% / 9% | 0% / 0% | GPU1 allocated memory but sampled compute util remained 0; slower than single preselect. |
| `dual_parallel_costed` | adaptec3 + newblue2 | 193.687780 wall | 0.132% / 8% | 0% / 0% | Throughput run; wall time dominated by adaptec3. |

Profile counters for `adaptec3`:

| Scenario | `route_all_ms` | `specify_all_range_ms` | `cuda_prepare_ms` | `cuda_maze_ms` | CUDA Batches | CUDA Inputs |
|---|---:|---:|---:|---:|---:|---:|
| `single_costed` | 54242.891 | 54103.715 | 0.000 | 1068.330 | 0 | 0 |
| `dual_visible_costed` | 53295.448 | 53158.383 | 0.000 | 861.536 | 0 | 0 |
| `single_preselect` | 55237.586 | 55109.771 | 646.620 | 1044.491 | 1 | 465829 |
| `dual_multigpu_preselect` | 54868.129 | 54744.162 | 728.413 | 848.683 | 1 | 465829 |

## CUDA Conclusion

The VM has two V100 GPUs, but current NTHU-Route does not have enough GPU-side
work to benefit from two GPUs for a single testcase.

- `dual_visible_costed` confirmed the current single-process CUDA path uses only
  GPU0.
- The opt-in two-GPU dogleg preselect path did not improve latency. It also made
  preselect preparation slower (`728.413 ms` vs `646.620 ms`), because duplicating
  cost-map copies and launching host threads costs more than the saved kernel work.
- `cuda_maze_ms` is only about one second on `adaptec3`, while the measured
  end-to-end run is roughly 195 seconds. Even a perfect multi-GPU implementation of
  that current substep would not move total runtime much.
- `nvidia-smi` sampling showed average GPU compute utilization near zero. This is
  consistent with many short CUDA calls separated by sequential CPU routing work.

Use single GPU as the CUDA baseline. Further CUDA work should focus on algorithmic
batching that creates larger independent GPU work units; adding devices to the
current sequential reroute loop is not a useful optimization direction.
