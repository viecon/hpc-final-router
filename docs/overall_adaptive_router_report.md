# Overall Adaptive Router Report

Date: 2026-06-04
Branch: `vm-fastest-benchmark-guard`
Code commit: `0f7103a`

## Requirement Clarification

The final router must be one overall strategy.  It must not select a different
strategy by testcase name.  Benchmark-specific portfolio selection is only useful
for diagnosis, not as the final result.

The implemented final candidate is therefore a single adaptive router behavior:

1. Use low-layer-first net-guided fast layer assignment.
2. Run a short initial P3 repair.
3. If overflow is still detected, continue P2 repair from the completed P2
   iteration up to a configured maximum.
4. Run a deeper P3 repair.

The trigger is runtime routing state (`overflow > trigger`), not benchmark name.

## No Testcase Hardcoding

The final candidate was audited as one overall router behavior:

- No testcase-name branch was added for `adaptec`, `bigblue`, `newblue`, or any
  specific benchmark filename.
- The adaptive branch is only:
  `cal_max_overflow() > NTHU_ADAPTIVE_REPAIR_TRIGGER_OVERFLOW`.
- Tunables are global CLI/environment settings used for every benchmark in the
  run.
- Existing benchmark filename macros in the original parameter parser are input
  aliases from the upstream code, not optimization selection logic.

## Implemented Router Changes

### Low-Layer Net-Guided Layer Assignment

Environment:

```text
NTHU_FAST_GREEDY_LAYER=1
NTHU_FAST_GREEDY_LAYER_NET_GUIDED=1
NTHU_NET_GUIDED_LOW_LAYER_FIRST=1
```

Purpose:

- Keep fast layer assignment.
- Prefer lower legal layers to reduce via/wirelength inflation.
- Use congestion fallback only when a low layer is not legal.

### Overflow-Triggered Adaptive Repair

Environment:

```text
NTHU_ADAPTIVE_LEGAL_REPAIR=1
NTHU_ADAPTIVE_REPAIR_TRIGGER_OVERFLOW=0
NTHU_ADAPTIVE_REPAIR_P2_MAX_ITER=10
```

Logic:

- After the first post-processing pass, call `cal_max_overflow()`.
- If overflow is zero, stop.
- If overflow remains, resume P2 repair from the actual completed P2 iteration.
- This avoids the previous bug where the adaptive repair skipped P2 iteration 7.

### Adaptive P3 Budget

Environment:

```text
NTHU_ADAPTIVE_INITIAL_P3_MAX_ITER=4
NTHU_ADAPTIVE_INITIAL_P3_INIT_BOX=66
NTHU_ADAPTIVE_INITIAL_P3_BOX_INC=122
NTHU_ADAPTIVE_REPAIR_P3_MAX_ITER=24
NTHU_ADAPTIVE_REPAIR_P3_INIT_BOX=80
NTHU_ADAPTIVE_REPAIR_P3_BOX_INC=140
```

Logic:

- First P3 pass is short.
- Deep P3 is only used after overflow-triggered adaptive P2 repair.
- This is a routing-state adaptive rule, not a benchmark-specific switch.

## Final Overall Strategy

Command configuration used for final overall tests:

```text
--p2-init-box-size=5 --p2-box-expand-size=5
--p2-max-iteration=6 --overflow-threshold=1800
--p3-max-iteration=24 --p3-init-box-size=80 --p3-box-expand-size=140

NTHU_FAST_GREEDY_LAYER=1
NTHU_FAST_GREEDY_LAYER_NET_GUIDED=1
NTHU_NET_GUIDED_LOW_LAYER_FIRST=1
NTHU_ADAPTIVE_LEGAL_REPAIR=1
NTHU_ADAPTIVE_REPAIR_P2_MAX_ITER=10
NTHU_ADAPTIVE_INITIAL_P3_MAX_ITER=4
NTHU_ADAPTIVE_INITIAL_P3_INIT_BOX=66
NTHU_ADAPTIVE_INITIAL_P3_BOX_INC=122
NTHU_ADAPTIVE_REPAIR_P3_MAX_ITER=24
NTHU_ADAPTIVE_REPAIR_P3_INIT_BOX=80
NTHU_ADAPTIVE_REPAIR_P3_BOX_INC=140
NTHU_POST_SORT_MODE=edge_count
```

