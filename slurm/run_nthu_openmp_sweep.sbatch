#!/bin/bash
#SBATCH -J nthu-omp-sweep
#SBATCH -p gp1d
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=64G
#SBATCH -t 04:00:00
#SBATCH -o logs/%x-%j.out
#SBATCH -e logs/%x-%j.err

set -euo pipefail

IMAGE=${IMAGE:-router.sif}
CONTAINER_RUNTIME=${CONTAINER_RUNTIME:-singularity}
THREADS_LIST=${THREADS_LIST:-"1 2 4 8"}

mkdir -p logs results

"$CONTAINER_RUNTIME" exec "$IMAGE" bash scripts/fetch_ispd08.sh

"$CONTAINER_RUNTIME" exec "$IMAGE" env \
  NTHU_DIR=external/nthu-route-original \
  NTHU_OPENMP=OFF \
  ROUTER_LABEL=nthu_original \
  RESULT_DIR=results/nthu_original \
  bash scripts/run_nthu_ispd08.sh

for threads in $THREADS_LIST; do
  "$CONTAINER_RUNTIME" exec "$IMAGE" env \
    NTHU_OPENMP=ON \
    ROUTER_LABEL="nthu_openmp_t${threads}" \
    RESULT_DIR="results/nthu_openmp_t${threads}" \
    OMP_NUM_THREADS="$threads" \
    bash scripts/run_nthu_ispd08.sh
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
