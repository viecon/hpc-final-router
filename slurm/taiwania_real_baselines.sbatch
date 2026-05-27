#!/bin/bash
#SBATCH --account=ACD115058
#SBATCH --partition=nycugpu_queue
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --gpus-per-node=1
#SBATCH --mem=64G
#SBATCH --time=0-00:20:00
#SBATCH --job-name=gr-baselines
#SBATCH --output=logs/%x_%j.log
#SBATCH --error=logs/%x_%j.err

set -euo pipefail

IMAGE=${IMAGE:-router.sif}
CONTAINER_RUNTIME=${CONTAINER_RUNTIME:-apptainer}
RUN_NTHU_ORIGINAL=${RUN_NTHU_ORIGINAL:-1}
RUN_NTHU_OPENMP=${RUN_NTHU_OPENMP:-1}
RUN_NCTU=${RUN_NCTU:-1}
export OMP_NUM_THREADS=${OMP_NUM_THREADS:-${SLURM_CPUS_PER_TASK:-4}}

mkdir -p logs results

"$CONTAINER_RUNTIME" exec "$IMAGE" bash scripts/fetch_ispd08.sh
if [[ "$RUN_NCTU" == 1 ]]; then
  "$CONTAINER_RUNTIME" exec "$IMAGE" bash scripts/fetch_nctugr.sh
fi

if [[ "$RUN_NTHU_ORIGINAL" == 1 ]]; then
  "$CONTAINER_RUNTIME" exec "$IMAGE" env \
    NTHU_DIR=external/nthu-route-original \
    NTHU_OPENMP=OFF \
    ROUTER_LABEL=nthu_original \
    RESULT_DIR=results/nthu_original \
    bash scripts/run_nthu_ispd08.sh
fi

if [[ "$RUN_NTHU_OPENMP" == 1 ]]; then
  "$CONTAINER_RUNTIME" exec "$IMAGE" env \
    NTHU_OPENMP=ON \
    ROUTER_LABEL=nthu_openmp \
    RESULT_DIR=results/nthu_openmp \
    OMP_NUM_THREADS="$OMP_NUM_THREADS" \
    bash scripts/run_nthu_ispd08.sh
fi

if [[ "$RUN_NCTU" == 1 ]]; then
  "$CONTAINER_RUNTIME" exec "$IMAGE" bash scripts/run_nctugr_ispd08.sh
fi

OUT=results/real_baselines_summary.csv
: > "$OUT"
first=1
for summary in results/nthu_original/summary.csv results/nthu_openmp/summary.csv results/nctu/summary.csv; do
  [[ -f "$summary" ]] || continue
  if [[ "$first" == 1 ]]; then
    cat "$summary" > "$OUT"
    first=0
  else
    tail -n +2 "$summary" >> "$OUT"
  fi
done
echo "wrote $OUT"
