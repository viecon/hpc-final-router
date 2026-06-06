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

It also has a stricter transactional experiment enabled by:

```bash
export NTHU_TRANSACTIONAL_REROUTE_BATCHES=1
```

The transactional path does not call serial `range_router()` as fallback. Workers
propose local route transactions only; the main thread commits only transactions
that still pass the final legality check. Failed transactions are skipped.

The experiment splits overflow reroute into chunked two-stage rounds:

| Stage | Parallel? | Global congestion mutation? | Work |
| --- | --- | --- | --- |
| Proposal | Yes, OpenMP per-thread scratch | No | Copy each overflow `Two_pin_element_2d`, try L-shape/dogleg/monotonic candidates against the current congestion snapshot, and keep only zero-overflow candidate paths. |
| Commit | No, deterministic serial order | Yes | Re-check the proposed path against the latest congestion, rip up the old path, update the twopin path, and insert the new path. |

The transactional variant now also has a hard-reroute proposal path: an
endpoint-stable strict-capacity maze search inside a bounded local box. It is
still a transaction proposal, not a fallback. The worker only returns a candidate
path; the deterministic commit loop still performs the final capacity check
before mutating global congestion.

In the older two-stage path, all overflow candidates are processed through
proposal chunks. The chunk cap only limits proposal working-set size; it no
longer sends the remaining tail directly to serial routing. Serial
`range_router()` is reserved for proposal failures or commit-time conflicts, and
by default those failures are queued until all proposal chunks have completed.
This prevents serial fallback from being interleaved with the parallel proposal
phase.

The log line reports separate `proposal_ms`, `commit_ms`, and `fallback_ms`
fields. These are the numbers to use for Amdahl-style analysis; total CPU
utilization alone is misleading because correctness verification and serial
fallback are single-core.

The old two-stage path still uses serial fallback for unresolved candidates. The
transactional path does not: failed, stale, or commit-rejected transactions leave
the old path in place.

## Environment Knobs

### Transactional Reroute

| Variable | Default | Meaning |
| --- | --- | --- |
| `NTHU_TRANSACTIONAL_REROUTE_BATCHES` | off | Enable conflict-graph transactional reroute. |
| `NTHU_TRANSACTIONAL_BATCH_LIMIT` | OpenMP max threads | Max non-conflicting transactions per batch. |
| `NTHU_TRANSACTIONAL_MAX_CANDIDATES` | unlimited | Cap overflow candidates; skipped candidates do not fall back. |
| `NTHU_TRANSACTIONAL_LSHAPE` | on | Allow endpoint-stable L-shape transaction proposals. |
| `NTHU_TRANSACTIONAL_DOGLEG` | on | Allow endpoint-stable dogleg transaction proposals. |
| `NTHU_TRANSACTIONAL_STRICT_MAZE` | on | Allow endpoint-stable strict-capacity maze proposals in workers. Set `0` to disable. |
| `NTHU_TRANSACTIONAL_STRICT_MAZE_MAX_AREA` | 4096 | Max local search area for transactional strict maze. Falls back to `NTHU_STRICT_LEGAL_MAZE_MAX_AREA` if set. |
| `NTHU_TRANSACTIONAL_PROPOSAL_WAVE_BATCHES` | 16 | Number of deterministic batches proposed in one OpenMP wave before serial commit. |

Safety model:

- build a conflict graph with expanded reroute bounding boxes and same-net
  exclusion;
- each worker reads the current congestion snapshot and writes only local
  `Two_pin_element_2d` copies plus thread-local `MonotonicRouting` scratch;
- shared `congestion`, `NetDirtyBit`, and real twopin paths are touched only in
  the deterministic commit loop;
- commit re-checks `check_path_no_overflow(candidate_path, net_id, true)` before
  remove/insert;
- no serial fallback is used. A rejected transaction leaves the old path in
  place.

The first safe version commits only endpoint-stable paths. This avoids mutating
the shared multi-terminal maze tree from worker threads. Endpoint-changing maze
transactions would need an additional net-tree transaction/merge layer.

### Two-Stage Reroute

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

## Router-Only Profile After Deferred Fallback

Commit: `288af0e`

Result roots on the VM:

```text
/home/ubuntu/hpc-final-router/results/vm_two_stage_parallel/router_only_20260606_288af0e_baseline
/home/ubuntu/hpc-final-router/results/vm_two_stage_parallel/router_only_20260606_288af0e_two_stage
```

Both rows use the same OpenMP build and `OMP_NUM_THREADS=14`. The reported
seconds and CPU samples are for the `NthuRoute` process only; Lab2 verifier runs
afterward and is not included in the router CPU samples.

