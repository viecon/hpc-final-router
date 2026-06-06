# Transactional Reroute Technical Comparison

Date: 2026-06-06
Branch: `experiment-transactional-virtual-ripup`
Codebase: `codebases/hpc-final-router-virtual-ripup`

## Goal

Keep the main router algorithm aligned with NTHU-Route:

- keep NTHU's initial routing, rip-up/reroute loop, congestion map, monotonic routing,
  maze repair, and layer assignment;
- use the papers only for the parallel synchronization model: snapshot reads,
  transaction-local proposals, conflict-aware scheduling, and deterministic commit;
- avoid benchmark-name hardcoding and avoid best-row portfolios as final scores.

## Technical Comparison

| Method | Core idea | Relation to our code | Adopted now |
| --- | --- | --- | --- |
| NTHU-Route serial reroute | Remove old two-pin path, search a new path on the updated congestion map, then insert. | This is the correctness baseline. The important semantic detail is that search sees its own old path already removed. | Preserved. |
| Previous transactional wave branch | Propose paths in parallel, then serially commit accepted proposals. | Safe for writes, but proposal searched on the unremoved old path and commit checked candidate capacity before remove. This can reject candidates that the serial NTHU flow would allow. | Repaired in this branch. |
| NCTU-GR 2.0 | Task-based collision-aware routing and bounded-length maze routing instead of pure static partitioning. | Useful as a scheduling model: choose parallel tasks by collision risk, not testcase name. Full algorithm replacement is not suitable because we must remain NTHU-like. | Future Stage B: tile/conflict scheduler. |
| DSD 2013 overlapped regions | Route-search runs in parallel without locks; area-update is exclusive; invalid candidates are canceled/rerouted. | This is closest to our implementation: workers read a snapshot and commit serially with capacity recheck. | Stage A implemented. |
| SPRoute | Uses net-level parallelism, detects livelock/stall, reduces parallelism, then switches to finer-grain routing near convergence. | Useful for adaptive wave size when commit rejection or overflow reduction stalls. | Future Stage C. |
| SPRoute 2.0 | Deterministic batching and race-free R&R operations. | Matches our deterministic commit order and fixed batch planning requirement. | Partially adopted. |
| Parallel IP partitioning | Solve rectangular subregions independently, then patch boundaries. | This changes the router architecture too much for the current NTHU-based constraint. It is only useful as background for spatial conflict boxes. | Not adopted. |

## Stage A Implementation: Virtual Rip-Up

The new branch adds transaction-local virtual rip-up in
`external/nthu-route/src/router/Range_router.cpp`.

Code-level changes:

- `TransactionEdgeKey` and `TransactionEdgeCounts` represent the old two-pin
  path as edge counts.
- `check_path_no_overflow_virtual_remove()` evaluates a candidate using:

```text
effective_demand(edge) =
  current_demand(edge)
  - one_net_demand_if_this_twopin_is_the_last_use_on_edge
  + candidate_insert_demand
```

- `find_strict_legal_maze_path()` now accepts an optional removed-edge view.
  It may reuse edges that belong only to the old path being rerouted, but still
  avoids remaining same-net edges because those can create cycles during tree
  reconstruction.
- The transaction commit is still deterministic and serial:

```text
if old path still overflows:
  remove old path from global congestion
  if candidate is legal on latest global congestion:
    insert candidate
  else:
    rollback by reinserting old path
```

This follows the DSD 2013 route-search / area-update split without changing
NTHU's global routing algorithm.

## Stage A VM Finding

Stage A built on the VM, and the log confirmed that `Range_router.cpp` was
compiled into `NthuRoute`.

First smoke:

```text
commit=b276c39
result=/home/ubuntu/hpc-final-router-virtual-ripup/results/vm_transactional_virtual_ripup/smoke_adaptec3_b276c39
benchmark=adaptec3.dragon70.3d.30.50.90
seconds=632.821977
total_wirelength=13698653
total_overflow=3288216
max_overflow=2
```

