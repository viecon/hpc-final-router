# WL<=1.2 Single-Core Optimization Report

Date: 2026-06-04
Branch: `vm-fastest-benchmark-guard`
Code commit: `7300fb7`

## Goal

User target:

- Keep single-core wirelength within `1.2x` of `external/nthu-route-original`.
- Keep all originally legal cases legal: `overflow=0`, `max_overflow=0`.
- Try to reach about `2.8x` to `3.2x` speedup.

All tests and benchmarks in this report were run on the VM.  No files under
`external/nthu-route-original` were modified.

## VM Environment

- Host: VM at `ubuntu@202.5.251.114`
- CPU budget used by runner: up to 12 concurrent single-core router processes
- GPU not used for this specific single-core WL target
- Evaluator: `lab2-verifier.py`
- Build: `external/nthu-route/build-release-vm-wl-guard-cpu`
- OpenMP: off for router process measurements

Primary result roots:

```text
/home/ubuntu/hpc-final-router/results/vm_wl120_speed3/lowfirst_sweep_7300fb7_20260604T092057Z
/home/ubuntu/hpc-final-router/results/vm_wl120_speed3/plain_repair_sweep_7300fb7_20260604T103859Z
/home/ubuntu/hpc-final-router/results/vm_wl120_speed3/legal7_remaining_7300fb7_20260604T111203Z
/home/ubuntu/hpc-final-router/results/vm_wl120_speed3/moderate_repair_7300fb7_20260604T115045Z
/home/ubuntu/hpc-final-router/results/vm_wl120_speed3/output_repair_7300fb7_20260604T123206Z
```

## Implemented Change

Added an opt-in low-layer-first mode to the net-guided fast layer assignment:

```text
NTHU_NET_GUIDED_LOW_LAYER_FIRST=1
```

Logic:

- The previous net-guided layer assignment selected the lowest scoring legal
  layer, where congestion terms could push nets upward.
- That was good for legality, but it inflated via/wirelength.
- The new low-layer-first option chooses the first legal low layer before using
  congested fallback.  This keeps layer assignment closer to original low-layer
  behavior while preserving the fast greedy flow.

This is intentionally opt-in.  Default behavior is unchanged.

## Strategy Results

### Legal WL<=1.2 Portfolio

This is the best zero-overflow portfolio found in this round.

| Benchmark | Selected strategy | Original s | Selected s | Speedup | WL ratio | OF / Max |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| adaptec1 | `lowfirst_quality` | 441.963 | 318.287 | 1.39x | 1.142 | 0 / 0 |
| adaptec3 | `lowfirst_fast_a3style` | 479.186 | 240.558 | 1.99x | 1.163 | 0 / 0 |
| adaptec4 | `lowfirst_fast_a3style` | 130.667 | 98.323 | 1.33x | 1.111 | 0 / 0 |
| adaptec5 | `p2m10_p3m24_edge` | 1240.592 | 939.989 | 1.32x | 1.102 | 0 / 0 |
| bigblue1 | `p2m10_p3m24_edge` | 1206.307 | 688.489 | 1.75x | 1.114 | 0 / 0 |
| newblue2 | `lowfirst_fast_a3style` | 76.516 | 48.212 | 1.59x | 1.154 | 0 / 0 |
| newblue6 | `p2m10_p3m24_edge` | 3278.214 | 1160.438 | 2.82x | 1.091 | 0 / 0 |

Aggregate:

| Metric | Original | Selected |
| --- | ---: | ---: |
| Total runtime | 6853.445s | 3494.295s |
| Speedup | 1.00x | 1.961x |
| Average WL ratio | 1.000 | 1.125 |
| Worst WL ratio | 1.000 | 1.163 |
| Overflow guard | all zero | all zero |

Conclusion: the WL target and legality target are met, but the `2.8x-3.2x`
speedup target is not met under zero-overflow.  The best legal single-core result
in this round is `1.96x`.

### Illegal Speed Frontier

If overflow is ignored, the fastest WL<=1.2 rows are much faster:

| Benchmark | Fast strategy | Selected s | Speedup | WL ratio | OF / Max |
| --- | --- | ---: | ---: | ---: | ---: |
| adaptec1 | `lowfirst_fast_edgepost` | 206.811 | 2.14x | 1.156 | 1212 / 6 |
| adaptec3 | `lowfirst_fast_a3style` | 240.558 | 1.99x | 1.163 | 0 / 0 |
| adaptec4 | `lowfirst_fast_a3style` | 98.323 | 1.33x | 1.111 | 0 / 0 |
| adaptec5 | `lowfirst_edgepost` | 408.483 | 3.04x | 1.120 | 4888 / 10 |
| bigblue1 | `lowfirst_edgepost` | 291.542 | 4.14x | 1.146 | 3882 / 8 |
| newblue2 | `lowfirst_fast_a3style` | 48.212 | 1.59x | 1.154 | 0 / 0 |
| newblue6 | `edgepost_p3m6_limit1000` | 617.904 | 5.31x | 1.117 | 3660 / 10 |

