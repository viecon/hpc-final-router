# Aggressive Smoke Protocol

Date: 2026-06-07
Branch: `experiment-aggressive-smoke-protocol`

## Rule

Every aggressive optimization attempt must record:

- previous version / previous strategy;
- candidate version / candidate strategy;
- original NTHU baseline denominator;
- one easy smoke and one hard smoke;
- a 3x-original timeout gate;
- whether a failure is an implementation/supporting-code issue or an invalid
  optimization logic.

The smoke pair is:

| Role | Benchmark | Original seconds | 3x kill gate |
| --- | --- | ---: | ---: |
| easy | `newblue2.fastplace90.3d.50.20.100` | 76.516 | 230s |
| hard | `adaptec4.aplace60.3d.30.50.90` | 130.667 | 392s |

The helper script is:

```text
scripts/run_vm_aggressive_smoke.sh
```

It writes separate logs per strategy/benchmark and summarizes:

```text
results/vm_aggressive_smoke/<run_id>/smoke_summary.csv
results/vm_aggressive_smoke/<run_id>/strategy_catalog.csv
results/vm_aggressive_smoke/<run_id>/original_baseline.csv
```

## Previous Failed Direction: Transactional Reroute

Previous code branch:

```text
experiment-transactional-virtual-ripup
last commit: 8a9ad5c
```

Observed smoke:

| Benchmark | Original s | Candidate s | Speedup | Result |
| --- | ---: | ---: | ---: | --- |
| `newblue2` | 76.516 | ~71.116 | ~1.08x | legal |
| `adaptec4` | 130.667 | 242.157 | 0.54x | illegal, overflow 3.14M |
| `adaptec3` | 479.186 | 731.206 | 0.66x | illegal, overflow 3.27M |
| `adaptec2` | 173.992 | 720s timeout | <0.24x | no summary |

Classification:

- This is not only a bad support configuration.
- Single-case rerun did not recover speed or legality.
- The optimization logic is rejected for now.

Reason:

- The implementation adopted snapshot/proposal/deterministic commit, but not the
  full collision-aware or adaptive-routing algorithm from the papers.
- Hard cases need NTHU's serial rip-up/reroute semantics.  Bounded transaction
  proposals cannot safely rewrite the multi-terminal tree, and capped serial
  repair leaves overflow.

References for the rejected direction:

- NCTU-GR 2.0: collision-aware task scheduling and bounded-length maze routing.
- DSD 2013 overlapped routing regions: parallel route-search, exclusive
  area-update.
- SPRoute / SPRoute 2.0: adaptive parallelism and deterministic batching.

## Next Candidate: `aggressive_p3lite_v1`

Previous strategy:

```text
prev_final
```

This is the final high-overflow adaptive P2 budget strategy from
`reports/03-final-vm-strategy-results.md`.

Candidate strategy:

```text
aggressive_p3lite_v1
```

Logic:

- keep net-guided fast greedy layer assignment;
- keep routing-state adaptive legal repair;
- reduce initial P3 effort from 4 rounds to 1;
- reduce repair P2/P3 effort;
- add a post-processing overflow limit after the first round.

Hypothesis:

If the current final strategy spends too much time in early/deep P3 on easy or
moderate cases, this should improve time.  If it becomes illegal or slower, the
problem is not simply excessive P3 effort; the strategy needs a different repair
logic.

No new paper claim is attached to this candidate. It is an aggressive extension
of the already documented adaptive-budget direction.
