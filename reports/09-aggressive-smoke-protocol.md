# Aggressive Smoke Protocol

Date: 2026-06-07
Branch: `experiment-aggressive-smoke-protocol`

## Rule

Every aggressive optimization attempt must record:

- previous version / previous strategy;
- candidate version / candidate strategy;
- original NTHU baseline denominator;
- one easy smoke and one hard smoke;
- a 3x-original timeout gate;
- whether a failure is an implementation/supporting-code issue or an invalid
  optimization logic.

The smoke pair is:

| Role | Benchmark | Original seconds | 3x kill gate |
| --- | --- | ---: | ---: |
| easy | `newblue2.fastplace90.3d.50.20.100` | 76.516 | 230s |
| hard | `adaptec4.aplace60.3d.30.50.90` | 130.667 | 392s |

The helper script is:

```text
scripts/run_vm_aggressive_smoke.sh
```

It writes separate logs per strategy/benchmark and summarizes:

```text
results/vm_aggressive_smoke/<run_id>/smoke_summary.csv
results/vm_aggressive_smoke/<run_id>/strategy_catalog.csv
results/vm_aggressive_smoke/<run_id>/original_baseline.csv
```

## Previous Failed Direction: Transactional Reroute

Previous code branch:

```text
experiment-transactional-virtual-ripup
last commit: 8a9ad5c
```

Observed smoke:

| Benchmark | Original s | Candidate s | Speedup | Result |
| --- | ---: | ---: | ---: | --- |
| `newblue2` | 76.516 | ~71.116 | ~1.08x | legal |
| `adaptec4` | 130.667 | 242.157 | 0.54x | illegal, overflow 3.14M |
| `adaptec3` | 479.186 | 731.206 | 0.66x | illegal, overflow 3.27M |
| `adaptec2` | 173.992 | 720s timeout | <0.24x | no summary |

Classification:

- This is not only a bad support configuration.
- Single-case rerun did not recover speed or legality.
- The optimization logic is rejected for now.

Reason:

- The implementation adopted snapshot/proposal/deterministic commit, but not the
  full collision-aware or adaptive-routing algorithm from the papers.
- Hard cases need NTHU's serial rip-up/reroute semantics.  Bounded transaction
  proposals cannot safely rewrite the multi-terminal tree, and capped serial
  repair leaves overflow.

References for the rejected direction:

- NCTU-GR 2.0: collision-aware task scheduling and bounded-length maze routing.
- DSD 2013 overlapped routing regions: parallel route-search, exclusive
  area-update.
- SPRoute / SPRoute 2.0: adaptive parallelism and deterministic batching.

## Next Candidate: `aggressive_p3lite_v1`

Previous strategy:

```text
prev_final
```

This is the final high-overflow adaptive P2 budget strategy from
`reports/03-final-vm-strategy-results.md`.

Candidate strategy:

```text
aggressive_p3lite_v1
```

Logic:

- keep net-guided fast greedy layer assignment;
- keep routing-state adaptive legal repair;
- reduce initial P3 effort from 4 rounds to 1;
- reduce repair P2/P3 effort;
- add a post-processing overflow limit after the first round.

Hypothesis:

If the current final strategy spends too much time in early/deep P3 on easy or
moderate cases, this should improve time.  If it becomes illegal or slower, the
problem is not simply excessive P3 effort; the strategy needs a different repair
logic.

No new paper claim is attached to this candidate. It is an aggressive extension
of the already documented adaptive-budget direction.

### VM Smoke Result

Result root:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/aggr_p3lite_v1_2ea6819_
```

| Strategy | Role | Benchmark | Seconds | Speedup vs original | WL ratio | Overflow |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| `prev_final` | easy | `newblue2` | 46.957 | 1.629x | 1.151 | 0 / 0 |
| `aggressive_p3lite_v1` | easy | `newblue2` | 48.587 | 1.575x | 1.151 | 0 / 0 |
| `prev_final` | hard | `adaptec4` | 104.147 | 1.255x | 1.110 | 0 / 0 |
| `aggressive_p3lite_v1` | hard | `adaptec4` | 111.058 | 1.177x | 1.109 | 0 / 0 |

Classification:

- Not a 3x slowdown; no timeout.
- Not an implementation crash.
- This is a support-policy issue inside the same optimization family.

Reason:

- Reducing first P3 to one round left only small residual overflow:
  `newblue2` left 4 and `adaptec4` left 3.
- The adaptive repair path then entered P2 repair and ran a second
  post-processing pass, which cost more than the saved first P3 work.

Follow-up:

- Test `aggressive_p3lite_v2_postonly`: for tiny residual overflow, run
  post-only repair before P2 repair.

## Follow-Up Candidate: `aggressive_p3lite_v2_postonly`

Result root:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/aggr_p3lite_v2_d8af035_20260606T204103Z
```

