# Report Outline

## Title

Reproducible Benchmarking and Acceleration Study of VLSI Global Routers on Taiwania 2

## Motivation

Global routing is a major step in VLSI physical design. NCTU-GR 2.0 is especially
interesting for this course because it is from NCTU/NYCU and focuses on multithreaded
collision-aware global routing. Its public release is binary-only, so it is best used as
a black-box baseline.

NTHU-Route 2.0 is another strong Taiwan-made global router and has a modern open-source
C++ port. It is therefore the base for our source-level OpenMP acceleration.

## Real Baselines

- Benchmark suite: ISPD08 global-routing benchmarks.
- Evaluator: Lab2 Python validation checker, with official `eval2008.pl` as fallback
  and cross-check.
- Baseline A: NTHU-Route 2.0 source build with shared ISPD08 compatibility fixes
  including FLUTE `MAXD=1000`, high-degree fallback, per-layer vector sizing, and
  CRLF-safe LUT parsing.
- Improved version: NTHU-Route 2.0 with OpenMP analysis kernels.
- Baseline B: NCTU-GR 2.0 binary release.

Metrics:

- Runtime
- Total wirelength
- Total overflow
- Max overflow
- Overflowed nets / overflowed edges from the Lab2 checker

## Implementation Plan

1. Package both routers in a Singularity/Apptainer environment.
2. Run both routers on ISPD08 through Slurm.
3. Evaluate all results with the same Lab2 checker.
4. Use NTHU-Route source as the modifiable base for OpenMP acceleration.

## Possible Acceleration Direction

First implemented step: accelerate repeated analysis kernels around NTHU-Route's
rip-up-and-reroute stage:

- Parallel edge-cost pre-evaluation.
- Parallel overflow and wirelength reductions.
- Parallel range-interval construction with thread-local bins.
- Parallel post-processing candidate counter construction.

Stretch direction: parallelize NTHU-Route's actual rip-up-and-reroute stage:

- Identify congested two-pin nets.
- Dispatch independent or low-overlap nets as parallel tasks.
- Compare sequential reroute with batched CPU reroute.
- GPU direction should be framed as future work for batched candidate evaluation, not as
  a synthetic mini-router result.

## Slurm + Container Reproducibility

- Build and run under a Singularity/Apptainer image.
- Submit jobs with Slurm.
- Produce CSV outputs in `results/`.
- Generate plots with `scripts/plot.py`.

## Figures to Include

- NTHU-Route vs NCTU-GR runtime on ISPD08.
- NTHU-Route vs NCTU-GR wirelength/overflow on ISPD08.
- NTHU-Route OpenMP thread sweep showing limited analysis-kernel scaling on
  `adaptec1`.
- NTHU profiling breakdown showing why the current GPU opportunity is not in simple
  reductions.

## Current Adaptec1-3 Results

Taiwania Slurm + Apptainer, Lab2 checker:

| Benchmark | Router | Runtime (s) | Speedup vs NTHU original | Wirelength | Total overflow |
| --- | --- | ---: | ---: | ---: | ---: |
| adaptec1 | NTHU original | 398.602 | 1.000x | 5363235 | 0 |
| adaptec1 | NTHU OpenMP | 396.222 | 1.006x | 5362564 | 0 |
| adaptec1 | NCTU-GR 2.0 | 94.287 | 4.228x | 5444473 | 0 |
| adaptec2 | NTHU original | 160.380 | 1.000x | 4857976 | 958172 |
| adaptec2 | NTHU OpenMP | 159.388 | 1.006x | 4858513 | 958110 |
| adaptec2 | NCTU-GR 2.0 | 36.602 | 4.382x | 5268055 | 0 |
| adaptec3 | NTHU original | 422.956 | 1.000x | 13158101 | 0 |
| adaptec3 | NTHU OpenMP | 417.260 | 1.014x | 13157672 | 0 |
| adaptec3 | NCTU-GR 2.0 | 143.430 | 2.949x | 13111623 | 0 |

Generated report artifacts:

```text
results/real_baselines_adaptec123_summary.csv
results/plots_adaptec123/real_runtime.png
results/plots_adaptec123/real_wirelength.png
results/plots_adaptec123/real_overflow.png
results/plots_adaptec123/real_speedup_vs_nthu_original.csv
```

Observation: NCTU-GR is consistently much faster. On `adaptec2`, it also reaches zero
overflow while both NTHU variants leave large checker-reported overflow. The OpenMP
NTHU version remains behaviorally close to the source baseline and gives small speedups
because the accelerated analysis kernels are not the dominant work.

OpenMP sweep using the modified NTHU source:

| Variant | Runtime (s) | Speedup vs NTHU original | Wirelength | Total overflow |
| --- | ---: | ---: | ---: | ---: |
| NTHU original | 398.602 | 1.000x | 5363235 | 0 |
| OpenMP t1 | 403.239 | 0.989x | 5363235 | 0 |
| OpenMP t2 | 405.665 | 0.983x | 5362286 | 0 |
| OpenMP t4 | 396.461 | 1.005x | 5362296 | 0 |

Profiling with `NTHU_PROFILE=1` confirms why GPU offload is not yet attractive for the
current code shape:

| Profiled region | Total over 11 iterations | Share |
| --- | ---: | ---: |
| Pre-evaluate + overflow + wirelength reductions | 106.077 ms | 0.0285% |
| `route_all_2pin_net` | 372731.170 ms | 99.9715% |
| `specify_all_range` inside `route_all_2pin_net` | 372535.696 ms | 99.9477% of route_all |

Conclusion for this iteration: the OpenMP analysis kernels are correct and preserve
valid routing, but the runtime is still dominated by sequential rip-up/reroute work.
The next optimization target should be collision-aware batching of congested two-pin
nets rather than GPU reductions over grid edges.

## Limitations

- NCTU-GR cannot be instrumented internally because only a binary is public.
- NTHU-Route source is GPL-3.0, so source modifications should preserve license notices.
- GPU acceleration of NTHU-Route requires algorithmic restructuring; simple reduction
  offload would not improve end-to-end runtime.

## Future Work

- Parallelize NTHU-Route's congested-net rerouting.
- Add low-collision task batching based on bounding-box overlap.
- Add GPU candidate evaluation only after introducing collision-aware reroute batches.
- Compare with InstantGR as a modern GPU global router.

## Final Methods Summary

Use this newer summary for the final report:

```text
docs/methods_and_results_summary.md
results/method_speedups_summary.csv
results/cross_validation_checks.csv
```

Current verified legal NTHU source-code result:

| Benchmark set | Baseline time | Best legal NTHU time | Speedup | Overflow |
| --- | ---: | ---: | ---: | ---: |
| adaptec1-3 | 981.939003s | 422.179091s | 2.325883x | 0 |

Best legal NTHU rows:

| Benchmark | Router | Runtime | Speedup |
| --- | --- | ---: | ---: |
| adaptec1 | `nthu_a1_th1800_p2max6_p3box66_122` | 188.156013s | 2.118467x |
| adaptec2 | `nthu_p2_box5_5_th240` | 81.880970s | 1.958702x |
| adaptec3 | `nthu_cuda_a3_step8_p2max4_box35_50` | 152.142108s | 2.780007x |

Important distinction:

- NCTU-GR tuned black-box results can reach `5x+` legally.
- NTHU `bigblue1` can reach `5.063517x` runtime, but that route still has
  `3882` overflow and is therefore not a completed legal result.
