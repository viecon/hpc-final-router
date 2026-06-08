# VM Router Optimization Report

Date: 2026-06-05
Branch: `vm-fastest-benchmark-guard`
Final tested commit: `9c10d52`
VM: `ubuntu@202.5.251.114`, 16 vCPU, Apptainer `router.sif`
Build: `external/nthu-route/build-release-vm-strict-cpu`

## Final Overall Strategy

This is one overall strategy. It does not switch by benchmark name.  The only
adaptive decision is based on measured routing state: if the first repair-entry
overflow is high, spend more P2 repair budget.

Final command shape:

```bash
NTHU_FAST_GREEDY_LAYER=1 \
NTHU_FAST_GREEDY_LAYER_NET_GUIDED=1 \
NTHU_NET_GUIDED_LOW_LAYER_FIRST=1 \
NTHU_ADAPTIVE_LEGAL_REPAIR=1 \
NTHU_ADAPTIVE_REPAIR_P2_MAX_ITER=10 \
NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_TRIGGER=200 \
NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_MAX_ITER=24 \
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

Why this strategy:

- Net-guided fast greedy layer assignment keeps the fast layer path while avoiding
  the worst WL inflation from independent per-edge layer choices.
- Adaptive legal repair keeps original-legal cases legal.
- Small-overflow cap avoids over-repair on easy legal cases.
- High-overflow P2 budget fixes or reduces difficult original-overflow cases
  without touching legal7: in the legal7 guard, repair-entry overflows were
  `25`, `50`, `137`, and `175`, all below the `200` trigger.

Code-level changes in this round:

- `external/nthu-route/src/router/Construct_2d_tree.cpp`: added
  `NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_TRIGGER` and
  `NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_MAX_ITER`.  This raises repair P2 budget only
  when the measured overflow after initial post-processing is above the trigger.
- `external/nthu-route/src/router/Post_processing.cpp`: added an opt-in
  `NTHU_POST_STALL_LIMIT` guard for plateaued post-processing.  It is not part of
  the final command because the selected P2=24 rule gave better hard-case results.
- `external/nthu-route/src/router/Range_router.cpp`: added an opt-in strict legal
  maze fallback with phase and iteration gates.  It is left off in the final
  command after the clean probe showed slower plateau behavior.

## Latest Results

Result roots:

- Legal7 guard: `/home/ubuntu/hpc-final-router/results/vm_final_guard/legal7_trigger_p2_20_9c10d52_20260605T012126Z`
- P2=24 hard rerun: `/home/ubuntu/hpc-final-router/results/vm_high_p2_clean/clean_p2_24_hard3_9c10d52_20260605T013320Z`
- P2=24 A2/N5 rows: `/home/ubuntu/hpc-final-router/results/vm_high_p2_budget_sweep/high_p2_budget_sweep_9c10d52_20260605T004706Z`

The Legal7 guard was run with high-overflow max `20`, but the high-overflow rule
did not fire on any legal7 case. Therefore the final `max=24` strategy follows
the same legal7 routing path.

### Legal7 Guard

All original-legal cases remain legal.

Aggregate:

- Legal: `7/7`
- Original total time: `6853.445s`
- Final total time: `3910.736s`
- Speedup: `1.752x`
- Worst WL ratio: `1.151x`
- Average WL ratio: `1.118x`

| Benchmark | Original s | Final s | Speedup | WL Ratio | Overflow |
| --- | ---: | ---: | ---: | ---: | ---: |
| adaptec1 | 441.963 | 356.407 | 1.240x | 1.134 | 0 / 0 |
| adaptec3 | 479.186 | 456.877 | 1.049x | 1.114 | 0 / 0 |
| adaptec4 | 130.667 | 125.637 | 1.040x | 1.110 | 0 / 0 |
| adaptec5 | 1240.592 | 857.268 | 1.447x | 1.112 | 0 / 0 |
| bigblue1 | 1206.307 | 752.409 | 1.603x | 1.114 | 0 / 0 |
| newblue2 | 76.516 | 57.217 | 1.337x | 1.151 | 0 / 0 |
| newblue6 | 3278.214 | 1304.920 | 2.512x | 1.092 | 0 / 0 |

### Requested12

Requested set: adaptec1-5, bigblue1-3, newblue1, newblue2, newblue5, newblue6.

Aggregate:

- Legal: `10/12`
- Original-legal guard: `7/7`
- Original total time: `12295.597s`
- Final total time: `9144.395s`
- Speedup: `1.345x`
- Total overflow: `166`
- Worst WL ratio: `1.284x`
- Average WL ratio: `1.158x`

| Benchmark | Original Legal | Original s | Final s | Speedup | WL Ratio | Overflow |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| adaptec1 | yes | 441.963 | 356.407 | 1.240x | 1.134 | 0 / 0 |
| adaptec2 | no | 173.992 | 292.934 | 0.594x | 1.186 | 0 / 0 |
| adaptec3 | yes | 479.186 | 456.877 | 1.049x | 1.114 | 0 / 0 |
| adaptec4 | yes | 130.667 | 125.637 | 1.040x | 1.110 | 0 / 0 |
| adaptec5 | yes | 1240.592 | 857.268 | 1.447x | 1.112 | 0 / 0 |
| bigblue1 | yes | 1206.307 | 752.409 | 1.603x | 1.114 | 0 / 0 |
| bigblue2 | no | 1020.139 | 1084.253 | 0.941x | 1.284 | 68 / 2 |
| bigblue3 | no | 907.876 | 887.277 | 1.023x | 1.183 | 0 / 0 |
| newblue1 | no | 1043.267 | 1106.592 | 0.943x | 1.235 | 98 / 2 |
| newblue2 | yes | 76.516 | 57.217 | 1.337x | 1.151 | 0 / 0 |
| newblue5 | no | 2296.878 | 1862.603 | 1.233x | 1.186 | 0 / 0 |
| newblue6 | yes | 3278.214 | 1304.920 | 2.512x | 1.092 | 0 / 0 |

Compared with the previous selected strategy on original-overflow cases:

| Benchmark | Previous Overflow | Final Overflow | Previous s | Final s | Time vs Previous |
| --- | ---: | ---: | ---: | ---: | ---: |
| adaptec2 | 0 / 0 | 0 / 0 | 268.743 | 292.934 | 0.917x |
| bigblue2 | 314 / 4 | 68 / 2 | 1427.456 | 1084.253 | 1.317x |
| bigblue3 | 42 / 4 | 0 / 0 | 1513.179 | 887.277 | 1.705x |
| newblue1 | 504 / 4 | 98 / 2 | 2128.084 | 1106.592 | 1.923x |
| newblue5 | 94 / 4 | 0 / 0 | 3611.587 | 1862.603 | 1.939x |

## Optimization Attempts

Selected:

- Net-guided fast greedy layer assignment.
- Adaptive legal repair with small-overflow cap.
- High-overflow adaptive P2 budget: `trigger=200`, `max_iter=24`.

Tested but not selected:

- `NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_MAX_ITER=16`: fixed B3 and improved N5, but
  left B2/N1/N5 with more residual overflow.
- `NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_MAX_ITER=20`: improved B2 to `104 / 4`,
  N1 to `184 / 2`, B3 to `0 / 0`, and N5 to `4 / 2`; P2=24 was better.
- Strict legal maze fallback without post-accept: did not crash, but plateaued
  around B2 2D overflow `34` and N1 2D overflow `48`, slower than P2=24 clean.
- Strict legal maze with `NTHU_POST_ACCEPT_IMPROVEMENT=1`: rejected. A2/B3
  crashed during post-processing tree rebuild; post-accept is kept off.
- Excess/neighbor post repair: rejected because it made A2 illegal and worsened
  B2/B3/N1 overflow in the hard sweep.
- OpenMP reroute batching and CUDA dual-GPU paths remain opt-in only. Prior VM
  utilization logs showed real utilization problems are algorithmic: the dominant
  mutation loop is sequential, while current CUDA work is too small and fragmented
  to move end-to-end runtime.

## Correctness Notes

- `external/nthu-route-original` stayed unchanged on local and VM checks.
- VM benchmarks were run only on `ubuntu@202.5.251.114`.
- During one sweep the VM disk filled because old `.nthu.out` artifacts occupied
  most of the 94GB disk. Old generated outputs were removed while preserving CSV
  summaries and logs; corrupted rows from that sweep were rerun in clean result
  directories before being reported.