| Strategy | Role | Benchmark | Seconds | Speedup vs original | WL ratio | Overflow |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| `aggressive_p3lite_v2_postonly` | easy | `newblue2` | 46.542 | 1.644x | 1.151 | 0 / 0 |
| `aggressive_p3lite_v2_postonly` | hard | `adaptec4` | 106.239 | 1.230x | 1.109 | 0 / 0 |

Against `prev_final` in the same smoke:

- `newblue2`: 46.542s vs 46.957s, about 0.9% faster.
- `adaptec4`: 106.239s vs 104.147s, about 2.0% slower.

Classification:

- The v1 support issue was real and v2 fixed it: small residual overflow now
  goes through post-only repair and skips P2 repair.
- The net result is still not a meaningful improvement over `prev_final`.
- This family should not be promoted unless a broader set shows consistent
  speed without legality loss.

## Next Candidate: `frontier_edgecount_shortp3_v1`

This is a deliberately aggressive runtime-frontier smoke.

Logic:

- use fast greedy layer assignment;
- enable dogleg fast path and range skip;
- use edge-count post ordering;
- reduce P3 to only 2 rounds with a smaller box;
- stop post-processing after a limited overflow candidate set.

Hypothesis:

This should show whether the old edge-count runtime frontier still gives strong
speed on the smoke pair.  If it is illegal, the result is a frontier row only,
not a final-router candidate.

No new paper claim is attached to this candidate. It is an internal frontier
probe based on earlier VM strategy-matrix evidence.

### VM Smoke Result

Result root:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_edgecount_eb610bf_20260606T204740Z
```

| Strategy | Role | Benchmark | Seconds | Speedup vs original | WL ratio | Overflow |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| `frontier_edgecount_shortp3_v1` | easy | `newblue2` | 41.562 | 1.841x | 1.869 | 0 / 0 |
| `frontier_edgecount_shortp3_v1` | hard | `adaptec4` | 88.149 | 1.482x | 1.678 | 0 / 0 |

Classification:

- Runtime improved and no timeout occurred.
- Both smoke cases remained legal.
- WL is much too high; this is a runtime-frontier row, not a final candidate.

Follow-up:

- Test `frontier_edgecount_netguided_v2`, adding net-guided low-layer assignment
  to the same short-P3 frontier.  If it retains most of the speed while reducing
  WL, it becomes a promising direction.  If it loses most speed, the frontier is
  mainly a fast-layer quality tradeoff.

## Follow-Up Candidate: `frontier_edgecount_netguided_v2`

Result root:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_netguided_aeeeb0e_20260606T205340Z
```

| Strategy | Role | Benchmark | Seconds | Speedup vs original | WL ratio | Overflow |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| `frontier_edgecount_netguided_v2` | easy | `newblue2` | 41.536 | 1.842x | 1.159 | 0 / 0 |
| `frontier_edgecount_netguided_v2` | hard | `adaptec4` | 90.302 | 1.447x | 1.110 | 0 / 0 |

Against `prev_final` in the same smoke family:

- `newblue2`: 41.536s vs 46.957s, about 1.13x faster.
- `adaptec4`: 90.302s vs 104.147s, about 1.15x faster.

Classification:

- This fixes the v1 WL support problem without losing the speed gain.
- It passed the easy/hard smoke and did not trigger the 3x kill gate.
- This is the first candidate in this aggressive pass worth expanding to a
  larger guard set.

Next validation:

- Run the original-legal guard set with the same config.
- If all original-legal cases stay legal and the aggregate speedup remains
  above `prev_final`, then run requested12.

### Legal7 Guard Result

Result root:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_guard/frontier_netguided_legal7_8bec14a_20260606T230807Z
```

The legal7 expansion exposed a legality failure that the easy/hard smoke did
not cover:

| Benchmark | Status | Overflow / Max | Classification |
| --- | --- | ---: | --- |
| `adaptec1` | `ok` | `1212 / 6` | original-legal guard failure |
| `adaptec3` | `ok` | `10 / 2` | original-legal guard failure |
| `adaptec5` | `ok` | `4888 / 10` | original-legal guard failure |
| `bigblue1` | `ok` | `3882 / 8` | original-legal guard failure |
| `newblue6` | `ok` | `4484 / 10` | original-legal guard failure |

Aggregate:

| Metric | Value |
| --- | ---: |
| Legal rows | `2 / 7` |
| Timeouts | `0` |
| Original seconds | `6853.445` |
| Candidate seconds | `1702.490` |
| Suite speedup | `4.026x` |

This is not a timeout and not a crash.  The issue is that
`frontier_edgecount_netguided_v2` is a runtime-frontier config: it keeps the fast
layer/dogleg/range-skip path, but removes too much legalization budget for some
original-legal cases.

Follow-up candidate:

```text
frontier_netguided_adaptive_repair_v3
```

Logic:

- keep v2's fast frontier mechanisms;
- restore routing-state adaptive legal repair only when measured overflow remains
  after post-processing;
- use high-overflow P2 repair and a small final full-remainder repair gate;
- keep one config for all benchmarks.

Classification rule:

- If v3 fixes legal7 without a 3x timeout, v2's failure is a support-policy issue
  inside the frontier family.
- If v3 is still illegal or slower than the 3x gate, this frontier family is
  rejected as an overall candidate and kept only as runtime-frontier evidence.

### v3 Smoke Result

Result root:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_adaptive_v3_5c00905_20260606T231748Z
```

