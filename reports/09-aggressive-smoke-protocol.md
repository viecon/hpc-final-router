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

### v7 Standalone 14-Thread Follow-Up

The v7.6 result above ran easy and hard concurrently with 7 threads each.  A
follow-up standalone smoke used one benchmark at a time with
`ROUTER_THREADS=14`:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_proposal_reroute_v7_33e8cec_smoke_009_14t_seq
```

| Version | Benchmark | Seconds | Original seconds | Speedup vs original | WL | WL ratio | Overflow | Max overflow |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| v7.6 14t | newblue2 | 80.935161 | 76.516170 | 0.945x | 8797783 | 1.158 | 0 | 0 |
| v7.6 14t | adaptec4 | 132.629088 | 130.666544 | 0.985x | 13567513 | 1.111 | 0 | 0 |

Classification:

- The same proposal-only router is much faster when a single benchmark can use
  all 14 threads.
- It is legal, but still not a speed win against original on the smoke pair.
- This confirms that concurrent easy+hard smoke is useful for throughput, while
  standalone smoke is the fair per-case latency measure.

### v7.7 Adaptive Proposal Rounds

Commit:

```text
b3e7aa2 Adapt v7 proposal rounds on low overflow
```

Result root:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_proposal_reroute_v7_b3e7aa2_smoke_010_adaptive_14t_seq
```

Change:

- add `NTHU_PROPOSAL_REROUTE_ADAPTIVE_ROUNDS=1`;
- when current total overflow is at or below
  `NTHU_PROPOSAL_REROUTE_LOW_OVERFLOW_LIMIT=1000`, reduce proposal rounds from
  `6` to `NTHU_PROPOSAL_REROUTE_LOW_MAX_ROUNDS=2`;
- keep the same collision-aware, rip-up snapshot, deterministic improvement
  commit pipeline.

Result:

| Version | Benchmark | Seconds | Original seconds | Speedup vs original | WL | WL ratio | Overflow | Max overflow |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| v7.7 adaptive | newblue2 | 70.329429 | 76.516170 | 1.088x | 8793554 | 1.158 | 0 | 0 |
| v7.7 adaptive | adaptec4 | 145.945915 | 130.666544 | 0.895x | 13566665 | 1.111 | 0 | 0 |

Classification:

- Adaptive rounds helped `newblue2`: low-overflow repair avoided many extra
  proposal rounds and beat original runtime on the easy smoke.
- The same rule hurt `adaptec4`: it left a small tail for final repair, making
  the hard row slower than v7.6 14t.
- The idea is valid as an adaptive-parallelism probe, but the low-overflow
  policy is not uniformly better.

### Rejected v7.8 Global-Commit Gate

The next aggressive attempt tried to rescue rejected low-overflow proposals by
temporarily restoring the old path, tentatively inserting the proposed path,
and accepting only if whole-grid total overflow decreased.  This follows the
transaction / deterministic commit direction, but it must be cheap and must not
damage final-tail convergence.

Unbounded global gate:

```text
75dc930 Add global overflow gate for v7 proposals
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_proposal_reroute_v7_75dc930_smoke_011_globalgate_14t_seq
```

Observed result:

- `newblue2` completed legally in `95.609765s`, WL `8792786`.
- The run was manually stopped before completing hard because logs showed the
  support problem clearly: low-overflow phases spent about `0.9s-2.2s` in
  commit checks after scanning too many rejected proposals.
- Manual stop file:
  `manual_stop.txt` in the run root records the process groups stopped.

Capped global gate:

```text
75d20a4 Cap v7 global overflow commit tests
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_proposal_reroute_v7_75d20a4_smoke_012_globalcap16_14t_seq
```

| Version | Benchmark | Seconds | Original seconds | Speedup vs original | WL | WL ratio | Overflow | Max overflow |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| v7.8 cap16 | newblue2 | 78.000646 | 76.516170 | 0.981x | 8793620 | 1.158 | 0 | 0 |
| v7.8 cap16 | adaptec4 | 144.774601 | 130.666544 | 0.903x | 13568085 | 1.111 | 2 | 2 |

Classification:

- The cap fixed the support-cost issue: `global_tests` was bounded at 16 per
  round and commit time dropped from seconds to roughly hundreds of ms.
- It is still rejected because `adaptec4` ended with overflow.
- Timeline diagnosis: final full-remainder repair did run, but after six final
  rounds the capped global gate state still left `cur_cap-max_cap=1` and the
  evaluator reported `total_overflow=2`.
- Therefore global-commit gate is kept only as an off-by-default experiment.
  It is not part of the v7 default strategy.

### Current v7 Default At Branch Head

Commit:

```text
decf468 Disable rejected v7 global gate defaults
```

Result root:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_proposal_reroute_v7_decf468_smoke_013_default_14t_seq
```

Default v7 still includes the optional global-gate code, but the smoke/guard
configuration does not set `NTHU_PROPOSAL_REROUTE_GLOBAL_COMMIT_LIMIT`, so the
gate is disabled (`global_commit_limit=0` in logs).

| Version | Benchmark | Seconds | Original seconds | Speedup vs original | WL | WL ratio | Overflow | Max overflow |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| v7 default | newblue2 | 71.824901 | 76.516170 | 1.065x | 8792180 | 1.158 | 0 | 0 |
| v7 default | adaptec4 | 123.377374 | 130.666544 | 1.059x | 13566998 | 1.111 | 0 | 0 |

Classification:

- This is the current legal v7 branch-head smoke result.
- It beats original on both smoke rows, but WL remains about `1.11x-1.16x`
  original.
- It is still not the final recommended speed/quality router over the v5a/v4
  legal baseline; it is the technically correct proposal-only parallel
  prototype.
- No `external/nthu-route-original` changes were present during the VM syncs.

### v8 Aggressive Direct-Overflow Proposal Plan

Branch:

```text
experiment-v8-aggressive-parallel
```

Previous version:

```text
frontier_proposal_reroute_v7
```

New strategy:

```text
frontier_v8_direct_proposal
```

Code change:

- add opt-in `NTHU_V8_DIRECT_ROUTE_ALL=1` in
  `Route_2pinnets::route_all_2pin_net()`;
- when enabled, skip `init_gridcell()`, `define_interval()`,
  `divide_grid_edge_into_interval()`, and interval/range expansion for that P2
  round;
- scan all current two-pin paths in parallel, compute current overflow score,
  sort the hot set by overflow score and box size, then send only those hot
  paths into the v7 proposal-only deterministic commit pipeline;
- keep the same no-benchmark-name rule: the candidate set is selected only from
  current congestion/routing state.

Rationale:

- v7 made proposal generation parallel but still fed it from NTHU's original
  interval/range expansion path.
- The v8 experiment makes the parallel proposal stage the primary P2 work unit:
  scan is data-parallel, proposal search is per-candidate parallel, and commit
  remains deterministic/exclusive.
- This follows the same broad idea as collision-aware task scheduling and
  parallel route-search / exclusive-update literature, but it is intentionally
  more aggressive than the previous bounded v7 experiment.

Smoke gate:

- same easy+hard smoke pair as above;
- `ROUTER_THREADS=14`, `PARALLEL_BENCH_JOBS=1` for per-case latency;
- 3x-original timeout gate;
- if smoke is legal and not slower than the gate, expand to `legal7`;
- if a row is slower than 3x or illegal, classify as implementation/support vs
  invalid optimization logic before changing direction.

### v8 Smoke Results And Scheduler Fix

Initial commit:

```text
6d630e5 Add v8 direct proposal reroute experiment
```

Run roots:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_v8_direct_proposal_6d630e5_smoke_001_easy_14t
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_v8_direct_proposal_6d630e5_smoke_002_hard_14t
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_v8_direct_proposal_6d630e5_smoke_003_easy_16k_r4_14t
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_v8_direct_proposal_6d630e5_smoke_004_easy_16k_r6_14t
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_v8_direct_proposal_6d630e5_smoke_005_hard_16k_r6_14t
```

