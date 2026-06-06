# Performance Brief

Date: 2026-06-06

## Slide 1 - Goal

Explain performance by separating three result types:

- legal one-strategy final family,
- quality-sensitive legal portfolios,
- runtime frontier rows that are fast but illegal or high-WL.

This avoids mixing early portfolio experiments with the final single-strategy
router.

## Slide 2 - Current Defensible One-Strategy Result

| Scope | Original s | Current s | Speedup | WL ratio | Correctness |
| --- | ---: | ---: | ---: | --- | --- |
| requested12 latest recheck | 12295.597 | 9501.285 | 1.294x | avg 1.158, worst 1.284 | 10/12 legal, overflow 166 |
| requested12 earlier clean run | 12295.597 | 9144.395 | 1.345x | avg 1.158, worst 1.284 | 10/12 legal, overflow 166 |
| original-legal 7 latest recheck | 6853.445 | 4061.935 | 1.687x | avg 1.118, worst 1.151 | 7/7 legal |
| original-legal 7 earlier clean run | 6853.445 | 3910.736 | 1.752x | avg 1.118, worst 1.151 | 7/7 legal |

Takeaway: the final-family strategy is not the fastest possible result, but it
keeps every original-legal case legal and has controlled WL.

## Slide 3 - Main vs Current Under Same CLI

Source: `../main_vs_current_deep_comparison.md`

| Metric | `main` 6f44073 | Current d1b7584 |
| --- | ---: | ---: |
| Total seconds | 16441.272 | 9804.449 |
| Speedup | 1.000x | 1.677x |
| Legal rows | 4/12 | 10/12 |
| Total overflow | 20851542 | 166 |
| Average current/main WL ratio | 1.000 | 1.200 |
| Worst current/main WL ratio | 1.000 | 1.399 |

Takeaway: current is faster and much more legal than same-CLI main, even though
WL increases.

## Slide 4 - WL-Sensitive Legal Results

Source: `../../docs/wl120_single_core_optimization_report.md`

| Portfolio | Scope | Speedup | Avg WL | Worst WL | Correctness |
| --- | --- | ---: | ---: | ---: | --- |
| WL<=1.5 net-guided | original-legal 7 | 2.05x | 1.368 | 1.425 | 7/7 legal |
| WL<=1.2 low-layer | original-legal 7 | 1.961x | 1.125 | 1.163 | 7/7 legal |
| WL<=1.2 speed frontier | original-legal 7 | 3.585x | 1.138 | within 1.2 | illegal, overflow 13642 |

Takeaway: 2.8x to 3.2x is reachable only after weakening repair; legality is
the blocker.

## Slide 5 - Speed Frontier

Source: `../../docs/current_router_comparison_report.md`,
`../../docs/optimization_versions_report.md`

| Strategy | Scope | Speedup | WL | Correctness |
| --- | --- | ---: | --- | --- |
| fastest guarded portfolio | requested12 | 3.17x | original-legal avg/worst 1.767/1.862 | original-legal 7/7, hard cases residual overflow |
| edge-count post | requested12 | 5.38x | often 1.8x+ | legal coverage about 2/12 |
| edge-count post | 16-case matrix | median 4.331x | high / case-dependent | many illegal rows |

Takeaway: pruning post-processing can produce large speedups, but not a valid
final legal router.

## Slide 6 - Negative Hardware Results

| Direction | Result | Interpretation |
| --- | --- | --- |
| OpenMP scans | requested12 about 1.03x | correct but not on critical path |
| 12-thread OpenMP newblue2 | 63.587s vs 65.647s, avg CPU 103% | threads exist; mutation loop remains serial |
| parallel reroute prototype | newblue2 best 80.255s vs default 65.739s | higher CPU but more iterations/fallback |
| CUDA single/dual GPU | A3 about 191-200s, GPU avg util <0.2% | GPU work too small and fragmented |

Takeaway: hardware parallelism needs algorithmic batching; simply enabling more
threads/devices is not enough.

## Slide 7 - Final Performance Message

Use this wording:

> The final one-strategy router improves runtime by about 1.3x on requested12
> and 1.7x on original-legal cases, while preserving all original-legal
> benchmarks and keeping WL around 1.16x average.  Faster frontiers exist, but
> they either inflate WL too much or leave overflow.

Raw evidence:

- `../../docs/raw_data_index.md`
- `../optimization_methods_commit_summary.md`
- `../final_router_optimization_report_zh.md`
