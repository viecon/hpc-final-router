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

The synthesized reports stay under `reports/` instead of being moved into
`docs/`.  This keeps `docs/` as the evidence map while making the final reports
and presentation decks easier to find by prefix.

Filename prefixes after the 2026-06-06 cleanup:

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

## Chronology Guard

Do not compare rows across these periods unless the denominator and strategy are
explicitly stated.

| Period | Main source files | Code / strategy state | Correct comparison scope |
| --- | --- | --- | --- |
| 2026-05-27 early Taiwania runs | `10-early-source-strategy-report.md`, `11-early-results-summary.md`, `12-early-vm-speed-frontier.md` | Early NTHU source strategies: OpenMP kernels, fast layer, P2/P3 tuning, CUDA scoring, edge-count frontier. | Mostly adaptec1-3, 16-case matrix under Slurm walltime limits, and early fastest-guarded portfolios. |
| 2026-06-04 VM utilization and WL-guard runs | `20-vm-optimization-version-matrix.md`, `21-vm-multicore-utilization-log.md`, `22-vm-cuda-utilization-log.md`, `23-wl-guard-speedup.md`, `24-wl120-single-core-results.md`, `25-overall-adaptive-router-results.md` | VM-only profiling and strategy sweeps. Low-layer net-guided assignment and one-strategy adaptive repair were introduced. | VM-only legal7/requested12 comparisons; use these for utilization and WL<=1.2/WL<=1.5 claims. |
| 2026-06-05 final VM strategy reports | `../reports/03-final-vm-strategy-results.md`, `../reports/04-main-vs-final-router-comparison.md`, `../reports/05-wl-speed-literature-and-probes.md`, `../reports/06-bounded-length-reroute-probe.md`, `../reports/02-methods-by-commit-and-result.md` | High-overflow adaptive P2 budget, strict maze negative results, layer-penalty probe, bounded-length probe. | Current one-strategy final family, same-CLI main comparison, and final rejected/accepted method accounting. |
| 2026-06-06 final writeup | `../reports/01-final-router-optimization-zh.md`, `../reports/presentations/*.md` | Synthesized from the earlier evidence. No new benchmark rows. | Use for oral presentation/writeup; trace raw numbers back to the dated files above. |
| 2026-06-06 two-stage parallel reroute experiment | `26-two-stage-parallel-reroute-experiment.md` | Separate branch `experiment-two-stage-parallel-reroute`; proposal/commit split for reroute parallelization. | Experimental only. Compare only against same-branch runs with and without `NTHU_TWO_STAGE_PARALLEL_REROUTE=1`. |
| 2026-06-06 transactional virtual-ripup experiment | `../reports/08-transactional-reroute-technical-comparison.md` | Separate branch `experiment-transactional-virtual-ripup`; preserves NTHU-Route algorithm while adding transaction-local virtual rip-up and deterministic rollback commit. | Design/implementation note until VM build and benchmark rows are recorded. Compare only against same-runner transactional wave16 and original NTHU rows. |

## Raw / Historical Evidence Files

### Baseline and Early Strategy Matrix

| File | What it contains | Use it for |
| --- | --- | --- |
| `10-early-source-strategy-report.md` | Early full report with original code flow, strategy descriptions, 16-case retest matrix, and best legal NTHU result on adaptec1-3. | Early source-level method evidence and code-flow explanation. |
| `11-early-results-summary.md` | Short summary of early best legal NTHU rows and cross-router NCTU-GR comparison. | Quick early-result numbers for slides. |
| `12-early-vm-speed-frontier.md` | Fastest guarded portfolio from early VM matrix. | Speed frontier and score-safe portfolio caveats. |
| `13-bench16-retest-plan.md` | Planned 16-case retest matrix. | Understanding intended matrix coverage and timeout context. |
| `14-session-handoff-early-cleanup.md` | State after early result cleanup. | Historical context and preserved result CSV list. |

### VM Utilization and Hardware Direction

| File | What it contains | Use it for |
| --- | --- | --- |
| `21-vm-multicore-utilization-log.md` | OpenMP utilization measurements and conflict-aware parallel reroute prototype results. | Evidence that CPU utilization issue is algorithmic, not thread launch/binding. |
| `22-vm-cuda-utilization-log.md` | Single/dual GPU utilization and CUDA profile counters. | Evidence that current CUDA work is too small and dual GPU does not improve latency. |
| `31-openmp-design-notes.md` | Design notes for OpenMP kernels. | Implementation rationale for low-impact parallel scans. |
| `32-gpu-feasibility-notes.md` | GPU feasibility notes. | Earlier CUDA direction context. |

### WL and Adaptive Repair Runs

