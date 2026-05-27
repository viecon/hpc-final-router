#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

mkdir -p logs results/job_hooks results/targeted_repairs

design=benchmarks/ispd08/adaptec1.capo70.3d.35.50.90.gr
route=results/nthu_cuda_a1_th6000_p3big60_score25_cuda_a1_threshold_score25_fine/adaptec1.capo70.3d.35.50.90.nthu.out
edges=results/targeted_repairs/a1_cuda_th6000_p3big60_score25_astar_ultra.final.edges.csv
out=results/targeted_repairs/a1_cuda_th6000_p3big60_score25_layer_move.out
prefix=results/targeted_repairs/a1_cuda_th6000_p3big60_score25_layer_move

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
    --job-name=target-a1-layer \
    --output="$ROOT/logs/%x_%j.log" \
    --error="$ROOT/logs/%x_%j.err" \
    --wrap="cd '$ROOT' && python3 scripts/targeted_layer_move_repair.py --design '$design' --route '$route' --overflow-edges '$edges' --out '$out' --work-prefix '$prefix' --max-nets-per-edge 32 --max-trials 300; apptainer exec router.sif python3 external/lab2-checker/verifier.py '$design' '$out' --json > '${out%.out}.metrics.json' || true; bash scripts/refresh_indexes.sh"
)

echo "$job" > results/job_hooks/submitted_targeted_layer_move_a1_th6000_cuda.jobid
nohup env WATCH_INTERVAL_SECONDS=20 WATCH_COMMAND="bash scripts/refresh_indexes.sh" \
  bash scripts/watch_job_then_run.sh "$job" targeted_layer_move_a1_th6000_cuda-refresh >/dev/null 2>&1 &
echo "$job"
