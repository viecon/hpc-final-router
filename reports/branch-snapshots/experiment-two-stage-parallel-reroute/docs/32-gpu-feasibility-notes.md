# NTHU-Route GPU Feasibility

This project should not use the synthetic mini-router as a primary result. The report
should stay centered on real ISPD08 routers: NTHU-Route source, OpenMP-modified
NTHU-Route, and NCTU-GR.

## Profiling Result

Profiling run:

```text
job=898535
router=nthu_profile_openmp
benchmark=adaptec1.capo70.3d.35.50.90
threads=4
status=ok
seconds=403.728216
total_overflow=0
```

Aggregated over the 11 main routing iterations:

```text
pre_evaluate_congestion_cost + overflow reduction + wirelength reduction:
  106.077 ms total, 0.0285% of measured iteration time

route_all_2pin_net:
  372731.170 ms total, 99.9715% of measured iteration time

Inside route_all_2pin_net:
  init_gridcell:       170.782 ms
  define_interval:      12.702 ms
  divide_interval:      11.575 ms
  specify_all_range: 372535.696 ms, 99.9477% of route_all_2pin_net
```

## GPU Conclusion

A simple GPU port of congestion reductions or interval construction is not worth doing:
those kernels are already millisecond-level work. Even an infinitely fast GPU version of
those parts would barely move end-to-end runtime.

The dominant bottleneck is `RangeRouter::specify_all_range()`, which performs
range expansion, two-pin query/sort, and sequential rip-up/reroute mutation of a shared
congestion map. This is pointer-heavy C++ code with order-sensitive updates, so a
direct CUDA port would be high risk and unlikely to fit the project schedule.

## Viable GPU Direction

GPU only becomes credible if the algorithm is changed around batching:

1. Select candidate congested two-pin nets.
2. Build independent or low-overlap batches on CPU.
3. Evaluate candidate paths for each batch on GPU using flattened arrays.
4. Copy candidate deltas back.
5. Commit accepted paths on CPU in a deterministic order.

This would be a new collision-aware batched rerouter. It is valid future work, but it is
not a small extension of the current NTHU-Route code.

## Real Candidate Probe

After the initial synthetic CUDA smoke test, NTHU-Route was instrumented to dump real
reroute candidates without changing routing decisions:

```text
NTHU_DUMP_REROUTE_CANDIDATES=results/nthu_reroute_candidates_adaptec2.csv
rows=318419 candidates from adaptec2

NTHU_DUMP_REROUTE_CANDIDATES=results/nthu_reroute_candidates_adaptec3.csv
rows=497329 candidates from adaptec3

NTHU_DUMP_REROUTE_CANDIDATES=results/nthu_reroute_candidates_adaptec1.csv
rows=554728 candidates from adaptec1
```

The standalone candidate scorer can now read this CSV:

```text
results/real_candidate_cpu_adaptec2.csv
candidate_cpu: 216.329 ms, 192.493 ms, 177.528 ms

results/real_candidate_cuda_adaptec2.csv
cuda_candidate: 259.600 ms, 99.254 ms, 88.335 ms

results/real_candidate_cpu_adaptec3.csv
candidate_cpu: 775.885 ms, 683.647 ms, 670.857 ms

results/real_candidate_cuda_adaptec3.csv
cuda_candidate: 499.733 ms, 283.319 ms, 274.272 ms
```

The first CUDA run includes warmup overhead; subsequent runs show roughly a 2x scorer
speedup on real NTHU candidate coordinates (`1.97x` on `adaptec2`, `2.43x` on
`adaptec3`, measured in `results/gpu_real_candidate_summary.csv`). This supports GPU
as a candidate-evaluation accelerator, while CPU still owns deterministic route commits.

A second prototype evaluates a heavier dogleg-style candidate set: HV/VH plus sampled
via-x/via-y paths similar to the NTHU dogleg fastpath. On the same real candidate CSVs,
CPU and CUDA produced identical wirelength/overflow rows, but CUDA was much faster after
warmup:

```text
results/gpu_real_dogleg_candidate_summary.csv
adaptec1: CPU avg 9041.765 ms, CUDA avg 256.353 ms, speedup 35.271x
adaptec2: CPU avg 4074.685 ms, CUDA avg 107.030 ms, speedup 38.071x
adaptec3: CPU avg 10465.150 ms, CUDA avg 309.457 ms, speedup 33.818x
```

