# Methods and Results Summary

Last updated: 2026-05-27

## Executive Summary

The strongest **legal NTHU source-code result** currently available is the
best-per-benchmark combination on `adaptec1-3`:

| Benchmark set | Baseline time | Best legal NTHU time | Speedup | Overflow |
| --- | ---: | ---: | ---: | ---: |
| adaptec1-3 total | 981.939003s | 422.179091s | 2.325883x | 0 |

This is below the original stretch target of `5x-10x`, but it is reproducible,
checker-valid, and comes from source-level NTHU modifications/tuning rather than
switching routers.

The disk-quota cleanup may have removed some raw per-run directories, logs, and
route outputs. The final aggregate evidence is still preserved in the selected
CSV files under `results/` and in `docs/final_experiment_report.md`.

The only currently verified `5x+` legal results are **cross-router NCTU-GR**
comparisons:

| Benchmark set | Baseline | NCTU time | Speedup | Overflow | Note |
| --- | ---: | ---: | ---: | ---: | --- |
| adaptec1-3 tuned best-per-benchmark | 981.939003s | 193.550437s | 5.073298x | 0 | black-box NCTU-GR |
| bigblue1 tuned | 873.105913s | 168.417282s | 5.184182x | 0 | black-box NCTU-GR |

The best `bigblue1` NTHU result is a useful frontier point but is **not legal**:

| Benchmark | Baseline | NTHU frontier time | Speedup | Overflow |
| --- | ---: | ---: | ---: | ---: |
| bigblue1 | 873.105913s | 172.430727s | 5.063517x | 3882 |

## Methods Tried

### 1. Baseline Construction and Cross-Router Testing

What was done:

- Packaged NTHU-Route and NCTU-GR in the same Taiwania/Apptainer workflow.
- Evaluated all outputs with the same Lab2 checker.
- Fixed NTHU source compatibility issues needed for ISPD08 runs:
  FLUTE high-degree handling, per-layer vector sizing, CRLF-safe LUT parsing,
  and deterministic high-degree fallback.

Result:

| Method | Benchmark set | Time | Speedup vs NTHU original | Overflow |
| --- | --- | ---: | ---: | ---: |
| NTHU original | adaptec1-3 | 981.939003s | 1.000000x | mixed; adaptec2 overflows |
| NCTU-GR default | adaptec1-3 | 274.320014s | 3.579538x | 0 |
| NCTU-GR tuned | adaptec1-3 | 193.550437s | 5.073298x | 0 |

Interpretation:

NCTU-GR is a strong black-box baseline and can produce `5x+` legal numbers, but
that is not an NTHU source-code speedup.

### 2. OpenMP Analysis Kernels

What was done:

- Parallelized analysis-heavy kernels around NTHU's routing loop:
  congestion reductions, wirelength/overflow calculations, range setup, and
  post-processing candidate counting.

Result:

| Benchmark | Baseline | OpenMP time | Speedup | Overflow |
| --- | ---: | ---: | ---: | ---: |
| adaptec1 | 398.602398s | 396.221632s | 1.006009x | 0 |
| adaptec2 | 160.380428s | 159.388201s | 1.006225x | 958110 |
| adaptec3 | 422.956177s | 417.260015s | 1.013651x | 0 |
| adaptec1-3 total | 981.939003s | 972.869848s | 1.009322x | mixed |

Interpretation:

OpenMP was correct but not impactful. Profiling showed routing is dominated by
sequential rip-up/reroute behavior, so parallel reductions do not move the
end-to-end runtime much.

### 3. Fast Greedy Layer Assignment

What was done:

- Replaced the slower layer-assignment path with a fast greedy layer assignment.
- Kept checker legality as the primary acceptance criterion.

Representative legal results:

| Benchmark | Baseline | Method time | Speedup | Overflow |
| --- | ---: | ---: | ---: | ---: |
| adaptec1 | 398.602398s | 219.098877s | 1.819281x | 0 |
| adaptec2 | 160.380428s | 85.781977s | 1.869628x | 0 |
| adaptec3 | 422.956177s | 204.051424s | 2.072792x | 0 |

Interpretation:

This was the first broadly useful NTHU-side acceleration. It trades more
wirelength for much lower runtime while preserving zero overflow.

### 4. P2/P3 Budget and Threshold Tuning

What was done:

- Tuned P2 overflow thresholds, P2 max iteration, P3 box sizes, and P3 budgets.
- Goal was to avoid spending time on expensive repair loops when a faster legal
  route was possible.

Best legal NTHU results:

