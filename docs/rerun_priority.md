# Rerun Priority After Disk Quota Cleanup

Last updated: 2026-05-27

## Current Situation

The raw result directories and logs may be incomplete after disk cleanup, but the
important final report evidence is still present:

- `docs/final_experiment_report.md`
- `results/bench16_strategy_matrix_r2_summary.csv`
- `results/bench16_strategy_matrix_r2_speedups.csv`
- `results/bench16_strategy_matrix_r2_speedup_matrix.csv`
- `results/method_speedups_summary.csv`
- `results/cross_validation_checks.csv`
- `results/bench16_strategy_catalog.csv`

Therefore, no urgent rerun is required just to preserve the current report.
Reruns are only needed if we want fresh raw `.out/.eval/.log` evidence or if the
TA requires newly generated outputs.

## Slurm Policy Check

As of 2026-05-27, a 1-hour GPU job is accepted by Slurm. The test job reached
`PENDING` with reason `QOSGrpJobsLimit`, not `QOSMaxWallDurationPerJobLimit`.
That means the walltime policy is usable, but the group can only have one
running job at a time.

## Priority 0: Preserve Evidence

Do this before any heavy rerun:

1. Commit source, scripts, docs, and selected summary CSVs to git.
2. Do not commit raw `results/**`, `logs/**`, `router.sif`, benchmarks, or build
   directories.
3. Keep final report tables backed by the selected CSV files above.

## Priority 1: Minimal Final-Claim Rerun

Rerun only the rows needed for the main legal NTHU claim:

| Claim row | Why rerun |
| --- | --- |
| NTHU original on `adaptec1-3` | Denominator for final `2.325883x` claim. |
| Best legal NTHU on `adaptec1` | P2/P3 budget tuning, legal 2.118x result. |
| Best legal NTHU on `adaptec2` | P2 threshold tuning, legal 1.959x result. |
| Best legal NTHU on `adaptec3` | CUDA-assisted scoring, legal 2.780x result. |

This is the smallest rerun set that supports the final source-code speedup
claim. It is more valuable than rerunning all 16 cases.

## Priority 2: Cross-Router Baseline Rerun

Rerun NCTU-GR default/tuned on `adaptec1-3` if the report needs fresh evidence
for the `5.073298x` black-box comparison. This is not part of the NTHU
source-code claim, but it strengthens the baseline/cross-testing section.

## Priority 3: 16-Case Matrix Rerun

Only rerun the full matrix if we need a fresh full benchmark table:

- 16 benchmarks
- 6 NTHU strategies
- 96 jobs total, submitted serially by watcher

Use a new tag such as `bench16_strategy_matrix_r3` so the old `r2` CSV evidence
is not overwritten.

Suggested command:

```bash
TAG=bench16_strategy_matrix_r3 \
TIME_LIMIT=0-01:00:00 \
ACCOUNT=ACD115058 \
QOS=contest_v100 \
PARTITION=nycugpu_queue \
CPUS=4 \
GPUS=1 \
MEM=64G \
INTERVAL_SECONDS=60 \
bash scripts/watch_submit_bench16_strategy_matrix.sh
```

Because the current policy allows only one running job per group, this will take
a long time. Watch disk usage and keep only aggregate CSVs if quota becomes tight.

## Priority 4: Former Timeout Cases

If 1-hour jobs are stable, rerun the 22 timeout/header-only rows from the `r2`
matrix. This can improve the completeness of the 16-case comparison without
rerunning all 96 combinations.

The old timeout rows are listed in the report section "16-case speedup matrix"
and can be reconstructed from `results/bench16_strategy_matrix_r2_speedup_matrix.csv`.
