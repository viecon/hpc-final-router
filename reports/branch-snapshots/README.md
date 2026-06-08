# Branch Snapshots

These directories preserve `docs/` and `reports/` from experiment branches
without merging experiment code into `main`.

## Snapshot Table

| Snapshot directory | Source branch | Source commit | File count | Start here |
| --- | --- | --- | ---: | --- |
| [experiment-aggressive-smoke-protocol](experiment-aggressive-smoke-protocol/) | `experiment-aggressive-smoke-protocol` | `adb9dac` | 32 | [reports/09-aggressive-smoke-protocol.md](experiment-aggressive-smoke-protocol/reports/09-aggressive-smoke-protocol.md) |
| [experiment-proposal-reroute-v7](experiment-proposal-reroute-v7/) | `experiment-proposal-reroute-v7` | `acaa0a7` | 32 | [reports/09-aggressive-smoke-protocol.md](experiment-proposal-reroute-v7/reports/09-aggressive-smoke-protocol.md) |
| [experiment-transactional-virtual-ripup](experiment-transactional-virtual-ripup/) | `experiment-transactional-virtual-ripup` | `8a9ad5c` | 34 | [reports/08-transactional-reroute-technical-comparison.md](experiment-transactional-virtual-ripup/reports/08-transactional-reroute-technical-comparison.md) |
| [experiment-two-stage-parallel-reroute](experiment-two-stage-parallel-reroute/) | `experiment-two-stage-parallel-reroute` | `5d621a6` | 33 | [docs/26-two-stage-parallel-reroute-experiment.md](experiment-two-stage-parallel-reroute/docs/26-two-stage-parallel-reroute-experiment.md) |
| [experiment-v8-aggressive-parallel](experiment-v8-aggressive-parallel/) | `experiment-v8-aggressive-parallel` | `dba2ebd` | 32 | [reports/09-aggressive-smoke-protocol.md](experiment-v8-aggressive-parallel/reports/09-aggressive-smoke-protocol.md) |
| [vm-fastest-benchmark-guard](vm-fastest-benchmark-guard/) | `vm-fastest-benchmark-guard` | `3d27b67` | 31 | [reports/01-final-router-optimization-zh.md](vm-fastest-benchmark-guard/reports/01-final-router-optimization-zh.md) |

## Directory Layout

Each snapshot keeps the original branch layout:

```text
reports/branch-snapshots/<branch>/docs/
reports/branch-snapshots/<branch>/reports/
```

The snapshots are intentionally duplicated instead of deduplicated so that each
branch can be read as it existed at the recorded commit.

## Safety Rule

Do not use `git merge <experiment-branch>` for this documentation merge.  If a
new experiment branch must be added later, copy only `docs/` and `reports/` into
a new snapshot directory and update this README.