Aggregate speed frontier:

- Total runtime: `1911.833s`
- Speedup: `3.585x`
- Average WL ratio: `1.138`
- Total overflow: `13642`

This proves that the `2.8x-3.2x` time range is reachable only if repair is
weakened.  It is not a valid final router result because original-legal cases
become illegal.

## Failed Repair Attempts

### Moderate P3 Repair

I tried increasing P3 effort and changing candidate order:

- `edgepost_p3m6_limit1000`
- `edgepost_p3m10_unlimited`
- `edgepost_hot_excess`
- `quality_hot_excess`

These improved neither legality nor speed enough.  Example rows:

| Benchmark | Strategy | Seconds | WL ratio | OF / Max |
| --- | --- | ---: | ---: | ---: |
| adaptec5 | `edgepost_p3m6_limit1000` | 601.436 | 1.130 | 1466 / 10 |
| bigblue1 | `edgepost_p3m6_limit1000` | 344.105 | 1.150 | 2848 / 6 |
| newblue6 | `edgepost_p3m6_limit1000` | 617.904 | 1.117 | 3660 / 10 |
| adaptec5 | `quality_hot_excess` | 1423.072 | 1.122 | 38 / 2 |
| bigblue1 | `quality_hot_excess` | 886.075 | 1.135 | 262 / 6 |

Adding repair work without changing the repair algorithm mostly spends more time
on the same congested areas.

### Output-Level Targeted Repair

I also tried output-level near-legal repairs:

- `targeted_astar_segment_repair.py`
- `targeted_edge_split_fast_repair.py`

Results:

| Benchmark | Base output | Total s including repair | WL ratio | OF / Max | Result |
| --- | --- | ---: | ---: | ---: | --- |
| newblue6 | `p2m8_p3m30_default` | 1166.816 | 1.096 | 10 / 2 | no improvement |
| adaptec5 | `lowfirst_quality` | 975.347 | 1.119 | 6 / 2 | no improvement |
| bigblue1 | `lowfirst_quality` | 919.592 | 1.133 | 156 / 4 | no improvement |
| adaptec5 | `lowfirst_edgepost` | 2166.126 | 1.120 | 4888 / 10 | too large to repair |
| bigblue1 | `lowfirst_edgepost` | 1130.763 | 1.146 | 3882 / 8 | too large to repair |

The output repair scripts reduced some overflow-edge counts but did not reduce
total overflow on the hard rows.  This suggests the remaining overflows are not
isolated single-segment mistakes; they are congestion regions requiring real
rip-up/reroute decisions.

## Diagnosis

The optimization split is now clear:

- Wirelength inflation was mainly from fast layer assignment choosing upper
  layers too often.  `NTHU_NET_GUIDED_LOW_LAYER_FIRST=1` fixes this enough to
  keep all selected legal rows within `1.2x` original WL.
- The speed target is blocked by overflow repair on `adaptec5` and `bigblue1`.
  Fast edgepost variants reach `3x-4x` on those cases but leave thousands of
  overflow.  Legal fallback fixes overflow but drops to `1.32x-1.75x`.
- More P3 iterations or broader candidate filters do not solve this efficiently.
  They increase runtime but still leave overflow, or eventually become slower
  than the conservative fallback.

## Current Best Claim

The defensible final claim after this round is:

> The single-core router now has a zero-overflow WL<=1.2 portfolio on the
> original-legal seven cases, with total runtime `3494.295s` vs original
> `6853.445s`, i.e. `1.96x` speedup.  A `3.58x` WL<=1.2 speed frontier exists,
> but it is illegal and therefore cannot be used as the final result.

## Next Technical Direction

To reach `2.8x-3.2x` while staying legal, the next change should not be another
fixed P3 budget sweep.  It should change the internal repair algorithm:

1. During post-processing, identify connected overflow regions rather than
   independent overflow edges.
2. Rip up a bounded batch of nets touching that region.
3. Reinsert them with a strict-capacity-first maze route and only accept a batch
   if total overflow decreases.
4. Use the low-layer-first layer assignment after this repair.

That targets the real failure mode seen in A5/BB1: thousands of overflow units in
shared regions where single-edge or single-segment repairs do not reduce total
overflow.
