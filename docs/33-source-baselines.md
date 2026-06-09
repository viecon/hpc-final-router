# NTHU Source Baselines

The project keeps two NTHU-Route source trees:

- `external/nthu-route-original/`
  - Source exported from the upstream NTHU-Route repository `HEAD`.
  - Includes the same FLUTE capacity fix used by the OpenMP version: `MAXD` is raised
    from 350 to 1000 so the parser's original `<1000 pin` routing policy does not
    overflow FLUTE arrays.
  - Includes the same high-degree net fallback used by the OpenMP version: nets with
    more than 350 pins use a deterministic chain tree instead of FLUTE.
  - Includes shared ISPD08 compatibility fixes for per-layer vector sizing and CRLF
    FLUTE LUT parsing.
  - Used as the `nthu_original` baseline.
- `external/nthu-route/`
  - Modified source with OpenMP analysis-kernel acceleration.
  - Used as the `nthu_openmp` implementation.

This separation keeps the source-level comparison clean: the baseline is not just
the modified source compiled with OpenMP disabled. The shared changes are limited to
compatibility fixes needed to run ISPD08 cases reproducibly: FLUTE capacity/fallback,
per-layer vector sizing, and CRLF-safe LUT parsing.

`external/nthu-route-original/` was created with:

```bash
git -C external/nthu-route archive --format=tar HEAD \
  | tar -xf - -C external/nthu-route-original
```

On Windows, the archive may warn about the CodeQL symlink
`_codeql_detected_source_root`. That symlink is not needed for building or running
NTHU-Route.