| Strategy | Role | Benchmark | Seconds | Speedup vs original | WL ratio | Overflow |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| `frontier_netguided_adaptive_repair_v3` | easy | `newblue2` | 41.183 | 1.858x | 1.159 | 0 / 0 |
| `frontier_netguided_adaptive_repair_v3` | hard | `adaptec4` | 89.239 | 1.464x | 1.110 | 0 / 0 |

Classification:

- The v3 support change did not slow the smoke pair; both rows are slightly
  faster than v2 smoke and remain legal.
- No timeout occurred.
- Next validation is the same legal7 guard that rejected v2.

### v3 Legal7 Guard Result

Result root:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_guard/frontier_adaptive_v3_legal7_5c00905_20260606T232340Z
```

| Benchmark | Seconds | Speedup vs original | WL ratio | Overflow |
| --- | ---: | ---: | ---: | ---: |
| `adaptec1` | 325.665 | 1.357x | 1.145 | 2 / 2 |
| `adaptec3` | 292.554 | 1.638x | 1.130 | 0 / 0 |
| `adaptec4` | 100.797 | 1.296x | 1.110 | 0 / 0 |
| `adaptec5` | 698.291 | 1.777x | 1.114 | 0 / 0 |
| `bigblue1` | 534.539 | 2.257x | 1.134 | 0 / 0 |
| `newblue2` | 49.200 | 1.555x | 1.159 | 0 / 0 |
| `newblue6` | 911.106 | 3.598x | 1.110 | 152 / 4 |

Aggregate:

| Metric | Value |
| --- | ---: |
| Legal rows | `5 / 7` |
| Original-legal guard | `5 / 7` |
| Timeouts | `0` |
| Original seconds | `6853.445` |
| Candidate seconds | `2912.151` |
| Suite speedup | `2.353x` |

Classification:

- v3 fixed most of v2's legal7 failures and improved legal7 speed vs
  `prev_final` (`2.353x` vs `1.752x` against original), but it is not acceptable
  because all original-legal rows must remain legal.
- A1 and N6 are low-residual failures.  Logs show A1 reached final full
  remainder repair with `cal max overflow=1`, and N6 hit the post candidate
  limit `routed=80 limit=80` while still at small residual overflow.
- This is a support-policy issue in the same frontier family, not a crash or a
  3x slowdown.

Follow-up candidate:

```text
frontier_adaptive_late_score1_v4
```

v4 change:

- keep v3's overall strategy;
- lower late P2 reroute score gate from `4` to `1`;
- increase post overflow candidate limit after the first post round from `80`
  to `240`;
- increase final full-remainder repair from `limit=20, rounds=2` to
  `limit=80, rounds=6`.

Hypothesis:

The remaining failures are low-overflow residuals, so allowing low-score late
reroutes and more post candidates should restore legality with less cost than
returning to the heavier `prev_final` P3 budget.

### v4 Smoke Result

Result root:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_late_score1_v4_7cc5fdc_20260606T234222Z
```

| Strategy | Role | Benchmark | Seconds | Speedup vs original | WL ratio | Overflow |
| --- | --- | --- | ---: | ---: | ---: | ---: |
| `frontier_adaptive_late_score1_v4` | easy | `newblue2` | 41.127 | 1.860x | 1.159 | 0 / 0 |
| `frontier_adaptive_late_score1_v4` | hard | `adaptec4` | 89.638 | 1.458x | 1.110 | 0 / 0 |

Classification:

- v4 smoke remains legal and is not slower than v3 in any meaningful way.
- This validates the support-policy change on the smoke pair only; legal7 is
  still the correctness gate because v3's failures were on `adaptec1` and
  `newblue6`, not the smoke pair.

### v4 Legal7 Guard Result