| Version | Config | Benchmark | Seconds | Original seconds | Speedup | WL ratio | Overflow | Decision |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| v8.0 | 32k candidates, 8k batch, 6 rounds, edge quota 12 | `newblue2` | 89.192446 | 76.516170 | 0.858x | 1.158 | 0 / 0 | legal but slower |
| v8.0 | same | `adaptec4` | 140.773463 | 130.666544 | 0.928x | 1.112 | 0 / 0 | legal but slower |
| v8.1 | 16k candidates, 4k batch, 4 rounds, edge quota 8 | `newblue2` | 76.114445 | 76.516170 | 1.005x | 1.160 | 2 / 2 | rejected, illegal |
| v8.2 | 16k candidates, 4k batch, 6 rounds, edge quota 8 | `newblue2` | 69.379286 | 76.516170 | 1.103x | 1.160 | 0 / 0 | promising |
| v8.2 | same | `adaptec4` | 122.955319 | 130.666544 | 1.063x | 1.111 | 2 / 2 | rejected, illegal |

Diagnosis:

- The v8 direct hot-set path successfully creates parallel work.  During hard
  smoke, `NthuRoute` reached about 5x-7x CPU in the proposal phases.
- The scan/sort part is cheap.  Example `adaptec4` first P2 direct round:
  `scan_sort_ms=49.924`, but `proposal_ms=25879.529`.
- v8.0 was legal because it overfed proposal work, but that erased the range
  bypass speed gain.
- v8.1/v8.2 became fast enough, but hard/easy residual tails exposed a
  scheduler bug: when only one overflow edge remains, the conflict selector
  caps that edge at one candidate because `edge_limit=min(edge_quota, overuse)`.
  If that candidate is rejected, later rounds tend to retry the same class of
  candidate and leave a `2/2` overflow tail.

Follow-up code change:

- add `NTHU_V8_REJECT_COOLDOWN=1` to skip rejected candidates within the same
  proposal phase;
- add `NTHU_V8_LOW_OVERFLOW_EDGE_OVERSUBSCRIBE=1` so low-overflow phases may
  select up to `edge_quota` candidates on the same overflow edge and let
  deterministic commit choose a safe winner;
- keep the algorithm proposal-only: no serial `range_router()` fallback is
  added for v8.

This is classified as a support/scheduler issue inside the same direct-proposal
experiment, not a rejection of the v8 idea yet.  Rebuild and rerun the same
easy+hard smoke after committing the scheduler fix.

### v8.3 Scheduler Fix Result

Commit:

```text
dab712f Fix v8 low-overflow proposal starvation
```

Run root:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_v8_direct_proposal_dab712f_smoke_006_easy_scheduler_14t
```

Result:

| Version | Config | Benchmark | Seconds | Original seconds | Speedup | WL ratio | Overflow | Decision |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| v8.3 | 16k/r6 + reject cooldown + low-edge oversubscribe | `newblue2` | 71.749737 | 76.516170 | 1.066x | 1.156 | 1084 / 6 | rejected |

Diagnosis:

- `NTHU_V8_REJECT_COOLDOWN=1` is still plausible: it only prevents a rejected
  candidate from being selected again inside the same proposal phase.
- `NTHU_V8_LOW_OVERFLOW_EDGE_OVERSUBSCRIBE=1` is not safe as a default.  It
  allowed many same-edge candidates to be proposed in the same low-overflow
  phase; deterministic per-path improvement commit accepted many local moves,
  but the combined effect increased global overflow.
- Therefore oversubscribe is classified as invalid optimization logic for this
  router state.  It remains an opt-in experiment in code, but it is removed from
  the runner default.

Next run:

- v8.4 uses the same 16k/r6 direct proposal config and keeps only
  `NTHU_V8_REJECT_COOLDOWN=1`;
- easy smoke must be legal before hard is run.

### v8.4 Cooldown-Only Result

Commit:

```text
d3718d6 Disable v8 low-edge oversubscribe default
```

Run roots:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_v8_direct_proposal_d3718d6_smoke_007_easy_cooldown_14t
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_v8_direct_proposal_d3718d6_smoke_008_hard_cooldown_14t
```

Result:

| Version | Config | Benchmark | Seconds | Original seconds | Speedup | WL ratio | Overflow | Decision |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| v8.4 | 16k/r6 + reject cooldown only | `newblue2` | 65.073779 | 76.516170 | 1.176x | 1.158 | 0 / 0 | legal, faster |
| v8.4 | same | `adaptec4` | 129.601816 | 130.666544 | 1.008x | 1.111 | 2 / 2 | rejected, illegal |

Diagnosis:

- The direct proposal path is truly parallel in the high-overflow phase.  On
  hard smoke, the `NthuRoute` process ran with 14 OpenMP threads and reached
  about 4x-6x CPU during proposal generation.
