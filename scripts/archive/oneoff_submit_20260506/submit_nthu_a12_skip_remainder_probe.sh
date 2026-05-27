#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

mkdir -p logs results/job_hooks

RESULT_TAG=${RESULT_TAG:-a12_skip_remainder_probe}
OUT=${OUT:-"$ROOT/results/nthu_${RESULT_TAG}_summary.csv"}
ATTEMPTS_OUT=${ATTEMPTS_OUT:-"$ROOT/results/nthu_${RESULT_TAG}_attempts_summary.csv"}
VARIANTS_FILE=${VARIANTS_FILE:-"$ROOT/results/job_hooks/${RESULT_TAG}.variants"}

cat > "$VARIANTS_FILE" <<'EOF'
nthu_a1_skiprem|adaptec1*.gr|--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=1400|NTHU_RANGE_SKIP_REMAINDER=1
nthu_a2_dog_skiprem|adaptec2*.gr|--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=249 --p3-init-box-size=20 --p3-box-expand-size=30|NTHU_DOGLEG_FASTPATH=1 NTHU_DOGLEG_MAX_EXTRA=0 NTHU_DOGLEG_MIN_SCORE=500 NTHU_RANGE_SKIP_REMAINDER=1
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
    --time=0-00:12:00 \
    --job-name=nthu-a12-skip \
    --output="$ROOT/logs/%x_%j.log" \
    --error="$ROOT/logs/%x_%j.err" \
    --export=ALL,PROJECT_ROOT="$ROOT",CONTAINER_RUNTIME=apptainer,IMAGE=router.sif,EVALUATOR=lab2,OMP_NUM_THREADS=1,NTHU_OPENMP=OFF,NTHU_CUDA=OFF,BUILD_DIR="$ROOT/external/nthu-route/build-release-openmp-OFF-cuda-OFF",SKIP_INITIAL_BUILD=1,RUN_TAG="${RESULT_TAG}_summary",OUT="$OUT",ATTEMPTS_OUT="$ATTEMPTS_OUT",ADAPTIVE_VARIANTS_FILE="$VARIANTS_FILE" \
    scripts/slurm_nthu_adaptive_p2_job.sh
)

echo "$job" > "results/job_hooks/submitted_${RESULT_TAG}.jobid"
nohup env WATCH_INTERVAL_SECONDS=20 WATCH_COMMAND="bash scripts/refresh_indexes.sh" \
  bash scripts/watch_job_then_run.sh "$job" "${RESULT_TAG}-refresh" >/dev/null 2>&1 &
echo "$job"
