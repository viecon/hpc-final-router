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
- record suite-level speedup using total original seconds divided by total
  candidate seconds.

Initial guard set:

| Role | Benchmarks |
| --- | --- |
| `legal7` | `adaptec1`, `adaptec3`, `adaptec4`, `adaptec5`, `bigblue1`, `newblue2`, `newblue6` |

Acceptance for this guard:

- every row must keep `total_overflow=0` and `max_overflow=0`;
- no per-benchmark hardcode is allowed;
- if a row is slower than original by more than 3x, kill that run and classify
  the issue as support/implementation vs invalid optimization logic;
- if legal and faster than `prev_final` on aggregate, expand to the requested
  benchmark set.
