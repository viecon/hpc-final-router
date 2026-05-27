#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

TAG=${TAG:-bench16_strategy_matrix}
ACCOUNT=${ACCOUNT:-ACD115058}
QOS=${QOS:-contest_v100}
PARTITION=${PARTITION:-nycugpu_queue}
CPUS=${CPUS:-4}
GPUS=${GPUS:-1}
MEM=${MEM:-64G}
TIME_LIMIT=${TIME_LIMIT:-0-01:00:00}
BENCH_LIST=${BENCH_LIST:-"$ROOT/results/job_hooks/ispd08_all16.list"}
STRATEGIES=${STRATEGIES:-"nthu_original nthu_openmp_t4 nthu_fast_layer nthu_p2p3_budget nthu_cuda_score nthu_edgecount_post"}

mkdir -p logs results/job_hooks "results/${TAG}"

prev=""
submitted="$ROOT/results/job_hooks/submitted_${TAG}.jobs"
: > "$submitted"

while IFS= read -r bench; do
  [[ -n "$bench" ]] || continue
  for strategy in $STRATEGIES; do
    safe_bench=${bench%.gr}
    safe_bench=${safe_bench//[^A-Za-z0-9_]/_}
    job_name="b16-${strategy}-${safe_bench}"
    job_name=${job_name:0:120}
    dep_args=()
    if [[ -n "$prev" ]]; then
      dep_args=(--dependency="afterany:$prev")
    fi
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
        "${dep_args[@]}" \
        --wrap="cd '$ROOT' && apptainer exec --nv router.sif bash scripts/run_bench16_strategy_one.sh '$strategy' '$bench'"
    )
    echo "$job,$strategy,$bench" >> "$submitted"
    prev="$job"
  done
done < "$BENCH_LIST"

final_job=$(
  sbatch --parsable \
    --account="$ACCOUNT" \
    --qos="$QOS" \
    --partition="$PARTITION" \
    --nodes=1 \
    --ntasks-per-node=1 \
    --cpus-per-task=1 \
    --gpus-per-node=1 \
    --mem=8G \
    --time=0-00:10:00 \
    --job-name="b16-aggregate" \
    --output="$ROOT/logs/%x_%j.log" \
    --error="$ROOT/logs/%x_%j.err" \
    --dependency="afterany:$prev" \
    --wrap="cd '$ROOT' && python3 scripts/aggregate_bench16_strategy_matrix.py && bash scripts/refresh_indexes.sh"
)
echo "$final_job,aggregate,ALL" >> "$submitted"

echo "$final_job" > "$ROOT/results/job_hooks/submitted_${TAG}_final.jobid"
echo "$prev" > "$ROOT/results/job_hooks/submitted_${TAG}_last_run.jobid"
echo "submitted chain to $submitted"
echo "last run job: $prev"
echo "aggregate job: $final_job"
