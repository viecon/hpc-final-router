# Taiwania 2 Runbook

This is the minimal checklist for running the NTHU-Route and NCTU-GR baselines on
Taiwania 2 with Slurm and Apptainer/Singularity.

## Current QoS Note

As of 2026-05-27, the course notice says the temporary Slurm limits are:

```text
max running jobs per group: 1
resource cap: 2 nodes / 64 cores / 16 GPUs
max walltime: 1 hour
```

A lightweight 1-hour submission test reached `PENDING` with
`QOSGrpJobsLimit`, not a walltime-limit error. In practice, submit only one
experiment watcher at a time and expect it to wait if a teammate is using the
group slot.

After the disk-quota cleanup, prefer preserving source/docs/summary CSVs before
rerunning. For rerun priority, see `docs/rerun_priority.md`.

## Files to Upload

Upload the whole `hpc-final-router` directory, excluding local build/results clutter.
The important parts are:

- `container/Apptainer.def`
- `slurm/*.sbatch`
- `scripts/*.sh`
- `scripts/*.py`
- `external/nthu-route/`
- `external/nthu-route-original/`
- `external/lab2-checker/`
- `CMakeLists.txt`, `include/`, `src/`
- `docs/`

The ISPD08 benchmarks and NCTU-GR binary can be fetched on Taiwania by scripts:

- `scripts/fetch_ispd08.sh`
- `scripts/fetch_nctugr.sh`

If Taiwania compute nodes cannot access the internet, run those scripts on the login
node first, or upload these directories too:

- `benchmarks/ispd08/`
- `external/nctu-gr/`

## Upload From Local Machine

From a shell on your local machine:

```bash
cd /mnt/c/Users/twsha/Documents/work
tar --exclude='hpc-final-router/build*' \
    --exclude='hpc-final-router/results' \
    --exclude='hpc-final-router/logs' \
    --exclude='hpc-final-router/.git' \
    --exclude='hpc-final-router/external/nthu-route/.git' \
    -czf hpc-final-router.tar.gz hpc-final-router

scp hpc-final-router.tar.gz USER@HOST:~/
```

On Taiwania:

```bash
tar -xzf hpc-final-router.tar.gz
cd hpc-final-router
```

Replace `USER@HOST` with your Taiwania login.

## Build Container

If Apptainer build is available:

```bash
cd ~/hpc-final-router
module avail apptainer singularity
module load apptainer 2>/dev/null || module load singularity
apptainer build router.sif container/Apptainer.def
```

If the command is `singularity` instead:

```bash
singularity build router.sif container/Apptainer.def
```

If Taiwania does not allow image building, build `router.sif` on another Linux machine
with Apptainer/Singularity and upload the resulting `router.sif` into
`~/hpc-final-router/`.

The fetch scripts do not require `curl` specifically. They try `curl`, then `wget`,
then Python `urllib`, so an older `router.sif` with only `wget` can still download the
benchmarks and NCTU-GR.

## Quick Connectivity/Fetch Check

Run this once on the login node if internet access is available there:

```bash
cd ~/hpc-final-router
mkdir -p logs results
apptainer exec router.sif bash scripts/fetch_ispd08.sh
apptainer exec router.sif bash scripts/fetch_nctugr.sh
```

Use `singularity exec` instead of `apptainer exec` if that is the installed command.

## First Short Baseline Run

For the `ACD115058` account and `nycugpu_queue` partition, use the Taiwania-specific
scripts:

Submit a small first run:

```bash
cd ~/hpc-final-router
mkdir -p logs results
sbatch --export=ALL,BENCH_PATTERN='adaptec1*.gr',EVALUATOR=lab2,OMP_NUM_THREADS=4 slurm/taiwania_real_baselines.sbatch
```

If the site command is `singularity`:

```bash
sbatch --export=ALL,CONTAINER_RUNTIME=singularity,BENCH_PATTERN='adaptec1*.gr',EVALUATOR=lab2,OMP_NUM_THREADS=4 slurm/taiwania_real_baselines.sbatch
```