| File | What it contains | Use it for |
| --- | --- | --- |
| `23-wl-guard-speedup.md` | Net-guided fast layer WL<=1.5 legal7 portfolio. | Quality-sensitive speedup with controlled WL. |
| `24-wl120-single-core-results.md` | WL<=1.2 legal7 portfolio and illegal speed frontier. | Showing the speed/legal/WL trade-off. |
| `25-overall-adaptive-router-results.md` | One overall strategy without testcase-name hardcoding. | Explaining adaptive repair logic and why speed target was not reached. |
| `26-two-stage-parallel-reroute-experiment.md` | Branch-specific two-stage parallel reroute experiment. | Testing whether proposal/serial-commit split improves multicore utilization without unsafe concurrent congestion updates. |

### Final Synthesized Reports

These live in `reports/` because they interpret raw evidence rather than being
raw run logs. They are still indexed here so `docs/` is the full navigation root.

| File | What it contains | Use it for |
| --- | --- | --- |
| `../reports/03-final-vm-strategy-results.md` | High-overflow adaptive P2 budget results; legal7 and requested12 final-family numbers. | Current final-family speed/WL/correctness claim. |
| `../reports/04-main-vs-final-router-comparison.md` | Same-CLI comparison against `origin/main`. | Explaining why current is faster and much more legal than main under the tested CLI. |
| `../reports/05-wl-speed-literature-and-probes.md` | Method review, literature takeaways, and layer-penalty probe. | Literature-backed direction and negative layer-penalty result. |
| `../reports/06-bounded-length-reroute-probe.md` | Unsafe bounded rollback failure and safe bounded smoke result. | Bounded-length method diagnosis and rejection. |
| `../reports/02-methods-by-commit-and-result.md` | Commit-to-method and method-family performance summary. | Tracking which commit/report produced each claim. |
| `../reports/01-final-router-optimization-zh.md` | Final Chinese report with pitfalls, methods, results, future work, issues, and literature. | Main writeup. |
| `../reports/07-scoring-methodology.md` | Defines legal scoring policy. | Use before quoting speedups: one config, fixed set, total-time primary score, geomean secondary. |
| `../reports/08-transactional-reroute-technical-comparison.md` | Paper-to-code comparison for the transactional virtual-ripup branch. | Explaining why the new parallelization keeps the NTHU algorithm and only changes synchronization semantics. |

## Presentation Decks

| File | Grouping | Purpose |
| --- | --- | --- |
| `../reports/presentations/00-start-here.md` | Presentation entry point | Gives the recommended reading order for slide preparation. |
| `../reports/presentations/01-performance-and-score.md` | Performance and score quality | Shows speed/WL/correctness trade-offs and which result is defensible. |
| `../reports/presentations/02-optimization-methods.md` | Optimization method | Explains each method, code-level intervention, and impact. |
| `../reports/presentations/03-timeline-and-correctness.md` | Time and correctness | Prevents mixing results from different commits and clarifies accepted/rejected states. |

## Result Roots Mentioned by the Final Reports

These result directories are on the VM and may not be committed because raw route
outputs are large.

| Result root | Source report | Notes |
| --- | --- | --- |
| `/home/ubuntu/hpc-final-router/results/vm_final_guard/legal7_trigger_p2_20_9c10d52_20260605T012126Z` | `../reports/03-final-vm-strategy-results.md` | Legal7 guard for high-overflow strategy. |
| `/home/ubuntu/hpc-final-router/results/vm_high_p2_clean/clean_p2_24_hard3_9c10d52_20260605T013320Z` | `../reports/03-final-vm-strategy-results.md` | Hard-case P2=24 rerun. |
| `/home/ubuntu/hpc-final-router/results/vm_main_compare/main_vs_current_main12_6f44073_current_d1b7584_20260605T023037Z` | `../reports/04-main-vs-final-router-comparison.md` | Same-CLI main/current comparison. |
| `/home/ubuntu/hpc-final-router/results/vm_literature_guided_wl_speed/20260605T040511Z_3ae6b79` | `../reports/05-wl-speed-literature-and-probes.md` | Layer-penalty probe. |
| `/home/ubuntu/hpc-final-router/results/vm_bounded_length_reroute/20260605T044112Z_de271c9_full12` | `../reports/06-bounded-length-reroute-probe.md` | Unsafe bounded full12 and final recheck. |

## Current One-Config Numbers

Use these only as one-strategy final-family summaries. Older portfolio/frontier
rows are raw diagnostic evidence, not final answers.

| Scope | Original s | Current s | Speedup | WL ratio | Correctness |
| --- | ---: | ---: | ---: | --- | --- |
| requested12 latest recheck | 12295.597 | 9501.285 | 1.294x | avg 1.158, worst 1.284 | 10/12 legal, total overflow 166 |
| original-legal 7 latest recheck | 6853.445 | 4061.935 | 1.687x | avg 1.118, worst 1.151 | 7/7 legal |

## Rules for Future Edits

1. Add raw run logs, result roots, and reproducibility notes under `docs/`.
2. Add synthesized conclusions, score comparisons, and slides under `reports/`.
3. Always include date, commit, benchmark set, denominator, and routing config.
   Final score rows must be one config over a fixed set. Portfolio/frontier rows
   are diagnostics only.
4. Do not mix early Slurm 16-case matrix numbers with later VM requested12 final
   numbers without stating that they are different experiment periods.
