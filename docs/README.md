# Documentation Index

Last updated: 2026-06-06

This directory is now treated primarily as the raw-data and experiment-history
side of the project.  Synthesized conclusions, method comparisons, and
presentation-ready summaries live under `reports/`.

Start from `raw_data_index.md`; it maps each report to the dated experiment
period that produced it and prevents mixing rows from different implementation
stages.

## Read First

| File | Purpose |
| --- | --- |
| `raw_data_index.md` | Canonical map of raw evidence, report sources, result roots, chronology guards, and final presentation decks. |
| `final_experiment_report.md` | Complete report draft: experiment method, original NTHU flow, strategy-by-strategy changes, code snippets, and comparison tables. |
| `methods_and_results_summary.md` | Shorter result summary for slides or oral presentation. |
| `session_handoff.md` | Current project state after result cleanup; use this when resuming work. |
| `rerun_priority.md` | What to rerun if raw logs/results are required again. Current status: no rerun needed before preserving docs/source. |

## Synthesized Reports And Presentation Decks

The files below are outside `docs/` because they are interpreted summaries rather
than raw evidence. They are indexed here for navigation.

| File | Purpose |
| --- | --- |
| `../reports/final_router_optimization_report_zh.md` | Main Chinese report: pitfalls, optimization methods, WL/speed impact, future work, issues, literature. |
| `../reports/optimization_methods_commit_summary.md` | Method-family and commit-to-result summary. |
| `../reports/presentations/performance_brief.md` | Slide-style brief grouped by performance and WL/correctness trade-off. |
| `../reports/presentations/optimization_methods_brief.md` | Slide-style brief grouped by optimization method and code-level intervention. |
| `../reports/presentations/timeline_correctness_brief.md` | Slide-style brief grouped by chronology, final/rejected states, and correctness guard. |

## Experiment Notes

| File | Purpose |
| --- | --- |
| `bench16_retest_plan.md` | Original 16-case retest plan and selected strategies. |
| `nthu_gpu_feasibility.md` | GPU profiling, CUDA scorer results, and why end-to-end GPU gains are limited by sequential routing flow. |
| `nthu_openmp_design.md` | OpenMP design notes and why analysis-kernel parallelism gave only small end-to-end speedup. |
| `nthu_source_baselines.md` | Early source-baseline notes. |
| `taiwania_runbook.md` | Taiwania/Slurm/Apptainer command reference. |
| `report_outline.md` | Older outline. Keep as planning history; prefer `final_experiment_report.md` for current content. |

## Current Evidence Files

The raw per-run result directories may be incomplete after disk-quota cleanup. The
important small CSV evidence kept for the report is:

```text
results/bench16_strategy_catalog.csv
results/bench16_strategy_matrix_r2_summary.csv
results/bench16_strategy_matrix_r2_speedups.csv
results/bench16_strategy_matrix_r2_speedup_matrix.csv
results/method_speedups_summary.csv
results/cross_validation_checks.csv
results/real_baselines_summary.csv
results/real_baselines_adaptec123_summary.csv
```

Do not commit raw `results/**`, `logs/**`, `router.sif`, benchmarks, or build
directories. They are large and can recreate the disk-quota problem.
