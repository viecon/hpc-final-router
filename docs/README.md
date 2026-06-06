# Documentation Index

Last updated: 2026-06-06

This directory is now treated primarily as the raw-data and experiment-history
side of the project.  Synthesized conclusions, method comparisons, and
presentation-ready summaries live under `reports/`.

Start from `../reports/presentations/00-start-here.md` if you are building
slides. Start from `00-evidence-index.md` if you are checking raw evidence or
where a result came from.

## Presentation Reading Order

| Order | File | Purpose |
| ---: | --- | --- |
| 1 | `../reports/presentations/00-start-here.md` | Shortest path for preparing slides and backup material. |
| 2 | `../reports/presentations/01-performance-and-score.md` | Headline speed, WL, overflow, and legality claims. |
| 3 | `../reports/presentations/02-optimization-methods.md` | What each optimization did and why it helped or failed. |
| 4 | `../reports/presentations/03-timeline-and-correctness.md` | Which results belong to which implementation period. |
| 5 | `../reports/01-final-router-optimization-zh.md` | Full report for detailed explanation and backup slides. |
| 6 | `00-evidence-index.md` | Raw-data and result-root index for verification. |

## Naming Convention

| Prefix | Meaning |
| --- | --- |
| `docs/00-*` | Raw evidence index and source map. |
| `docs/10-*` | Early source/Slurm-era experiment notes. |
| `docs/20-*` | VM experiment, WL, multicore, and CUDA logs. |
| `docs/30-*` | Design notes and source baselines. |
| `docs/40-*` | Runbooks and rerun plans. |
| `docs/90-*` | Old planning material. |
| `reports/01-*` | Final synthesized report. |
| `reports/02-*` to `06-*` | Supporting method, comparison, and probe reports. |
| `reports/presentations/00-*` to `03-*` | Slide-oriented briefs. |

## Read First For Evidence

| File | Purpose |
| --- | --- |
| `00-evidence-index.md` | Canonical map of raw evidence, report sources, result roots, chronology guards, and final presentation decks. |
| `10-early-source-strategy-report.md` | Complete report draft: experiment method, original NTHU flow, strategy-by-strategy changes, code snippets, and comparison tables. |
| `11-early-results-summary.md` | Shorter result summary for slides or oral presentation. |
| `14-session-handoff-early-cleanup.md` | Current project state after result cleanup; use this when resuming work. |
| `41-rerun-priority.md` | What to rerun if raw logs/results are required again. Current status: no rerun needed before preserving docs/source. |

## Synthesized Reports And Presentation Decks

The files below are outside `docs/` because they are interpreted summaries rather
than raw evidence. They are indexed here for navigation.

| File | Purpose |
| --- | --- |
| `../reports/01-final-router-optimization-zh.md` | Main Chinese report: pitfalls, optimization methods, WL/speed impact, future work, issues, literature. |
| `../reports/02-methods-by-commit-and-result.md` | Method-family and commit-to-result summary. |
| `../reports/presentations/00-start-here.md` | Slide preparation entry point. |
| `../reports/presentations/01-performance-and-score.md` | Slide-style brief grouped by performance and WL/correctness trade-off. |
| `../reports/presentations/02-optimization-methods.md` | Slide-style brief grouped by optimization method and code-level intervention. |
| `../reports/presentations/03-timeline-and-correctness.md` | Slide-style brief grouped by chronology, final/rejected states, and correctness guard. |

## Experiment Notes

| File | Purpose |
| --- | --- |
| `13-bench16-retest-plan.md` | Original 16-case retest plan and selected strategies. |
| `32-gpu-feasibility-notes.md` | GPU profiling, CUDA scorer results, and why end-to-end GPU gains are limited by sequential routing flow. |
| `31-openmp-design-notes.md` | OpenMP design notes and why analysis-kernel parallelism gave only small end-to-end speedup. |
| `33-source-baselines.md` | Early source-baseline notes. |
| `40-taiwania-runbook.md` | Taiwania/Slurm/Apptainer command reference. |
| `90-old-report-outline.md` | Older outline. Keep as planning history; prefer `10-early-source-strategy-report.md` for current content. |

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
