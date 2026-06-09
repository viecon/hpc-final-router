# NTHU-Route OpenMP Acceleration Notes

The source-level acceleration is implemented in the NTHU-Route source tree under
`external/nthu-route`. It does not change the high-level routing algorithm or the
sequential rip-up/reroute order. Instead, it parallelizes analysis kernels whose work
items are independent.

## Build Switch

OpenMP is controlled by CMake:

```bash
cmake -S external/nthu-route -B external/nthu-route/build-release-openmp-ON \
  -G Ninja -DCMAKE_BUILD_TYPE=Release -DNTHU_ROUTE_ENABLE_OPENMP=ON
```

The serial comparison build uses:

```bash
cmake -S external/nthu-route -B external/nthu-route/build-release-openmp-OFF \
  -G Ninja -DCMAKE_BUILD_TYPE=Release -DNTHU_ROUTE_ENABLE_OPENMP=OFF
```

At runtime:

```bash
export OMP_NUM_THREADS=8
```

## Parallelized Kernels

- `Congestion::pre_evaluate_congestion_cost()`
  - Parallel edge-cost update over the 2D congestion map.
- `Congestion::cal_max_overflow()`
  - Parallel max/sum reduction over edges.
- `Congestion::cal_total_wirelength()`
  - Parallel sum reduction over edge demand.
- `RangeRouter::divide_grid_edge_into_interval()`
  - Parallel scan of grid edges into thread-local interval vectors, followed by merge.
- `Post_processing::initial_for_post_processing()`
  - Parallel computation of per-two-pin overflow counters before sequential rerouting.
- Selected initialization loops in `Route_2pinnets`.

## Shared Compatibility Fix

Both `nthu_original` and `nthu_openmp` raise FLUTE `MAXD` from 350 to 1000. The
upstream parser routes nets below 1000 pins, but the bundled FLUTE implementation used
fixed arrays bounded by `MAXD=350`; on ISPD08 `adaptec1`, the 508-pin net triggered a
release-build segmentation fault before routing iterations. Since FLUTE is still fragile
on that high-degree net, both variants use the same deterministic chain-tree fallback
for nets with more than 350 pins. The fallback preserves connectivity for validation
while keeping the OpenMP comparison fair.

Both source trees also carry two parser/runtime compatibility fixes discovered while
debugging `adaptec1`: `RoutingRegion` now sizes per-layer vectors to the layer count
instead of creating one-element vectors, and FLUTE LUT loading now consumes CRLF lines
correctly for the checked-in `POWV9.dat` and `POST9.dat` files.

## Why Not Parallelize Reroute Directly First?

`RangeRouter::range_router()` removes and reinserts paths in a shared congestion map.
Running multiple reroutes concurrently would require locking, transactional deltas, or
collision-aware batching. This first version keeps the routing mutation order sequential
so the output remains easier to validate against the Lab2 checker while still exposing
parallel work inside repeated hot analysis phases.

## Experiment Naming

The Slurm baseline job now emits:

- `nthu_original`: NTHU-Route source baseline in `external/nthu-route-original`
- `nthu_openmp`: NTHU-Route built with OpenMP enabled
- `nctu`: NCTU-GR 2.0 binary baseline

The combined CSV is:

```text
results/real_baselines_summary.csv
```
