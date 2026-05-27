# Documentation Index

Last updated: 2026-05-27

This directory now has two kinds of notes:

- Final-facing report material: use these for the term-project writeup and slides.
- Working notes: keep these for reproducibility, reruns, and future experiments.

## Read First

| File | Purpose |
| --- | --- |
| `final_experiment_report.md` | Complete report draft: experiment method, original NTHU flow, strategy-by-strategy changes, code snippets, and comparison tables. |
| `methods_and_results_summary.md` | Shorter result summary for slides or oral presentation. |
| `session_handoff.md` | Current project state after result cleanup; use this when resuming work. |
| `rerun_priority.md` | What to rerun if raw logs/results are required again. Current status: no rerun needed before preserving docs/source. |

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
