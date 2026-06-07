# Main vs Current Deep Comparison

Date: 2026-06-05
Branch: `vm-fastest-benchmark-guard`
Compared commits:

- `main`: `6f44073` (`origin/main`, separate VM worktree)
- `current`: `d1b7584` (same routing code as `9c10d52`; later commit updated reports)

## Method

All benchmark runs in this report were run on the VM only:
`ubuntu@202.5.251.114`, 16 vCPU, 2x Tesla V100-SXM2-32GB, Apptainer
`router.sif`, Lab2 verifier.

Result root:

```text
/home/ubuntu/hpc-final-router/results/vm_main_compare/main_vs_current_main12_6f44073_current_d1b7584_20260605T023037Z
```

Benchmark set: requested 12 cases, `adaptec1-5`, `bigblue1-3`,
`newblue1`, `newblue2`, `newblue5`, `newblue6`.

Both builds used OpenMP off and CUDA off.  Both used the same aggressive routing
budget:

```text
--p2-init-box-size=5 --p2-box-expand-size=5
--p2-max-iteration=6 --overflow-threshold=1800
--p3-max-iteration=24 --p3-init-box-size=80 --p3-box-expand-size=140
```

`main` was run without the current branch's new environment flags.  `current`
was run with the final overall strategy:

```text
NTHU_FAST_GREEDY_LAYER=1
NTHU_FAST_GREEDY_LAYER_NET_GUIDED=1
NTHU_NET_GUIDED_LOW_LAYER_FIRST=1
NTHU_ADAPTIVE_LEGAL_REPAIR=1
NTHU_ADAPTIVE_REPAIR_P2_MAX_ITER=10
NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_TRIGGER=200
NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_MAX_ITER=24
NTHU_ADAPTIVE_SMALL_OVERFLOW_P2_LIMIT=50
NTHU_ADAPTIVE_SMALL_OVERFLOW_P2_ROUNDS=1
NTHU_ADAPTIVE_INITIAL_P3_MAX_ITER=4
NTHU_ADAPTIVE_INITIAL_P3_INIT_BOX=66
NTHU_ADAPTIVE_INITIAL_P3_BOX_INC=122
NTHU_ADAPTIVE_REPAIR_P3_MAX_ITER=24
NTHU_ADAPTIVE_REPAIR_P3_INIT_BOX=80
NTHU_ADAPTIVE_REPAIR_P3_BOX_INC=140
NTHU_POST_SORT_MODE=edge_count
```

This comparison isolates code and strategy differences under the same CLI
budget.  It is not claiming that this CLI is the best legal configuration for
`main`; in fact, the measured `main` run becomes illegal on most cases.

## Aggregate Result

| Metric | `main` 6f44073 | `current` d1b7584 |
| --- | ---: | ---: |
| Total seconds | 16441.272 | 9804.449 |
| Overall speedup | 1.000x | 1.677x |
| Legal rows | 4 / 12 | 10 / 12 |
| Total overflow | 20851542 | 166 |
| Main-legal guard | 4 / 4 | 4 / 4 |
| Average current/main WL ratio | 1.000 | 1.200 |
| Worst current/main WL ratio | 1.000 | 1.399 |

Current is not just faster overall.  It changes the result class: same-CLI
`main` is legal on only 4 cases, while `current` is legal on 10.  The remaining
current overflows are small residual cases: `bigblue2` has `68 / 2`, and
`newblue1` has `98 / 2`.

For the cases where same-CLI `main` is already legal (`adaptec1`, `adaptec3`,
`adaptec4`, `newblue2`), current keeps all four legal.  The WL ratio on that
legal subset averages `1.118x`, worst `1.149x`.

## Per-Benchmark Result

| Case | Main s | Current s | Speedup | Main WL | Current WL | WL Ratio | Main OF/Max | Current OF/Max |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| adaptec1 | 315.394 | 384.770 | 0.820x | 5503109 | 6081526 | 1.105 | 0/0 | 0/0 |
| adaptec2 | 821.830 | 298.426 | 2.754x | 4893423 | 5759135 | 1.177 | 960812/2 | 0/0 |
| adaptec3 | 449.404 | 484.121 | 0.928x | 13175323 | 14657453 | 1.112 | 0/0 | 0/0 |
| adaptec4 | 144.871 | 128.903 | 1.124x | 12230628 | 13544728 | 1.107 | 0/0 | 0/0 |
| adaptec5 | 893.260 | 952.044 | 0.938x | 14996548 | 17277384 | 1.152 | 1955522/2 | 0/0 |
| bigblue1 | 711.184 | 831.123 | 0.856x | 5373291 | 6212221 | 1.156 | 608008/2 | 0/0 |
| bigblue2 | 1325.409 | 1242.176 | 1.067x | 7239018 | 10123919 | 1.399 | 3491266/4 | 68/2 |
| bigblue3 | 3234.714 | 993.556 | 3.256x | 11689544 | 14525711 | 1.243 | 3068518/4 | 0/0 |
| newblue1 | 2017.855 | 1253.900 | 1.609x | 3716994 | 5035606 | 1.355 | 1455608/4 | 98/2 |
| newblue2 | 66.356 | 54.747 | 1.212x | 7610087 | 8745989 | 1.149 | 0/0 | 0/0 |
| newblue5 | 4971.193 | 1845.377 | 2.694x | 20477084 | 25554633 | 1.248 | 6267278/4 | 0/0 |
| newblue6 | 1489.802 | 1335.304 | 1.116x | 16170543 | 19305056 | 1.194 | 3044530/4 | 0/0 |

Speed wins:

