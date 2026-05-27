#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

TARGET=${TARGET:-a1}
RADIUS=${RADIUS:-10}
MAX_NETS=${MAX_NETS:-24}
mkdir -p logs results/job_hooks results/targeted_repairs

case "$TARGET" in
  a1)
    name=target-astar-a1
    design=benchmarks/ispd08/adaptec1.capo70.3d.35.50.90.gr
    route=results/nthu_a1_th10000_p3iter30_a1_th10000_repair_sweep/adaptec1.capo70.3d.35.50.90.nthu.out
    out=results/targeted_repairs/a1_th10000_p3iter30_astar_segment.out
    prefix=results/targeted_repairs/a1_th10000_p3iter30_astar_segment
    passes=6
    ;;
  a3)
    name=target-astar-a3
    design=benchmarks/ispd08/adaptec3.dragon70.3d.30.50.90.gr
    route=results/nthu_a3_p3budget10_a3_p3_budget_frontier/adaptec3.dragon70.3d.30.50.90.nthu.out
    out=results/targeted_repairs/a3_p3budget10_astar_segment.out
    prefix=results/targeted_repairs/a3_p3budget10_astar_segment
    passes=8
    ;;
  *)
    echo "unknown TARGET=$TARGET (expected a1 or a3)" >&2
    exit 2
    ;;
esac

job=$(
  sbatch --parsable \
    --account=ACD115058 \
    --partition=nycugpu_queue \
    --nodes=1 \
    --ntasks-per-node=1 \
    --cpus-per-task=4 \
    --gpus-per-node=1 \
    --mem=32G \
    --time=0-00:25:00 \
    --job-name="$name" \
    --output="$ROOT/logs/%x_%j.log" \
    --error="$ROOT/logs/%x_%j.err" \
    --wrap="cd '$ROOT' && python3 scripts/targeted_astar_segment_repair.py --design '$design' --route '$route' --out '$out' --work-prefix '$prefix' --max-passes '$passes' --max-nets-per-edge '$MAX_NETS' --radius '$RADIUS'; apptainer exec router.sif python3 external/lab2-checker/verifier.py '$design' '$out' --json > '${out%.out}.metrics.json' || true; bash scripts/refresh_indexes.sh"
)

printf "%s\n" "$job" > "results/job_hooks/submitted_targeted_astar_segment_${TARGET}.jobid"
nohup env WATCH_INTERVAL_SECONDS=20 WATCH_COMMAND="bash scripts/refresh_indexes.sh" \
  bash scripts/watch_job_then_run.sh "$job" "targeted_astar_segment_${TARGET}-refresh" >/dev/null 2>&1 &

printf "%s=%s\n" "$TARGET" "$job"
