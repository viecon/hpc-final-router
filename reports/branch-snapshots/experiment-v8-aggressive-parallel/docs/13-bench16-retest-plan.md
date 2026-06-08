# ISPD08 16-Case Retest Plan

Last updated: 2026-05-22

## Requirement Mapping

User request:

1. List existing strategies.
2. Retest the strategies that include algorithmic improvement or optimization on all
   16 ISPD08 testcases.

## Existing Strategies

| Strategy | Type | 16-case retest? | Reason |
| --- | --- | --- | --- |
| `nthu_original` | baseline | yes | Required denominator for per-benchmark speedup. |
| `nthu_openmp_t4` | implementation optimization | yes | Parallelizes NTHU analysis/counter kernels. |
| `nthu_fast_layer` | algorithm optimization | yes | Replaces slower layer assignment with fast greedy layer assignment. |
| `nthu_p2p3_budget` | algorithm/parameter optimization | yes | Changes P2/P3 routing effort, thresholds, and search boxes. |
| `nthu_cuda_score` | GPU algorithm optimization | yes | Uses CUDA-assisted costed maze/candidate scoring. |
| `nthu_edgecount_post` | algorithm optimization | yes | Changes post-processing candidate priority to edge-count ordering. |
| `nctu_default` | cross-router baseline | no | Black-box router comparison, not NTHU algorithm improvement. |
| `nctu_tuned` | cross-router tuning | no | Black-box parameter tuning, not NTHU source-code optimization. |
| targeted Python repairs | external postprocess | no | Runtime accounting and integration are not comparable to router-internal strategies. |

The exact catalog is also in:

```text
results/bench16_strategy_catalog.csv
```

## Slurm Plan

QoS constraints as announced:

```text
max running jobs per user: 1
resource cap: 2 nodes / 64 cores / 16 GPUs
max walltime: 1 hour
```

Implementation:

- Submit one small Slurm job per `(strategy, testcase)`.
- Chain all jobs with `--dependency=afterany:<previous_jobid>`, so only one job can
  run at a time.
- Each job has a 1-hour walltime.
- Final aggregation job runs after the last testcase and writes:

```text
results/bench16_strategy_matrix_summary.csv
results/bench16_strategy_matrix_speedups.csv
```

Scripts:

```text
scripts/run_bench16_strategy_one.sh
scripts/submit_bench16_strategy_matrix.sh
scripts/watch_submit_bench16_strategy_matrix.sh
scripts/aggregate_bench16_strategy_matrix.py
```

Because the active QoS also appears to limit submitted jobs, the current execution
uses the watcher script instead of submitting the full dependency chain at once:

```text
TAG=bench16_strategy_matrix_r1 \
  nohup bash scripts/watch_submit_bench16_strategy_matrix.sh \
  > logs/watch_submit_bench16_strategy_matrix_r1.nohup 2>&1 &
```