- Current is faster on 8 / 12 cases.
- The largest wins are `bigblue3` (`3.256x`), `adaptec2` (`2.754x`),
  `newblue5` (`2.694x`), and `newblue1` (`1.609x`).
- Current is slower on `adaptec1`, `adaptec3`, `adaptec5`, and `bigblue1`.
  For `adaptec5` and `bigblue1`, the slower current output is legal while main
  is illegal.

Quality wins:

- Main total overflow is `20851542`; current total overflow is `166`.
- Current fixes all main-overflow cases except small residual overflow on
  `bigblue2` and `newblue1`.
- Same-CLI main spends `4971.193s` on `newblue5` and still leaves
  `6267278 / 4` overflow.  Current finishes in `1845.377s` and reaches `0 / 0`.

## Code Logic Difference

### `main` 6f44073

The main branch follows the standard NTHU route structure:

1. Build FLUTE/two-pin trees.
2. Run fixed-budget P2 rip-up/reroute.
3. Run fixed-budget P3 post-processing.
4. Run layer assignment.
5. Output and verify.

Under the tested CLI, `main` does not have the routing-state adaptive repair
logic from the current branch.  It keeps spending the fixed P3 budget even when
overflow is not improving.  The clearest example is `newblue5`: the log reaches
post-processing iteration 24 with max overflow still around 8, then layer
assignment expands this into `6267278` total 3D overflow.

### `current` d1b7584

The current branch adds one overall adaptive strategy.  It does not branch on
benchmark names.

Key routing changes:

- `external/nthu-route/src/router/Layerassignment.cpp`
  - Adds net-guided fast greedy layer assignment.
  - `NTHU_NET_GUIDED_LOW_LAYER_FIRST=1` prefers the lowest legal layer before
    using congested fallback.  This keeps the speed of the fast layer path while
    avoiding many 3D overflow explosions from main.
- `external/nthu-route/src/router/Construct_2d_tree.cpp`
  - Adds `NTHU_ADAPTIVE_LEGAL_REPAIR`.
  - After initial post-processing, it measures overflow.  If overflow remains,
    it resumes P2 from the actual completed iteration instead of restarting or
    blindly accepting the result.
  - Small-overflow cases are capped to avoid over-repair.
  - High-overflow cases get more P2 budget through
    `NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_TRIGGER=200` and
    `NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_MAX_ITER=24`.
- `external/nthu-route/src/router/Post_processing.cpp`
  - Splits P3 parameters into initial and repair phases.
  - Final strategy uses short initial P3 and deeper P3 only after adaptive
    repair.
  - `NTHU_POST_SORT_MODE=edge_count` prioritizes denser overflow candidates.
- `external/nthu-route/src/router/Range_router.cpp`
  - Adds opt-in strict legal maze and OpenMP batch experiments.
  - These are not enabled in the final strategy because they were slower or
    unstable on the VM sweeps.
- `external/nthu-route/src/router/CudaDogleg.cu`
  - Adds opt-in single/multi-GPU dogleg preselection work and removes redundant
    synchronizations.
  - CUDA is not enabled in the final result because GPU utilization stayed near
    zero and did not improve end-to-end latency.

The synthetic router under `src/router.cpp` also gained a strict-capacity-first
A* legalization pass for `seq`, `cpu`, candidate CPU, and CUDA candidate modes.
That is useful for synthetic `router_bench`, but the benchmark table above is
the real NTHU ISPD08 router path.

## Optimization Direction Analysis

### What Actually Helped

The biggest useful direction is not raw multithreading or CUDA.  It is changing
when repair work is spent:

- Main often routes fast but leaves huge overflow after layer assignment.
- Current detects the bad state and spends more P2/P3 only when measured
  overflow justifies it.
- The high-overflow P2 extension is especially important for `bigblue3`,
  `newblue5`, and `newblue6`.

The layer assignment change is also critical.  Main can have relatively small
2D residual overflow but still explode in 3D after layer assignment.  Net-guided
low-layer assignment reduces that failure mode.

### What Did Not Become Final

OpenMP and CUDA were both investigated:

- OpenMP worker threads were created correctly, but profiling showed average CPU
  near one core.  The bottleneck is the sequential `RangeRouter::range_router()`
  mutation loop, not thread launch or binding.
- A conflict-aware OpenMP batch prototype increased CPU utilization, but changed
  route order, required serial fallback, and was slower.
- CUDA single/dual GPU profiling showed very low GPU utilization.  Current GPU
  work units are too small and are separated by sequential CPU routing work.

Therefore the final router remains a single-process CPU router, while the VM
runner uses many independent benchmark processes to use available cores.

### Remaining Problems

Current still has two residual illegal cases:

- `bigblue2`: `68 / 2`
- `newblue1`: `98 / 2`

Both are much better than main, but not fully legal.  More fixed P3 budget is
unlikely to be efficient because main's `newblue5` demonstrates that fixed P3
can spend thousands of seconds without meaningful overflow reduction.

The next real improvement should target connected overflow regions:

1. Identify a bounded congested region from overflow edges.
2. Rip up a small set of nets touching that region.
3. Propose routes against a read-only congestion snapshot.
4. Commit only routes that reduce total overflow and do not create new large
   overflows.
5. Use deterministic serial commit for correctness; parallelize only proposal
   generation when conflicts are known to be independent.

This is more promising than adding more OpenMP pragmas or more GPU devices to
the current in-place mutation loop.

## Verification Notes

- Benchmarks in this report were run only on the VM.
- `main` was run from a separate VM worktree at
  `/home/ubuntu/hpc-final-router-main-compare`.
- The current branch was not switched to `main`, and `main` was not modified.
- `external/nthu-route-original` is outside the modified code path and should
  remain untouched; this was checked separately before finalizing.