Result root:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_guard/frontier_late_score1_v4_legal7_7cc5fdc_20260606T234646Z
```

| Benchmark | Seconds | Speedup vs original | WL ratio | Overflow |
| --- | ---: | ---: | ---: | ---: |
| `adaptec1` | 367.382 | 1.203x | 1.137 | 0 / 0 |
| `adaptec3` | 289.303 | 1.656x | 1.130 | 0 / 0 |
| `adaptec4` | 100.058 | 1.306x | 1.110 | 0 / 0 |
| `adaptec5` | 887.325 | 1.398x | 1.108 | 0 / 0 |
| `bigblue1` | 672.508 | 1.794x | 1.128 | 0 / 0 |
| `newblue2` | 49.478 | 1.546x | 1.159 | 0 / 0 |
| `newblue6` | 1166.294 | 2.811x | 1.099 | 0 / 0 |

Aggregate:

| Metric | Value |
| --- | ---: |
| Legal rows | `7 / 7` |
| Original-legal guard | `7 / 7` |
| Timeouts | `0` |
| Original seconds | `6853.445` |
| Candidate seconds | `3532.347` |
| Suite speedup | `1.940x` |

Classification:

- v4 is the first aggressive frontier in this run that passes the original-legal
  `legal7` gate.
- It is slower than illegal v3 (`2.353x`) because `newblue6` needs late P2
  iterations through 16 before post-processing can remove the residual overflow.
  The run is still faster than the prior legal `prev_final` legal7 aggregate
  recorded earlier (`1.752x`).
- The fix is a support-policy change, not a new benchmark-specific branch:
  all legal7 rows use the same routing config.
- Next step: test whether in-process OpenMP conflict batching can recover some
  runtime without changing v4's legality policy.

### v5 OpenMP Conflict-Batch Candidate

Implementation hook:

```text
frontier_openmp_conflict_batch_v5
```

Planned change:

- keep the v4 routing parameters unchanged;
- enable `NTHU_PARALLEL_REROUTE_BATCHES=1`;
- run an OpenMP build with `ROUTER_OPENMP=ON` and a fixed
  `ROUTER_THREADS` value;
- use conflict-box batching inside `RangeRouter::route_twopin_candidates()`;
- record profile logs (`NTHU_PROFILE=1`, `NTHU_PARALLEL_REROUTE_LOG=1`) so
  the result can be classified as useful parallelism vs serialization overhead.

Why this is a separate experiment:

- The current single-process reroute path removes and reinserts each old route
  into the shared congestion map.  Therefore, parallelizing all overflow
  two-pin nets with a raw `omp parallel for` is not safe.
- The available implementation instead batches nets whose conservative
  conflict boxes do not overlap.  This is close in spirit to collision-aware
  task scheduling in NCTU-GR 2.0 and the route-search / exclusive-commit idea
  in the overlapped-region parallel routing paper, but this implementation is
  more conservative because it still mutates the real congestion map during
  each accepted candidate route.
- If smoke is more than 3x slower than original, the timeout gate kills the run
  and the logs are used to classify whether the cause is implementation/support
  overhead or a rejected optimization direction.

References used for this experiment design:

- Wen-Hao Liu et al., "NCTU-GR 2.0: Multithreaded Collision-Aware Global
  Routing with Bounded-Length Maze Routing", DAC 2010,
  DOI: `10.1145/1837274.1837324`.
  <https://www.researchgate.net/publication/221060550_NCTU-GR_20_Multithreaded_Collision-Aware_Global_Routing_with_Bounded-Length_Maze_Routing>
- Yasuhiro Shintani et al., "A Multithreaded Parallel Global Routing Method
  with Overlapped Routing Regions", DSD 2013, DOI: `10.1109/DSD.2013.70`.
  <https://www.researchgate.net/publication/262361280_A_Multithreaded_Parallel_Global_Routing_Method_with_Overlapped_Routing_Regions>
- Jiayuan He et al., "SPRoute: A Scalable Parallel Negotiation-Based Global
  Router", ICCAD 2019, DOI: `10.1109/ICCAD45719.2019.8942105`.
  <https://eurekamag.com/research/102/862/102862952.php>

### v5 Smoke / OpenMP Findings

Support issue:

- `frontier_openmp_conflict_batch_v5_c0ce0d9_001` produced no rows because the
  VM host shell has no `cmake`; this is a runner/build setup failure
  (`exit_code=127`), not an algorithm result.
- Reusing an old OpenMP build produced bad WL (`newblue2` WL ratio `1.426x`,
  `adaptec4` WL ratio `1.321x`).  A current-source OpenMP build was therefore
  rebuilt inside `router.sif`:

```text
/home/ubuntu/hpc-final-router/external/nthu-route/build-release-vm-openmp-current
```

Current-source smoke results:

| Strategy / run | Benchmark | Seconds | Speedup vs original | WL ratio | Overflow |
| --- | --- | ---: | ---: | ---: | ---: |
| `frontier_openmp_control_v5a` | `newblue2` | 40.802 | 1.875x | 1.159 | 0 / 0 |
| `frontier_openmp_control_v5a` | `adaptec4` | 86.754 | 1.506x | 1.110 | 0 / 0 |
| `frontier_openmp_conflict_batch_v5` (`max_candidates=2048`) | `newblue2` | 39.980 | 1.914x | 1.161 | 0 / 0 |
| `frontier_openmp_conflict_batch_v5` (`max_candidates=2048`) | `adaptec4` | 85.577 | 1.527x | 1.110 | 0 / 0 |
| `frontier_openmp_conflict_batch_v5` (`max_candidates=8192`) | `newblue2` | 41.567 | 1.841x | 1.161 | 0 / 0 |
| `frontier_openmp_conflict_batch_v5` (`max_candidates=8192`) | `adaptec4` | 86.405 | 1.512x | 1.110 | 0 / 0 |

Result roots:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_openmp_control_v5a_e75f115_current_001
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_openmp_conflict_batch_v5_c0ce0d9_current_001
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_openmp_conflict_batch_v5_c0ce0d9_current_max8192_001
```