| Benchmark | Best router | Baseline | Time | Speedup | Overflow |
| --- | --- | ---: | ---: | ---: | ---: |
| adaptec1 | `nthu_a1_th1800_p2max6_p3box66_122` | 398.602398s | 188.156013s | 2.118467x | 0 |
| adaptec2 | `nthu_p2_box5_5_th240` | 160.380428s | 81.880970s | 1.958702x | 0 |

Interpretation:

Tuning the search effort was more effective than OpenMP. The best legal
adaptec1/adaptec2 results are mostly from controlling how much routing repair work
NTHU performs.

### 5. CUDA Candidate Scoring

What was done:

- Built CUDA scorers for dogleg/candidate evaluation.
- Measured standalone GPU speedups on real NTHU candidate coordinates.
- Integrated CUDA-assisted scoring into some NTHU `adaptec3` experiments.

Standalone GPU scorer speedups:

| Benchmark | CPU avg | CUDA avg | Speedup |
| --- | ---: | ---: | ---: |
| adaptec1 | 9041.765 ms | 256.353 ms | 35.271x |
| adaptec2 | 4074.685 ms | 107.030 ms | 38.071x |
| adaptec3 | 10465.150 ms | 309.457 ms | 33.818x |

Best legal integrated NTHU result:

| Benchmark | Best router | Baseline | Time | Speedup | Overflow |
| --- | --- | ---: | ---: | ---: | ---: |
| adaptec3 | `nthu_cuda_a3_step8_p2max4_box35_50` | 422.956177s | 152.142108s | 2.780007x | 0 |

Interpretation:

GPU is very effective on the isolated scoring kernel, but the end-to-end gain is
limited by the rest of NTHU's routing flow. The report should present this as a
successful kernel acceleration plus an honest integration bottleneck.

### 6. BigBlue1 5x Frontier Search

What was done:

- Used `bigblue1` as a difficult self-speedup target:
  `873.105913s` legal NTHU baseline, so `5x` requires `<=174.621183s`.
- Tuned late reroute scoring, P3 box sizes, second post-processing budget, and
  post-processing candidate sorting.
- Best selector so far is `edge_count`: prioritize two-pin nets touching more
  overflow edges.

Current NTHU frontier:

| Router | Time | Speedup | Overflow | Legal? |
| --- | ---: | ---: | ---: | --- |
| `nthu_b1_late4_p3box54_88_p3m2_edgecount_limit80` | 172.430727s | 5.063517x | 3882 | no |

Interpretation:

The runtime target is reachable, but legality is not. This is useful negative
evidence: aggressive pruning can give the desired time, but the remaining overflow
is too large to claim success.

## Final Legal NTHU Combination

Using the fastest legal NTHU row per `adaptec1-3` benchmark:

| Benchmark | Router | Time | Speedup | Wirelength | Overflow |
| --- | --- | ---: | ---: | ---: | ---: |
| adaptec1 | `nthu_a1_th1800_p2max6_p3box66_122` | 188.156013s | 2.118467x | 9429701 | 0 |
| adaptec2 | `nthu_p2_box5_5_th240` | 81.880970s | 1.958702x | 5243762 | 0 |
| adaptec3 | `nthu_cuda_a3_step8_p2max4_box35_50` | 152.142108s | 2.780007x | 22444948 | 0 |
| total | best legal NTHU combination | 422.179091s | 2.325883x | - | 0 |

## Cross-Validation

Generated artifacts:

```text
results/method_speedups_summary.csv
results/cross_validation_checks.csv
results/bench16_strategy_matrix_r2_summary.csv
results/bench16_strategy_matrix_r2_speedups.csv
results/bench16_strategy_matrix_r2_speedup_matrix.csv
```

Cross-validation checks performed:

- Re-read the source summary CSVs for all key rows.
- Recomputed speedups from the fixed NTHU original baselines.
- Confirmed checker status is `ok`.
- Confirmed expected `total_overflow` values.
- Confirmed referenced `.out` files exist.

All 9 key checks passed in `results/cross_validation_checks.csv`.

The 16-case retest matrix contains 96 intended NTHU strategy/testcase
combinations. The preserved aggregate result has 74 valid summary rows, 22
timeout/header-only rows, and 0 missing rows in the aggregate accounting.

## Recommended Report Framing

Main claim:

> We achieved a reproducible `2.33x` legal NTHU source-code speedup on the
> `adaptec1-3` benchmark set through fast layer assignment, routing-effort
> tuning, and selective CUDA-assisted scoring. Cross-router NCTU-GR tuning
> reached `5.07x`, and an NTHU `bigblue1` frontier reached `5.06x` runtime but
> remained illegal due to overflow.

Important caveat:

The `5x+` NTHU `bigblue1` number should not be presented as a completed result.
It is a frontier/ablation result because the route has nonzero overflow.
