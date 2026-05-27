#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

mkdir -p logs results/job_hooks

RESULT_TAG=${RESULT_TAG:-nthu_reroute_score_filter_probe}
OUT=${OUT:-"$ROOT/results/${RESULT_TAG}_summary.csv"}
ATTEMPTS_OUT=${ATTEMPTS_OUT:-"$ROOT/results/${RESULT_TAG}_attempts_summary.csv"}
VARIANTS_FILE=${VARIANTS_FILE:-"$ROOT/results/job_hooks/${RESULT_TAG}.variants"}

cat > "$VARIANTS_FILE" <<'EOF'
nthu_a3_skip_reroute_score2|adaptec3*.gr|--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=4800|NTHU_DOGLEG_FASTPATH=1 NTHU_DOGLEG_MAX_EXTRA=0 NTHU_DOGLEG_MIN_SCORE=1 NTHU_DOGLEG_STEP=12 NTHU_RANGE_SKIP_REMAINDER=1 NTHU_REROUTE_MIN_OVERFLOW_SCORE=2
nthu_a3_skip_reroute_score3|adaptec3*.gr|--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=4800|NTHU_DOGLEG_FASTPATH=1 NTHU_DOGLEG_MAX_EXTRA=0 NTHU_DOGLEG_MIN_SCORE=1 NTHU_DOGLEG_STEP=12 NTHU_RANGE_SKIP_REMAINDER=1 NTHU_REROUTE_MIN_OVERFLOW_SCORE=3
nthu_a3_skip_reroute_score5|adaptec3*.gr|--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=4800|NTHU_DOGLEG_FASTPATH=1 NTHU_DOGLEG_MAX_EXTRA=0 NTHU_DOGLEG_MIN_SCORE=1 NTHU_DOGLEG_STEP=12 NTHU_RANGE_SKIP_REMAINDER=1 NTHU_REROUTE_MIN_OVERFLOW_SCORE=5
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
    --time=0-00:20:00 \
    --job-name=nthu-reroute-score \
    --output="$ROOT/logs/%x_%j.log" \
    --error="$ROOT/logs/%x_%j.err" \
    --export=ALL,PROJECT_ROOT="$ROOT",CONTAINER_RUNTIME=apptainer,IMAGE=router.sif,EVALUATOR=lab2,OMP_NUM_THREADS=1,NTHU_OPENMP=OFF,NTHU_CUDA=OFF,BUILD_DIR="$ROOT/external/nthu-route/build-release-openmp-OFF-reroute-filter",SKIP_INITIAL_BUILD=0,RUN_TAG="${RESULT_TAG}",OUT="$OUT",ATTEMPTS_OUT="$ATTEMPTS_OUT",ADAPTIVE_VARIANTS_FILE="$VARIANTS_FILE" \
    scripts/slurm_nthu_adaptive_p2_job.sh
)

echo "$job" > "results/job_hooks/submitted_${RESULT_TAG}.jobid"
nohup env WATCH_INTERVAL_SECONDS=20 WATCH_COMMAND="bash scripts/refresh_indexes.sh" \
  bash scripts/watch_job_then_run.sh "$job" "${RESULT_TAG}-refresh" >/dev/null 2>&1 &
echo "$job"
