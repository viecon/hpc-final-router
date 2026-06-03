# VM Multicore Optimization Log

Last updated: 2026-06-04

## Goal

Investigate why the current OpenMP/multithreaded NTHU-Route direction does not use
multiple cores effectively, determine whether the utilization issue is a launch/binding
problem or an algorithmic bottleneck, and record follow-up optimization strategies.

## VM Environment

- VM: `ubuntu@202.5.251.114`
- Branch: `vm-fastest-benchmark-guard`
- Profiling helper: `scripts/run_vm_openmp_utilization.sh`
- Container: `apptainer exec --nv router.sif`
- CPU: 16 vCPU, 1 thread per core, 2 sockets visible to `lscpu`
- OpenMP runtime settings used for profiling:
  - `OMP_PROC_BIND=close`
  - `OMP_PLACES=cores`

## Current OpenMP Implementation

The existing OpenMP implementation parallelizes independent analysis kernels:

- congestion cost update
- max-overflow and wirelength reductions
- interval construction scans
- post-processing candidate counters
- selected initialization loops

It intentionally leaves `RangeRouter::range_router()` sequential because it mutates
the shared congestion map by removing and reinserting two-pin paths. Directly running
those reroutes in parallel would introduce data races and route-order nondeterminism.

## Profiling Method

`scripts/run_vm_openmp_utilization.sh` builds the OpenMP NTHU source and runs one
benchmark at several `OMP_NUM_THREADS` values. During each route it samples:

- process CPU percentage
- live thread count
- per-thread CPU sum and max
- route validity through the Lab2 checker
- NTHU `NTHU_PROFILE=1` breakdown

The first helper revision sampled the wrapper shell PID. This was fixed by launching
the router with `exec env ... ./NthuRoute`, so `$!` is the actual router process.

## Measured Results

### `newblue2.fastplace90.3d.50.20.100`

Result directory:

```text
results/vm_openmp_utilization/newblue2_fixed_20260603T231515Z/
```

| Threads | Seconds | Avg Process CPU | Max Process CPU | Avg Live Threads | Overflow |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 65.646939 | 99.398 | 106.000 | 1.000 | 0 |
| 4 | 64.611125 | 100.665 | 104.000 | 3.339 | 0 |
| 8 | 63.586878 | 102.198 | 106.000 | 6.508 | 0 |
| 12 | 63.587045 | 103.144 | 110.000 | 9.492 | 0 |

Profile breakdown:

| Threads | Iterations | `route_all` Share | `specify_all_range` Share of `route_all` |
| ---: | ---: | ---: | ---: |
| 1 | 4 | 0.992426 | 0.989974 |
| 4 | 4 | 0.996140 | 0.991494 |
| 8 | 4 | 0.997073 | 0.991382 |
| 12 | 4 | 0.997441 | 0.991347 |

Interpretation: OpenMP threads are created, but average CPU remains near one core.
Thread binding is not the blocker. The dominant work is still the sequential
`specify_all_range()` path.

Binding/cache-placement check:

```text
results/vm_openmp_utilization/newblue2_t12_spread_20260603T234236Z/
```

| Threads | Binding | Seconds | Avg Process CPU | Avg Live Threads | Overflow |
| ---: | --- | ---: | ---: | ---: | ---: |
| 12 | close | 63.587045 | 103.144 | 9.492 | 0 |
| 12 | spread | 59.504593 | 102.798 | 9.491 | 0 |

The spread run did not raise CPU utilization; it still averaged roughly one core.
It finished faster, but also completed only 3 routing iterations versus 4 in the
close run, so this should not be interpreted as cache placement fixing multicore
utilization.

### `adaptec3.dragon70.3d.30.50.90`

Result directory:

```text
results/vm_openmp_utilization/adaptec3_t1_12_20260603T232355Z/
```

| Threads | Seconds | Avg Process CPU | Max Process CPU | Avg Live Threads | Overflow |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 491.501180 | 99.840 | 107.000 | 1.000 | 0 |
| 12 | 485.314663 | 101.785 | 105.000 | 11.315 | 0 |

Profile breakdown:

| Threads | Iterations | `route_all` Share | `specify_all_range` Share of `route_all` |
| ---: | ---: | ---: | ---: |
| 1 | 8 | 0.998021 | 0.998154 |
| 12 | 8 | 0.999589 | 0.998764 |

Interpretation: the larger benchmark has the same utilization shape. OpenMP creates
workers, but the process still averages almost exactly one core. The parallelized
analysis kernels shrink, but they are hidden by the sequential `specify_all_range()`
work.

## Strategy Assessment

### Not Enough: More OpenMP Threads

Increasing `OMP_NUM_THREADS` from 1 to 12 produced only a small runtime change on
`newblue2` while CPU stayed near 100%. This means the runtime is not limited by
OpenMP thread placement or lack of worker creation.

### Not Enough: Analysis-Kernel Parallelism

The profiled parallel kernels shrink modestly, but they are less than 1% of total
runtime on the measured case. Optimizing these reductions further cannot materially
improve end-to-end runtime.

### Risky: Naive Parallel Reroute

`range_router()` performs:

1. old-path overflow check
2. remove old two-pin path from the shared congestion map
3. find a replacement path using current congestion
4. insert the new path back into the shared congestion map

Parallelizing this loop without conflict control would cause races on edge demand,
route-order-dependent behavior, and likely overflow regressions.

### Plausible Next Direction: Conflict-Aware Batching

A real multicore optimization would need to batch two-pin reroutes whose old paths
and bounding boxes do not overlap, then commit the batch in a deterministic order.
Expected work:

- compute each candidate's bounding box and touched-edge set
- greedily color candidates into low-conflict batches
- run route search in parallel using a read-only congestion snapshot
- commit accepted routes sequentially with final legality checks
- fall back to current sequential route when a conflict is detected

This is a larger algorithmic change than adding OpenMP pragmas to existing loops.

## Current Conclusion

The utilization issue is real, but it is not caused by bad OpenMP launch settings.
The code creates OpenMP worker threads, yet the dominant route mutation loop remains
serial. The current OpenMP direction is therefore a correct but low-impact optimization.

The next worthwhile multicore attempt is conflict-aware reroute batching, not more
parallel reductions or thread-binding tweaks.

## Action Items

1. Keep the existing OpenMP analysis-kernel implementation as a correctness-preserving
   baseline and report it as a limited/negative result.
2. Do not spend more time on `OMP_NUM_THREADS`, `OMP_PROC_BIND`, or simple reduction
   tuning; the VM measurements show those knobs do not lift process CPU beyond one
   effective core.
3. If implementing a new multicore optimization, start with a small conflict-aware
   batching prototype behind an environment flag. Acceptance must require:
   - selected original-legal benchmarks remain `overflow=0,max_overflow=0`
   - speedup is measured against the single-thread source build on the same VM
   - any rejected/overflowing batch rows are kept as ablation evidence, not final claims