This proves that virtual rip-up alone does not make the no-fallback transaction
path legal on the original-legal guard set.  The transactional stage committed
many safe easy reroutes, but endpoint-stable proposals cannot replace NTHU's
hard serial reroute behavior on difficult nets.

## Stage B Implementation: Deterministic Serial Repair

The branch adds `NTHU_TRANSACTIONAL_SERIAL_REPAIR`, default enabled.

Flow:

```text
parallel transaction proposals
deterministic serial transaction commit
scan still-overflowing two-pins
run original NTHU range_router() serially on those remaining hard cases
```

This is not a router-algorithm replacement. It keeps NTHU's hard-case reroute
logic for nets that the safe transaction model could not resolve. The purpose is
to preserve correctness while still extracting parallel work from easy overflow
transactions.

The log now reports:

- `serial_repair`: remaining overflow two-pins repaired by original
  `range_router()`;
- `repair_skipped`: originally-overflow candidates that became clean before the
  serial repair scan;
- `repair_ms`: time spent in the deterministic hard-case repair phase.

The first unbounded repair probe on `adaptec3` showed why this must be adaptive:

```text
commit=9d5b1ff
first large batch:
  serial_repair=116360
  repair_ms=262589.405
second small batch:
  serial_repair=608
  repair_ms=11457.776
```

The large repair does preserve NTHU hard-case semantics, but it serializes too
much work and destroys the speed goal. Therefore the branch now bounds serial
repair with:

```text
NTHU_TRANSACTIONAL_SERIAL_REPAIR_MAX_CANDIDATES
default=5000
```

If the live overflow candidate count is above this threshold, the transaction
stage logs `repair_deferred` and skips serial repair for that large batch. Small
late batches still use original NTHU `range_router()` to clean hard residual
overflow. This is a routing-state policy, not benchmark-name selection.

## Correctness Contract

- Worker threads do not mutate global congestion.
- Global congestion is mutated only in deterministic commit order or in the
  final serial NTHU repair phase.
- A candidate accepted by the virtual view is not trusted blindly; it is checked
  again after serially removing the old path.
- If the latest map invalidates the candidate, the old path is restored.
- `external/nthu-router-original` and `external/nthu-route-original` remain
  untouched.

## Current Limitations

This is a Stage A repair, not the final multicore scheduler.

- `try_l_shape_fastpath()` and `try_dogleg_fastpath()` still generate candidates
  with their existing global congestion checks, so they may still reject some
  candidates that would become legal after virtual rip-up.
- `MonotonicRouting` still uses the original `Congestion::get_cost_2d()` view.
  Its final candidate is checked with virtual rip-up, but its cost search is not
  fully transaction-aware yet.
- Stage B still needs VM validation after the serial repair commit is pushed.

## Next Experiments

Use one fixed routing config, not selected rows:

1. Build this branch on the VM.
2. Run a small legal smoke first, especially the previously failing legal7 row.
3. Compare against the previous wave16 branch on `newblue2` and legal7.
4. Record `proposed`, `committed`, `commit_rejected`, `rollback`, final overflow,
   WL, and total runtime.
5. If Stage A is legal but underutilized, implement Stage B tile/conflict-aware
   scheduling with deterministic commit.

## References

- NCTU-GR 2.0 / collision-aware global routing:
  <https://ir.lib.nycu.edu.tw/bitstream/11536/21646/1/000318163800005.pdf>
- DSD 2013 overlapped routing regions:
  <https://www.researchgate.net/publication/262361280_A_Multithreaded_Parallel_Global_Routing_Method_with_Overlapped_Routing_Regions>
- SPRoute ICCAD 2019:
  <https://userweb.cs.txstate.edu/~burtscher/papers/iccad19.pdf>
- SPRoute 2.0 ASP-DAC 2022:
  <https://csl.yale.edu/~rajit/ps/ASPDAC_2022.pdf>
- Parallel IP global routing:
  <https://citeseerx.ist.psu.edu/document?doi=7d7bdc8bfc59bdc478c3b35e3fc31b641dcbc50c&repid=rep1&type=pdf>
