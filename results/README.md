# Results Index

This directory keeps raw router outputs, verifier outputs, summaries, plots, and
lightweight indexes. Do not delete raw per-run directories until the final report is
frozen; many summary rows point to their `.out`, `.log`, `.eval`, and
`.metrics.json` files.

## Current Best All-Legal NTHU Result

Baseline:

```text
Original NTHU adaptec1+2+3 total: 981.939003s
```

Current best legal combination:

```text
adaptec1:
  router: nthu_a1_th1800_p2max6_p3box66_122
  summary: nthu_a1_p2max6_p3box_narrow2_summary.csv
  runtime: 188.156013s
  overflow: 0

adaptec2:
  router: nthu_p2_box5_5_th240
  summary: nthu_p2_adaptec2_threshold2_summary.csv
  runtime: 81.880970s
  overflow: 0

adaptec3:
  router: nthu_cuda_a3_step8_p2max4_box35_50
  summary: nthu_cuda_a3_p2max_p3box_sweep_summary.csv
  runtime: 152.142108s
  overflow: 0

Total: 422.179091s
Speedup vs original NTHU: 2.3259x
```

This is still below the project stretch target of `5x-10x`, but it is the best
verified all-legal NTHU acceleration available in this workspace as of
2026-05-14.

## Start Here

```text
real_baselines_summary.csv
nthu_bigblue1_self_probe_summary.csv
nthu_a1_p2max6_p3box_narrow2_summary.csv
nthu_cuda_a3_p2max_p3box_sweep_summary.csv
nthu_b1_second_p3_selector_probe_summary.csv
nthu_b1_second_p3_fine_gate_summary.csv
nctu_wl50_p2m2_maze20_greedy_bigblue_summary.csv
method_speedups_summary.csv
cross_validation_checks.csv
nthu_b1_rscore_p3box_micro_summary.csv
nthu_fast_greedy_layer_a1_summary.csv
nthu_p2_adaptec2_threshold2_summary.csv
nthu_cuda_fast_greedy_layer_a3_summary.csv
nthu_fast_greedy_layer_a3_summary.csv
nthu_fast_greedy_layer_a1_threshold_sweep_summary.csv
nthu_fast_greedy_layer_a2_conservative_summary.csv
nthu_fast_greedy_layer_a2_openmp_summary.csv
nthu_cuda_fast_greedy_layer_a3_score_sweep_summary.csv
large_outputs_20260506.csv
all_summaries_catalog.csv
legal_runtime_ranking.csv
manifest.csv
```

- `real_baselines_summary.csv`: original NTHU, NTHU OpenMP, and NCTU-GR baseline
  runs on `adaptec1-3`.
- `nthu_bigblue1_self_probe_summary.csv`: legal NTHU original baseline for
  `bigblue1`; this is the current self-speedup target case.
- `nthu_a1_p2max6_p3box_narrow2_summary.csv`: current best legal NTHU `adaptec1`
  result.
- `nthu_cuda_a3_p2max_p3box_sweep_summary.csv`: current best legal NTHU `adaptec3`
  result.
- `nthu_b1_second_p3_selector_probe_summary.csv`: current best time-legal but still
  illegal `bigblue1` NTHU frontier.
- `method_speedups_summary.csv`: report-ready method summary with speedups,
  legality, and source files.
- `cross_validation_checks.csv`: sanity checks for key reported rows.
- `nthu_b1_rscore_p3box_micro_summary.csv`: current best time-legal B1 frontier
  around the 5x threshold; all variants are still illegal because overflow is
  nonzero.
- `nthu_fast_greedy_layer_a1_summary.csv`: current best `adaptec1`.
- `nthu_p2_adaptec2_threshold2_summary.csv`: current best `adaptec2`.
- `nthu_cuda_fast_greedy_layer_a3_summary.csv`: current best `adaptec3`, using CUDA
  maze scoring plus fast greedy layer assignment.
- `nthu_fast_greedy_layer_a3_summary.csv`: CPU-only fast greedy layer `adaptec3`
  comparison.
- `nthu_fast_greedy_layer_a1_threshold_sweep_summary.csv`: high-threshold A1 probes;
  legal but slower than the current A1 best.
