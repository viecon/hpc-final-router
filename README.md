# HPC Final Router

Benchmark harness and experiment report for an HPC final project around VLSI
global routing. The project focuses on real ISPD08 router baselines:
NTHU-Route source, modified NTHU-Route strategies, and NCTU-GR as a
cross-router black-box baseline.

The formal benchmark target is Taiwania 2 through Slurm + Singularity/Apptainer. Local
execution is only for smoke tests.

## Current Report Status

Read these first:

- `docs/README.md`: documentation map and current evidence files.
- `docs/final_experiment_report.md`: complete report draft.
- `docs/methods_and_results_summary.md`: short result summary.
- `docs/session_handoff.md`: current state after disk-quota cleanup.
- `docs/rerun_priority.md`: what to rerun if fresh raw logs are needed.

Main legal NTHU source-code result:

| Benchmark set | NTHU original | Best legal NTHU | Speedup | Overflow |
| --- | ---: | ---: | ---: | ---: |
| `adaptec1-3` | 981.939003s | 422.179091s | 2.325883x | 0 |

The original stretch target was `5x-10x` NTHU self-speedup. The honest final
NTHU source-code result is about `2.33x`; `5x+` appears only in black-box
NCTU-GR comparisons or illegal NTHU runtime-frontier experiments.

## Project Scope

Real baselines:

- NTHU-Route 2.0 source baseline in `external/nthu-route-original`.
- OpenMP-modified NTHU-Route in `external/nthu-route`.
- NCTU-GR 2.0 black-box binary baseline fetched by `scripts/fetch_nctugr.sh`.
- ISPD08 `.gr` benchmarks fetched by `scripts/fetch_ispd08.sh`.
- Lab2 Python checker metrics: wirelength, total overflow, max overflow,
  overflowed nets, overflowed edges.
- Official `eval2008.pl` remains available as a fallback evaluator.

NCTU-GR is used as a Chiao Tung black-box baseline because the public release is
binary-only. NTHU-Route is the modifiable source-code baseline.

## Build Container

Taiwania 2 usually does not allow building containers with root privileges on login
nodes. Build the image on a machine where Apptainer/Singularity can build images, then
upload `router.sif` with this repository.

```bash
apptainer build router.sif container/Apptainer.def
```

If the site exposes `singularity` instead of `apptainer`, the image format and commands
are compatible.

## Real ISPD08 Baselines

Run both real routers on ISPD08:

```bash
mkdir -p logs results
sbatch --export=ALL,CONTAINER_RUNTIME=apptainer slurm/run_real_baselines.sbatch
```

The job downloads ISPD08 benchmarks, downloads NCTU-GR 2.0, builds NTHU-Route 2.0, runs
both routers, evaluates outputs with the Lab2 checker when available, and writes:

```text
results/real_baselines_summary.csv
```

You can also run individual steps in a shell/container:

```bash
bash scripts/fetch_ispd08.sh
bash scripts/fetch_nctugr.sh
bash scripts/run_nthu_ispd08.sh
bash scripts/run_nctugr_ispd08.sh
```

For a quick first trial, restrict the benchmark pattern:

```bash
BENCH_PATTERN='adaptec1*.gr' bash scripts/run_nthu_ispd08.sh
BENCH_PATTERN='adaptec1*.gr' bash scripts/run_nctugr_ispd08.sh
```

The evaluator is selectable:

```bash
EVALUATOR=lab2 bash scripts/run_nthu_ispd08.sh
EVALUATOR=perl bash scripts/run_nctugr_ispd08.sh
```

`EVALUATOR=auto` is the default and prefers
`external/lab2-checker/verifier.py`, falling back to NTHU-Route's `eval2008.pl`.

## Deprecated Mini-Router Sandbox

The synthetic mini-router is kept only as an old sandbox. It is no longer a project
baseline, and the report should use the real ISPD08 NTHU/NCTU runs instead.

```bash
cmake -S . -B build -G Ninja -DROUTER_ENABLE_CUDA=OFF -DCMAKE_BUILD_TYPE=Release
cmake --build build
./build/router_bench --mode seq --grid 64 --nets 500 --repeats 2
./build/router_bench --mode cpu --grid 64 --nets 500 --threads 4 --repeats 2
```

## Plot

```bash
apptainer exec router.sif python3 scripts/plot.py \
  results/real_baselines_summary.csv \
  --outdir results/plots
```

## Report Angles

- NTHU-Route 2.0 as open-source CPU source baseline.
- NCTU-GR 2.0 as NYCU/NCTU black-box CPU baseline.
- ISPD08 official benchmarks plus Lab2/eval2008 validation for credible metrics.
- Reproducibility with Slurm + Apptainer.
- OpenMP analysis kernels, fast layer assignment, P2/P3 budget tuning, CUDA
  candidate scoring, and edge-count post-processing are compared as separate
  strategies.
- GPU feasibility is documented from NTHU-Route profiling and real candidate
  scoring probes rather than synthetic mini-router results.

## Citation Anchors

Wen-Hao Liu, Wei-Chun Kao, Yih-Lang Li, and Kai-Yuan Chao,
"NCTU-GR 2.0: Multithreaded Collision-Aware Global Routing With Bounded-Length Maze Routing,"
IEEE TCAD, 2013.

Yen-Jung Chang, Yu-Ting Lee, and Ting-Chi Wang,
"NTHU-Route 2.0: A Fast and Stable Global Router,"
ICCAD, 2008.