Classification:

- Current-source OpenMP control keeps WL and legality close to v4, but smoke
  speedup over v4 is small (`newblue2`: about `1.01x`; `adaptec4`: about
  `1.03x`).
- Conflict batching is not rejected for correctness on smoke, but it does not
  clearly beat the OpenMP-control run.  Increasing parallel candidates from
  `2048` to `8192` increases scheduling/fallback work and slows `newblue2`.
- Profile evidence for `max_candidates=2048`: `newblue2` had
  `parallel_inputs=2048` but `serial_tail=158989`; `adaptec4` had
  `parallel_inputs=2048` with serial tails of `178210` and `78626` across the
  first two P2 iterations.  This explains why CPU utilization is still close to
  one core for most of the run.
- v5a is being expanded to `legal7` as the safer OpenMP control.  Conflict
  batching remains an experimental branch, not the current best candidate.

### v6 Residual Direct-Overflow Repair Candidate

Previous version:

```text
frontier_adaptive_late_score1_v4
frontier_openmp_control_v5a
```

Implementation delta:

- add `Construct_2d_tree::force_direct_overflow_candidates` so a repair phase
  can use the existing direct-overflow candidate path without enabling it for
  the whole run;
- keep the same NTHU `range_router()` rip-up/reroute/commit semantics after
  candidates are selected;
- in adaptive repair, enable direct-overflow P2 only when measured overflow is
  at or below `NTHU_ADAPTIVE_DIRECT_OVERFLOW_LIMIT`;
- before final full-remainder fallback, try
  `NTHU_FINAL_DIRECT_OVERFLOW_REPAIR_ROUNDS` rounds when measured overflow is
  at or below `NTHU_FINAL_DIRECT_OVERFLOW_REPAIR_LIMIT`;
- restore `BOXSIZE_INC` after the prepass so a failed direct prepass does not
  silently alter the existing full-remainder fallback.

Fixed v6 config under test:

```text
frontier_direct_residual_v6
NTHU_ADAPTIVE_DIRECT_OVERFLOW_LIMIT=80
NTHU_FINAL_DIRECT_OVERFLOW_REPAIR_LIMIT=80
NTHU_FINAL_DIRECT_OVERFLOW_REPAIR_ROUNDS=3
```

Reasoning:

- The original NTHU flow is still sequential and order-sensitive, but low
  residual overflow does not always need another full interval expansion over
  every candidate range.
- This is a routing-state based narrowing step, not a benchmark-specific row
  choice.  It follows the same general direction as collision-aware repair
  scheduling in NCTU-GR and adaptive parallelism in SPRoute: focus work on
  currently conflicting routes first, then fall back to the conservative serial
  repair if residual overflow remains.

Smoke rule:

- run the standard easy/hard pair (`newblue2`, `adaptec4`) against original
  baselines;
- if either row exceeds the 3x-original timeout gate, kill and classify;
- if smoke is legal and not slower, expand to `legal7`; otherwise keep v4/v5a
  as the best legal baseline.

### v7 Proposal-Only Phased Reroute Candidate

Previous legal baselines:

```text
frontier_adaptive_late_score1_v4
frontier_openmp_control_v5a
```

Implementation delta:

- replace in-place reroute execution with phases when
  `NTHU_PROPOSAL_REROUTE_BATCHES=1`:
  1. collect overflow two-pin candidates using the existing NTHU candidate
     order;
  2. generate route proposals on a read-only congestion snapshot using
     per-thread local `MonotonicRouting` and local
     `Multisource_multisink_mazeroute`;
  3. deterministically validate and commit proposed paths to the shared
     congestion map;
- do not call serial `range_router()` as a fallback inside the v7 proposal
  path.  A failed proposal is skipped and must be handled by later NTHU repair
  rounds;
- rebuild the local maze net tree from current two-pin endpoints so proposal
  maze routing can see rerouted Steiner endpoints without mutating the shared
  router tree;
- route P3 post-processing through `route_twopin_candidates(..., version=3)`
  so v7 covers post-processing too.  With proposal mode disabled this remains
  the old serial behavior.

Fixed v7 config under test:

```text
frontier_proposal_reroute_v7
NTHU_PROPOSAL_REROUTE_BATCHES=1
NTHU_PROPOSAL_REROUTE_MAZE=1
NTHU_PROPOSAL_REROUTE_LOG=1
NTHU_PROPOSAL_REROUTE_MAX_CANDIDATES=16384
```

Paper mapping:

- NCTU-GR 2.0 motivates collision-aware/task-style routing instead of blind
  shared-state mutation.
- DSD 2013 overlapped routing regions uses parallel search and exclusive
  update/commit; v7 follows the same proposal/commit split at net granularity.
- SPRoute motivates phased/adaptive parallel routing where unsuccessful
  proposals are not forced through unsafe concurrent commits.

