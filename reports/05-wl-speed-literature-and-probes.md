# Final Methods, Results, and WL-Preserving Speedup Research Log

Date: 2026-06-05
Branch: `vm-fastest-benchmark-guard`
Current commit while recording: `3ae6b79`

## Scope

This log reviews all optimization methods attempted so far, compares the current
router against `origin/main` and the original baseline, records a literature
check, and documents one extra VM probe run.  The goal is specifically:

- keep wirelength from growing too much,
- improve speed where current speedup is still weak,
- keep originally legal cases legal,
- run validation on the VM with parallel benchmark execution.

All local source comparisons were done from this branch.  All benchmark/probe
runs were done only on the VM.

## Current Best Results

### Current vs `origin/main`

Source: `04-main-vs-final-router-comparison.md`

Same CLI budget, same VM, same requested 12 benchmarks:

| Metric | `main` 6f44073 | Current d1b7584 |
| --- | ---: | ---: |
| Total seconds | 16441.272 | 9804.449 |
| Overall speedup | 1.000x | 1.677x |
| Legal rows | 4 / 12 | 10 / 12 |
| Total overflow | 20851542 | 166 |
| Main-legal guard | 4 / 4 | 4 / 4 |
| Average current/main WL ratio | 1.000 | 1.200 |
| Worst current/main WL ratio | 1.000 | 1.399 |

Interpretation:

- Current is much better than `main` under the same aggressive CLI budget.
- The remaining current weak cases are `bigblue2` and `newblue1`, both with
  small residual overflow and high WL ratio against same-CLI main.
- `adaptec1`, `adaptec3`, `adaptec5`, and `bigblue1` still have weak speedup
  or slowdown in same-CLI comparison, but `adaptec5` and `bigblue1` are illegal
  on same-CLI main, so current is paying runtime to restore legality.

### Current vs Original Baseline

Source: `03-final-vm-strategy-results.md`

Requested 12:

| Metric | Original | Current final |
| --- | ---: | ---: |
| Total seconds | 12295.597 | 9144.395 |
| Speedup | 1.000x | 1.345x |
| Legal rows | 7 / 12 original-legal | 10 / 12 |
| Original-legal guard | 7 / 7 | 7 / 7 |
| Total overflow | original overflow on 5 cases | 166 |
| Average WL ratio | 1.000 | 1.158 |
| Worst WL ratio | 1.000 | 1.284 |

Legal7 guard:

| Metric | Original | Current final |
| --- | ---: | ---: |
| Total seconds | 6853.445 | 3910.736 |
| Speedup | 1.000x | 1.752x |
| Legal rows | 7 / 7 | 7 / 7 |
| Average WL ratio | 1.000 | 1.118 |
| Worst WL ratio | 1.000 | 1.151 |

Interpretation:

- On originally legal cases, WL is already controlled reasonably well.
- The one-overall-strategy speedup is real but below the requested 2.8x to 3.2x.
- The old WL<=1.2 portfolio reached about 1.96x on legal7, but it was a selected
  portfolio rather than one overall strategy.

## Review of Attempted Methods

| Method | Result | Decision |
| --- | --- | --- |
| OpenMP reductions/scans | Correct, but process CPU stayed near one effective core; dominant work remained sequential `specify_all_range()`. | Keep as negative evidence; not final. |
| Conflict-aware OpenMP reroute prototype | Raised CPU utilization, but route order changed, serial fallback dominated, and runtime was worse. | Opt-in only; not final. |
| CUDA costed maze / dogleg preselect | Correct on probes, but GPU utilization stayed near zero and dual GPU did not improve single-case latency. | Not final. |
| Fast greedy layer assignment | Large speed gains, but WL inflated around 1.7x to 1.9x in early variants. | Replaced by net-guided low-layer version. |
| Net-guided low-layer assignment | Brought WL close to original while keeping fast layer path. | Selected. |
| Edge-count post-processing | Very fast, but too many illegal rows. | Speed frontier only. |
| Adaptive legal repair | Fixed original-legal cases and greatly reduced hard-case overflow. | Selected. |
| High-overflow P2 budget | Improved B2/B3/N1/N5 hard cases without changing legal7 behavior. | Selected. |
| Strict legal maze fallback | Avoided some overflow but plateaued and was slower; post-accept variant crashed in tree rebuild. | Rejected. |
| Output-level repair scripts | Did not reduce total overflow enough; overflow regions were not isolated segment mistakes. | Rejected. |
| Layer penalty probe in this log | No WL or overflow change on 4 representative cases. | Negative result; WL issue is not fixed by simple layer-penalty tuning. |

