# Wirelength-Guard Speedup Report

Date: 2026-06-04
Branch: `vm-fastest-benchmark-guard`
Code commit: `69f3eb7`

## VM Run

Benchmarks were run only on the VM:

```text
/home/ubuntu/hpc-final-router/results/vm_wl_guard/runs/legal7_netguided_69f3eb7_20260604T042504Z
```

Environment: 16 vCPU VM, `MAX_ROUTER_CORES=12`, `PARALLEL_BENCH_JOBS=7`,
Apptainer container, `lab2-verifier.py`.  The run launches one single-threaded
router process per testcase, so legal cases are benchmarked concurrently across
cores.

`external/nthu-route-original` remained unchanged on both local and VM copies.

## Optimization Methods

Current optimization families tracked: 7.

| Family | Status |
| --- | --- |
| OpenMP analysis-kernel parallelism | Correct but low end-to-end impact. |
| Fast greedy layer assignment | Fast, but previous version inflated wirelength. |
| Net-guided fast greedy layer assignment | New in `69f3eb7`; keeps each net closer to one preferred layer. |
| P2/P3 routing budget tuning | Strong speed lever, may need repair for legality. |
| Conservative legal repair | Restores zero overflow on original-legal cases. |
| Edge-count post-processing / reroute pruning | Strong speed frontier, weaker legality coverage. |
| CUDA costed-maze / dogleg scoring | Useful on selected cases; dual GPU did not improve latency. |

## New Strategy

The new `NTHU_FAST_GREEDY_LAYER_NET_GUIDED=1` path changes fast layer assignment
from independent per-edge layer choice to a per-net preferred layer.  Each net first
scores candidate layers by projected demand and via preference, then individual
edges deviate only when needed to avoid overflow.  This keeps most edges of a net
on fewer layers, reducing via/wirelength inflation while preserving fast layer
runtime.

Two VM variants were benchmarked:

| Strategy | Purpose |
| --- | --- |
| `fast_layer_netguided_budget` | Faster routing budget; accepts speed when already legal. |
| `fast_layer_netguided_repair` | Conservative repair fallback for budget rows with overflow. |

## Legal7 Portfolio, WL <= 1.5x

Selection rule: only original-legal cases are considered here, selected rows must
have `overflow=0,max_overflow=0`, and selected wirelength must be at most `1.5x`
original.

| Benchmark | Selected strategy | Original s | Selected s | Speedup | WL ratio | OF / Max |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| adaptec1 | `fast_layer_netguided_budget` | 441.963 | 261.288 | 1.69x | 1.401 | 0 / 0 |
| adaptec3 | `fast_layer_netguided_budget` | 479.186 | 400.789 | 1.20x | 1.302 | 0 / 0 |
| adaptec4 | `fast_layer_netguided_budget` | 130.667 | 116.625 | 1.12x | 1.320 | 0 / 0 |
| adaptec5 | `fast_layer_netguided_repair` | 1240.592 | 854.320 | 1.45x | 1.350 | 0 / 0 |
| bigblue1 | `fast_layer_netguided_repair` | 1206.307 | 609.836 | 1.98x | 1.425 | 0 / 0 |
| newblue2 | `fast_layer_netguided_budget` | 76.516 | 54.345 | 1.41x | 1.417 | 0 / 0 |
| newblue6 | `fast_layer_netguided_repair` | 3278.214 | 1046.369 | 3.13x | 1.359 | 0 / 0 |

Aggregate over the 7 original-legal cases:

| Metric | Value |
| --- | ---: |
| Original total time | 6853.445s |
| Selected total time | 3343.573s |
| Speedup | 2.05x |
| Average WL ratio | 1.368 |
| Worst WL ratio | 1.425 |
| Legality | 7/7 zero overflow |

Compared with the previous fastest legal guarded portfolio on the same 7 cases:

| Portfolio | Speedup | Average WL ratio | Worst WL ratio |
| --- | ---: | ---: | ---: |
| Previous fastest guarded | 2.18x | 1.767 | 1.862 |
| New WL<=1.5 net-guided | 2.05x | 1.368 | 1.425 |

The new portfolio gives up about 6% relative speed versus the previous fastest
guarded legal portfolio, but substantially reduces wirelength inflation.

## 12-Case Note

For the full requested 12-case set, this run only optimized the 7 original-legal
cases and leaves the 5 original-overflow cases at their original rows in the
WL-threshold portfolio.  Under `WL<=1.5x`, the 12-case portfolio speedup is `1.40x`.
The existing fastest-guarded 12-case report remains the speed frontier, but it has
larger wirelength inflation.

## Recommendation

Use the `WL<=1.5 net-guided` portfolio for quality-sensitive claims: it keeps all
original-legal cases legal, keeps worst WL ratio under `1.43x`, and still reaches
`2.05x` aggregate speedup on the legal subset.
