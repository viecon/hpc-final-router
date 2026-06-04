# Current Router Comparison Report

Date: 2026-06-04  
Branch: `vm-fastest-benchmark-guard`  
Reported code commit: `58cc00f` plus this report commit on the same branch.

## Scope

Benchmarks were run only on the VM. The main 12-case comparison uses VM result files
under:

```text
/home/ubuntu/hpc-final-router/results/vm_real_matrix/summary_live.csv
```

Environment: 16 CPU cores, 164 GiB memory, 2x Tesla V100-SXM2-32GB, Apptainer
container, `lab2-verifier.py` evaluator.

## Routers And Optimizations

| Router / Strategy | Purpose | Main Optimization |
|---|---|---|
| `true_original` | Baseline | Original NTHU-Route behavior. |
| `nthu_fast_layer` / `nthu_fast_layer_repair` | Legal speed path | Faster greedy layer assignment plus conservative repair. |
| `nthu_p2p3_budget` / `nthu_p2p3_legal_repair` | Legal guard path | Smaller P2/P3 routing budgets, with legal repair when needed. |
| `nthu_edgecount_post` | Speed frontier | Edge-count prioritized post-processing and reroute pruning. |
| `nthu_cuda_score` | CUDA experiment | CUDA costed-maze / dogleg scoring hooks. |

`external/nthu-route-original` was kept unchanged.

## Fastest Guarded Result

Selection rule: if original has `overflow=0`, the optimized row must also have
`overflow=0` and `max_overflow=0`. If original already overflows, the fastest completed
optimized row is listed as an improvement/frontier row.

| Benchmark | Original s | Orig WL | Orig OF | Selected Strategy | Selected s | Sel WL | Sel OF / Max | Speedup |
|---|---:|---:|---:|---|---:|---:|---:|---:|
| adaptec1 | 441.963 | 5,363,235 | 0 | `nthu_p2p3_budget` | 279.999 | 9,429,701 | 0 / 0 | 1.58x |
| adaptec2 | 173.992 | 4,857,976 | 958,172 | `nthu_edgecount_post` | 52.005 | 9,059,483 | 866 / 8 | 3.35x |
| adaptec3 | 479.186 | 13,158,101 | 0 | `nthu_cuda_score` | 217.153 | 22,444,948 | 0 / 0 | 2.21x |
| adaptec4 | 130.667 | 12,207,270 | 0 | `nthu_edgecount_post` | 93.985 | 20,483,808 | 0 / 0 | 1.39x |
| adaptec5 | 1,240.592 | 15,535,357 | 0 | `nthu_fast_layer_repair` | 868.938 | 27,358,856 | 0 / 0 | 1.43x |
| bigblue1 | 1,206.307 | 5,575,865 | 0 | `nthu_fast_layer_repair` | 606.801 | 10,344,977 | 0 / 0 | 1.99x |
| bigblue2 | 1,020.139 | 7,886,236 | 1,928,338 | `nthu_edgecount_post` | 139.228 | 14,499,734 | 3,004 / 14 | 7.33x |
| bigblue3 | 907.876 | 12,282,111 | 1,724,140 | `nthu_edgecount_post` | 121.010 | 27,933,253 | 1,536 / 10 | 7.50x |
| newblue1 | 1,043.267 | 4,077,044 | 839,522 | `nthu_edgecount_post` | 44.254 | 7,801,498 | 2,368 / 12 | 23.57x |
| newblue2 | 76.516 | 7,595,602 | 0 | `nthu_cuda_score` | 43.382 | 14,140,283 | 0 / 0 | 1.76x |
| newblue5 | 2,296.878 | 21,540,842 | 3,427,158 | `nthu_edgecount_post` | 380.232 | 41,425,719 | 1,962 / 10 | 6.04x |
| newblue6 | 3,278.214 | 17,683,846 | 0 | `nthu_p2p3_legal_repair` | 1,033.382 | 30,913,365 | 0 / 0 | 3.17x |

Aggregate over the 12 rows:

- Original total time: `12295.597s`
- Fastest guarded total time: `3880.369s`
- Aggregate speedup: `3.17x`
- Original-legal guard: `7/7` original-legal benchmarks remain `overflow=0,max_overflow=0`.

## Score-Safe Portfolio

The fastest guarded router is legal where original is legal, but it increases wirelength
substantially, usually around `1.6x-1.9x` of original. If final score must stay very
close to original wirelength, use this conservative portfolio:

- For benchmarks where `true_original` is already legal, keep `true_original`.
- For benchmarks where `true_original` overflows, use the fastest optimized overflow
  reduction row.

This portfolio preserves original score exactly on all 7 original-legal cases, while
still improving the 5 original-overflow cases.

Aggregate:

- Score-safe total time: `7590.174s`
- Speedup vs original total time: `1.62x`
- Original-legal score regression: none, because those rows use original output.

## Legality And Correctness

- Fastest guarded table: every benchmark that was legal under original remained legal.
- On original-overflow cases, optimized strategies reduce overflow by orders of
  magnitude, but not always to zero.
- `newblue6` is legal under `nthu_p2p3_legal_repair`.
- CUDA dual-GPU tests did not improve single-testcase latency; current CUDA work should
  be treated as single-GPU only unless a future batched rerouter is implemented.

## Recommendation

Use two reported configurations:

1. `score-safe portfolio` for conservative grading claims.
2. `fastest guarded` for speedup/frontier claims.

Do not claim that the fastest guarded setting preserves wirelength quality; it preserves
legality on original-legal cases and gives a strong speed comparison.
