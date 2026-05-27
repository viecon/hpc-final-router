#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

mkdir -p logs results/job_hooks

RESULT_TAG=${RESULT_TAG:-cuda_extra_a3_step6}
OUT=${OUT:-"$ROOT/results/nthu_${RESULT_TAG}_summary.csv"}
variants_file="$ROOT/results/job_hooks/${RESULT_TAG}.variants"

common_args="--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=4000"
common_env="NTHU_DOGLEG_FASTPATH=1 NTHU_DOGLEG_MIN_SCORE=1 NTHU_DOGLEG_STEP=6 NTHU_CUDA_DOGLEG_PRESELECT=1 NTHU_CUDA_DOGLEG_LEGAL_FILTER=1 NTHU_CUDA_DOGLEG_TRUST_LEGAL_FILTER=1 NTHU_CUDA_DOGLEG_MIN_BATCH=64 NTHU_CUDA_DOGLEG_SKIP_CPU_FALLBACK=1"

cat > "$variants_file" <<EOF
nthu_a3_cuda_r4_extra4_gpuonly|$common_args|$common_env NTHU_DOGLEG_RADIUS=4 NTHU_DOGLEG_MAX_EXTRA=4
nthu_a3_cuda_r4_extra8_gpuonly|$common_args|$common_env NTHU_DOGLEG_RADIUS=4 NTHU_DOGLEG_MAX_EXTRA=8
nthu_a3_cuda_r6_extra4_gpuonly|$common_args|$common_env NTHU_DOGLEG_RADIUS=6 NTHU_DOGLEG_MAX_EXTRA=4
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
    --job-name=nthu-cuda-extra \
    --output="$ROOT/logs/%x_%j.log" \
    --error="$ROOT/logs/%x_%j.err" \
    --export=ALL,PROJECT_ROOT="$ROOT",CONTAINER_RUNTIME=apptainer,IMAGE=router.sif,EVALUATOR=lab2,OMP_NUM_THREADS=1,NTHU_OPENMP=OFF,NTHU_CUDA=ON,SKIP_INITIAL_BUILD=0,BUILD_DIR="$ROOT/external/nthu-route/build-release-openmp-OFF-cuda-ON-radius",BENCH_PATTERN=adaptec3*.gr,RESULT_SUFFIX="$RESULT_TAG",OUT="$OUT",VARIANTS_FILE="$variants_file" \
    scripts/slurm_nthu_variant_sweep_job.sh
)

echo "$job" > "results/job_hooks/submitted_${RESULT_TAG}.jobid"
nohup env WATCH_INTERVAL_SECONDS=20 WATCH_COMMAND="bash scripts/refresh_indexes.sh" \
  bash scripts/watch_job_then_run.sh "$job" "${RESULT_TAG}-refresh" >/dev/null 2>&1 &
echo "$job"
