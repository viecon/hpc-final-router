# Benchmark Scoring Methodology

Date: 2026-06-06

## Policy

Final results must use one routing configuration over a fixed benchmark set.
Do not report a best-per-benchmark portfolio as the answer. Portfolio and
frontier rows may remain in raw evidence only as diagnostics.

Primary score:

```text
suite_speedup = sum(original_seconds) / sum(candidate_seconds)
```

This answers the concrete question: if we run the whole benchmark set once, how
much wall time does the routing configuration save?

Secondary score:

```text
geomean_speedup = geometric_mean(original_seconds_i / candidate_seconds_i)
```

Use this only as an equal-weight per-benchmark robustness indicator. Do not use
the arithmetic mean of per-benchmark speedups.

Correctness gates:

- For original-legal cases, candidate output must keep `overflow=0` and
  `max_overflow=0`.
- For requested sets that include original-overflow cases, report legal row
  count, total overflow, max overflow, and residual overflow cases.
- Report `WL` ratio as average and worst over the same fixed set.

## Rationale

SPEC CPU reports an overall suite metric from selected per-benchmark ratios by
using the geometric mean, not the arithmetic mean:
<https://spec.org/cpu2017/Docs/overview>.

Fleming and Wallace's benchmark-summary paper warns that arithmetic means of
normalized benchmark results can lead to wrong conclusions and recommends the
geometric mean for normalized ratios:
<https://evaluate.inf.usi.ch/node/374.html>.

For a fixed workload where each benchmark is run once, total execution time is
also meaningful. Computer architecture teaching notes describe total execution
time as the simplest relative-performance summary and define speedup as execution
time before divided by execution time after:
<https://www.cse.scu.edu/~m1wang/architecture/Perform2.pdf>.

Therefore this project reports:

1. `suite_speedup` as the main score for a fixed benchmark set.
2. `geomean_speedup` as secondary context.
3. Per-benchmark rows only as explanation, not as selectable strategy choices.
