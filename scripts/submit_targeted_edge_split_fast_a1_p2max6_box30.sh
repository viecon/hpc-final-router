#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

mkdir -p logs results/job_hooks results/targeted_repairs

design=benchmarks/ispd08/adaptec1.capo70.3d.35.50.90.gr
route=results/nthu_a1_th1800_p2max6_p3box30_50_a1_p2max_repair_refine/adaptec1.capo70.3d.35.50.90.nthu.out
out=results/targeted_repairs/a1_th1800_p2max6_p3box30_50_edge_split_fast.out
prefix=results/targeted_repairs/a1_th1800_p2max6_p3box30_50_edge_split_fast

job=$(
  sbatch --parsable \
    --account=ACD115058 \
    --partition=nycugpu_queue \
    --nodes=1 \
    --ntasks-per-node=1 \
    --cpus-per-task=4 \
    --gpus-per-node=1 \
    --mem=32G \
    --time=0-00:20:00 \
    --job-name=target-a1-p2split \
    --output="$ROOT/logs/%x_%j.log" \
    --error="$ROOT/logs/%x_%j.err" \
    --wrap="cd '$ROOT' && python3 scripts/targeted_edge_split_fast_repair.py --design '$design' --route '$route' --out '$out' --work-prefix '$prefix' --max-passes 20 --max-nets-per-edge 80; apptainer exec router.sif python3 external/lab2-checker/verifier.py '$design' '$out' --json > '${out%.out}.metrics.json' || true; bash scripts/refresh_indexes.sh"
)

echo "$job" > results/job_hooks/submitted_targeted_edge_split_fast_a1_p2max6_box30.jobid
nohup env WATCH_INTERVAL_SECONDS=20 WATCH_COMMAND="bash scripts/refresh_indexes.sh" \
  bash scripts/watch_job_then_run.sh "$job" targeted_edge_split_fast_a1_p2max6_box30-refresh >/dev/null 2>&1 &
echo "$job"
