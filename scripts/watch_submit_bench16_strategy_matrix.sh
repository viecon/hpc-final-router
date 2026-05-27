#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

TAG=${TAG:-bench16_strategy_matrix_r1}
ACCOUNT=${ACCOUNT:-ACD115058}
QOS=${QOS:-contest_v100}
PARTITION=${PARTITION:-nycugpu_queue}
CPUS=${CPUS:-4}
GPUS=${GPUS:-1}
MEM=${MEM:-64G}
TIME_LIMIT=${TIME_LIMIT:-0-00:59:00}
BENCH_LIST=${BENCH_LIST:-"$ROOT/results/job_hooks/ispd08_all16.list"}
STRATEGIES=${STRATEGIES:-"nthu_original nthu_openmp_t4 nthu_fast_layer nthu_p2p3_budget nthu_cuda_score nthu_edgecount_post"}
INTERVAL_SECONDS=${INTERVAL_SECONDS:-60}
STATE_ID=${STATE_ID:-$TAG}

mkdir -p logs results/job_hooks "results/${TAG}"

TASKS=${TASKS_FILE:-"$ROOT/results/job_hooks/${TAG}.tasks"}
STATE="$ROOT/results/job_hooks/${STATE_ID}.state"
CURRENT="$ROOT/results/job_hooks/${STATE_ID}.current_job"
SUBMITTED="$ROOT/results/job_hooks/submitted_${STATE_ID}.jobs"
LOG="$ROOT/logs/watch_submit_${STATE_ID}.log"

if [[ ! -s "$TASKS" && -z "${TASKS_FILE:-}" ]]; then
  : > "$TASKS"
  while IFS= read -r bench; do
    [[ -n "$bench" ]] || continue
    for strategy in $STRATEGIES; do
      printf '%s,%s\n' "$strategy" "$bench" >> "$TASKS"
    done
  done < "$BENCH_LIST"
elif [[ ! -s "$TASKS" ]]; then
  echo "task file is missing or empty: $TASKS" >&2
  exit 1
fi

if [[ ! -s "$STATE" ]]; then
  echo 1 > "$STATE"
fi
: > "$SUBMITTED"

is_active() {
  local job=$1
  [[ -n "$job" ]] || return 1
  timeout 10s squeue -j "$job" -h 2>/dev/null | grep -q .
}

submit_one() {
  local line_no=$1
  local task strategy bench safe_bench job_name job
  task=$(sed -n "${line_no}p" "$TASKS")
  [[ -n "$task" ]] || return 1
  strategy=${task%%,*}
  bench=${task#*,}
  safe_bench=${bench%.gr}
  safe_bench=${safe_bench//[^A-Za-z0-9_]/_}
  job_name="b16-${strategy}-${safe_bench}"
  job_name=${job_name:0:120}
  job=$(
    sbatch --parsable \
      --account="$ACCOUNT" \
      --qos="$QOS" \
      --partition="$PARTITION" \
      --nodes=1 \
      --ntasks-per-node=1 \
      --cpus-per-task="$CPUS" \
      --gpus-per-node="$GPUS" \
      --mem="$MEM" \
      --time="$TIME_LIMIT" \
      --job-name="$job_name" \
      --output="$ROOT/logs/%x_%j.log" \
      --error="$ROOT/logs/%x_%j.err" \
      --export=ALL,PROJECT_ROOT="$ROOT",TAG="$TAG",EVALUATOR=lab2,OMP_NUM_THREADS="$CPUS",JOBS="$CPUS" \
      --wrap="cd '$ROOT' && apptainer exec --nv router.sif bash scripts/run_bench16_strategy_one.sh '$strategy' '$bench'"
  )
  if [[ -z "$job" ]]; then
    echo "[$(date '+%F %T')] sbatch returned empty job id line=$line_no strategy=$strategy bench=$bench" >> "$LOG"
    return 1
  fi
  printf '%s,%s,%s\n' "$job" "$strategy" "$bench" >> "$SUBMITTED"
  echo "$job" > "$CURRENT"
  echo $((line_no + 1)) > "$STATE"
  echo "[$(date '+%F %T')] submitted line=$line_no job=$job strategy=$strategy bench=$bench" >> "$LOG"
}

total=$(wc -l < "$TASKS")
echo "[$(date '+%F %T')] watcher start tag=$TAG total_tasks=$total" >> "$LOG"

while true; do
  line_no=$(cat "$STATE")
  current_job=$(cat "$CURRENT" 2>/dev/null || true)

  if [[ -n "$current_job" ]] && is_active "$current_job"; then
    sleep "$INTERVAL_SECONDS"
    continue
  fi

  if [[ "$line_no" -gt "$total" ]]; then
    echo "[$(date '+%F %T')] all tasks submitted and last job finished; aggregating" >> "$LOG"
    python3 scripts/aggregate_bench16_strategy_matrix.py
    bash scripts/refresh_indexes.sh
    echo "[$(date '+%F %T')] done" >> "$LOG"
    exit 0
  fi

  if submit_one "$line_no"; then
    sleep "$INTERVAL_SECONDS"
  else
    echo "[$(date '+%F %T')] submit failed for line=$line_no; retrying later" >> "$LOG"
    sleep "$INTERVAL_SECONDS"
  fi
done
