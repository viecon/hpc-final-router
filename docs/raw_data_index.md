# Raw Data and Report Source Index

Date: 2026-06-06
Branch: `vm-fastest-benchmark-guard`

## Purpose

This file is the canonical entry point for raw evidence, historical experiment
notes, and synthesized reports.  It exists to avoid mixing results from different
implementation periods.

Repository convention after this cleanup:

- `docs/`: raw evidence, historical experiment notes, run context, result roots,
  and reproducibility notes.
- `reports/`: synthesized method summaries, performance interpretation, and
  presentation-ready conclusions.
- `reports/presentations/`: short decks grouped by performance, optimization
  method, and chronology/correctness.

The older `reports/*.md` files are indexed here instead of moved.  This keeps
existing links and commit history stable while making `docs/` the place to find
the full evidence map.

## Chronology Guard

Do not compare rows across these periods unless the denominator and strategy are
explicitly stated.

| Period | Main source files | Code / strategy state | Correct comparison scope |
| --- | --- | --- | --- |
| 2026-05-27 early Taiwania runs | `final_experiment_report.md`, `methods_and_results_summary.md`, `current_router_comparison_report.md` | Early NTHU source strategies: OpenMP kernels, fast layer, P2/P3 tuning, CUDA scoring, edge-count frontier. | Mostly adaptec1-3, 16-case matrix under Slurm walltime limits, and early fastest-guarded portfolios. |
| 2026-06-04 VM utilization and WL-guard runs | `optimization_versions_report.md`, `vm_multicore_optimization_log.md`, `vm_cuda_optimization_log.md`, `wirelength_guard_speedup_report.md`, `wl120_single_core_optimization_report.md`, `overall_adaptive_router_report.md` | VM-only profiling and strategy sweeps. Low-layer net-guided assignment and one-strategy adaptive repair were introduced. | VM-only legal7/requested12 comparisons; use these for utilization and WL<=1.2/WL<=1.5 claims. |
| 2026-06-05 final VM strategy reports | `../reports/vm_router_optimization_report.md`, `../reports/main_vs_current_deep_comparison.md`, `../reports/final_methods_wl_speed_research_log.md`, `../reports/bounded_length_reroute_probe.md`, `../reports/optimization_methods_commit_summary.md` | High-overflow adaptive P2 budget, strict maze negative results, layer-penalty probe, bounded-length probe. | Current one-strategy final family, same-CLI main comparison, and final rejected/accepted method accounting. |
| 2026-06-06 final writeup | `../reports/final_router_optimization_report_zh.md`, `../reports/presentations/*.md` | Synthesized from the earlier evidence. No new benchmark rows. | Use for oral presentation/writeup; trace raw numbers back to the dated files above. |

## Raw / Historical Evidence Files

### Baseline and Early Strategy Matrix

| File | What it contains | Use it for |
| --- | --- | --- |
| `final_experiment_report.md` | Early full report with original code flow, strategy descriptions, 16-case retest matrix, and best legal NTHU result on adaptec1-3. | Early source-level method evidence and code-flow explanation. |
| `methods_and_results_summary.md` | Short summary of early best legal NTHU rows and cross-router NCTU-GR comparison. | Quick early-result numbers for slides. |
| `current_router_comparison_report.md` | Fastest guarded portfolio from early VM matrix. | Speed frontier and score-safe portfolio caveats. |
| `bench16_retest_plan.md` | Planned 16-case retest matrix. | Understanding intended matrix coverage and timeout context. |
| `session_handoff.md` | State after early result cleanup. | Historical context and preserved result CSV list. |

### VM Utilization and Hardware Direction

| File | What it contains | Use it for |
| --- | --- | --- |
| `vm_multicore_optimization_log.md` | OpenMP utilization measurements and conflict-aware parallel reroute prototype results. | Evidence that CPU utilization issue is algorithmic, not thread launch/binding. |
| `vm_cuda_optimization_log.md` | Single/dual GPU utilization and CUDA profile counters. | Evidence that current CUDA work is too small and dual GPU does not improve latency. |
| `nthu_openmp_design.md` | Design notes for OpenMP kernels. | Implementation rationale for low-impact parallel scans. |
| `nthu_gpu_feasibility.md` | GPU feasibility notes. | Earlier CUDA direction context. |

### WL and Adaptive Repair Runs

| File | What it contains | Use it for |
| --- | --- | --- |
| `wirelength_guard_speedup_report.md` | Net-guided fast layer WL<=1.5 legal7 portfolio. | Quality-sensitive speedup with controlled WL. |
| `wl120_single_core_optimization_report.md` | WL<=1.2 legal7 portfolio and illegal speed frontier. | Showing the speed/legal/WL trade-off. |
| `overall_adaptive_router_report.md` | One overall strategy without testcase-name hardcoding. | Explaining adaptive repair logic and why speed target was not reached. |