Result root:

```text
/home/ubuntu/hpc-final-router/results/vm_wl120_speed3/overall_adaptive_single_0f7103a_20260604T140141Z
```

## Legal7 Result

This is the cleanest final comparison because these seven original rows are
already legal and therefore must remain legal.

| Benchmark | Original s | Overall s | Speedup | WL ratio | OF / Max |
| --- | ---: | ---: | ---: | ---: | ---: |
| adaptec1 | 441.963 | 421.791 | 1.05x | 1.127 | 0 / 0 |
| adaptec3 | 479.186 | 430.629 | 1.11x | 1.114 | 0 / 0 |
| adaptec4 | 130.667 | 114.173 | 1.14x | 1.110 | 0 / 0 |
| adaptec5 | 1240.592 | 980.566 | 1.27x | 1.103 | 0 / 0 |
| bigblue1 | 1206.307 | 700.567 | 1.72x | 1.114 | 0 / 0 |
| newblue2 | 76.516 | 51.719 | 1.48x | 1.151 | 0 / 0 |
| newblue6 | 3278.214 | 1170.261 | 2.80x | 1.092 | 0 / 0 |

Aggregate:

| Metric | Original | Overall adaptive |
| --- | ---: | ---: |
| Total runtime | 6853.445s | 3869.707s |
| Speedup | 1.00x | 1.771x |
| Legal rows | 7 / 7 | 7 / 7 |
| Average WL ratio | 1.000 | 1.116 |
| Worst WL ratio | 1.000 | 1.151 |
| Total overflow | 0 | 0 |

## Requested12 Result

Same overall strategy, same code, same rule set.

Result root:

```text
/home/ubuntu/hpc-final-router/results/vm_wl120_speed3/overall_adaptive_requested12_0f7103a_20260604T142342Z
```

Aggregate:

| Scope | Cases | Legal rows | WL<=1.2 rows | Runtime | Speedup | Guard |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| all12 | 12 | 8 / 12 | 10 / 12 | 13339.551s | 0.922x | pass |
| original-legal subset | 7 | 7 / 7 | 7 / 7 | 4290.141s | 1.597x | pass |

The all12 scope includes cases where original already overflowed.  The required
guard is that originally legal cases remain legal; that guard passed.

## Rejected Overall Variant

I also tested adding dogleg/range-skip fast paths to the same adaptive strategy.

```text
/home/ubuntu/hpc-final-router/results/vm_wl120_speed3/overall_adaptive_dogleg_0f7103a_20260604T162503Z
/home/ubuntu/hpc-final-router/results/vm_wl120_speed3/overall_adaptive_dogleg_p2m12_0f7103a_20260604T165333Z
```

Results:

| Variant | Speedup | Legal rows | Total overflow | Decision |
| --- | ---: | ---: | ---: | --- |
| dogleg p2m10 | 1.810x | 4 / 7 | 218 | reject |
| dogleg p2m12 | 1.792x | 5 / 7 | 92 | reject |

Dogleg improved some runtimes but left overflow on original-legal cases, so it is
not acceptable as the final overall router.

## Final Status

The final overall router now satisfies:

- Single strategy for all benchmarks.
- No benchmark-name hardcoding.
- Original-legal cases remain legal.
- WL for original-legal cases stays within `1.2x`.

It does not reach the requested `2.8x-3.2x` overall speedup.  The achieved legal
overall speedup is:

- `1.771x` on the dedicated legal7 run.
- `1.597x` on the requested12 run, restricted to originally legal cases.

The measured reason is that the fast paths that approach `2.8x+` leave overflow,
and the legal repair needed for `adaptec5` and `bigblue1` consumes the saved time.
