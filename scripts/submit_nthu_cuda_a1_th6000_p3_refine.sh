#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

mkdir -p logs results/job_hooks

RESULT_TAG=${RESULT_TAG:-cuda_a1_th6000_p3_refine}
OUT=${OUT:-"$ROOT/results/nthu_${RESULT_TAG}_summary.csv"}
VARIANTS_FILE=${VARIANTS_FILE:-"$ROOT/results/job_hooks/${RESULT_TAG}.variants"}
BUILD_DIR=${BUILD_DIR:-"$ROOT/external/nthu-route/build-release-openmp-OFF-cuda-ON"}

base_env="NTHU_FAST_GREEDY_LAYER=1 NTHU_RANGE_SKIP_REMAINDER=1 NTHU_CUDA_COSTED_MAZE_FASTPATH=1 NTHU_CUDA_MAZE_MAX_AREA=256 NTHU_CUDA_MAZE_MIN_OVERFLOW_SCORE=25"
base_args="--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=6000"

cat > "$VARIANTS_FILE" <<EOF
nthu_cuda_a1_th6000_p3iter70_box30_50_score25|$base_args --p3-max-iteration=70 --p3-init-box-size=30 --p3-box-expand-size=50|$base_env
nthu_cuda_a1_th6000_p3iter80_box30_50_score25|$base_args --p3-max-iteration=80 --p3-init-box-size=30 --p3-box-expand-size=50|$base_env
nthu_cuda_a1_th6000_p3iter60_box35_60_score25|$base_args --p3-max-iteration=60 --p3-init-box-size=35 --p3-box-expand-size=60|$base_env
nthu_cuda_a1_th6000_p3iter70_box35_60_score25|$base_args --p3-max-iteration=70 --p3-init-box-size=35 --p3-box-expand-size=60|$base_env
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
    --job-name=nthu-cuda-a1p3ref \
    --output="$ROOT/logs/%x_%j.log" \
    --error="$ROOT/logs/%x_%j.err" \
    --export=ALL,PROJECT_ROOT="$ROOT",CONTAINER_RUNTIME=apptainer,IMAGE=router.sif,EVALUATOR=lab2,OMP_NUM_THREADS=1,NTHU_OPENMP=OFF,NTHU_CUDA=ON,JOBS=4,BUILD_DIR="$BUILD_DIR",SKIP_INITIAL_BUILD=1,BENCH_PATTERN=adaptec1*.gr,RESULT_SUFFIX="$RESULT_TAG",OUT="$OUT",VARIANTS_FILE="$VARIANTS_FILE" \
    scripts/slurm_nthu_variant_sweep_job.sh
)

echo "$job" > "results/job_hooks/submitted_${RESULT_TAG}.jobid"
nohup env WATCH_INTERVAL_SECONDS=20 WATCH_COMMAND="bash scripts/refresh_indexes.sh" \
  bash scripts/watch_job_then_run.sh "$job" "${RESULT_TAG}-refresh" >/dev/null 2>&1 &
echo "$job"