This is the strongest GPU signal so far: not a direct maze-router port, but a batched
candidate scorer whose cost grows enough to amortize launch/copy overhead.

The scorer also has an optional `--gr` capacity-map loader. With projected 2D
capacities from the original ISPD `.gr` files, the dogleg scorer still shows
`32.43x` to `37.31x` speedup (`results/gpu_real_dogleg_gr_candidate_summary.csv`).
That run is useful as a capacity-map smoke test, but the exact route-choice
correctness evidence should use the non-`.gr` dogleg run, where CPU/CUDA path metrics
match exactly.

## End-to-End Fastpath Probe

The standalone scorer speedup is not an end-to-end NTHU speedup. A small final-parameter
NTHU sweep was run to check whether the same dogleg/L-shape idea helps inside the real
sequential routing loop:

```text
results/nthu_dogleg_final_a2_compare.csv
nthu_lshape_a1_final:             legal, 0.991x vs repeat baseline, WL +12331
nthu_dogleg0_score10_a1_final:    illegal, overflow 959204

results/nthu_dogleg_final_a2_compare.csv
nthu_lshape_a2_final:             legal, 0.992x vs repeat baseline, WL +4277
nthu_dogleg0_a2_final:            illegal, 0.671x, overflow 967822
nthu_dogleg0_score10_a2_final:    illegal, 0.789x, overflow 964808

results/nthu_dogleg_final_a3_compare.csv
nthu_lshape_a3_final:             legal, 1.038x vs repeat baseline, WL +13469
nthu_dogleg0_score10_a3_final:    legal, 1.045x, WL -23
```

This reinforces the GPU position: dogleg-style candidate evaluation is promising, but
safe end-to-end use needs a selective per-benchmark or congestion-aware gate plus CPU
commit/checking. It should not be enabled globally.

The current all-legal mixed setting is now r6:

```text
results/nthu_fallback_p2_serial_final_r6_summary.csv
adaptec1: P2 threshold 1400, no dogleg, 235.013917s
adaptec2: P2 threshold 245 + P3 box 20/30 + dogleg score500 gate, 83.571947s
adaptec3: P2 threshold 4000 + dogleg score1 gate, 271.006949s
```

## Aggressive End-to-End CUDA Hook

An opt-in CUDA hook now exists inside NTHU `RangeRouter`:

```text
NTHU_CUDA=ON
NTHU_DOGLEG_FASTPATH=1
NTHU_CUDA_DOGLEG_PRESELECT=1
```

The implementation batches the dogleg candidate-cost preselection on GPU, then lets the
existing CPU path perform length/overflow checks and commit routes. If the GPU-selected
candidate is not acceptable, the router falls back to the existing CPU dogleg search.
This keeps legality conservative while testing whether the `33x-38x` standalone dogleg
scorer speedup survives inside the real NTHU loop.

Files:

```text
external/nthu-route/src/router/CudaDogleg.*
external/nthu-route/src/router/Range_router.*
scripts/run_nthu_ispd08.sh
scripts/submit_nthu_cuda_preselect_a3.sh
```

Build status: both the default CPU/stub build and the CUDA-enabled build pass in
`router.sif`. End-to-end probes targeted `adaptec3` score10 and score5:

```text
results/nthu_cuda_preselect_a3_summary.csv
results/nthu_cuda_preselect_a3_compare.csv
results/nthu_cuda_preselect_a3_score5_summary.csv
results/nthu_cuda_preselect_a3_score5_compare.csv
```

Measured end-to-end effect:

```text
score10 CUDA preselect: 288.314292s vs CPU 290.105237s, legal, 1.006212x
score5 CUDA preselect:  285.901136s vs CPU 286.073167s, legal, 1.000602x
```

So the hook is correct and slightly positive, but the current router-level gain is tiny.
The stronger practical improvement is the CPU dogleg score1 gate in r6.

## Report Position

Use the GPU finding as a scoped result:

- The project attempted to identify GPU-suitable kernels.
- Profiling showed the obvious data-parallel kernels are not the bottleneck.
- The real bottleneck is sequential shared-state rerouting.
- Real-candidate CUDA scorers show GPU can help the batched-evaluation part,
  especially for dogleg-style candidate scoring.
- Therefore, the credible GPU next step is collision-aware batching with CPU commit,
  not a direct CUDA port of the whole maze router.
