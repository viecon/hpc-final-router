# Two-Stage Parallel Reroute Experiment

Date: 2026-06-06
Branch: `experiment-two-stage-parallel-reroute`
Base commit: `3d27b67` (`vm-fastest-benchmark-guard`)

## Purpose

This is a branch-specific experiment to test whether reroute can use CPU cores
more effectively without allowing parallel threads to mutate the global
congestion map.

The prior OpenMP reroute prototype called the full `range_router()` inside
parallel batches. Even with conflict boxes, that path still performs rip-up,
path mutation, and congestion insert/remove in the worker threads. This makes
correctness hard to reason about and limits how aggressively the work can be
parallelized.

## Implementation

`external/nthu-route/src/router/Range_router.cpp` now has an opt-in path enabled
only by:

```bash
export NTHU_TWO_STAGE_PARALLEL_REROUTE=1
```

The experiment splits overflow reroute into chunked two-stage rounds:

| Stage | Parallel? | Global congestion mutation? | Work |
| --- | --- | --- | --- |
| Proposal | Yes, OpenMP per-thread scratch | No | Copy each overflow `Two_pin_element_2d`, try L-shape/dogleg/monotonic candidates against the current congestion snapshot, and keep only zero-overflow candidate paths. |
| Commit | No, deterministic serial order | Yes | Re-check the proposed path against the latest congestion, rip up the old path, update the twopin path, and insert the new path. |

All overflow candidates are processed through proposal chunks. The chunk cap only
limits proposal working-set size; it no longer sends the remaining tail directly
to serial routing. Serial `range_router()` is reserved for proposal failures or
commit-time conflicts, and by default those failures are queued until all proposal
chunks have completed. This prevents serial fallback from being interleaved with
the parallel proposal phase.

The log line reports separate `proposal_ms`, `commit_ms`, and `fallback_ms`
fields. These are the numbers to use for Amdahl-style analysis; total CPU
utilization alone is misleading because correctness verification and serial
fallback are single-core.

Maze reroute remains serial fallback. This is intentional: the maze path can
adjust multi-terminal tree state, so it is not safe to run in the proposal phase
without a larger tree-transaction design.

## Environment Knobs

| Variable | Default | Meaning |
| --- | --- | --- |
| `NTHU_TWO_STAGE_PARALLEL_REROUTE` | off | Enable the two-stage experiment. |
| `NTHU_TWO_STAGE_BATCH_LIMIT` | `NTHU_PARALLEL_REROUTE_BATCH_LIMIT`, or OpenMP max threads | Cap proposal worker count. |
| `NTHU_TWO_STAGE_MAX_CANDIDATES` | `NTHU_PARALLEL_REROUTE_MAX_CANDIDATES`, default 4096 | Proposal chunk size. All overflow candidates are still processed chunk-by-chunk. |
| `NTHU_TWO_STAGE_SERIAL_FALLBACK` | on | Route unresolved proposal failures through normal serial `range_router()`. |
| `NTHU_TWO_STAGE_DEFER_FALLBACK` | on | Queue unresolved fallback candidates until all proposal chunks finish. |
| `NTHU_TWO_STAGE_LSHAPE` | on | Enable/disable L-shape proposal candidates. |
| `NTHU_TWO_STAGE_DOGLEG` | on | Enable/disable dogleg proposal candidates. |

## Expected Comparison

Run on the VM only. Compare the same router branch with and without
`NTHU_TWO_STAGE_PARALLEL_REROUTE=1`, and include `NTHU_PROFILE=1` plus
`NTHU_PARALLEL_REROUTE_LOG=1` when measuring utilization and proposal/commit
counts.

The first useful benchmark is not the full final matrix. Start with a smoke case
that previously showed reroute time, then one or two legal requested cases:

```bash
NTHU_PROFILE=1 NTHU_PARALLEL_REROUTE_LOG=1 \
NTHU_TWO_STAGE_PARALLEL_REROUTE=1 NTHU_TWO_STAGE_BATCH_LIMIT=14 \
<existing fastest command>
```

Acceptance criteria for continuing this direction:

- No regression in legality on cases that were legal before.
- `two-stage parallel reroute` logs show meaningful `proposed` and `committed`
  counts; otherwise the parallel stage is not doing useful work.
- End-to-end runtime improves after including proposal overhead and serial
  fallback.

## Initial Smoke

`fa32290` first smoke on `newblue2` showed legality preserved but no speedup:

| Variant | Seconds | WL | Overflow | Notes |
| --- | ---: | ---: | ---: | --- |
| `baseline_openmp14` | 44.307 | 8745387 | 0 | Same OpenMP build, two-stage off. |
| `two_stage_openmp14` | 47.133 | 8757736 | 0 | L-shape/dogleg proposal off; almost all fallback. |
| `two_stage_ld_openmp14` | 46.190 | 8753892 | 0 | L-shape/dogleg on; proposal useful but first implementation still sent tail to serial fallback. |

This motivated two follow-up implementation changes:

- chunk all overflow candidates through the parallel proposal stage instead of
  only the first chunk;
- defer serial fallback until after all proposal chunks, with timing logs for
  proposal/commit/fallback.

## Status

Chunked implementation pending VM build and benchmark. Do not treat this branch
as part of the final router family until the VM result rows are appended here.
