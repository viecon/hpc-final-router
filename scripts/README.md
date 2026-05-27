# Scripts Index

This directory now keeps only reusable experiment drivers, active submit scripts,
and small utility scripts at top level.

## Active Submit Scripts

Current fast greedy layer / CUDA layer-assignment path:

```text
submit_nthu_fast_greedy_layer_a1.sh
submit_nthu_fast_greedy_layer_a1_high_threshold.sh
submit_nthu_fast_greedy_layer_a1_threshold_sweep.sh
submit_nthu_fast_greedy_layer_a2.sh
submit_nthu_fast_greedy_layer_a2_conservative.sh
submit_nthu_fast_greedy_layer_a2_openmp.sh
submit_nthu_fast_greedy_layer_a3.sh
submit_nthu_fast_greedy_layer_continuity_a1.sh
submit_nthu_fast_greedy_layer_continuity_a2.sh
submit_nthu_fast_greedy_layer_continuity_a3.sh
submit_nthu_cuda_fast_greedy_layer_a3.sh
submit_nthu_cuda_fast_greedy_layer_a3_score_sweep.sh
submit_nthu_cuda_fast_greedy_layer_continuity_a3.sh
```

Hook / retry helpers:

```text
submit_afterany_hook.sh
continue_after_fast_continuity_a3.sh
retry_submit_until_success.sh
watch_job_then_run.sh
```

## Core Utilities

```text
run_nthu_ispd08.sh
run_nthu_adaptive_p2.sh
run_nthu_variant_sweep.sh
run_nctugr_ispd08.sh
evaluate_route.py
compare_variant_summary.py
rank_router_results.py
refresh_indexes.sh
plot.py
summarize_gpu_real_candidates.py
```

## Archive

2026-05-06 cleanup moved one-off generated submit scripts out of the top level:

```text
scripts/archive/oneoff_submit_20260506/
```

It contains 106 old `submit_*.sh` files from earlier sweeps. They are not deleted,
only archived.

Python bytecode cache files were also moved out of the top level:

```text
scripts/archive/pycache_20260506/
```

When adding new experiment scripts, keep top-level scripts reusable. Put abandoned
one-off sweep launchers in an archive folder once their results have been summarized.
