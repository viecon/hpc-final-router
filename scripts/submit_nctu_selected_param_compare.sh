#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

mkdir -p logs results/job_hooks

RESULT_TAG=${RESULT_TAG:-nctu_selected_param_compare}
BENCH_PATTERN=${BENCH_PATTERN:-*.gr}
OUT=${OUT:-"$ROOT/results/${RESULT_TAG}_summary.csv"}

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
    --job-name=nctu-param-cmp \
    --output="$ROOT/logs/%x_%j.log" \
    --error="$ROOT/logs/%x_%j.err" \
    --export=ALL,RESULT_TAG="$RESULT_TAG",BENCH_PATTERN="$BENCH_PATTERN",OUT="$OUT" \
    --wrap="cd '$ROOT' && bash scripts/run_nctu_selected_param_compare.sh"
)

echo "$job" > "results/job_hooks/submitted_${RESULT_TAG}.jobid"
nohup env WATCH_INTERVAL_SECONDS=20 WATCH_COMMAND="bash scripts/refresh_indexes.sh" \
  bash scripts/watch_job_then_run.sh "$job" "${RESULT_TAG}-refresh" >/dev/null 2>&1 &
echo "$job"