Smoke rule:

- run only the standard easy/hard smoke first;
- use the existing 3x-original kill gate;
- if smoke is legal and not slower than the legal baseline family, expand to
  `legal7`; otherwise classify as implementation/support issue or invalid
  optimization logic before trying another aggressive direction.

Initial v7 smoke result:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_proposal_reroute_v7_5749c5b_smoke_002
```

Both smoke rows hit the 3x-original timeout gate:

| Benchmark | Gate | Result |
| --- | ---: | --- |
| `newblue2` | 230s | timeout before first proposal summary |
| `adaptec4` | 392s | timeout during iteration 2 |

Observed `adaptec4` first iteration:

```text
proposal reroute phase candidates=180253 proposed=35496 committed=10769
rejected=24727 skipped=144757 allow_maze=1 proposal_ms=330979.158
commit_ms=724.081
```

Classification:

- This is an implementation/support issue within the v7 experiment, not enough
  evidence to reject phased proposal-only routing.
- The bug is that v7.0 sent every overflow candidate into local maze proposal.
  That defeats the collision-aware scheduling idea and makes proposal search
  dominate runtime before deterministic commit matters.
- v7.1 keeps the same proposal-only algorithmic structure but sorts by current
  overflow score and caps proposal work at top `16384` candidates.  This is a
  routing-state based task scheduling rule, not a benchmark-specific branch.

v7.1 smoke result:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_proposal_reroute_v7_f7c9e38_smoke_003
```

Run control:

- launched via background `setsid -f` from the VM;
- `launcher.pid=2578064`, `launcher.pgid=2578064`;
- `newblue2` hit its `230s` gate and exited with `exit_code=124`;
- because the easy row already failed smoke, the remaining hard row was stopped
  manually by killing process groups `2578382` and `2578064`;
- no active v7 process remained after kill.

Observed `newblue2` proposal rounds before timeout:

| P2 iter | Candidates | Proposed | Committed | Rejected | Proposal ms | 2D overflow after |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 16384 | 5828 | 2197 | 3631 | 43162 | 52605 |
| 2 | 16384 | 4267 | 389 | 3878 | 28990 | 50397 |
| 3 | 16384 | 3947 | 64 | 3883 | 44859 | 50061 |
| 4 | 16384 | 3864 | 10 | 3854 | 38228 | 50027 |
| 5 | 16384 | 3845 | 0 | 3845 | 43208 | 50027 |

Classification:

- v7.1 fixed the v7.0 support issue of unbounded proposal work, but the
  proposal-only logic is still not competitive on smoke.
- The deterministic commit phase rejects most proposals after the first round
  because many independently generated proposals target the same residual
  congestion.  This is the exact conflict/livelock problem described by
  collision-aware parallel routing papers.
- Without a stronger conflict graph or soft-capacity negotiation before
  proposal generation, this aggressive proposal-only path cannot clear even the
  easy smoke row inside the 3x gate.
- Do not run `legal7` for v7.1.  Keep v4/v5a as the legal baseline.

v7.2 smoke result:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_proposal_reroute_v7_e2730c4_smoke_004
```

Run control:

- launched via background `setsid -f` from the VM;
- `launcher.pid=2578970`, `launcher.pgid=2578970`;
- `newblue2` completed in `49.592691s` but failed legality;
- because the easy row already failed smoke, the remaining hard row was stopped
  manually by killing process groups `2579109` and `2578970`;
- no active v7 process remained after kill.

Observed `newblue2` output:

| Metric | Value |
| --- | ---: |
| total_wirelength | 8799859 |
| total_overflow | 152222 |
| max_overflow | 60 |
| overflowed_nets | 78940 |
| overflowed_edges | 23320 |

Key proposal diagnostic:

```text
proposal reroute round=1 hot_pool=16384 selected=4 conflict_skipped=16380
proposal reroute round=2 hot_pool=240 selected=1 conflict_skipped=239
proposal reroute round=3 hot_pool=240 selected=1 conflict_skipped=239
```

Classification:

- v7.2 fixed the v7.1 timeout symptom, but the conservative bounding-box
  conflict graph over-serialized the proposal phase.
- The easy row finished quickly only because almost no proposal work was
  allowed through; legality regressed badly.
- This is an implementation/support issue in the conflict model, not yet enough
  evidence to reject proposal-only reroute as an optimization direction.
- Do not run `legal7` for v7.2.

v7.3 smoke result:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_proposal_reroute_v7_ae05cb2_smoke_005
```

Run control:

- launched via background `setsid -f` from the VM;
- `launcher.pid=2579436`, `launcher.pgid=2579436`;
- `newblue2` completed in `61.800743s` but failed legality;
- because the easy row already failed smoke, the remaining hard row was stopped
  manually by killing process groups `2579639` and `2579436`;
- no active v7 process remained after kill.

Observed `newblue2` output:

