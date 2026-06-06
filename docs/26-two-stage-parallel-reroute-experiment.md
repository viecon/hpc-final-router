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

The experiment splits overflow reroute into two stages:

| Stage | Parallel? | Global congestion mutation? | Work |
| --- | --- | --- | --- |
| Proposal | Yes, OpenMP per-thread scratch | No | Copy each overflow `Two_pin_element_2d`, try dogleg/L-shape/monotonic candidates against the current congestion snapshot, and keep only zero-overflow candidate paths. |
| Commit | No, deterministic serial order | Yes | Re-check the proposed path against the latest congestion, rip up the old path, update the twopin path, and insert the new path. |

Maze reroute remains serial fallback. This is intentional: the maze path can
adjust multi-terminal tree state, so it is not safe to run in the proposal phase
without a larger tree-transaction design.

## Environment Knobs

| Variable | Default | Meaning |
| --- | --- | --- |
| `NTHU_TWO_STAGE_PARALLEL_REROUTE` | off | Enable the two-stage experiment. |
| `NTHU_TWO_STAGE_BATCH_LIMIT` | `NTHU_PARALLEL_REROUTE_BATCH_LIMIT`, or OpenMP max threads | Cap proposal worker count. |
| `NTHU_TWO_STAGE_MAX_CANDIDATES` | `NTHU_PARALLEL_REROUTE_MAX_CANDIDATES`, default 4096 | Cap how many overflow twopins enter the proposal stage per reroute call. |
| `NTHU_TWO_STAGE_SERIAL_FALLBACK` | on | Route unresolved proposal failures through normal serial `range_router()`. |
| `NTHU_TWO_STAGE_LSHAPE` | follows `NTHU_L_SHAPE_FASTPATH` | Enable/disable L-shape proposal candidates. |
| `NTHU_TWO_STAGE_DOGLEG` | follows `NTHU_DOGLEG_FASTPATH` | Enable/disable dogleg proposal candidates. |

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

## Status

Pending VM build and benchmark. Do not treat this branch as part of the final
router family until the VM result rows are appended here.
