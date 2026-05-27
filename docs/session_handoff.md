# HPC Final Router Session Handoff

Last updated: 2026-05-27

## Current Status

We are no longer actively chasing new runs. The current task is documentation
cleanup and preserving the project on GitHub.

The raw `results/` and `logs/` directories may be incomplete because disk quota was
hit and some outputs were cleared. The important aggregate evidence for the report is
still present:

```text
docs/final_experiment_report.md
docs/methods_and_results_summary.md
results/bench16_strategy_catalog.csv
results/bench16_strategy_matrix_r2_summary.csv
results/bench16_strategy_matrix_r2_speedups.csv
results/bench16_strategy_matrix_r2_speedup_matrix.csv
results/method_speedups_summary.csv
results/cross_validation_checks.csv
results/real_baselines_summary.csv
results/real_baselines_adaptec123_summary.csv
```

The priority is:

1. Keep docs/source/selected summary CSVs.
2. Put the repository on GitHub.
3. Rerun only if fresh raw logs or checker outputs are required.

## Main Result To Report

The strongest legal NTHU source-code claim is:

| Benchmark set | NTHU original | Best legal NTHU | Speedup | Overflow |
| --- | ---: | ---: | ---: | ---: |
| `adaptec1-3` | 981.939003s | 422.179091s | 2.325883x | 0 |

Best legal rows:

| Benchmark | Strategy | Runtime | Speedup | Overflow |
| --- | --- | ---: | ---: | ---: |
| `adaptec1` | P2/P3 budget tuning | 188.156013s | 2.118467x | 0 |
| `adaptec2` | P2 threshold tuning | 81.880970s | 1.958702x | 0 |
| `adaptec3` | CUDA candidate scoring + P2/P3 tuning | 152.142108s | 2.780007x | 0 |

Important caveat: the original stretch goal was `5x-10x` NTHU self-speedup.
That was not reached legally. Legal NTHU source-code speedup is about `2.33x`.
The `5x+` results belong either to NCTU-GR black-box comparison or illegal NTHU
runtime-frontier experiments with nonzero overflow.

## 16-Case Matrix State

The 16-case retest matrix used 6 NTHU strategies:

```text
nthu_original
nthu_openmp_t4
nthu_fast_layer
nthu_p2p3_budget
nthu_cuda_score
nthu_edgecount_post
```

Current aggregate state:

- 96 intended strategy/testcase combinations.
- 74 valid summary rows.
- 22 timeout/header-only rows.
- 0 missing rows in the aggregate accounting.

The compact matrix is in:

```text
results/bench16_strategy_matrix_r2_speedup_matrix.csv
```

Interpretation:

- `*` means the row completed but is illegal because `total_overflow > 0`.
- `timeout` means no valid summary under the walltime used by that run.
- `done, no baseline` means the strategy completed, but `nthu_original` timed
  out on that testcase, so speedup could not be computed.

## Strategy Summary

| Strategy | Result |
| --- | --- |
| NTHU original | Denominator for all source-code speedups. |
| OpenMP analysis kernels | Correct but small, about `1.009x` on `adaptec1-3`; bottleneck stayed sequential reroute. |
| Fast greedy layer assignment | Broadly useful legal acceleration, roughly `1.8x-2.1x` on `adaptec1-3` representative runs. |
| P2/P3 budget tuning | Best legal result for `adaptec1`; useful because it reduces expensive routing effort. |
| P2 threshold tuning | Best legal result for `adaptec2`. |
| CUDA candidate scoring | Standalone dogleg scorer reached `33x-38x`, but integrated legal NTHU result is `2.78x` on `adaptec3`. |
| Edge-count post-processing | Produces large runtime-frontier numbers but often illegal due to overflow. |
| NCTU-GR | Strong black-box baseline; useful for cross-router comparison, not an NTHU source-code speedup. |

## Slurm Policy Note

The latest course notice says the temporary Slurm policy is:

```text
max running jobs per group: 1
resource cap: 2 nodes / 64 cores / 16 GPUs
max walltime: 1 hour
```

A quick 1-hour submission test reached `PENDING` with reason
`QOSGrpJobsLimit`, not a walltime error. That means 1-hour jobs appear accepted,
but the group job slot may be occupied by a teammate. Do not launch heavy reruns
until the repository is preserved.

## GitHub Preservation

The `.gitignore` is set up to keep large/generated files out:

```text
logs/
results/** except selected summary CSVs
*.sif
benchmarks/
build*/
external/nctu-gr/
external/nthu-route/build*/
external/nthu-route/adaptec*.gr
external/nthu-route-original/build*/
external/nthu-route-original/adaptec*.gr
```

GitHub push still needs a remote repository URL because `gh` is not installed on
this machine and the directory was not originally a git repository.

Suggested next command sequence:

```bash
git init
git checkout -b main
git add .
git status --short
git commit -m "Add routing acceleration report and reproducible scripts"
git remote add origin <github-repo-url>
git push -u origin main
```

Check `git status --ignored` before committing if anything unexpectedly large is
staged.
