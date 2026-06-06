# Timeline and Correctness Brief

Date: 2026-06-06

## Slide 1 - Why Timeline Matters

The repository contains results from several implementation periods.  Some rows
are:

- early best-per-benchmark portfolios,
- Slurm 16-case matrix runs,
- VM utilization probes,
- VM one-strategy final-family runs,
- post-final negative probes.

Do not mix these without stating the date, commit, denominator, benchmark set,
and whether the result is a portfolio or one strategy.

## Slide 2 - Experiment Periods

| Date | Main files | Strategy state | Safe claim |
| --- | --- | --- | --- |
| 2026-05-27 | `../../docs/10-early-source-strategy-report.md`, `../../docs/11-early-results-summary.md` | Early source methods: OpenMP, fast layer, P2/P3, CUDA, edge-count. | adaptec1-3 legal NTHU speedup `2.325883x`; 16-case matrix as broad evidence. |
| 2026-06-04 | `../../docs/23-wl-guard-speedup.md`, `../../docs/24-wl120-single-core-results.md`, `../../docs/25-overall-adaptive-router-results.md` | Net-guided low-layer and adaptive repair development. | WL<=1.2 legal7 `1.961x`; one-strategy legal7 `1.771x`. |
| 2026-06-05 | `../03-final-vm-strategy-results.md`, `../04-main-vs-final-router-comparison.md` | High-overflow P2 final family. | requested12 `1.345x`, legal7 `1.752x`, total overflow `166`. |
| 2026-06-05 later | `../05-wl-speed-literature-and-probes.md`, `../06-bounded-length-reroute-probe.md` | Layer-penalty and bounded-length probes. | negative results; final remains bounded off. |
| 2026-06-06 | `../01-final-router-optimization-zh.md`, this deck set | Synthesis only. | no new benchmark rows. |

## Slide 3 - Correctness Guard

Final-family correctness target:

- if original was legal, optimized must remain `overflow=0,max_overflow=0`;
- requested12 contains original-overflow hard cases, so those are judged by
  overflow reduction and final residual overflow.

Latest final-family state:

| Scope | Legal rows | Total overflow | Max overflow | Guard |
| --- | ---: | ---: | ---: | --- |
| original-legal 7 | 7/7 | 0 | 0 | pass |
| requested12 | 10/12 | 166 | 2 | B2/N1 still residual |

## Slide 4 - Portfolio vs One-Strategy

Portfolio examples:

- early adaptec1-3 best legal combination,
- fastest guarded 12-case portfolio,
- WL<=1.2 legal7 portfolio.

One-strategy examples:

- overall adaptive router,
- high-overflow adaptive P2 final family.

Important distinction:

> Portfolio results show upper bounds and diagnosis.  The final router claim
> should use one global strategy controlled by routing-state signals, not by
> testcase names.

## Slide 5 - Accepted Timeline

| Stage | Accepted idea | Why |
| --- | --- | --- |
| early fast layer | fast layer assignment | first meaningful speed path |
| WL guard | net-guided low-layer assignment | reduced WL inflation from 1.7x-1.9x to around 1.12x on legal7 |
| adaptive repair | measured-overflow trigger | restored original-legal correctness |
| high-overflow P2 | larger P2 only when overflow is high | reduced hard-case overflow without touching legal7 behavior |

## Slide 6 - Rejected Timeline

| Stage | Rejected idea | Reason |
| --- | --- | --- |
| OpenMP scans | use as main speed claim | correct but only about 1.03x |
| parallel reroute prototype | enable by default | higher CPU but slower / unsafe direct maze commit |
| CUDA dual GPU | use for single-testcase latency | GPU1 stayed idle or overhead dominated |
| edge-count frontier | claim as final | fast but mostly illegal |
| strict legal maze | enable final | plateaued or crashed in post-accept variant |
| layer penalty tuning | reduce WL/overflow | no WL or overflow change |
| bounded-length reject-only | enable final | correct safe version but too slow |

## Slide 7 - Result Traceability

When presenting a number, cite one of these:

| Claim | Source |
| --- | --- |
| latest final-family requested12 `1.294x`, overflow `166` | `../06-bounded-length-reroute-probe.md` final recheck |
| earlier clean selected requested12 `1.345x` | `../03-final-vm-strategy-results.md` |
| current vs same-CLI main `1.677x` | `../04-main-vs-final-router-comparison.md` |
| WL<=1.2 legal7 `1.961x` | `../../docs/24-wl120-single-core-results.md` |
| OpenMP/CUDA utilization | `../../docs/21-vm-multicore-utilization-log.md`, `../../docs/22-vm-cuda-utilization-log.md` |
| method/commit map | `../02-methods-by-commit-and-result.md` |

## Slide 8 - Final Statement

Recommended wording:

> The final implementation is a single adaptive NTHU-Route strategy.  It does
> not hardcode testcase names.  It preserves all original-legal cases, keeps
> requested12 WL around 1.16x average, and reduces total overflow to 166.  Faster
> results exist only as portfolios or illegal speed frontiers.

Raw evidence map:

- `../../docs/00-evidence-index.md`
