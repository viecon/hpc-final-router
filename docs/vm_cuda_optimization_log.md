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

Pending VM run.