| Metric | Value |
| --- | ---: |
| seconds | 61.800743 |
| total_wirelength | 8796689 |
| total_overflow | 148610 |
| max_overflow | 60 |
| overflowed_nets | 78072 |
| overflowed_edges | 22797 |

Key proposal diagnostic:

```text
proposal reroute phase rounds=6 hot_pool_scanned=98304 selected=1509
conflict_skipped=96795 proposed=676 committed=94 rejected=582 edge_conflict=1
proposal reroute phase rounds=6 hot_pool_scanned=240 selected=22
conflict_skipped=218 proposed=0 committed=0 rejected=0 edge_conflict=1
```

Classification:

- v7.3 improved v7.2's box-conflict bug, but it still incorrectly treated a
  shared old overflow edge as an exclusive resource.
- That is too conservative: moving multiple nets off the same overused edge is
  required when `max_overflow` is high.
- The safety property belongs in deterministic commit, where the new path is
  capacity-checked before insertion.  The scheduler should only bound, not
  forbid, same-edge proposals.
- Do not run `legal7` for v7.3.

v7.4 smoke result:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_proposal_reroute_v7_21ae42e_smoke_006_easy
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_proposal_reroute_v7_21ae42e_smoke_006_hard
```

Run control:

- launched as two independent background run dirs using `SMOKE_ROLES=easy` and
  `SMOKE_ROLES=hard`;
- easy `launcher.pid=2579970`, `launcher.pgid=2579970`;
- hard `launcher.pid=2579977`, `launcher.pgid=2579977`;
- each run used `ROUTER_THREADS=7`, so the pair could use up to 14 cores;
- `newblue2` completed in `183.673020s` but failed legality;
- because the easy row failed, the hard evaluator was stopped manually by
  killing process groups `2580017` and `2579977`;
- no active v7 process remained after kill.

Observed `newblue2` output:

| Metric | Value |
| --- | ---: |
| seconds | 183.673020 |
| total_wirelength | 8788345 |
| total_overflow | 137904 |
| max_overflow | 60 |
| overflowed_nets | 77138 |
| overflowed_edges | 22444 |

Key proposal diagnostic:

```text
proposal reroute phase rounds=6 hot_pool_scanned=98304 selected=10605
proposed=3415 committed=550 rejected=2865 edge_quota=8
proposal reroute phase rounds=6 hot_pool_scanned=49152 selected=5314
proposed=1508 committed=10 rejected=1498 edge_quota=8
proposal reroute phase rounds=6 hot_pool_scanned=240 selected=38
proposed=0 committed=0 rejected=0 edge_quota=8
```

Classification:

- v7.4 fixed the v7.3 under-parallel selection issue: selected candidates rose
  from about `1509` per phase to about `10605`, and concurrent easy+hard CPU
  use reached roughly 10 cores.
- Legality barely improved (`148610 -> 137904` overflow on `newblue2`) while
  runtime worsened (`61.80s -> 183.67s`).
- The root cause is not old-edge scheduling anymore.  The proposal engine
  generates paths on a stale congestion snapshot, then deterministic commit
  rejects almost all candidates because the commit rule requires a fully legal
  new path.
- Original NTHU `range_router` does not require every intermediate reroute to
  be zero-overflow; it removes the old path, accepts routed paths, and relies on
  negotiation/repair rounds to converge.  v7.4 was stricter than original and
  therefore rejected the useful intermediate moves.
- Do not run `legal7` for v7.4.

v7.5 smoke result:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_proposal_reroute_v7_c49fff4_smoke_007_easy
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_proposal_reroute_v7_c49fff4_smoke_007_hard
```

Run control:

- launched as two independent background run dirs using `SMOKE_ROLES=easy` and
  `SMOKE_ROLES=hard`;
- easy `launcher.pid=2582767`, `launcher.pgid=2582767`;
- hard `launcher.pid=2582774`, `launcher.pgid=2582774`;
- each run used `ROUTER_THREADS=7`;
- `newblue2` hit the `230s` gate with `exit_code=124`;
- because the easy row timed out, the hard evaluator was stopped manually by
  killing process groups `2582811` and `2582774`;
- no active v7 process remained after kill.

Key proposal diagnostic:

```text
proposal reroute phase rounds=6 hot_pool_scanned=98304 selected=10611
proposed=3413 committed=554 rejected=2859 improvement_commit=1
proposal reroute phase rounds=6 hot_pool_scanned=81920 selected=8687
proposed=90 committed=77 rejected=13 improvement_commit=1
```

Classification:

- Improvement commit helped some phases, but did not improve the smoke gate.
- Runtime became worse than v7.4 and `newblue2` timed out before evaluation.
- The remaining mismatch with original NTHU is proposal search state: original
  serial `range_router` removes the old path before route search, while v7.5
  still generated proposals on a snapshot where the old path was present.
- Do not run `legal7` for v7.5.