- The remaining failure is the low-overflow tail.  The log repeatedly shows
  `low_overflow=1`, `selected=1`, `committed=0`, so the conflict selector and
  local improvement commit keep retrying safe-looking candidates without
  reducing the final global overflow.
- v8.4 is not expanded to `legal7`, because the hard smoke is originally legal
  but ends with evaluator `total_overflow=2,max_overflow=2`.

### v8.5 Low-Tail Global Commit Plan

Code change:

- keep v8 direct hot-set scanning and proposal-only path generation;
- after the normal proposal phase, if measured total overflow is small
  (`NTHU_V8_LOW_TAIL_GLOBAL_REPAIR_LIMIT`, default 16), collect the remaining
  overflowed two-pin paths;
- propose candidate paths in parallel on the current congestion snapshot;
- commit proposals sequentially and deterministically only if global
  `total_overflow` decreases and `max_overflow` does not increase.

This is the safe replacement for v8.3 oversubscribe.  It still follows the
paper-inspired proposal/commit structure, but the low-tail commit gate is global
instead of local, so one locally acceptable candidate cannot silently increase
overall overflow.

### v8.5 Low-Tail Global Commit Result

Commit:

```text
dc92a5f Add v8 low-tail global repair
```

Run roots:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_v8_direct_proposal_dc92a5f_smoke_009_easy_globaltail_14t
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_v8_direct_proposal_dc92a5f_smoke_010_hard_globaltail_14t
```

Result:

| Version | Config | Benchmark | Seconds | Original seconds | Speedup | WL ratio | Overflow | Decision |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| v8.5 | v8.4 + low-tail global commit | `newblue2` | 65.319120 | 76.516170 | 1.171x | 1.158 | 0 / 0 | legal, faster |
| v8.5 | same | `adaptec4` | 132.181477 | 130.666544 | 0.989x | 1.111 | 2 / 2 | rejected, illegal |

Diagnosis:

- The global commit gate is safe, but it did not find an acceptable candidate
  for the hard low-tail case.
- In the hard log, the tail phase entered `total_overflow=1` internally
  (evaluator reports `2/2`) and repeatedly collected 32 inputs, but only 0-2
  proposals were generated.  The few generated proposals were rejected by the
  global gate.
- Therefore the bottleneck is proposal generation under the direct P2
  `BOXSIZE_INC=5` search box, not the deterministic commit rule.

### v8.6 Low-Tail Wide-Box Proposal Plan

Code change:

- keep the v8.5 global commit gate;
- during only the v8 low-tail proposal phase, temporarily increase
  `construct_2d_tree.BOXSIZE_INC` from the P2 value to
  `NTHU_V8_LOW_TAIL_BOX_INC` (default 66);
- restore the original box size immediately after the parallel proposal phase;
- do not switch by benchmark name and do not re-enable serial `range_router()`
  fallback.

Hypothesis:

- high-overflow routing remains the same fast direct proposal strategy;
- low-tail proposal gets enough search area to produce legal alternatives;
- deterministic global commit prevents the v8.3 oversubscribe failure mode.

### v8.6 Wide-Box Proposal Result And Layer Diagnosis

Commit:

```text
cdb8fed Add v8 low-tail wide-box proposal
```

Run roots:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_v8_direct_proposal_cdb8fed_smoke_011_easy_widebox_14t
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_v8_direct_proposal_cdb8fed_smoke_012_hard_widebox_14t
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_v8_direct_proposal_cdb8fed_smoke_013_hard_layerrepair_14t
```

Result:

| Version | Config | Benchmark | Seconds | Original seconds | Speedup | WL ratio | Overflow | Decision |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| v8.6 | v8.5 + low-tail wide box 66 | `newblue2` | 68.137027 | 76.516170 | 1.123x | 1.158 | 0 / 0 | legal |
| v8.6 | same | `adaptec4` | 134.711842 | 130.666544 | 0.970x | 1.111 | 2 / 2 | rejected, illegal |
| v8.6-probe | same + existing layer overflow repair | `adaptec4` | 134.626645 | 130.666544 | 0.971x | 1.111 | 2 / 2 | rejected, moved 0 |

Diagnosis:

- Wide-box low-tail proposal increased the number of proposed candidates on
  the hard tail, but every candidate was rejected by the global gate.
- The single evaluator overflow edge is vertical `(399,386,layer6)`, demand
  30, capacity 28.  The same 2D edge is already full on layer2 and layer4, so
  the existing layer-only repair cannot move a segment to another vertical
  layer without causing a different overflow.  Its log reports
  `Layer overflow repair moved 0 segments`.
- Therefore the remaining issue is a true 2D tail: one net must be rerouted
  away from that 2D edge.  Layer reassignment alone is insufficient.

### v8.7 Low-Tail Self-Ripup Plan

Code change:

- keep the parallel v8 direct proposal path for the high-overflow phase;
- keep v8.6 wide-box parallel low-tail proposal as the first attempt;
- if overflow remains, test low-tail candidates one by one by ripping up only
  that candidate, running maze with `NTHU_V8_LOW_TAIL_SELF_RIPUP_BOX_INC`
  (default 122), and committing only if global total overflow decreases;
- this is deterministic and targeted to the residual tail, not a return to the
  old interval/range-router expansion.

Risk:

- the self-ripup phase is serial by design because it mutates the shared
  congestion map.  It is only enabled when the measured total overflow is within
  the low-tail limit, so the main routing work remains parallel.

### v8.7 Self-Ripup Result

Commit:

```text
de25537 Add v8 low-tail self-ripup repair
```

Run roots:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_v8_direct_proposal_de25537_smoke_014_easy_selfripup_14t
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_v8_direct_proposal_de25537_smoke_015_hard_selfripup_14t
```

Result:

| Version | Config | Benchmark | Seconds | Original seconds | Speedup | WL ratio | Overflow | Decision |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| v8.7 | v8.6 + low-tail self-ripup box 122 | `newblue2` | 69.025091 | 76.516170 | 1.109x | 1.158 | 0 / 0 | legal |
| v8.7 | same | `adaptec4` | 112.467956 | 130.666544 | 1.162x | 1.111 | 0 / 0 | legal, promote to guard |

Key logs:

- easy: `self-ripup inputs=14 proposed=6 committed=2`, final internal
  overflow `0/0`;
- hard: `self-ripup inputs=33 proposed=9 committed=4`, internal overflow
  reduced from 13 to 4 in 2D, and final Lab2 evaluator reports `0/0`.

Decision:

- v8.7 is the first v8 direct-proposal variant that passes both easy and hard
  smoke while remaining faster than original on both rows.
- Expand to the `legal7` guard before any requested-set benchmark.

### v8.7 legal7 Guard Abort And High-Residual Fix

Guard run:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_guard/frontier_v8_direct_proposal_9e55b5d_legal7_selfripup_2x7t
```

