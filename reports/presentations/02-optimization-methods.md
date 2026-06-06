# Optimization Methods Brief

Date: 2026-06-06

## Slide 1 - Original Pitfalls

The original router has five practical bottlenecks:

- rip-up/reroute mutates shared congestion state sequentially,
- fixed P2/P3 budgets do not adapt to measured overflow,
- layer assignment is expensive, but naive fast layer inflates WL,
- post-processing can be fast only by leaving overflow,
- CUDA work units are too small relative to CPU routing.

## Slide 2 - Method Map

| Method | Target | Result |
| --- | --- | --- |
| OpenMP analysis kernels | CPU scan/reduction speed | correct, about 1.03x only |
| Conflict-aware reroute batches | real multicore routing | higher CPU, slower |
| Fast greedy layer | layer assignment time | fast, WL too high |
| Net-guided low-layer | WL control | selected WL direction |
| Adaptive legal repair | original-legal correctness | selected |
| High-overflow P2 budget | hard-case overflow | selected |
| Edge-count post | runtime frontier | useful but mostly illegal |
| CUDA scoring | candidate/maze scoring | correct sub-kernel, weak end-to-end |
| Strict/bounded maze | overflow/WL control | rejected or opt-in only |

## Slide 3 - Fast Layer Implementation

The layer assignment dispatcher chooses fast assignment only when explicitly
enabled:

```cpp
if (std::getenv("NTHU_FAST_GREEDY_LAYER") != nullptr) {
    if (std::getenv("NTHU_FAST_GREEDY_LAYER_NET_GUIDED") != nullptr) {
        fast_net_guided_layer_assignment();
    } else {
        fast_greedy_layer_assignment();
    }
}
```

Impact:

- plain fast layer: requested12 `1.59x`, but original-legal WL avg/worst
  `1.743/1.851`;
- net-guided low-layer WL<=1.2 legal7 portfolio: `1.961x`, avg/worst WL
  `1.125/1.163`.

## Slide 4 - Net-Guided Low-Layer Assignment

Main idea:

- build per-net edge lists,
- score candidate layers with continuity and overflow penalties,
- prefer low legal layers when `NTHU_NET_GUIDED_LOW_LAYER_FIRST=1`,
- use congestion fallback only when needed.

Key knobs:

```text
NTHU_FAST_GREEDY_LAYER=1
NTHU_FAST_GREEDY_LAYER_NET_GUIDED=1
NTHU_NET_GUIDED_LOW_LAYER_FIRST=1
```

Why it helped:

- plain fast greedy chose layers edge-by-edge;
- net-guided assignment keeps one net on fewer layers and reduces via/WL growth.

## Slide 5 - Adaptive Repair Implementation

Main idea:

- run a short initial repair,
- measure overflow,
- if overflow remains, continue P2 from the completed iteration,
- if overflow is high, raise P2 max iteration,
- if overflow is small, cap extra repair to avoid over-repair.

Key env:

```text
NTHU_ADAPTIVE_LEGAL_REPAIR=1
NTHU_ADAPTIVE_REPAIR_P2_MAX_ITER=10
NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_TRIGGER=200
NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_MAX_ITER=24
NTHU_ADAPTIVE_SMALL_OVERFLOW_P2_LIMIT=50
NTHU_ADAPTIVE_SMALL_OVERFLOW_P2_ROUNDS=1
```

Impact:

- legal7 clean run: `1.752x`, WL avg/worst `1.118/1.151`, `7/7` legal;
- requested12 clean run: `1.345x`, WL avg/worst `1.158/1.284`,
  `10/12` legal, total overflow `166`.

## Slide 6 - Edge-Count Post-Processing

Main idea:

- count overflow edges touched by each candidate,
- sort candidates by overflow edge count, max overflow, and total overflow,
- spend repair time on denser overflow candidates first.

Impact:

- requested12 speed frontier: `5.38x`;
- 16-case matrix median speedup: `4.331x`;
- legal coverage poor, so it is not a final legal strategy.

Use this as an ablation:

> The router can be much faster if we stop repair early; the hard part is doing
> so without leaving overflow.

## Slide 7 - Multicore and CUDA Lessons

OpenMP:

- scans/reductions parallelized correctly,
- route mutation loop remains sequential,
- conflict-aware prototype increased CPU use but changed route order and was
  slower.

CUDA:

- standalone scorer fast,
- integrated CUDA accounts for about one second inside a roughly 195-second A3
  route,
- dual GPU did not improve single-case latency.

Conclusion:

> Future parallel work must batch independent route proposals and commit them
> deterministically.  Small kernels and direct shared-state parallelism do not
> move end-to-end runtime.

## Slide 8 - Bounded-Length Diagnosis

Goal:

- reduce detour/WL by rejecting over-length maze paths.

What failed:

- first implementation rolled back `two_pin.path` after `mm_maze_route_p()` had
  already mutated the tree;
- full12 bounded probe failed `12/12`.

Safe fix:

- pass `max_path_edges` into `MM_mazeroute`;
- reject before `adjust_twopin_element()`.

Result:

- A2/A4 smoke legal and slightly lower WL;
- A2 `2.557x` slower, A4 `6.039x` slower;
- keep opt-in, final disabled.

## Slide 9 - Accepted vs Rejected

Accepted in final family:

- net-guided low-layer fast layer,
- adaptive legal repair,
- high-overflow P2 budget,
- edge-count ordering as a controlled candidate priority.

Rejected or opt-in:

- OpenMP scans as final speed claim,
- conflict-aware reroute prototype,
- CUDA single/dual GPU as final path,
- strict legal maze,
- bounded-length reject-only guard,
- layer penalty tuning.

Detailed source:

- `../02-methods-by-commit-and-result.md`
- `../01-final-router-optimization-zh.md`
