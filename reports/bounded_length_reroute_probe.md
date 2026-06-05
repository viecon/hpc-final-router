# Bounded-Length Reroute Probe

Date: 2026-06-05
Branch: `vm-fastest-benchmark-guard`

## Purpose

This run tested the next WL-preserving speed direction from the literature
review: bounded-length maze routing.  The intent was to reduce long detours
without hardcoding benchmark names and without changing the selected default
strategy unless the new method clearly improved the overall result.

All builds, tests, and benchmarks in this report were run on the VM only.

## Implementation Tried

Commits:

- `de271c9`: added an opt-in `NTHU_BOUNDED_LENGTH_REROUTE` guard in
  `Range_router`.
- `5b0fea5`: fixed the guard so maze rejection happens before
  `MM_mazeroute::adjust_twopin_element()` mutates the multi-source/multi-sink
  tree.

The first version rejected over-length paths after maze routing returned.  That
was unsafe because `mm_maze_route_p()` calls `adjust_twopin_element()`, which
rewires the internal tree adjacency.  Rolling back only `two_pin.path/pin1/pin2`
after that point left the route tree inconsistent and caused output-time
crashes.

The safe version passes a `max_path_edges` limit into `mm_maze_route_p()` and
rejects the traced path before `adjust_twopin_element()`.  This keeps the tree
consistent.  The feature remains opt-in; default routing is unchanged.

## VM Runs

Full baseline/result root:

```text
/home/ubuntu/hpc-final-router/results/vm_bounded_length_reroute/20260605T044112Z_de271c9_full12
```

Parallel policy:

- two runner processes,
- each with `PARALLEL_BENCH_JOBS=7`,
- peak observed `NthuRoute` processes: 14 on a 16-vCPU VM.

Common CLI:

```text
--p2-init-box-size=5 --p2-box-expand-size=5 --p2-max-iteration=6 --overflow-threshold=1800 --p3-max-iteration=24 --p3-init-box-size=80 --p3-box-expand-size=140
```

Selected final env:

```text
NTHU_FAST_GREEDY_LAYER=1
NTHU_FAST_GREEDY_LAYER_NET_GUIDED=1
NTHU_NET_GUIDED_LOW_LAYER_FIRST=1
NTHU_ADAPTIVE_LEGAL_REPAIR=1
NTHU_POST_SORT_MODE=edge_count
```

with the adaptive repair budget env already documented in
`reports/final_methods_wl_speed_research_log.md`.

## Full Final Recheck

This is the selected strategy with bounded-length disabled.

| Benchmark | Seconds | WL | Overflow/Max |
| --- | ---: | ---: | ---: |
| adaptec1 | 374.937 | 6081526 | 0/0 |
| adaptec2 | 289.548 | 5759135 | 0/0 |
| adaptec3 | 472.465 | 14657453 | 0/0 |
| adaptec4 | 129.473 | 13544728 | 0/0 |
| adaptec5 | 909.799 | 17277384 | 0/0 |
| bigblue1 | 806.043 | 6212221 | 0/0 |
| bigblue2 | 1184.971 | 10123919 | 68/2 |
| bigblue3 | 951.719 | 14525711 | 0/0 |
| newblue1 | 1212.523 | 5035606 | 98/2 |
| newblue2 | 52.848 | 8745989 | 0/0 |
| newblue5 | 1800.589 | 25554633 | 0/0 |
| newblue6 | 1316.370 | 19305056 | 0/0 |

Aggregate:

| Metric | Value |
| --- | ---: |
| Total seconds | 9501.285 |
| Legal cases | 10 / 12 |
| Original-legal guard | 7 / 7 |
| Total overflow | 166 |
| Max overflow | 2 |
| Total WL | 146823361 |

Against the original baseline from `reports/vm_router_optimization_report.md`:

| Metric | Original | Current recheck |
| --- | ---: | ---: |
| Full requested-set seconds | 12295.597 | 9501.285 |
| Full requested-set speedup | 1.000x | 1.294x |
| Original-legal seconds | 6853.445 | 4061.935 |
| Original-legal speedup | 1.000x | 1.687x |
| Original-legal correctness | 7 / 7 legal | 7 / 7 legal |

## Unsafe Bounded Attempt

The initial external rollback version was run on all 12 cases with:

```text
NTHU_BOUNDED_LENGTH_REROUTE=1
NTHU_BOUNDED_LENGTH_POST_ONLY=1
NTHU_BOUNDED_LENGTH_RATIO=1.15
NTHU_BOUNDED_LENGTH_EXTRA=8
NTHU_BOUNDED_LENGTH_ORIGINAL_EXTRA=0
```

Result: `12 / 12` rows failed.  Representative logs:

- `adaptec2`: aborted with `vector::_M_range_check` after many
  `bounded-length reroute reject` messages.
- `adaptec4`: same failure mode.

Root cause: rejection happened after `mm_maze_route_p()` had already changed the
internal tree.  This identified the exact problematic segment and led to
commit `5b0fea5`.

## Safe Bounded Smoke

After `5b0fea5`, the two formerly crashing cases were rerun with the same
bounded env but using the separate VM build directory
`external/nthu-route/build-release-bounded-safe`.

| Case | Final seconds | Safe bounded seconds | Time ratio | Final WL | Safe bounded WL | Overflow/Max |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| adaptec2 | 289.548 | 740.369 | 2.557x slower | 5759135 | 5750722 | 0/0 |
| adaptec4 | 129.473 | 781.975 | 6.039x slower | 13544728 | 13525365 | 0/0 |

Conclusion:

- The safe bounded version is correct on the two crash reproductions.
- It slightly lowers WL on those two cases, but the speed cost is too high.
- It is rejected as an overall best strategy.
- The selected best env remains bounded-length disabled.

## Current Decision

Keep `5b0fea5` because it prevents an opt-in experimental mode from corrupting
the route tree, but do not enable `NTHU_BOUNDED_LENGTH_REROUTE` in the final
strategy.  The result is not hardcoded by benchmark; the rejected method was
controlled only by path-length and routing-phase signals.

The next useful implementation would be a true bounded search inside
`MM_mazeroute`, continuing the search for an in-bound candidate instead of
rejecting the first found path.  The current safe guard proves where the limit
must be enforced, but not yet a profitable speed/quality tradeoff.

## Integrity Checks

- VM final commit after safety fix: `5b0fea5`.
- End-of-run active `NthuRoute` processes: `0`.
- `git diff --name-only -- external/nthu-route-original`: no output.