Result:

| Version | Config | Benchmark | Seconds | Original seconds | Speedup | WL ratio | Overflow | Decision |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| v8.7 guard | 16k direct/proposal, 2x7t guard | `adaptec1` | 204.089962 | 441.962666 | 2.166x | 1.192 | 7308 / 4 | rejected, guard abort |

Diagnosis:

- `adaptec1` is originally legal, so the guard was stopped after this failure
  and the remaining process groups were killed.
- This is not a low-tail issue.  The NTHU log ended with internal 2D overflow
  `cur_cap-max_cap=3654`, far above the low-tail self-ripup trigger.
- The direct/proposal hot set was underfed for this larger benchmark.

High-residual probes:

| Probe | Benchmark | Seconds | Original seconds | Speedup | WL ratio | Overflow | Decision |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| highcov32k | `adaptec1` | 165.190281 | 441.962666 | 2.675x | 1.192 | 4360 / 2 | rejected |
| highcov32k+p2x32 | `adaptec1` | 231.355847 | 441.962666 | 1.910x | 1.214 | 0 / 0 | legal |

Decision:

- promote high coverage and larger high-overflow repair budget to v8.8
  default: direct limit 32768, proposal max candidates 32768, proposal batch
  8192, adaptive repair P2 max 16, high-overflow P2 max 32, final full-remainder
  rounds 12;
- rerun smoke before legal7 because the default changed.

### v8.8 Fixed High-Coverage Smoke Rejection

Run roots:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_v8_direct_proposal_d1c96d1_smoke_016_easy_highcovp2x32_14t
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_v8_direct_proposal_d1c96d1_smoke_017_hard_highcovp2x32_14t
```

Result:

| Version | Config | Benchmark | Seconds | Original seconds | Speedup | WL ratio | Overflow | Decision |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| v8.8 | fixed 32k direct/proposal, P2 max 32 | `newblue2` | 90.584202 | 76.516170 | 0.845x | 1.156 | 0 / 0 | rejected, legal but slower |
| v8.8 | same | `adaptec4` | 151.274472 | 130.666544 | 0.864x | 1.111 | 0 / 0 | rejected, legal but slower |

Diagnosis:

- fixed high coverage solves residual overflow but charges every benchmark the
  large-case repair cost;
- this contradicts the single-strategy goal because easy and hard smoke both
  become slower than original even though v8.7 was faster on both;
- high coverage should be a runtime fallback for cases where the fast path
  leaves residual overflow, not the default path.

### v8.9 Runtime Emergency Repair Design

Implementation branch:

```text
experiment-v8-aggressive-parallel
```

Design:

- restore the v8.7 fast defaults for normal execution: direct limit 16384,
  proposal max candidates 16384, proposal batch 4096, adaptive repair P2 max 8,
  high-overflow P2 max 16, final full-remainder rounds 6;
- add a `NTHU_V8_EMERGENCY_REPAIR` phase that activates only when measured 2-D
  overflow remains after the normal adaptive/final repair flow;
- during the emergency phase, temporarily override direct/proposal budgets to
  the high-coverage values: direct limit 32768, proposal max candidates 32768,
  proposal batch 8192, P2 max 32;
- proposal generation remains parallel and commit remains deterministic and
  exclusive; this follows the proposal/commit direction of overlapped-region
  parallel routing while avoiding the fixed highcov cost on already-legal rows;
- no benchmark name or benchmark family is used.  The trigger is only runtime
  routing state: remaining overflow after the fast path.

Paper mapping:

| Paper direction | What v8.9 borrows | Why it matches the current failure |
| --- | --- | --- |
| NCTU-GR 2.0 collision-aware task routing | keep conflict-aware candidate scheduling and avoid blindly oversubscribing hot edges | v8.3 showed unsafe oversubscription creates massive overflow |
| DSD 2013 overlapped routing regions | parallel route-search/proposal with exclusive area-update/commit | proposal path can use threads safely while commit stays deterministic |
| SPRoute 2019 two-phase parallelism | fast high-parallelism path first, stronger repair only when progress is insufficient | fixed highcov was legal but too slow on easy/hard smoke |
| SPRoute 2.0 bulk-synchronous determinism | route from a shared snapshot, then deterministic commit | keeps results reproducible and avoids racing global congestion updates |

Next experiment:

- rebuild current source on VM;
- run easy+hard smoke with v8.9 defaults;
- if both smoke rows are legal and not slower than v8.7 by more than the gate,
  rerun `legal7`;
- if a smoke row is slower than 3x original, kill the process group and
  classify the issue before continuing.

### v8.9 Runtime Emergency Smoke And Guard Abort

Smoke run roots:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_v8_direct_proposal_ccf61c2_smoke_018_easy_runtime_emergency_14t
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_v8_direct_proposal_ccf61c2_smoke_019_hard_runtime_emergency_14t
```

Smoke result:

| Version | Config | Benchmark | Seconds | Original seconds | Speedup | WL ratio | Overflow | Emergency |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| v8.9 | fast default + late emergency | `newblue2` | 67.779847 | 76.516170 | 1.129x | 1.158 | 0 / 0 | no |
| v8.9 | same | `adaptec4` | 106.832822 | 130.666544 | 1.223x | 1.111 | 0 / 0 | no |

