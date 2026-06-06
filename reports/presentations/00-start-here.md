# Presentation Start Here

Date: 2026-06-06

Use this file as the first stop when preparing slides.  The goal is to keep the
presentation focused on final defensible claims, while still making the raw
evidence traceable.

## Recommended Reading Order

| Order | File | Why first |
| ---: | --- | --- |
| 1 | `01-performance-and-score.md` | Starts from the routing problem, benchmark set, original runtime, main-branch bottlenecks, and final speedup. |
| 2 | `02-optimization-methods.md` | Explains what was changed in the router and why each method helped or failed. |
| 3 | `03-timeline-and-correctness.md` | Separates early portfolios, VM probes, final global-strategy results, and rejected probes. |
| 4 | `../01-final-router-optimization-zh.md` | Full Chinese report for detailed explanations and backup slides. |
| 5 | `../../docs/00-evidence-index.md` | Raw-data index when a number needs a dated source or VM result root. |

## Slide Flow

For a short presentation:

1. What global routing is: connect nets on a capacity-limited grid.
2. Why it matters: runtime, wirelength, overflow, and legal routing all matter.
3. Benchmark set and original NTHU-Route runtime.
4. What the `origin/main` docs already showed: the bottleneck is sequential
   rip-up/reroute and repair effort, not simple reduction kernels.
5. Current acceleration strategy: net-guided fast layer, adaptive repair,
   high-overflow P2 budget, and edge-count priority.
6. Original vs current result: runtime, WL ratio, overflow, and original-legal
   cases.
7. Why some faster rows are not the final claim: portfolios, high-WL rows, and
   illegal runtime frontiers.
8. Future work: where speed is still blocked.

For a deeper technical presentation:

1. Start with the short flow above.
2. Add the method table from `../02-methods-by-commit-and-result.md`.
3. Add utilization evidence from `../../docs/21-vm-multicore-utilization-log.md`
   and `../../docs/22-vm-cuda-utilization-log.md`.
4. Add raw result roots from `../../docs/00-evidence-index.md` only when the
   audience asks for reproducibility.

## Naming Convention

- `reports/presentations/00-*`: entry point.
- `reports/presentations/01-*`: performance and score quality.
- `reports/presentations/02-*`: optimization method explanation.
- `reports/presentations/03-*`: chronology and correctness guard.
- `reports/01-*`: final synthesized report.
- `reports/02-*` to `06-*`: supporting method, comparison, and probe reports.
- `docs/00-*`: raw evidence index.
- `docs/10-*`: early source/Slurm-era experiment notes.
- `docs/20-*`: VM experiment and utilization logs.
- `docs/30-*`: design notes.
- `docs/40-*`: runbooks and rerun plans.
- `docs/90-*`: old planning material.
