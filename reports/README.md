# Reports Index

This directory is the main-facing report entry point.  The raw experiment
documents from non-main branches are preserved under
[branch-snapshots/](branch-snapshots/).  Those snapshots include only `docs/`
and `reports/`; experiment code was not merged into `main`.

## Suggested Reading Order

| Order | File | Purpose |
| ---: | --- | --- |
| 1 | [../docs/00-evidence-index.md](../docs/00-evidence-index.md) | Overall evidence map and scoring convention. |
| 2 | [branch-snapshots/README.md](branch-snapshots/README.md) | Source branch and commit table. |
| 3 | [branch-snapshots/vm-fastest-benchmark-guard/reports/01-final-router-optimization-zh.md](branch-snapshots/vm-fastest-benchmark-guard/reports/01-final-router-optimization-zh.md) | Main final-router optimization report draft. |
| 4 | [branch-snapshots/vm-fastest-benchmark-guard/reports/02-methods-by-commit-and-result.md](branch-snapshots/vm-fastest-benchmark-guard/reports/02-methods-by-commit-and-result.md) | Optimization method timeline and result summary. |
| 5 | [branch-snapshots/experiment-proposal-reroute-v7/reports/09-aggressive-smoke-protocol.md](branch-snapshots/experiment-proposal-reroute-v7/reports/09-aggressive-smoke-protocol.md) | Latest aggressive proposal-reroute experiments and rejected/global-gate notes. |

## Presentation Material

Start with:

| Path | Purpose |
| --- | --- |
| [branch-snapshots/vm-fastest-benchmark-guard/reports/presentations/README.md](branch-snapshots/vm-fastest-benchmark-guard/reports/presentations/README.md) | Presentation file map. |
| [branch-snapshots/vm-fastest-benchmark-guard/reports/presentations/00-start-here.md](branch-snapshots/vm-fastest-benchmark-guard/reports/presentations/00-start-here.md) | Slide ordering and framing. |
| [branch-snapshots/vm-fastest-benchmark-guard/reports/presentations/01-performance-and-score.md](branch-snapshots/vm-fastest-benchmark-guard/reports/presentations/01-performance-and-score.md) | Performance/score slides. |
| [branch-snapshots/vm-fastest-benchmark-guard/reports/presentations/02-optimization-methods.md](branch-snapshots/vm-fastest-benchmark-guard/reports/presentations/02-optimization-methods.md) | Optimization methods slides. |
| [branch-snapshots/vm-fastest-benchmark-guard/reports/presentations/03-timeline-and-correctness.md](branch-snapshots/vm-fastest-benchmark-guard/reports/presentations/03-timeline-and-correctness.md) | Timeline and legality slides. |

## Experiment-Specific Starting Points

| Topic | Start here |
| --- | --- |
| Final legal baseline and fastest guarded strategy | [branch-snapshots/vm-fastest-benchmark-guard/reports/03-final-vm-strategy-results.md](branch-snapshots/vm-fastest-benchmark-guard/reports/03-final-vm-strategy-results.md) |
| Main vs optimized router comparison | [branch-snapshots/vm-fastest-benchmark-guard/reports/04-main-vs-final-router-comparison.md](branch-snapshots/vm-fastest-benchmark-guard/reports/04-main-vs-final-router-comparison.md) |
| Literature and WL/speed tradeoff probes | [branch-snapshots/vm-fastest-benchmark-guard/reports/05-wl-speed-literature-and-probes.md](branch-snapshots/vm-fastest-benchmark-guard/reports/05-wl-speed-literature-and-probes.md) |
| Bounded-length reroute probe | [branch-snapshots/vm-fastest-benchmark-guard/reports/06-bounded-length-reroute-probe.md](branch-snapshots/vm-fastest-benchmark-guard/reports/06-bounded-length-reroute-probe.md) |
| Transactional virtual-ripup technical comparison | [branch-snapshots/experiment-transactional-virtual-ripup/reports/08-transactional-reroute-technical-comparison.md](branch-snapshots/experiment-transactional-virtual-ripup/reports/08-transactional-reroute-technical-comparison.md) |
| Scoring methodology | [branch-snapshots/experiment-two-stage-parallel-reroute/reports/07-scoring-methodology.md](branch-snapshots/experiment-two-stage-parallel-reroute/reports/07-scoring-methodology.md) |
| Proposal-only v7 experiments | [branch-snapshots/experiment-proposal-reroute-v7/reports/09-aggressive-smoke-protocol.md](branch-snapshots/experiment-proposal-reroute-v7/reports/09-aggressive-smoke-protocol.md) |

## Snapshot Policy

The snapshot directories are raw evidence.  Keep branch-specific conclusions in
those directories, and put only cross-branch navigation or synthesis in this
main-facing `reports/README.md`.