- `nthu_fast_greedy_layer_a2_conservative_summary.csv` and
  `nthu_fast_greedy_layer_a2_openmp_summary.csv`: A2 fast-layer probes; legal
  variants did not beat the older `th240` result.
- `nthu_cuda_fast_greedy_layer_a3_score_sweep_summary.csv`: aggressive A3 score
  sweep; score25 was illegal.
- `large_outputs_20260506.csv`: top large `.out` files by size. These are indexed
  instead of compressed/deleted because they are verifier evidence.
- `all_summaries_catalog.csv`, `legal_runtime_ranking.csv`, `manifest.csv`:
  generated indexes.

## GPU Evidence

Standalone GPU candidate scoring had strong local speedups:

```text
dogleg-style scorer:
  adaptec1: 35.27x
  adaptec2: 38.07x
  adaptec3: 33.82x
```

End-to-end NTHU speedup is much smaller because full routing time is dominated by
serial phases, output generation, verification, and data movement. The useful GPU
path so far is selective: CUDA helps score/rank expensive maze or dogleg choices,
then CPU/NTHU still performs most of the routing flow.

## Current B1 Frontier

`bigblue1` is the most promising NTHU self-speedup target currently indexed:

```text
NTHU original legal baseline: 873.105913s, overflow 0
5x threshold: 174.621183s

Best time-legal frontier:
  nthu_b1_late4_p3box54_88_p3m2_edgecount_limit80
  summary: nthu_b1_second_p3_selector_probe_summary.csv
  runtime: 172.430727s
  overflow: 3882
```

This is not a successful 5x result yet because the verifier overflow is nonzero.
It is the active experimental frontier for trading a small amount of time for a
large reduction in overflow.

Recent B1 frontier probes:

```text
nthu_b1_late4_p3box54_88_p3m2_limit50:
  summary: nthu_b1_tiny_second_p3_low_probe_summary.csv
  runtime: 173.291516s
  overflow: 3968

nthu_b1_late4_p3box54_88_p3m2_limit60:
  summary: nthu_b1_second_p3_fine_gate_summary.csv
  runtime: 172.558426s
  overflow: 3960

nthu_b1_late4_p3box54_88_p3m2_edgecount_limit80:
  summary: nthu_b1_second_p3_selector_probe_summary.csv
  runtime: 172.430727s
  overflow: 3882

nthu_b1_late4_p3box54_88_p3m2_limit70:
  summary: nthu_b1_second_p3_fine_gate_summary.csv
  runtime: 176.185167s
  overflow: 3958

nthu_b1_late4_p3box54_88_p3m2_limit80:
  summary: nthu_b1_second_p3_fine_gate_summary.csv
  runtime: 176.083565s
  overflow: 3954
```

The raw second-P3-budget curve has poor marginal return after limit60: overflow
improves only slightly while runtime exceeds the 5x threshold. The next active
hypotheses are candidate-selection probes (`density`, `edge_count`, `max_edge`,
hot-edge filtering) and rebuilt impact-based sort modes (`impact`, `hot_density`).

## Cleanup Notes

2026-05-06 cleanup:

```text
results/large_outputs_20260506.csv
```

Large `.out` files dominate disk usage. They were not compressed on the login node
and were not deleted. If disk pressure becomes urgent, archive only superseded
illegal run directories after confirming their summary rows are no longer needed.

## Historical Evidence

Older but still useful summary files include:

```text
nthu_fallback_p2_serial_final_r6_summary.csv
nthu_fallback_p2_serial_final_r5_summary.csv
nthu_fallback_p2_serial_final_r4_summary.csv
nthu_fallback_p2_serial_final_r3_summary.csv
nthu_p2_recommended_summary.csv
nthu_p2_tuning_summary.csv
gpu_real_candidate_summary.csv
gpu_real_dogleg_candidate_summary.csv
gpu_real_dogleg_gr_candidate_summary.csv
nthu_dogleg_final_a1_compare.csv
nthu_dogleg_final_a2_compare.csv
nthu_dogleg_final_a3_compare.csv
```

These document earlier P2/P3 tuning, dogleg gating, and standalone GPU scorer work.
They are no longer the current best integrated result, but they are still useful for
report history and for avoiding repeated dead ends.
