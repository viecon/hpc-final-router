# Evidence Index

This file is the main-facing entry point for the router optimization evidence.
The experiment branches were not merged into `main`; only their `docs/` and
`reports/` directories were copied into branch-specific snapshots under
`reports/branch-snapshots/`.

## Read First

| Path | Use |
| --- | --- |
| [../reports/README.md](../reports/README.md) | Human-readable report index and suggested reading order. |
| [../reports/branch-snapshots/README.md](../reports/branch-snapshots/README.md) | Exact branch snapshot list with source commits and starting files. |
| [README.md](README.md) | Older main documentation index from the pre-snapshot cleanup. |

## Evidence Types

| Type | Where |
| --- | --- |
| Main-facing summaries | [../reports/README.md](../reports/README.md) |
| Raw branch documentation snapshots | [../reports/branch-snapshots/](../reports/branch-snapshots/) |
| Presentation-oriented notes | `reports/branch-snapshots/*/reports/presentations/` |
| Historical working docs | `reports/branch-snapshots/*/docs/` |

## Branch Snapshot Summary

| Branch snapshot | Focus |
| --- | --- |
| `experiment-aggressive-smoke-protocol` | Aggressive smoke protocol and runtime-frontier experiments. |
| `experiment-proposal-reroute-v7` | Proposal-only parallel reroute, adaptive rounds, rejected global-commit gate, and current v7 smoke result. |
| `experiment-transactional-virtual-ripup` | Transactional virtual-ripup attempt and failure analysis. |
| `experiment-two-stage-parallel-reroute` | Two-stage/wave parallel reroute experiment, legal7 result, and scoring policy. |
| `vm-fastest-benchmark-guard` | Main performance baseline, quality guard, and presentation material. |

## Scoring Convention

Use one router configuration for a reported strategy. Do not choose rows from
different configurations to form one score. Per-case speedup is:

```text
original seconds / candidate seconds
```

For a benchmark suite, prefer aggregate speedup:

```text
sum(original seconds) / sum(candidate seconds)
```

Rows with overflow must be reported as illegal or frontier-only; they should not
be mixed into a final legal-router score.