## Literature Check

Primary sources checked:

- NTHU-Route 2.0 paper:
  <https://www.cecs.uci.edu/~papers/iccad08/PDFs/Papers/05A.1.pdf>
- NCTU-GR 2.0 paper:
  <https://ir.lib.nycu.edu.tw/bitstream/11536/21646/1/000318163800005.pdf>
- SPRoute paper:
  <https://csl.yale.edu/~rajit/ps/sproute.pdf>
- FastRoute 4.0 paper page:
  <https://www.researchgate.net/publication/221154485_FastRoute_40_Global_router_with_efficient_via_minimization>
- CUGR paper/code page:
  <https://github.com/cuhk-eda/cu-gr>
  and <https://cwpui.com/doc/c10.pdf>

Relevant takeaways:

- NTHU-Route 2.0 improves both quality and runtime through history-based cost,
  congested-region ordering, and implementation techniques.  Our current branch
  already follows this spirit through adaptive repair and overflow-driven P2
  budget, but our remaining weak cases show fixed P3 can still waste time when
  overflow plateaus.
- NCTU-GR 2.0 directly targets our problem: bounded-length maze routing limits
  detours, uses RSMT-aware routing to preserve shorter trees, and adds
  task-based collision-aware parallel routing.  The paper reports almost the
  same routing quality with multicore speedup.  This is the closest match to
  "speed up without WL growth".
- SPRoute shows that useful per-testcase multicore routing needs adaptive
  parallelism: start with net-level parallelism, lower parallelism when livelock
  appears, and use fine-grain parallelism for convergence.  This matches our VM
  evidence that naive parallel commits are unsafe.
- FastRoute 4.0 emphasizes via-aware Steiner tree generation, 3-bend routing, and
  careful layer assignment ordering.  That supports adding a real via/3D
  wirelength optimization step rather than only tweaking layer scores.
- CUGR uses detailed-routability-driven 3D global routing, 3D pattern routing,
  and multi-level bounded maze routing.  The relevant idea for this codebase is
  to route many nets fast and near-optimally with pattern routing, then reserve
  expensive maze routing for the smaller hard region.

## Extra VM Probe

Result root:

```text
/home/ubuntu/hpc-final-router/results/vm_literature_guided_wl_speed/20260605T040511Z_3ae6b79
```

Parallel policy:

- Two independent runner processes.
- Each runner used `PARALLEL_BENCH_JOBS=4`.
- Expected maximum: 8 single-core `NthuRoute` processes at once.
- Benchmarks: `adaptec1`, `adaptec3`, `bigblue2`, `newblue1`.

Variants:

- `final_recheck`: current final selected env.
- `wl_layer_penalty_probe`: final env plus stronger net-guided layer penalties:
  `NTHU_NET_GUIDED_LAYER_PENALTY=0.08`,
  `NTHU_NET_GUIDED_EDGE_CHANGE_PENALTY=1.20`,
  `NTHU_NET_GUIDED_EDGE_LAYER_PENALTY=0.010`.

Result:

