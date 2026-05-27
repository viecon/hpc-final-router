#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

mkdir -p logs results/job_hooks

RESULT_TAG=${RESULT_TAG:-nthu_b1_rscore_time_shave}
OUT=${OUT:-"$ROOT/results/${RESULT_TAG}_summary.csv"}
VARIANTS_FILE=${VARIANTS_FILE:-"$ROOT/results/job_hooks/${RESULT_TAG}.variants"}
BUILD_DIR=${BUILD_DIR:-"$ROOT/external/nthu-route/build-release-openmp-OFF-cuda-ON-excess-edge"}

args="--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=10000 --p2-max-iteration=5 --p3-max-iteration=1 --p3-init-box-size=42 --p3-box-expand-size=65"
common_env="NTHU_FAST_GREEDY_LAYER=1 NTHU_DOGLEG_FASTPATH=1 NTHU_DOGLEG_MAX_EXTRA=0 NTHU_DOGLEG_MIN_SCORE=1 NTHU_DOGLEG_STEP=8 NTHU_RANGE_SKIP_REMAINDER=1 NTHU_REROUTE_SCORE_P2_ONLY=1"
cuda_env="NTHU_CUDA_COSTED_MAZE_FASTPATH=1 NTHU_CUDA_MAZE_MAX_AREA=256 NTHU_CUDA_MAZE_MIN_OVERFLOW_SCORE=42"

cat > "$VARIANTS_FILE" <<EOF
nthu_b1_rscore4_p2m5_no_cuda_maze|$args|$common_env NTHU_REROUTE_MIN_OVERFLOW_SCORE=4
nthu_b1_rscore4_p2m5_cuda_score100|$args|$common_env $cuda_env NTHU_CUDA_MAZE_MIN_OVERFLOW_SCORE=100 NTHU_REROUTE_MIN_OVERFLOW_SCORE=4
nthu_b1_rscore5_p2m5_cuda|$args|$common_env $cuda_env NTHU_REROUTE_MIN_OVERFLOW_SCORE=5
nthu_b1_rscore5_p2m5_no_cuda_maze|$args|$common_env NTHU_REROUTE_MIN_OVERFLOW_SCORE=5
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
    --job-name=nthu-b1-rscore-ts \
    --output="$ROOT/logs/%x_%j.log" \
    --error="$ROOT/logs/%x_%j.err" \
    --export=ALL,PROJECT_ROOT="$ROOT",CONTAINER_RUNTIME=apptainer,IMAGE=router.sif,EVALUATOR=lab2,OMP_NUM_THREADS=1,NTHU_OPENMP=OFF,NTHU_CUDA=ON,JOBS=4,BUILD_DIR="$BUILD_DIR",SKIP_INITIAL_BUILD=1,BENCH_PATTERN=bigblue1*.gr,RESULT_SUFFIX="$RESULT_TAG",OUT="$OUT",VARIANTS_FILE="$VARIANTS_FILE" \
    scripts/slurm_nthu_variant_sweep_job.sh
)

echo "$job" > "results/job_hooks/submitted_${RESULT_TAG}.jobid"
nohup env WATCH_INTERVAL_SECONDS=20 WATCH_COMMAND="bash scripts/refresh_indexes.sh" \
  bash scripts/watch_job_then_run.sh "$job" "${RESULT_TAG}-refresh" >/dev/null 2>&1 &
echo "$job"
