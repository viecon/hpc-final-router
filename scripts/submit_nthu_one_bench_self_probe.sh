#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

BENCH_PATTERN=${BENCH_PATTERN:?BENCH_PATTERN is required, e.g. newblue1*.gr}
RESULT_TAG=${RESULT_TAG:?RESULT_TAG is required}
LABEL_PREFIX=${LABEL_PREFIX:?LABEL_PREFIX is required, e.g. n1}
JOB_NAME=${JOB_NAME:-nthu-self}

mkdir -p logs results/job_hooks

OUT=${OUT:-"$ROOT/results/${RESULT_TAG}_summary.csv"}
VARIANTS_FILE=${VARIANTS_FILE:-"$ROOT/results/job_hooks/${RESULT_TAG}.variants"}
BUILD_DIR=${BUILD_DIR:-"$ROOT/external/nthu-route/build-release-openmp-OFF-cuda-ON-reeval"}

fast_env="NTHU_FAST_GREEDY_LAYER=1 NTHU_DOGLEG_FASTPATH=1 NTHU_DOGLEG_MAX_EXTRA=0 NTHU_DOGLEG_MIN_SCORE=1 NTHU_DOGLEG_STEP=8 NTHU_RANGE_SKIP_REMAINDER=1 NTHU_CUDA_COSTED_MAZE_FASTPATH=1 NTHU_CUDA_MAZE_MAX_AREA=256 NTHU_CUDA_MAZE_MIN_OVERFLOW_SCORE=42"

cat > "$VARIANTS_FILE" <<EOF
nthu_${LABEL_PREFIX}_original||
nthu_${LABEL_PREFIX}_fast_a1_style|--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=1800 --p2-max-iteration=6 --p3-init-box-size=66 --p3-box-expand-size=122|NTHU_FAST_GREEDY_LAYER=1
nthu_${LABEL_PREFIX}_fast_a3_style|--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=300000 --p3-max-iteration=8 --p2-max-iteration=4 --p3-init-box-size=35 --p3-box-expand-size=50|$fast_env
nthu_${LABEL_PREFIX}_target_p2m3_p3m1|--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=50000 --p2-max-iteration=3 --p3-max-iteration=1 --p3-init-box-size=66 --p3-box-expand-size=122|$fast_env
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
    --job-name="$JOB_NAME" \
    --output="$ROOT/logs/%x_%j.log" \
    --error="$ROOT/logs/%x_%j.err" \
    --export=ALL,PROJECT_ROOT="$ROOT",CONTAINER_RUNTIME=apptainer,IMAGE=router.sif,EVALUATOR=lab2,OMP_NUM_THREADS=1,NTHU_OPENMP=OFF,NTHU_CUDA=ON,JOBS=4,BUILD_DIR="$BUILD_DIR",SKIP_INITIAL_BUILD=1,BENCH_PATTERN="$BENCH_PATTERN",RESULT_SUFFIX="$RESULT_TAG",OUT="$OUT",VARIANTS_FILE="$VARIANTS_FILE" \
    scripts/slurm_nthu_variant_sweep_job.sh
)

echo "$job" > "results/job_hooks/submitted_${RESULT_TAG}.jobid"
nohup env WATCH_INTERVAL_SECONDS=20 WATCH_COMMAND="bash scripts/refresh_indexes.sh" \
  bash scripts/watch_job_then_run.sh "$job" "${RESULT_TAG}-refresh" >/dev/null 2>&1 &
echo "$job"