Check progress:

```bash
squeue -u "$USER"
tail -f logs/gr-baselines-*.out
tail -f logs/gr-baselines-*.err
```

The Taiwania-specific scripts write `logs/%x_%j.log` and `logs/%x_%j.err`, so for
these scripts the concrete pattern is usually:

```bash
tail -f logs/gr-baselines_*.log
tail -f logs/gr-baselines_*.err
```

## Full Baseline Run

After the short run works:

```bash
cd ~/hpc-final-router
sbatch --export=ALL,EVALUATOR=lab2 slurm/taiwania_real_baselines.sbatch
```

For the OpenMP scaling experiment:

```bash
sbatch --export=ALL,THREADS_LIST='1 2 4',EVALUATOR=lab2 slurm/taiwania_nthu_openmp_sweep.sbatch
```

If `results/nthu_original/summary.csv` already exists and you only want the OpenMP
thread sweep:

```bash
sbatch --time=0-00:30:00 --export=ALL,BENCH_PATTERN='adaptec1*.gr',THREADS_LIST='1 2 4',RUN_NTHU_ORIGINAL=0,EVALUATOR=lab2 slurm/taiwania_nthu_openmp_sweep.sbatch
```

The sweep script builds the OpenMP binary once and reuses it for later thread counts.
For manual runs, `scripts/run_nthu_ispd08.sh` also accepts `SKIP_BUILD=1` when the
target `NthuRoute` binary already exists in the selected build directory.

Outputs:

- `results/nthu_original/summary.csv`
- `results/nthu_openmp/summary.csv`
- `results/nctu/summary.csv`
- `results/real_baselines_summary.csv`
- `results/nthu_openmp_sweep_summary.csv` if you run the OpenMP sweep
- per-benchmark route outputs and logs under `results/nthu_original/`,
  `results/nthu_openmp/`, and `results/nctu/`

The combined CSV contains three router labels by default:

- `nthu_original`
- `nthu_openmp`
- `nctu`

To skip one group:

```bash
sbatch --export=ALL,RUN_NTHU_ORIGINAL=0,EVALUATOR=lab2 slurm/taiwania_real_baselines.sbatch
```

## Plot Results

Generate report plots inside the container, since the login environment may not have
`pandas` or `matplotlib` installed:

```bash
apptainer exec router.sif python3 scripts/plot.py \
  results/real_baselines_summary.csv \
  --outdir results/plots
```

For the current three-case report table, the generated artifacts are:

```text
results/plots_adaptec123/real_runtime.png
results/plots_adaptec123/real_wirelength.png
results/plots_adaptec123/real_overflow.png
results/plots_adaptec123/real_summary.csv
```

## Optional Perl Cross-Check

Run with the original NTHU `eval2008.pl` instead of the Lab2 checker:

```bash
sbatch --export=ALL,CONTAINER_RUNTIME=apptainer,EVALUATOR=perl slurm/run_real_baselines.sbatch
```

## NTHU Profiling

To collect phase timings for GPU/OpenMP feasibility analysis:

```bash
sbatch --account=ACD115058 --partition=nycugpu_queue \
  --nodes=1 --ntasks-per-node=1 --cpus-per-task=4 --gpus-per-node=1 \
  --mem=64G --time=0-00:12:00 --job-name=nthu-profile \
  --output=logs/%x_%j.log --error=logs/%x_%j.err \
  --export=ALL \
  --wrap="apptainer exec router.sif env BENCH_PATTERN='adaptec1*.gr' EVALUATOR=lab2 NTHU_OPENMP=ON NTHU_PROFILE=1 ROUTER_LABEL=nthu_profile_openmp RESULT_DIR=results/nthu_profile_openmp OMP_NUM_THREADS=4 SKIP_BUILD=1 bash scripts/run_nthu_ispd08.sh"
```

The synthetic mini-router scripts remain in the repository as a sandbox, but they are
not part of the main NTHU/NCTU project evidence.
