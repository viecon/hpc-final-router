#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

mkdir -p logs results/job_hooks

RESULT_TAG=${RESULT_TAG:-cuda_final_a3_cached}
OUT=${OUT:-"$ROOT/results/nthu_${RESULT_TAG}_summary.csv"}
ATTEMPTS_OUT=${ATTEMPTS_OUT:-"$ROOT/results/nthu_${RESULT_TAG}_attempts_summary.csv"}
BUILD_DIR=${BUILD_DIR:-"$ROOT/external/nthu-route/build-release-openmp-OFF-cuda-ON-batchprefilter"}
variants_file="$ROOT/results/job_hooks/${RESULT_TAG}.variants"

attempts="--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=200000;;--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=50000;;--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=24000;;--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=12000;;--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=4800"
base_env="NTHU_DOGLEG_FASTPATH=1 NTHU_DOGLEG_MAX_EXTRA=0 NTHU_DOGLEG_MIN_SCORE=1 NTHU_DOGLEG_STEP=12 NTHU_RANGE_SKIP_REMAINDER=1"
cuda_env="$base_env NTHU_CUDA_DOGLEG_PRESELECT=1 NTHU_CUDA_DOGLEG_LEGAL_FILTER=1 NTHU_CUDA_DOGLEG_TRUST_LEGAL_FILTER=1"

cat > "$variants_file" <<EOF
nthu_a3_final_cuda_cached_min64|adaptec3*.gr|$attempts|$cuda_env NTHU_CUDA_DOGLEG_MIN_BATCH=64
nthu_a3_final_cuda_cached_min128|adaptec3*.gr|$attempts|$cuda_env NTHU_CUDA_DOGLEG_MIN_BATCH=128
EOF

job=$(
  sbatch --parsable \
    --account=ACD115058 \
    --partition=nycugpu_queue \
    --nodes=1 \
    --ntasks-per-node=1 \
    --cpus-per-task=4 \
    --gpus-per-node=1 \
    --mem=64G \
    --time=0-00:30:00 \
    --job-name=nthu-cuda-a3-cached \
    --output="$ROOT/logs/%x_%j.log" \
    --error="$ROOT/logs/%x_%j.err" \
    --export=ALL,PROJECT_ROOT="$ROOT",CONTAINER_RUNTIME=apptainer,IMAGE=router.sif,EVALUATOR=lab2,OMP_NUM_THREADS=1,NTHU_OPENMP=OFF,NTHU_CUDA=ON,SKIP_INITIAL_BUILD=1,BUILD_DIR="$BUILD_DIR",RUN_TAG="${RESULT_TAG}_summary",OUT="$OUT",ATTEMPTS_OUT="$ATTEMPTS_OUT",ADAPTIVE_VARIANTS_FILE="$variants_file" \
    scripts/slurm_nthu_adaptive_p2_job.sh
)

echo "$job" > "results/job_hooks/submitted_${RESULT_TAG}.jobid"
nohup env WATCH_INTERVAL_SECONDS=20 WATCH_COMMAND="bash scripts/refresh_indexes.sh" \
  bash scripts/watch_job_then_run.sh "$job" "${RESULT_TAG}-refresh" >/dev/null 2>&1 &
echo "$job"