Guard run:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_guard/frontier_v8_direct_proposal_ccf61c2_legal7_runtime_emergency_2x7t
```

Partial guard result:

| Version | Config | Benchmark | Seconds | Original seconds | Speedup | WL ratio | Overflow | Decision |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| v8.9 guard | 2 jobs x 7 threads | `adaptec1` | 464.100994 | 441.962666 | 0.952x | 1.232 | 794 / 2 | rejected, original-legal row failed |
| v8.9 guard | same | `adaptec3` | 357.507412 | 479.186273 | 1.340x | 1.144 | 0 / 0 | legal |

Diagnosis:

- v8.9 activated emergency too late on `adaptec1`: the fast path reached
  internal overflow 3654 at iteration 16, then emergency reduced it only to
  397 by iteration 32;
- evaluator still reported `total_overflow=794`, `max_overflow=2`, so the
  guard was killed after `adaptec1` completed;
- the previous legal highcov+p2x32 probe succeeded because high coverage was
  applied earlier, not only as a last-stage rescue.

### v8.10 Early Emergency Design

Design change:

- keep the v8.9 fast default for normal rows;
- add `NTHU_V8_EMERGENCY_EARLY_TRIGGER`, default `30000`;
- when adaptive repair begins and the measured 2-D overflow is above this
  trigger, temporarily switch direct/proposal budgets to highcov values and
  extend P2 to `NTHU_V8_EMERGENCY_P2_MAX_ITER=32`;
- restore normal direct/proposal limits after the adaptive loop.

Why this is not benchmark hardcoding:

- the decision uses only runtime routing state: remaining overflow after the
  fast path;
- smoke rows that are already easy enough should stay on the fast path;
- high-residual rows such as `adaptec1` get high coverage before the solution
  enters a low-progress tail.

### v8.10 Adaptec1 Probe And P2 Tail Decision

Probe roots:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_probe/frontier_v8_direct_proposal_dd142e1_adaptec1_early_emergency_14t
/home/ubuntu/hpc-final-router/results/vm_aggressive_probe/frontier_v8_direct_proposal_dd142e1_adaptec1_early_emergency_p2x48_14t
```

Result:

| Probe | Benchmark | Threads | Seconds | Original seconds | Speedup | WL ratio | Overflow | Decision |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| early emergency P2 max 32 | `adaptec1` | 14 | 199.536161 | 441.962666 | 2.215x | 1.212 | 346 / 2 | rejected, still illegal |
| early emergency P2 max 48 | `adaptec1` | 14 | 216.206094 | 441.962666 | 2.044x | 1.221 | 0 / 0 | legal, promote default |

Key log:

```text
v8 early emergency repair enabled: overflow=33295 trigger=30000 current_iter=5 max_iter=48
v8 low-tail self-ripup phase inputs=32 proposed=7 committed=5 rejected=2 total_overflow=0
2D max overflow = 0
```

Decision:

- set `NTHU_V8_EMERGENCY_P2_MAX_ITER` default from 32 to 48;
- keep `NTHU_V8_EMERGENCY_EARLY_TRIGGER=30000`, because smoke rows did not
  trigger early emergency and kept the fast-path speed;
- rerun `legal7` with the promoted default.

### v8.10 Legal7 Abort And v8.11 Scheduler Fix

Legal7 run:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_guard/frontier_v8_direct_proposal_5daaec9_legal7_early_emergency_p2x48_2x7t
```

Partial result before abort:

| Version | Config | Benchmark | Seconds | Original seconds | Speedup | WL ratio | Overflow | Decision |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| v8.10 | 2 jobs x 7 threads, early emergency P2 max 48 | `adaptec1` | 395.146402 | 441.962666 | 1.118x | 1.221 | 0 / 0 | legal |
| v8.10 | same | `adaptec3` | 362.617606 | 479.186273 | 1.321x | 1.144 | 0 / 0 | legal |
| v8.10 | same | `adaptec4` | 152.954350 | 130.666544 | 0.854x | 1.111 | 0 / 0 | legal but slower under 2x7t |
| v8.10 | same | `bigblue1` | killed after max iter evidence | 1206.306768 | n/a | n/a | internal 12417 / 6 | rejected, original-legal row failed |

Key `bigblue1` evidence:

```text
v8 early emergency repair enabled: overflow=61512 trigger=30000 current_iter=5 max_iter=48
proposal reroute phase ... hot_pool_scanned=184844 selected=4974 conflict_skipped=179870 proposed=4360 committed=469 ... low_overflow=12251
cal max overflow= 6 cur_cap-max_cap= 12417
```

Classification:

- Not a timeout: `bigblue1` was still far below its 3x-original gate.
- Not a crash or build issue: CPU utilization stayed around six cores per
  7-thread router process.
- This is a scheduler-policy failure in the v8.10 support logic.  During
  high-residual emergency repair, collision-aware selection was too
  conservative: most hot candidates were skipped because overuse-1 edges were
  limited to one selected proposal per round.

v8.11 design:

- keep the same fast path and the same early emergency trigger;
- add `NTHU_V8_EMERGENCY_EDGE_OVERSUBSCRIBE`, enabled by default only for
  `frontier_v8_direct_proposal`;
- when emergency repair is active, allow overflow-edge selection up to
  `NTHU_PROPOSAL_REROUTE_OVERFLOW_EDGE_QUOTA` even if the current overuse is
  only 1;
- keep deterministic/exclusive commit unchanged, so unsafe proposals are still
  rejected against the shared congestion map;
- this follows the collision-aware task scheduling direction from NCTU-GR and
  the proposal/commit direction from deterministic batch routers, but does not
  use benchmark names or benchmark-family switches.

Next experiment:

- rebuild on VM after pushing v8.11;
- run the normal easy+hard smoke;
- run a `bigblue1` failure probe because the new flag is emergency-only and
  the easy/hard smoke may not exercise it;
- use the guard helper's `BENCH_LIST_OVERRIDE` only to reduce experiment
  turnaround time; the router strategy and env remain the same as legal7;
- if the probe is legal and not slow, rerun legal7.

### v8.11 Smoke, Failure Probe, And v8.12 Direction

Smoke run:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_smoke/frontier_v8_direct_proposal_60dbb0c_smoke_easyhard_emerg_edge_2x7t
```

| Version | Config | Benchmark | Seconds | Original seconds | Speedup | WL ratio | Overflow | Decision |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| v8.11 | smoke, 7 OpenMP threads | `newblue2` | 81.201087 | 76.516170 | 0.942x | 1.158 | 0 / 0 | legal, not faster |
| v8.11 | smoke, 7 OpenMP threads | `adaptec4` | 135.866790 | 130.666544 | 0.962x | 1.111 | 0 / 0 | legal, not faster |

