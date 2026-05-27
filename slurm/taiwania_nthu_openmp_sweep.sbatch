#!/bin/bash
#SBATCH --account=ACD115058
#SBATCH --partition=nycugpu_queue
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --gpus-per-node=1
#SBATCH --mem=64G
#SBATCH --time=0-00:20:00
#SBATCH --job-name=nthu-omp-sweep
#SBATCH --output=logs/%x_%j.log
#SBATCH --error=logs/%x_%j.err

set -euo pipefail

IMAGE=${IMAGE:-router.sif}
CONTAINER_RUNTIME=${CONTAINER_RUNTIME:-apptainer}
THREADS_LIST=${THREADS_LIST:-"1 2 4"}
RUN_NTHU_ORIGINAL=${RUN_NTHU_ORIGINAL:-1}

mkdir -p logs results

"$CONTAINER_RUNTIME" exec "$IMAGE" bash scripts/fetch_ispd08.sh

if [[ "$RUN_NTHU_ORIGINAL" == 1 ]]; then
  "$CONTAINER_RUNTIME" exec "$IMAGE" env \
    NTHU_DIR=external/nthu-route-original \
    NTHU_OPENMP=OFF \
    ROUTER_LABEL=nthu_original \
    RESULT_DIR=results/nthu_original \
    bash scripts/run_nthu_ispd08.sh
fi

for threads in $THREADS_LIST; do
  skip_build=0
  if [[ -n "${openmp_built:-}" ]]; then
    skip_build=1
  fi
  "$CONTAINER_RUNTIME" exec "$IMAGE" env \
    NTHU_OPENMP=ON \
    ROUTER_LABEL="nthu_openmp_t${threads}" \
    RESULT_DIR="results/nthu_openmp_t${threads}" \
    OMP_NUM_THREADS="$threads" \
    SKIP_BUILD="$skip_build" \
    bash scripts/run_nthu_ispd08.sh
  openmp_built=1
done

OUT=results/nthu_openmp_sweep_summary.csv
: > "$OUT"
first=1
for summary in results/nthu_original/summary.csv results/nthu_openmp_t*/summary.csv; do
  [[ -f "$summary" ]] || continue
  if [[ "$first" == 1 ]]; then
    cat "$summary" > "$OUT"
    first=0
  else
    tail -n +2 "$summary" >> "$OUT"
  fi
done
echo "wrote $OUT"