### Final Synthesized Reports

These live in `reports/` because they interpret raw evidence rather than being
raw run logs. They are still indexed here so `docs/` is the full navigation root.

| File | What it contains | Use it for |
| --- | --- | --- |
| `../reports/vm_router_optimization_report.md` | High-overflow adaptive P2 budget results; legal7 and requested12 final-family numbers. | Current final-family speed/WL/correctness claim. |
| `../reports/main_vs_current_deep_comparison.md` | Same-CLI comparison against `origin/main`. | Explaining why current is faster and much more legal than main under the tested CLI. |
| `../reports/final_methods_wl_speed_research_log.md` | Method review, literature takeaways, and layer-penalty probe. | Literature-backed direction and negative layer-penalty result. |
| `../reports/bounded_length_reroute_probe.md` | Unsafe bounded rollback failure and safe bounded smoke result. | Bounded-length method diagnosis and rejection. |
| `../reports/optimization_methods_commit_summary.md` | Commit-to-method and method-family performance summary. | Tracking which commit/report produced each claim. |
| `../reports/final_router_optimization_report_zh.md` | Final Chinese report with pitfalls, methods, results, future work, issues, and literature. | Main writeup. |

## Presentation Decks

| File | Grouping | Purpose |
| --- | --- | --- |
| `../reports/presentations/performance_brief.md` | Performance and score quality | Shows speed/WL/correctness trade-offs and which result is defensible. |
| `../reports/presentations/optimization_methods_brief.md` | Optimization method | Explains each method, code-level intervention, and impact. |
| `../reports/presentations/timeline_correctness_brief.md` | Time and correctness | Prevents mixing results from different commits and clarifies accepted/rejected states. |

## Result Roots Mentioned by the Final Reports

These result directories are on the VM and may not be committed because raw route
outputs are large.

| Result root | Source report | Notes |
| --- | --- | --- |
| `/home/ubuntu/hpc-final-router/results/vm_final_guard/legal7_trigger_p2_20_9c10d52_20260605T012126Z` | `../reports/vm_router_optimization_report.md` | Legal7 guard for high-overflow strategy. |
| `/home/ubuntu/hpc-final-router/results/vm_high_p2_clean/clean_p2_24_hard3_9c10d52_20260605T013320Z` | `../reports/vm_router_optimization_report.md` | Hard-case P2=24 rerun. |
| `/home/ubuntu/hpc-final-router/results/vm_main_compare/main_vs_current_main12_6f44073_current_d1b7584_20260605T023037Z` | `../reports/main_vs_current_deep_comparison.md` | Same-CLI main/current comparison. |
| `/home/ubuntu/hpc-final-router/results/vm_literature_guided_wl_speed/20260605T040511Z_3ae6b79` | `../reports/final_methods_wl_speed_research_log.md` | Layer-penalty probe. |
| `/home/ubuntu/hpc-final-router/results/vm_bounded_length_reroute/20260605T044112Z_de271c9_full12` | `../reports/bounded_length_reroute_probe.md` | Unsafe bounded full12 and final recheck. |

## Current Best Numbers

Use these only as the latest one-strategy final-family summary. For older
portfolio/frontier claims, use the dated source reports above.

| Scope | Original s | Current s | Speedup | WL ratio | Correctness |
| --- | ---: | ---: | ---: | --- | --- |
| requested12 latest recheck | 12295.597 | 9501.285 | 1.294x | avg 1.158, worst 1.284 | 10/12 legal, total overflow 166 |
| requested12 earlier clean selected | 12295.597 | 9144.395 | 1.345x | avg 1.158, worst 1.284 | 10/12 legal, total overflow 166 |
| original-legal 7 latest recheck | 6853.445 | 4061.935 | 1.687x | avg 1.118, worst 1.151 | 7/7 legal |
| original-legal 7 earlier clean selected | 6853.445 | 3910.736 | 1.752x | avg 1.118, worst 1.151 | 7/7 legal |

## Rules for Future Edits

1. Add raw run logs, result roots, and reproducibility notes under `docs/`.
2. Add synthesized conclusions, score comparisons, and slides under `reports/`.
3. Always include date, commit, benchmark set, denominator, and whether a strategy
   is a portfolio, one-strategy router, or speed frontier.
4. Do not mix early Slurm 16-case matrix numbers with later VM requested12 final
   numbers without stating that they are different experiment periods.