v7.6 smoke result:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_proposal_reroute_v7_ce50164_smoke_008_easy
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_proposal_reroute_v7_ce50164_smoke_008_hard
```

Run control:

- launched as two independent background run dirs using `SMOKE_ROLES=easy` and
  `SMOKE_ROLES=hard`;
- easy `launcher.pid=2585923`, `launcher.pgid=2585923`;
- hard `launcher.pid=2585930`, `launcher.pgid=2585930`;
- each run used `ROUTER_THREADS=7`;
- no active v7 process remained after both summaries were written.

Result:

| Benchmark | Seconds | Original seconds | Runtime ratio | WL | Original WL | WL ratio | Overflow | Max overflow |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| newblue2 | 105.994150 | 76.516170 | 1.385 | 8795823 | 7595602 | 1.158 | 0 | 0 |
| adaptec4 | 183.891179 | 130.666544 | 1.407 | 13565009 | 12207270 | 1.111 | 0 | 0 |

Key proposal diagnostic:

```text
newblue2 first large phase:
proposed=10893 committed=9826 rejected=1067 ripup_snapshot=1
newblue2 final repair:
cal max overflow=0 cur_cap-max_cap=0

adaptec4 late repair:
proposed=146 committed=60 rejected=86 ripup_snapshot=1
proposed=2 committed=2 rejected=0 ripup_snapshot=1
cal max overflow=0 cur_cap-max_cap=0
```

Classification:

- v7.6 fixes the proposal-only correctness bug: batch rip-up snapshot plus
  deterministic improvement commit can clear both smoke rows to
  `overflow=0`.
- The missing rip-up snapshot was the main problem.  v7.5 generated proposals
  against the wrong congestion state; v7.6 proposal commit count rose from
  hundreds to thousands in the first large phase.
- It is not a performance winner.  Smoke runtime is about `1.39x-1.41x`
  slower than original and much slower than the v5a/v4 legal baseline.
- Do not promote v7.6 as the final router strategy for speed.  Keep it as the
  technically correct proposal-only transaction prototype and retain v5a/v4 as
  the legal performance baseline.

Final v7.6 config:

- keep proposal-only semantics: no serial `range_router()` fallback inside the
  v7 path;
- split each route phase into multiple transaction rounds:
  1. recompute current overflow score;
  2. sort the hot pool by overflow score;
  3. select a deterministic bounded set using unique net ids plus old-path
     overflow-edge quotas;
  4. sequentially rip up the selected old paths to create a stable proposal
     snapshot;
  5. generate proposals in parallel against that snapshot;
  6. commit proposals in deterministic order, inserting the new path or
     restoring the old path;
  7. stop when no proposal commits or `NTHU_PROPOSAL_REROUTE_MAX_ROUNDS` is
     reached;
- commit rule changes from strict zero-overflow to transactional improvement:
  after removing the old path, accept the proposal if its inserted overflow
  score improves by at least `NTHU_POST_ACCEPT_MIN_DELTA`;
```text
NTHU_PROPOSAL_REROUTE_MAX_CANDIDATES=16384
NTHU_PROPOSAL_REROUTE_BATCH_SIZE=4096
NTHU_PROPOSAL_REROUTE_MAX_ROUNDS=6
NTHU_PROPOSAL_REROUTE_CONFLICT_AWARE=1
NTHU_PROPOSAL_REROUTE_OVERFLOW_EDGE_CONFLICT=1
NTHU_PROPOSAL_REROUTE_OVERFLOW_EDGE_QUOTA=8
NTHU_PROPOSAL_REROUTE_IMPROVEMENT_COMMIT=1
NTHU_PROPOSAL_REROUTE_RIPUP_BEFORE_PROPOSE=1
```

## Guard Expansion: original-legal legal7

Helper:

```text
scripts/run_vm_aggressive_guard.sh
```

Purpose:

- validate the promising `frontier_edgecount_netguided_v2` smoke winner on the
  original-legal subset before running the full requested benchmark set;
- preserve one config across all rows, with no benchmark-specific switching;
- compare every row against the original NTHU runtime and WL denominator;
- run each benchmark in its own log directory with a 3x-original timeout gate;
- record suite-level speedup using total original seconds divided by total
  candidate seconds, including timeout rows at their kill threshold.

Initial guard set:

| Role | Benchmarks |
| --- | --- |
| `legal7` | `adaptec1`, `adaptec3`, `adaptec4`, `adaptec5`, `bigblue1`, `newblue2`, `newblue6` |

Expansion set after `legal7` passes:

| Role | Benchmarks |
| --- | --- |
| `requested12` | `adaptec1-5`, `bigblue1-3`, `newblue1`, `newblue2`, `newblue5`, `newblue6` |

Acceptance for this guard:

- for `legal7`, every row must keep `total_overflow=0` and
  `max_overflow=0`;
- no per-benchmark hardcode is allowed;
- if a row is slower than original by more than 3x, kill that run and classify
  the issue as support/implementation vs invalid optimization logic;
- for `requested12`, the strict correctness gate is that all originally legal
  rows remain legal; original-overflow rows are reported separately;
- if `legal7` is legal and faster than `prev_final` on aggregate, expand to the
  requested benchmark set.
