#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

mkdir -p logs results/job_hooks

RESULT_TAG=${RESULT_TAG:-cuda_final_a2}
OUT=${OUT:-"$ROOT/results/nthu_${RESULT_TAG}_summary.csv"}
ATTEMPTS_OUT=${ATTEMPTS_OUT:-"$ROOT/results/nthu_${RESULT_TAG}_attempts_summary.csv"}
variants_file="$ROOT/results/job_hooks/${RESULT_TAG}.variants"

attempts="--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=249 --p3-init-box-size=20 --p3-box-expand-size=30;;--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=245 --p3-init-box-size=20 --p3-box-expand-size=30;;--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=225;;--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=200"
base_env="NTHU_DOGLEG_FASTPATH=1 NTHU_DOGLEG_MAX_EXTRA=0 NTHU_DOGLEG_MIN_SCORE=500"
cuda_env="$base_env NTHU_CUDA_DOGLEG_PRESELECT=1 NTHU_CUDA_DOGLEG_LEGAL_FILTER=1 NTHU_CUDA_DOGLEG_TRUST_LEGAL_FILTER=1 NTHU_CUDA_DOGLEG_MIN_BATCH=64"

cat > "$variants_file" <<EOF
nthu_a2_final_cpu_cuda_build|adaptec2*.gr|$attempts|$base_env
nthu_a2_final_cuda_trust|adaptec2*.gr|$attempts|$cuda_env
nthu_a2_final_cuda_gpuonly|adaptec2*.gr|$attempts|$cuda_env NTHU_CUDA_DOGLEG_SKIP_CPU_FALLBACK=1
nthu_a2_final_cuda_radius4|adaptec2*.gr|$attempts|$cuda_env NTHU_DOGLEG_RADIUS=4
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
    --time=0-00:25:00 \
    --job-name=nthu-cuda-final-a2 \
    --output="$ROOT/logs/%x_%j.log" \
    --error="$ROOT/logs/%x_%j.err" \
    --export=ALL,PROJECT_ROOT="$ROOT",CONTAINER_RUNTIME=apptainer,IMAGE=router.sif,EVALUATOR=lab2,OMP_NUM_THREADS=1,NTHU_OPENMP=OFF,NTHU_CUDA=ON,SKIP_INITIAL_BUILD=1,BUILD_DIR="$ROOT/external/nthu-route/build-release-openmp-OFF-cuda-ON-radius",RUN_TAG="${RESULT_TAG}_summary",OUT="$OUT",ATTEMPTS_OUT="$ATTEMPTS_OUT",ADAPTIVE_VARIANTS_FILE="$variants_file" \
    scripts/slurm_nthu_adaptive_p2_job.sh
)

echo "$job" > "results/job_hooks/submitted_${RESULT_TAG}.jobid"
nohup env WATCH_INTERVAL_SECONDS=20 WATCH_COMMAND="bash scripts/refresh_indexes.sh" \
  bash scripts/watch_job_then_run.sh "$job" "${RESULT_TAG}-refresh" >/dev/null 2>&1 &
echo "$job"