Targeted `bigblue1` guard:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_guard/frontier_v8_direct_proposal_60dbb0c_bigblue1_emerg_edge_14t
```

| Version | Config | Benchmark | Seconds | Original seconds | Speedup | WL ratio | Overflow | Decision |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| v8.11 | emergency edge oversubscribe, 14 threads | `bigblue1` | 348.062577 | 1206.306768 | 3.466x | 1.241 | 36902 / 8 | rejected, original-legal row failed |

Evidence and classification:

- CPU utilization was healthy, about 9-10 cores on a 14-thread router process.
- `edge_oversubscribe=1` worked: selected candidates rose from the v8.10
  failure's roughly 5k tail selections to roughly 23k-27k per emergency phase.
- The repair still plateaued near 40k internal overflow during emergency P2.
  After post-processing, internal 2D overflow reached only 18451 and the Lab2
  checker reported 36902 total overflow.
- The problem is no longer only candidate scheduling.  The fast proposal loop
  needs stronger convergence/negotiation at the residual tail.

Literature mapping for the next probe:

- NCTU-GR 2.0 uses task-based collision-aware parallel routing with
  bounded-length maze routing, and reports parallel speedup without changing
  the final legality target.  Reference: DAC 2010,
  DOI `10.1145/1837274.1837324`.
- Shintani et al. route-search/area-update separates parallel search from
  exclusive update, then cancels/reroutes candidates that violate congestion.
  Reference: DSD 2013, DOI `10.1109/DSD.2013.70`.
- SPRoute observes that fixed high net-level parallelism can livelock, so it
  lowers parallelism and eventually uses finer-grain work to guarantee
  convergence.  Reference: ICCAD 2019, DOI `10.1109/ICCAD45719.2019.8942105`.
- SPRoute 2.0 emphasizes deterministic batched routing and soft capacity.
  Reference: ASP-DAC 2022 program/PDF.

v8.12 probe direction:

- keep the high-parallel proposal front end;
- enable stronger deterministic/global acceptance only after measured overflow
  enters a residual tail;
- do not branch on benchmark names;
- classify any slow probe above the 3x gate as rejected.

Low-tail probe:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_guard/frontier_v8_direct_proposal_60dbb0c_bigblue1_globaltail25k_14t
```

| Version | Config | Benchmark | Seconds | Original seconds | Speedup | WL ratio | Overflow | Decision |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| v8.12 probe A | global commit limit 25k, low-tail self-ripup 25k | `bigblue1` | 594.909129 | 1206.306768 | 2.028x | 1.243 | 25006 / 8 | rejected, improves overflow but still illegal |

Key evidence:

```text
v8 low-tail self-ripup ... total_overflow=23672 -> 20251
...
v8 low-tail self-ripup ... total_overflow=12503
Lab2 checker total_overflow=25006 max_overflow=8
```

Classification:

- This is a real convergence improvement but insufficient for legality.
- The extra deterministic/global tail costs about 247 seconds over v8.11 on
  `bigblue1`, reducing speedup from 3.466x to 2.028x.
- The residual 2D overflow remains too high for 3D legality; simply increasing
  low-tail self-ripup is likely to keep paying seconds for diminishing returns.

Invalid final-full probe:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_guard/frontier_v8_direct_proposal_60dbb0c_bigblue1_finalfull50k12_14t
```

Result matched v8.11 because the runner still hardcoded
`NTHU_FINAL_FULL_REMAINDER_REPAIR_LIMIT=80`; only the rounds override was
passed through.  This probe is classified as a support-script error, not an
algorithm result.  The guard/smoke helpers were updated so
`V8_FINAL_FULL_REMAINDER_REPAIR_LIMIT` now controls the v8 strategy's
`NTHU_FINAL_FULL_REMAINDER_REPAIR_LIMIT`.

Corrected final-full probe:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_guard/frontier_v8_direct_proposal_bc04a43_bigblue1_finalfull50k12_14t
```

| Version | Config | Benchmark | Seconds | Original seconds | Speedup | WL ratio | Overflow | Decision |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| v8.12 probe B | final full-remainder limit 50k, 12 rounds | `bigblue1` | 417.556938 | 1206.306768 | 2.889x | 1.253 | 30678 / 6 | rejected, still illegal |

Key evidence:

```text
final full-remainder repair enabled: overflow=18451 trigger=0 limit=50000 rounds=12
Final full-remainder repair P2 round: 12 iter=60
cal max overflow= 9 cur_cap-max_cap= 17770
Lab2 checker total_overflow=30678 max_overflow=6
```

Classification:

- The support-script bug is fixed; the 50k final-full gate really ran.
- Extra full-remainder P2 rounds did not create legality.  The 2D residual
  dropped only from 18451 to 17770 during the 12 explicit full-remainder rounds,
  then post-processing reached 15339 before layer assignment still produced
  30678 checker overflow.
- This rejects "just run more NTHU full tail" as the next default.

v8.13 strict-tail design:

- add opt-in `NTHU_V8_LOW_TAIL_STRICT_CAPACITY`;
- only affects v8 low-tail self-ripup;
- after removing the old path, commit a proposed path only if it can be
  inserted with `check_path_no_overflow(..., true)`;
- keep proposal generation parallel and commit order deterministic;
- use this as a targeted `bigblue1` probe with the same routing-state tail
  trigger, not a benchmark-name branch.

v8.13 strict-tail result:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_guard/frontier_v8_direct_proposal_b0ba5b8_bigblue1_stricttail25k_14t
```

| Version | Config | Benchmark | Seconds | Original seconds | Speedup | WL ratio | Overflow | Decision |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| v8.13 probe | strict-capacity low-tail commit, 25k gate | `bigblue1` | 414.349595 | 1206.306768 | 2.911x | 1.241 | 34978 / 10 | rejected, still illegal |

Key evidence:

```text
v8 low-tail self-ripup round=1 inputs=240 proposed=240 committed=0 rejected=240 ... strict_capacity=1
```

Classification:

- Strict commit alone does not work because the v8 proposal generator still
  uses the normal NTHU maze path.  It proposes paths that improve congestion
  cost but are not strict-capacity insertions.
- The existing strict legal maze helper is only wired into the original
  in-place `range_router()` fallback, not into `propose_reroute_path()`.

v8.14 strict-proposal design:

- reuse existing `find_strict_legal_maze_path()` inside `propose_reroute_path`;
- only activate through `NTHU_STRICT_LEGAL_MAZE=1`, with normal defaults off;
- combine with the v8 low-tail strict commit probe so proposal generation and
  commit acceptance agree on strict-capacity legality;
- this follows the DSD 2013 route-search/candidate-validate/update split more
  closely than v8.13 did.

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

## v8.14-v8.16: Proposal Parallelism Correctness Audit

Reference ideas checked:

| Paper | Relevant idea | Local interpretation |
| --- | --- | --- |
| NCTU-GR 2.0, DAC/TCAD 2010, DOI `10.1145/1837274.1837324` | collision-aware task scheduling and bounded-length maze routing | select parallel work by routing-state conflicts, not by benchmark name |
| Shintani et al., DSD 2013, DOI `10.1109/DSD.2013.70` | parallel route search followed by exclusive/cancelable area update | keep proposal search parallel, but make congestion update deterministic and checked |
| SPRoute, ICCAD 2019, DOI `10.1109/ICCAD45719.2019.8942105` | start with net-level parallelism, lower parallelism when livelock/conflicts block convergence | classify failed smoke as conflict/convergence limits rather than blindly increasing threads |

v8.14 strict-proposal result:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_guard/frontier_v8_direct_proposal_9c5b3a1_bigblue1_strictproposal_tail25k_14t
```

