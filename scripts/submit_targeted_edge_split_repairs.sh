#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

mkdir -p logs results/job_hooks results/targeted_repairs
TARGET=${TARGET:-a1}

submit_one() {
  local name=$1
  local design=$2
  local route=$3
  local out=$4
  local prefix=$5
  local max_passes=$6
  local max_nets=$7
  local max_trials=$8

  sbatch --parsable \
    --account=ACD115058 \
    --partition=nycugpu_queue \
    --nodes=1 \
    --ntasks-per-node=1 \
    --cpus-per-task=4 \
    --gpus-per-node=1 \
    --mem=32G \
    --time=0-00:30:00 \
    --job-name="$name" \
    --output="$ROOT/logs/%x_%j.log" \
    --error="$ROOT/logs/%x_%j.err" \
    --wrap="cd '$ROOT' && python3 scripts/targeted_edge_split_repair.py --design '$design' --route '$route' --out '$out' --work-prefix '$prefix' --max-passes '$max_passes' --max-nets-per-edge '$max_nets' --max-trials '$max_trials'; apptainer exec router.sif python3 external/lab2-checker/verifier.py '$design' '$out' --json > '${out%.out}.metrics.json' || true; bash scripts/refresh_indexes.sh"
}

if [ "$TARGET" = "a1" ] || [ "$TARGET" = "both" ]; then
  a1_job=$(
    submit_one \
      target-split-a1 \
      benchmarks/ispd08/adaptec1.capo70.3d.35.50.90.gr \
      results/nthu_a1_th10000_p3iter30_a1_th10000_repair_sweep/adaptec1.capo70.3d.35.50.90.nthu.out \
      results/targeted_repairs/a1_th10000_p3iter30_edge_split.out \
      results/targeted_repairs/a1_th10000_p3iter30_edge_split \
      5 20 160
  )
  printf "%s\n" "$a1_job" > results/job_hooks/submitted_targeted_edge_split_a1.jobid
  nohup env WATCH_INTERVAL_SECONDS=20 WATCH_COMMAND="bash scripts/refresh_indexes.sh" \
    bash scripts/watch_job_then_run.sh "$a1_job" targeted_edge_split_a1-refresh >/dev/null 2>&1 &
  printf "a1=%s\n" "$a1_job"
fi

if [ "$TARGET" = "a3" ] || [ "$TARGET" = "both" ]; then
  a3_job=$(
    submit_one \
      target-split-a3 \
      benchmarks/ispd08/adaptec3.dragon70.3d.30.50.90.gr \
      results/nthu_a3_p3budget10_a3_p3_budget_frontier/adaptec3.dragon70.3d.30.50.90.nthu.out \
      results/targeted_repairs/a3_p3budget10_edge_split.out \
      results/targeted_repairs/a3_p3budget10_edge_split \
      6 18 180
  )
  printf "%s\n" "$a3_job" > results/job_hooks/submitted_targeted_edge_split_a3.jobid
  nohup env WATCH_INTERVAL_SECONDS=20 WATCH_COMMAND="bash scripts/refresh_indexes.sh" \
    bash scripts/watch_job_then_run.sh "$a3_job" targeted_edge_split_a3-refresh >/dev/null 2>&1 &
  printf "a3=%s\n" "$a3_job"
fi