| Variant | Router s | Avg CPU | Max CPU | Live threads avg/max | WL | Overflow |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| baseline OpenMP14 | 43.849 | 102.643% | 108.000% | 9.976 / 14 | 8747566 | 0 |
| two-stage deferred | 43.753 | 116.024% | 133.000% | 9.976 / 14 | 8741767 | 0 |

Observed speedup is only `43.849 / 43.753 = 1.002x`. The result is legal and WL
is not worse on this case, but the multicore gain is effectively negligible.

Two-stage phase totals from `two-stage parallel reroute` logs:

| Metric | Total |
| --- | ---: |
| `parallel_candidates` | 227221 |
| `proposed` | 49002 |
| `committed` | 12909 |
| `fallback_queued` | 131969 |
| `fallback_skipped` | 108188 |
| `serial_fallback` | 23781 |
| `proposal_ms` | 356.272 |
| `commit_ms` | 259.454 |
| `fallback_ms` | 7423.071 |

Measured Amdahl fraction for the forced-parallel proposal phase:

```text
P = proposal_ms / router_seconds = 0.356272 / 43.752587 = 0.00814
S_14 = 1 / ((1 - P) + P / 14) = 1.0076x
S_infinite = 1 / (1 - P) = 1.0082x
```

This is why the process can show 14 live threads but still average only about
one core. The part made parallel by this experiment is too small; the runtime is
still dominated by serial fallback, route order, and congestion/tree mutation.

## No-Fallback Transactional Reroute

Commit: `de658dd`

Result root:

```text
/home/ubuntu/hpc-final-router/results/vm_two_stage_parallel/router_only_20260606_de658dd_transactional_nomaze
```

This run enabled:

```bash
NTHU_TRANSACTIONAL_REROUTE_BATCHES=1
NTHU_TRANSACTIONAL_BATCH_LIMIT=14
```

and did not enable strict maze. It used no fallback.

| Variant | Router s | Avg CPU | Max CPU | Live threads avg/max | WL | Overflow |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| transactional no-maze | 378.126 | 506.480% | 609.000% | 9.495 / 14 | 8876411 | 0 |

This proves the code is genuinely parallelizing transaction proposal, but the
first scheduler was too expensive: `newblue2` became `8.62x` slower than the
baseline OpenMP14 row (`43.849s`). Representative first-iteration log:

```text
transaction_candidates=161023
batches=17510
parallel_batches=15824
serialized_batches=1686
proposed=18313
committed=8841
invalid=142710
fallback=0
propose_ms=30502.659
commit_ms=223.800
```

Two bottlenecks were identified:

- conflict batching repeatedly scanned the remaining candidate list and produced
  tens of thousands of tiny batches;
- each batch rebuilt thread-local `MonotonicRouting` scratch, so batch overhead
  dominated actual routing work.

Follow-up implementation after `de658dd`:

- one-pass greedy conflict coloring instead of repeated remaining-list scans;
- one reusable `MonotonicRouting` scratch object per OpenMP worker;
- log `plan_ms` separately from `propose_ms` and `commit_ms`.

Commit `fa8289d` result:

```text
/home/ubuntu/hpc-final-router/results/vm_two_stage_parallel/router_only_20260606_fa8289d_transactional_nomaze
```

| Variant | Router s | Avg CPU | Max CPU | WL | Overflow |
| --- | ---: | ---: | ---: | ---: | ---: |
| transactional optimized conflict graph | 149.104 | 117.239% | 127.000% | 8878899 | 0 |

This fixed the scratch rebuild cost but exposed exact conflict planning as the
new serial bottleneck: representative `plan_ms` values were `13s` to `21s` per
large reroute call.

Commit `63881a3` changed the default scheduler to snapshot chunks and kept exact
conflict graph only behind `NTHU_TRANSACTIONAL_CONFLICT_GRAPH=1`.

Result roots:

```text
/home/ubuntu/hpc-final-router/results/vm_two_stage_parallel/router_only_20260606_63881a3_transactional_chunk
/home/ubuntu/hpc-final-router/results/vm_two_stage_parallel/router_only_20260606_63881a3_transactional_chunk_t1
```

| Variant | Threads | Router s | Avg CPU | Max CPU | WL | Overflow |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| transactional chunk | 1 | 60.509 | 95.291% | 107.000% | 8875858 | 0 |
| transactional chunk | 14 | 53.188 | 136.692% | 182.000% | 8876316 | 0 |

Thread scaling for the safe no-fallback transaction path is `60.509 / 53.188 =
1.138x`. It is real parallelism, but not enough to beat the baseline OpenMP14 row
(`43.849s`). The reason is that safe transaction proposal is now cheap:

```text
first large transactional chunk call:
transaction_candidates=161038
batches=11503
scheduler=chunk
plan_ms=31.301
propose_ms=246.786
commit_ms=140.775
fallback=0
```