| Version | Config | Benchmark | Seconds | Original seconds | Speedup | WL ratio | Overflow | Decision |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| v8.14 | strict legal maze proposal + strict tail, 14 threads | `bigblue1` | 154.037570 | 1206.306768 | 7.831x | 1.207 | 216358 / 34 | rejected, fast but illegal |

Classification:

- The runtime frontier is real, but legality is not close enough.
- Strict proposal/tail did not remove the high-congestion plateau; it must not be
  presented as a final legal result.

v8.15 strict legal repair design:

- after the v8 proposal initial route, select overflowed two-pin paths;
- remove selected old paths, run strict-capacity maze proposal in parallel;
- restore every original path before commit;
- deterministic serial commit removes only the candidate's own old path, then
  accepts only if the proposal can be inserted without overflow.

This is the safe version of the DSD-style "parallel route-search, exclusive
area-update, cancel on violation" pattern.

v8.15 smoke records:

| Run | Build/config | Benchmark | Result | Classification |
| --- | --- | --- | --- | --- |
| `strictrepair_v8_15_14t` | wrong default build dir, OpenMP off | `newblue2` | 42.963665s, WL 8758589, overflow 0 / 0 | support/config error, not valid as 14-thread evidence |
| `strictrepair_v8_15_openmp14t` | OpenMP build, high low-tail budget | `newblue2` | killed at 230s gate | support/config error, low-tail/global repair budget dominated runtime |
| `strictrepair_v8_15b_openmp14t` | OpenMP build, strict trigger 30k | `newblue2` | 109.886664s, WL 8797634, overflow 1614 / 26 | rejected, early strict repair perturbed an original-legal case |
| `strictrepair_v8_15c_trigger80k_openmp14t` | OpenMP build, strict trigger 80k | `newblue2` | 117.656313s, WL 8788554, overflow 1584 / 24 | rejected, OpenMP proposal remains illegal even when strict repair is skipped |

Key diagnosis from v8.15c:

- OpenMP proposal search is not the only issue; the main proposal commit path
  still commits while all selected old paths are removed from the shared
  congestion map.
- If a proposal is accepted in that reduced snapshot, later rejected candidates
  restore their old paths afterward.  That can invalidate an earlier acceptance.
- This is a correctness bug in the transaction/commit protocol, not a reason to
  abandon net-level parallel route search.
- The strict legal repair phase itself is thread-safe, but too weak on
  `bigblue1`: at around 111k 2D overflow, it often selected 48 candidates and
  committed 0-1 legal paths per round.

v8.16 safe proposal commit change:

- add env flag `NTHU_PROPOSAL_REROUTE_SAFE_COMMIT`;
- keep parallel proposal generation on the ripped-up snapshot;
- before deterministic commit, restore all selected original paths;
- commit one proposal at a time on the real current congestion map by removing
  only that two-pin's old path;
- recompute the current old-path overflow score when safe commit is active,
  instead of reusing the pre-snapshot score;
- expose the flag through `V8_PROPOSAL_SAFE_COMMIT` in VM smoke/guard helpers.

Expected smoke:

```text
BUILD_DIR=/home/ubuntu/hpc-final-router/external/nthu-route/build-release-vm-openmp-current
ROUTER_OPENMP=ON
ROUTER_THREADS=14
V8_PROPOSAL_SAFE_COMMIT=1
BENCH_LIST_OVERRIDE=newblue2.fastplace90.3d.50.20.100,adaptec4.aplace60.3d.30.50.90
```

Acceptance for the next smoke:

- `newblue2` must return to `overflow=0,max_overflow=0` because original is legal;
- any run over the 3x original gate is killed and classified;
- if easy+hard smoke passes, expand to `legal7` with the exact same config.

v8.16 safe proposal commit smoke:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_guard/frontier_v8_direct_proposal_f567792_smoke_easyhard_safecommit_v8_16_openmp14t
```

| Version | Config | Benchmark | Seconds | Original seconds | Speedup | WL ratio | Overflow | Decision |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| v8.16 | safe proposal commit, default low-tail limit 16 | `newblue2` | 93.997339 | 76.516170 | 0.814x | 1.158 | 86 / 2 | rejected, original-legal case still illegal |

Evidence:

- `safe_commit=1` is active in every proposal log line.
- CPU utilization during proposal was about 5.8-7.3 cores on the 14-thread run;
  early and late stages were closer to one core.
- Compared with v8.15c, overflow improved from `1584 / 24` to `86 / 2`, so the
  restored-snapshot deterministic commit fixed a real part of the OpenMP
  correctness problem.
- The remaining issue is a low-overflow tail; the run was killed before
  `adaptec4` finished because `newblue2` already failed the original-legal
  guard.

v8.17 config probe:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_guard/frontier_v8_direct_proposal_f567792_smoke_easyhard_safecommit_lowtail128_v8_17_openmp14t
```

| Version | Config | Benchmark | Seconds | Original seconds | Result | Decision |
| --- | --- | --- | ---: | ---: | --- | --- |
| v8.17 | safe commit + low-tail limit 128 + 128 self-ripup tests | `newblue2` | 230 gate | 76.516170 | timeout | rejected, low-tail repair cost explodes |

Evidence:

```text
v8 low-tail global repair ... total_overflow=118 -> 116, commit_ms=9721
v8 low-tail self-ripup ... total_overflow=88 -> 73, elapsed_ms=10442
...
timeout=1
```

