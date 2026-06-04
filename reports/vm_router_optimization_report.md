# VM Router Optimization Report

Date: 2026-06-05
Branch: `vm-fastest-benchmark-guard`
Final tested commit: `7318914`
VM: `ubuntu@202.5.251.114`, Apptainer `router.sif`, CPU release build `external/nthu-route/build-release-vm-wl-guard-cpu`

## Final Overall Strategy

This is one overall strategy. It does not select parameters by benchmark name.

- Keep the optimized NTHU router under `external/nthu-route`; `external/nthu-route-original` is unchanged.
- Use net-guided fast greedy layer assignment:
  - `NTHU_FAST_GREEDY_LAYER=1`
  - `NTHU_FAST_GREEDY_LAYER_NET_GUIDED=1`
  - `NTHU_NET_GUIDED_LOW_LAYER_FIRST=1`
- Use conservative adaptive legal repair:
  - initial P2 max 6, initial P3 max 4
  - repair P2 max 10, repair P3 max 24
  - `NTHU_POST_SORT_MODE=edge_count`
- Add state-driven small-overflow cap:
  - `NTHU_ADAPTIVE_SMALL_OVERFLOW_P2_LIMIT=50`
  - `NTHU_ADAPTIVE_SMALL_OVERFLOW_P2_ROUNDS=1`
  - If first repair overflow is small enough, run only one extra P2 round and let repair P3 finish. Larger-overflow cases still use the full repair budget.

Final command shape:

```bash
NTHU_FAST_GREEDY_LAYER=1 \
NTHU_FAST_GREEDY_LAYER_NET_GUIDED=1 \
NTHU_NET_GUIDED_LOW_LAYER_FIRST=1 \
NTHU_ADAPTIVE_LEGAL_REPAIR=1 \
NTHU_ADAPTIVE_REPAIR_P2_MAX_ITER=10 \
NTHU_ADAPTIVE_SMALL_OVERFLOW_P2_LIMIT=50 \
NTHU_ADAPTIVE_SMALL_OVERFLOW_P2_ROUNDS=1 \
NTHU_ADAPTIVE_INITIAL_P3_MAX_ITER=4 \
NTHU_ADAPTIVE_INITIAL_P3_INIT_BOX=66 \
NTHU_ADAPTIVE_INITIAL_P3_BOX_INC=122 \
NTHU_ADAPTIVE_REPAIR_P3_MAX_ITER=24 \
NTHU_ADAPTIVE_REPAIR_P3_INIT_BOX=80 \
NTHU_ADAPTIVE_REPAIR_P3_BOX_INC=140 \
NTHU_POST_SORT_MODE=edge_count \
./NthuRoute --p2-init-box-size=5 --p2-box-expand-size=5 \
  --p2-max-iteration=6 --overflow-threshold=1800 \
  --p3-max-iteration=24 --p3-init-box-size=80 --p3-box-expand-size=140
```

## Legal7 Result

Result root:
`/home/ubuntu/hpc-final-router/results/vm_dynamic_small50/overall_dynamic_small50_7df3b08_20260604T192922Z`

Aggregate:

- Legal: `7/7`
- Original-legal guard: `7/7`
- Total original time: `6853.445s`
- Total optimized time: `3551.687s`
- Speedup: `1.930x`
- Worst WL ratio: `1.151x`
- Average WL ratio: `1.118x`

| Benchmark | Time s | Speedup | WL Ratio | Overflow |
| --- | ---: | ---: | ---: | ---: |
| adaptec1 | 326.607 | 1.353x | 1.134 | 0 / 0 |
| adaptec3 | 431.561 | 1.110x | 1.114 | 0 / 0 |
| adaptec4 | 114.414 | 1.142x | 1.110 | 0 / 0 |
| adaptec5 | 792.782 | 1.565x | 1.112 | 0 / 0 |
| bigblue1 | 689.248 | 1.750x | 1.114 | 0 / 0 |
| newblue2 | 50.974 | 1.501x | 1.151 | 0 / 0 |
| newblue6 | 1146.101 | 2.860x | 1.092 | 0 / 0 |

## Requested12 Result

Result root:
`/home/ubuntu/hpc-final-router/results/vm_dynamic_small50_requested12/requested12_dynamic_small50_7318914_20260604T215705Z`

The requested set contains 12 benchmarks: adaptec1-5, bigblue1-3, newblue1, newblue2, newblue5, newblue6. Among these, the original router was legal on 7 cases. The optimized router is legal on all 7 original-legal cases.

Original-illegal cases were still run and recorded, but they are not used as zero-overflow guard failures.

| Benchmark | Original Legal | Time s | Speedup | WL Ratio | Overflow |
| --- | --- | ---: | ---: | ---: | ---: |
| adaptec1 | yes | 360.453 | 1.226x | 1.134 | 0 / 0 |
| adaptec2 | no | 268.743 | 0.647x | 1.186 | 0 / 0 |
| adaptec3 | yes | 453.237 | 1.057x | 1.114 | 0 / 0 |
| adaptec4 | yes | 120.832 | 1.081x | 1.110 | 0 / 0 |
| adaptec5 | yes | 867.539 | 1.430x | 1.112 | 0 / 0 |
| bigblue1 | yes | 783.132 | 1.540x | 1.114 | 0 / 0 |
| bigblue2 | no | 1427.456 | 0.715x | 1.289 | 314 / 4 |
| bigblue3 | no | 1513.179 | 0.600x | 1.183 | 42 / 4 |
| newblue1 | no | 2128.084 | 0.490x | 1.234 | 504 / 4 |
| newblue2 | yes | 53.993 | 1.417x | 1.151 | 0 / 0 |
| newblue5 | no | 3611.587 | 0.636x | 1.186 | 94 / 4 |
| newblue6 | yes | 1316.830 | 2.489x | 1.092 | 0 / 0 |

## Optimization Attempts

Selected:

- Net-guided fast layer assignment: replaced original KLAT-heavy layer assignment for the optimized path.
- Adaptive legal repair: keeps original-legal cases at zero overflow.
- Small-overflow P2 cap: improved A1/A5 by not spending full repair P2 when first repair overflow is already small.

Rejected or not selected:

- OpenMP/multithread reroute: A1 profile was `359.8s` single-core vs `583.2s` OpenMP batch. Utilization exists, but batching creates many serial fallbacks and scheduler overhead.
- Direct overflow candidate routing: faster on some cases but left A1/N6 illegal.
- Range skip remainder: reached about `2.01x` but left A1/B1 illegal. Final fallback made it legal but slowed aggregate to `1.90x`, worse than the selected strategy.
- Layer-only overflow repair: did not help A1 because the remaining overflow was true 2D capacity overflow, not layer assignment overflow.
- CUDA single/dual GPU A3 probes: single and dual GPU both ran around `191-200s`, but WL was about `22.4M` vs original `13.2M`, outside the final WL guard. Dual GPU did not materially improve single GPU for the selected quality target.

## Correctness Notes

- Final selected Legal7 has `overflow=0,max_overflow=0` on every row.
- Requested12 confirms every original-legal case remains legal.
- `external/nthu-route-original` / `external/nthu-router-original` diff was checked and remained empty.
