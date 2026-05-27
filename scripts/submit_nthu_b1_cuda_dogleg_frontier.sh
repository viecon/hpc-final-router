#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

mkdir -p logs results/job_hooks

RESULT_TAG=${RESULT_TAG:-nthu_b1_cuda_dogleg_frontier}
OUT=${OUT:-"$ROOT/results/${RESULT_TAG}_summary.csv"}
VARIANTS_FILE=${VARIANTS_FILE:-"$ROOT/results/job_hooks/${RESULT_TAG}.variants"}
BUILD_DIR=${BUILD_DIR:-"$ROOT/external/nthu-route/build-release-openmp-OFF-cuda-ON-overflow-sort"}

base_args="--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=10000 --p2-max-iteration=4 --p3-init-box-size=42 --p3-box-expand-size=65"
base_env="NTHU_FAST_GREEDY_LAYER=1 NTHU_DOGLEG_FASTPATH=1 NTHU_DOGLEG_MAX_EXTRA=0 NTHU_DOGLEG_MIN_SCORE=1 NTHU_DOGLEG_STEP=8 NTHU_RANGE_SKIP_REMAINDER=1 NTHU_CUDA_COSTED_MAZE_FASTPATH=1 NTHU_CUDA_MAZE_MAX_AREA=256 NTHU_CUDA_MAZE_MIN_OVERFLOW_SCORE=42"
dogleg_env="NTHU_CUDA_DOGLEG_PRESELECT=1 NTHU_CUDA_DOGLEG_LEGAL_FILTER=1 NTHU_CUDA_DOGLEG_TRUST_LEGAL_FILTER=1 NTHU_CUDA_DOGLEG_MIN_BATCH=64"

cat > "$VARIANTS_FILE" <<EOF
nthu_b1_cudadogleg_p2m4_p3m1_safe|$base_args --p3-max-iteration=1|$base_env $dogleg_env
nthu_b1_cudadogleg_p2m4_p3m1_skipfallback|$base_args --p3-max-iteration=1|$base_env $dogleg_env NTHU_CUDA_DOGLEG_SKIP_CPU_FALLBACK=1
nthu_b1_cudadogleg_sort_p2m4_p3m1|$base_args --p3-max-iteration=1|$base_env $dogleg_env NTHU_RANGE_SORT_BY_OVERFLOW_SCORE=1
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
    --job-name=nthu-b1-cudadogleg \
    --output="$ROOT/logs/%x_%j.log" \
    --error="$ROOT/logs/%x_%j.err" \
    --export=ALL,PROJECT_ROOT="$ROOT",CONTAINER_RUNTIME=apptainer,IMAGE=router.sif,EVALUATOR=lab2,OMP_NUM_THREADS=1,NTHU_OPENMP=OFF,NTHU_CUDA=ON,JOBS=4,BUILD_DIR="$BUILD_DIR",SKIP_INITIAL_BUILD=1,BENCH_PATTERN=bigblue1*.gr,RESULT_SUFFIX="$RESULT_TAG",OUT="$OUT",VARIANTS_FILE="$VARIANTS_FILE" \
    scripts/slurm_nthu_variant_sweep_job.sh
)

echo "$job" > "results/job_hooks/submitted_${RESULT_TAG}.jobid"
nohup env WATCH_INTERVAL_SECONDS=20 WATCH_COMMAND="bash scripts/refresh_indexes.sh" \
  bash scripts/watch_job_then_run.sh "$job" "${RESULT_TAG}-refresh" >/dev/null 2>&1 &
echo "$job"