The remaining wall time is dominated by the unchanged range query/candidate build
path and by extra iterations caused by low no-fallback transaction coverage.

## Hard-Reroute Strict Maze

Commit `9c13b54` made endpoint-stable strict-capacity maze proposals the default
inside transactional reroute. This is the first no-fallback transactional version
that solves the hard-reroute coverage problem on `newblue2`.

Earlier `63881a3` code with the same behavior enabled by env:

```text
/home/ubuntu/hpc-final-router/results/vm_two_stage_parallel/router_only_20260606_63881a3_transactional_strictmaze4096
```

| Variant | Router s | Avg CPU | Max CPU | Live threads avg/max | WL | Overflow |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| transactional strict maze area 4096 | 38.541 | 146.122% | 224.000% | 8.973 / 14 | 8845493 | 0 |

Same-runner comparison after making strict maze the default:

```text
/home/ubuntu/hpc-final-router/results/vm_two_stage_parallel/router_only_20260606_9c13b54_no_transaction_same_runner
/home/ubuntu/hpc-final-router/results/vm_two_stage_parallel/router_only_20260606_9c13b54_transactional_nomaze_same_runner
/home/ubuntu/hpc-final-router/results/vm_two_stage_parallel/router_only_20260606_9c13b54_transactional_strictmaze_default
```

| Variant | Router s | WL | Overflow | Notes |
| --- | ---: | ---: | ---: | --- |
| no transaction | 53.122 | 7608823 | 0 | Same OpenMP build and arguments; transactional env off. |
| transactional no-maze | 68.475 | 7741966 | 0 | No fallback, but cheap proposals do not cover hard reroutes. |
| transactional strict maze default | 47.281 | 7716274 | 0 | No fallback; strict maze default area 4096. |

Strict maze changes the first large transactional call from mostly invalid cheap
proposals to useful hard-reroute proposals:

```text
no-maze:     proposed=18352 committed=8732 invalid=142692 commit_rejected=68
strict maze: proposed=127297 committed=12339 invalid=33763 commit_rejected=314
```

It also reduces the number of transactional calls on this case from 12 to 4 and
cuts post-processing reroute time from about `20.3s` to about `2.7s`. The
same-runner speedup over no transaction is `53.122 / 47.281 = 1.124x`; the WL
ratio is `7716274 / 7608823 = 1.014x`.

## Proposal Wave Parallelization

Commit `3c1c0e4` changed proposal scheduling from one OpenMP parallel region per
small deterministic batch to one region per wave of batches. Safety is unchanged:
workers still read a snapshot and write only proposals; commit remains serial and
rechecks capacity in deterministic order.

Result roots:

```text
/home/ubuntu/hpc-final-router/results/vm_two_stage_parallel/router_only_20260606_3c1c0e4_transactional_wave8
/home/ubuntu/hpc-final-router/results/vm_two_stage_parallel/router_only_20260606_3c1c0e4_transactional_wave16
/home/ubuntu/hpc-final-router/results/vm_two_stage_parallel/router_only_20260606_3c1c0e4_transactional_wave32
/home/ubuntu/hpc-final-router/results/vm_two_stage_parallel/router_only_20260606_3c1c0e4_transactional_wave64_default
```

| Proposal wave batches | Router s | WL | Overflow | First-call `proposal_waves` | First-call `propose_ms` | First-call `commit_rejected` |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 (`9c13b54`) | 47.281 | 7716274 | 0 | 11505 | 1266.167 | 314 |
| 8 | 46.740 | 7715496 | 0 | 1438 | 630.296 | 979 |
| 16 | 46.598 | 7719284 | 0 | 719 | 575.773 | 1455 |
| 32 | 48.364 | 7720576 | 0 | 360 | 653.563 | 2069 |
| 64 | 48.316 | 7723366 | 0 | 180 | 675.350 | 3147 |

Wave scheduling confirms the expected tradeoff. Larger waves reduce OpenMP
parallel-region overhead, but stale proposals increase commit rejection. On this
case wave 16 is the best measured balance, so it is the default after the latest
code change.

## Current Status

The current branch is no longer just a diagnostic fallback experiment. The latest
transactional path is:

- no serial fallback;
- strict-capacity hard-reroute proposals enabled by default;
- deterministic commit with final capacity recheck;
- wave-based OpenMP proposal scheduling, default wave size 16.

On `newblue2` it is legal and improves same-runner time from `53.122s` to
`46.598s` (`1.14x`) with WL about `1.015x` of the no-transaction row. The
remaining limit is that only reroute proposal is parallelized; interval
construction, candidate query/sort, final commit, post-processing bookkeeping,
and 3D assignment still keep average CPU far below 14 full cores.
