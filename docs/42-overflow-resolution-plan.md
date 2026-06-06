# Overflow Resolution Plan

Last updated: 2026-06-02

## Problem

The 16-case `r2` matrix contains many rows with nonzero `total_overflow`.
Those rows cannot be presented as final legal speedup results. They are still
useful as ablation/frontier evidence, but the final claim must only use rows
with:

```text
status = ok
total_overflow = 0
```

## Current Interpretation

Overflow rows fall into two different groups:

1. Aggressive strategies that are fast but intentionally under-repair.
   These include most `nthu_edgecount_post` and many `nthu_cuda_score` rows.
   They should be framed as negative/ablation experiments, not final results.

2. Near-legal rows with small overflow.
   These are worth rerunning with a legal-repair variant now that QoS allows
   longer jobs.

Examples from `r2`:

| Benchmark | Strategy | Overflow | Why it is worth rerunning |
| --- | --- | ---: | --- |
| `bigblue3` | `nthu_fast_layer` | 26 | Small overflow; likely repairable with more post-processing. |
| `newblue5` | `nthu_fast_layer` | 30 | Small overflow; good legal-repair target. |
| `bigblue2` | `nthu_fast_layer` | 88 | Still close enough to try. |
| `newblue1` | `nthu_fast_layer` | 168 | Moderate overflow; try after the smaller cases. |

Rows where original/OpenMP have hundreds of thousands or millions of overflow
are not good immediate repair targets. More walltime alone is unlikely to turn
them into strong legal speedup rows.

## New Repair Strategies

Two conservative strategies were added to `scripts/run_bench16_strategy_one.sh`:

| Strategy | Purpose |
| --- | --- |
| `nthu_fast_layer_repair` | Keep fast greedy layer assignment, but use zero overflow threshold, larger P2/P3 repair budgets, and edge-count post-processing order without the aggressive candidate limit. |
| `nthu_p2p3_legal_repair` | Even more conservative P2/P3 budget for cases where `nthu_fast_layer_repair` still leaves overflow. |

These are not meant to produce the largest speedup. They are meant to convert
near-legal fast-layer rows into valid final-report rows.

## Recommended Rerun Order

Run one watcher with the near-legal cases first:

```text
nthu_fast_layer_repair,bigblue3.aplace70.3d.50.10.90.m8.gr
nthu_fast_layer_repair,newblue5.ntup50.3d.40.10.100.gr
nthu_fast_layer_repair,bigblue2.mpl60.3d.40.60.60.gr
nthu_fast_layer_repair,newblue1.ntup50.3d.30.50.90.gr
nthu_p2p3_legal_repair,bigblue3.aplace70.3d.50.10.90.m8.gr
nthu_p2p3_legal_repair,newblue5.ntup50.3d.40.10.100.gr
nthu_p2p3_legal_repair,bigblue2.mpl60.3d.40.60.60.gr
nthu_p2p3_legal_repair,newblue1.ntup50.3d.30.50.90.gr
```

If those become legal, add them to the final legal comparison table. If they
remain illegal, keep them as honest failed repair attempts and do not claim
their speedups.

## Report Rule

The final report should not hide overflow. Use three categories:

| Category | Include in final claim? | Description |
| --- | --- | --- |
| Legal source-code result | yes | `status=ok` and `total_overflow=0`. |
| Cross-router baseline | yes, but separate | NCTU-GR comparison; not NTHU source-code speedup. |
| Runtime frontier / ablation | no | Fast but overflowed rows. Useful to explain why the strategy was rejected. |
