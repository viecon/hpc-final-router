#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

mkdir -p logs results/job_hooks results/targeted_repairs

job=$(
  sbatch --parsable \
    --account=ACD115058 \
    --partition=nycugpu_queue \
    --nodes=1 \
    --ntasks-per-node=1 \
    --cpus-per-task=4 \
    --gpus-per-node=1 \
    --mem=32G \
    --time=0-00:30:00 \
    --job-name=target-repair-a1 \
    --output="$ROOT/logs/%x_%j.log" \
    --error="$ROOT/logs/%x_%j.err" \
    --wrap="cd '$ROOT' && python3 scripts/targeted_layer_move_repair.py --design benchmarks/ispd08/adaptec1.capo70.3d.35.50.90.gr --route results/nthu_a1_th10000_p3iter30_a1_th10000_repair_sweep/adaptec1.capo70.3d.35.50.90.nthu.out --overflow-edges results/overflow_dumps/a1_th10000_p3iter30.edges.csv --out results/targeted_repairs/a1_th10000_p3iter30_layer_move.out --work-prefix results/targeted_repairs/a1_th10000_p3iter30_layer_move --max-nets-per-edge 10 --max-trials 120 && apptainer exec router.sif python3 external/lab2-checker/verifier.py benchmarks/ispd08/adaptec1.capo70.3d.35.50.90.gr results/targeted_repairs/a1_th10000_p3iter30_layer_move.out --json > results/targeted_repairs/a1_th10000_p3iter30_layer_move.metrics.json || true && bash scripts/refresh_indexes.sh"
)

echo "$job" > results/job_hooks/submitted_targeted_layer_move_a1.jobid
nohup env WATCH_INTERVAL_SECONDS=20 WATCH_COMMAND="bash scripts/refresh_indexes.sh" \
  bash scripts/watch_job_then_run.sh "$job" targeted_layer_move_a1-refresh >/dev/null 2>&1 &
echo "$job"