Classification:

- The repair strategy is logically moving overflow down, but it is being called
  repeatedly inside P2 emergency iterations.
- That means the same small overflow tail pays repeated full-grid
  `current_overflow_stats()` commit tests.
- This is an implementation/scheduling problem, not evidence that the
  transaction model itself cannot work.

v8.18 post-only tail/legalization design:

- add `NTHU_V8_LOW_TAIL_POST_ONLY`;
- add `NTHU_V8_STRICT_LEGAL_REPAIR_POST_ONLY`;
- keep parallel proposal and emergency P2 unchanged;
- run expensive low-tail global/self-ripup and strict legal repair only in
  post/P3 (`version == 3`) when these phases are explicitly enabled.

Expected probe:

```text
V8_PROPOSAL_SAFE_COMMIT=1
V8_LOW_TAIL_POST_ONLY=1
V8_LOW_TAIL_GLOBAL_REPAIR_LIMIT=128
V8_LOW_TAIL_GLOBAL_REPAIR_MAX_CANDIDATES=512
V8_LOW_TAIL_SELF_RIPUP_MAX_TESTS=128
V8_STRICT_LEGAL_REPAIR=1
V8_STRICT_LEGAL_REPAIR_POST_ONLY=1
V8_STRICT_LEGAL_REPAIR_MAX_OVERFLOW=128
```

v8.18 post-only smoke:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_guard/frontier_v8_direct_proposal_6b7fbb2_smoke_easyhard_postonly_tail_strict_v8_18_openmp14t
```

| Version | Config | Benchmark | Seconds | Original seconds | Speedup | WL ratio | Overflow | Decision |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| v8.18 | safe commit + post-only low-tail/strict repair | `newblue2` | 96.430931 | 76.516170 | 0.793x | 1.157 | 0 / 0 | legal but slower |
| v8.18 | same config | `adaptec4` | 307.841549 | 130.666544 | 0.424x | 1.111 | 5934 / 24 | rejected, hard case illegal |

Evidence:

```text
newblue2: v8 low-tail self-ripup ... total_overflow=43 -> 14 -> 1 -> 0
adaptec4: v8 strict legal repair skipped: total_overflow=2967 max_total=128
adaptec4: 3D # of overflow = 5934, 3D max overflow = 24
```

Classification:

- Post-only scheduling fixed the repeated P2 tail-repair cost and made the easy
  original-legal case legal again.
- It is still not a valid final config because `adaptec4` remains illegal.
- The hard case reaches post/P3 with internal overflow around 2967, above the
  128 repair gate.  At that point the normal local path-score proposal gate
  rejects almost all 240 post candidates, even though a candidate might reduce
  total overflow globally.

v8.19 post-only global commit design:

- expose existing `NTHU_PROPOSAL_REROUTE_GLOBAL_COMMIT_LIMIT` and
  `NTHU_PROPOSAL_REROUTE_GLOBAL_COMMIT_MAX_TESTS` through the VM runner;
- add `NTHU_PROPOSAL_REROUTE_GLOBAL_COMMIT_POST_ONLY`;
- only in post/P3, allow rejected local-score candidates to be tested by full
  `current_overflow_stats()` and accepted if total overflow decreases;
- keep P2 unchanged so the expensive global tests do not repeat during
  emergency iterations.

Expected probe:

```text
V8_PROPOSAL_SAFE_COMMIT=1
V8_PROPOSAL_GLOBAL_COMMIT_LIMIT=4096
V8_PROPOSAL_GLOBAL_COMMIT_MAX_TESTS=96
V8_PROPOSAL_GLOBAL_COMMIT_POST_ONLY=1
V8_LOW_TAIL_POST_ONLY=1
V8_LOW_TAIL_GLOBAL_REPAIR_LIMIT=128
V8_STRICT_LEGAL_REPAIR=1
V8_STRICT_LEGAL_REPAIR_POST_ONLY=1
```

v8.19 post-only global commit smoke:

```text
/home/ubuntu/hpc-final-router/results/vm_aggressive_guard/frontier_v8_direct_proposal_878c770_smoke_easyhard_postglobal96_v8_19_openmp14t
```

| Version | Config | Benchmark | Seconds | Original seconds | Speedup | WL ratio | Overflow | Decision |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| v8.19 | v8.18 + post-only global commit limit 4096, max tests 96 | `newblue2` | 106.182082 | 76.516170 | 0.721x | 1.157 | 0 / 0 | legal but slower |
| v8.19 | same config | `adaptec4` | 392 gate | 130.666544 | 0.333x | NA | timeout | rejected |

Evidence:

```text
adaptec4 post: global_tests=144, global_committed=0, commit_ms about 2966-3165 per phase
adaptec4 router log still ended with 3D overflow = 5934 / 24 before evaluator hit timeout gate
```

Classification:

- Post-only global commit is expensive and did not find valid global-improving
  candidates on the hard plateau.
- It should not be kept in the default v8 config.
- The next useful test is not more global stats; it is to revisit
  collision-aware candidate scheduling now that safe commit avoids the old
  ripped-snapshot correctness bug.

v8.20 safe oversubscribe scheduling probe:

- expose `V8_PROPOSAL_LOW_OVERFLOW_LIMIT` and `V8_PROPOSAL_LOW_MAX_ROUNDS`;
- expose `V8_LOW_OVERFLOW_EDGE_OVERSUBSCRIBE`;
- keep `NTHU_PROPOSAL_REROUTE_SAFE_COMMIT=1`;
- disable the v8.19 post-only global commit gate;
- raise the low-overflow routing-state threshold to cover the `adaptec4`
  3k-4k plateau and allow more candidates per overflow edge.

Expected probe:

```text
V8_PROPOSAL_SAFE_COMMIT=1
V8_PROPOSAL_LOW_OVERFLOW_LIMIT=4096
V8_PROPOSAL_LOW_MAX_ROUNDS=6
V8_LOW_OVERFLOW_EDGE_OVERSUBSCRIBE=1
V8_PROPOSAL_EDGE_QUOTA=16
V8_LOW_TAIL_POST_ONLY=1
V8_LOW_TAIL_GLOBAL_REPAIR_LIMIT=128
V8_STRICT_LEGAL_REPAIR=1
V8_STRICT_LEGAL_REPAIR_POST_ONLY=1
```