| Benchmark | Final s | Probe s | Probe time ratio | Final WL | Probe WL | Probe/Final WL | Final OF/Max | Probe OF/Max |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| adaptec1 | 358.902 | 359.092 | 1.001 | 6081526 | 6081526 | 1.000 | 0/0 | 0/0 |
| adaptec3 | 453.801 | 457.369 | 1.008 | 14657453 | 14657453 | 1.000 | 0/0 | 0/0 |
| bigblue2 | 1126.586 | 1128.790 | 1.002 | 10123919 | 10123919 | 1.000 | 68/2 | 68/2 |
| newblue1 | 1167.455 | 1159.453 | 0.993 | 5035606 | 5035606 | 1.000 | 98/2 | 98/2 |

Aggregate over the probe four:

| Metric | Final | Layer-penalty probe |
| --- | ---: | ---: |
| Total seconds | 3106.744 | 3104.704 |
| Total overflow | 166 | 166 |
| WL delta | baseline | no change |

Conclusion from this probe:

- Simple layer-penalty tuning does not fix high WL or residual overflow in the
  current final strategy.
- Because low-layer-first already chooses the first legal low layer, these
  penalty knobs rarely change the selected layers.
- The remaining WL/speed problem is mainly in 2D reroute detours and the repair
  schedule, not in the final layer score weights.

## Recommended Next Implementation Directions

### 1. Bounded-Length Maze Routing in `Range_router` / `MM_mazeroute`

Implement a NCTU-GR-style bounded-length search before the existing full maze:

- Let `L = manhattan + detour_budget`.
- Start with a small budget for post-processing and adaptive repair.
- Relax only when no feasible overflow-reducing path exists.
- Score congestion under the length bound instead of allowing long detours.

Why this is high priority:

- It directly targets high WL cases.
- It can reduce maze search space and runtime.
- It is a better version of our rejected strict legal maze: strict legal search
  blocked overflow but did not optimize detour length enough and plateaued.

### 2. Region-Based Residual Overflow Repair

For `bigblue2` and `newblue1`, the remaining overflow is tiny but stubborn.
Fixed P3 spends a lot of time with weak improvement.  Instead:

- Build connected components of overflow edges.
- Select nets touching each component.
- Rip up a bounded set of those nets.
- Reroute with bounded-length maze proposals.
- Commit only if total overflow decreases and WL increase stays under a cap.

This matches the measured failure mode better than more global P3 iterations.

### 3. Task-Based Conflict-Aware Parallel Proposal

Do not parallelize in-place commits.  Use a two-phase design:

1. Build independent route proposals against a read-only congestion snapshot.
2. Commit accepted proposals serially or by non-overlapping conflict sets.

This is the SPRoute/NCTU-GR direction and explains why our first OpenMP prototype
increased CPU but did not improve runtime.

### 4. 3D WL/Via-Aware Refinement

FastRoute/CUGR/NCTU-GR all indicate that vias and layer assignment should be part
of the whole flow, not only a final score tweak.  The current net-guided low-layer
assignment is a good first step, but the next step should be:

- negotiate via/overflow in layer assignment,
- allow local layer moves only when vias and overflow remain legal,
- preserve net continuity to avoid unnecessary layer changes.

### 5. Cost and Data-Layout Optimization

This is lower risk but probably smaller impact:

- cache repeated edge cost lookups in hot route boxes,
- avoid rebuilding candidate lists that did not change,
- store route-box candidate features contiguously for better cache behavior.

Do this after bounded-length routing, because current profiling shows the
algorithmic reroute loop dominates.

## Final Assessment

The current final router is defensible:

- It is much better than `main` under the same CLI budget.
- It keeps all original-legal cases legal.
- It reduces requested12 overflow to `166`.
- Legal7 WL is within about `1.15x` of original.

But the remaining gap to a stronger final claim is real:

- Requested12 overall speedup vs original is only `1.345x`.
- Same-CLI current/main worst WL ratio is `1.399x`.
- B2/N1 still have small residual overflow.

The best next direction is not more layer-score tuning, more fixed P3, or simply
turning on more OpenMP threads.  The next implementation should combine
bounded-length maze routing, connected-overflow-region repair, and task-based
parallel proposal generation.  That is the most plausible path to improve speed
without giving back wirelength quality.
