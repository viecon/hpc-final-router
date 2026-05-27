#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

TARGET=${TARGET:-p4}
mkdir -p logs results/job_hooks results/targeted_repairs

case "$TARGET" in
  p4)
    route=results/nthu_cuda_a3_p3budget4_score50_box30_50_cuda_a3_box30_50_frontier/adaptec3.dragon70.3d.30.50.90.nthu.out
    out=results/targeted_repairs/a3_cuda_p3budget4_score50_box30_50_astar.out
    prefix=results/targeted_repairs/a3_cuda_p3budget4_score50_box30_50_astar
    name=target-a3b30-p4
    ;;
  p5)
    route=results/nthu_cuda_a3_p3budget5_score50_box30_50_cuda_a3_box30_50_frontier/adaptec3.dragon70.3d.30.50.90.nthu.out
    out=results/targeted_repairs/a3_cuda_p3budget5_score50_box30_50_astar.out
    prefix=results/targeted_repairs/a3_cuda_p3budget5_score50_box30_50_astar
    name=target-a3b30-p5
    ;;
  p6)
    route=results/nthu_cuda_a3_p3budget6_score50_box30_50_cuda_a3_box30_50_frontier/adaptec3.dragon70.3d.30.50.90.nthu.out
    out=results/targeted_repairs/a3_cuda_p3budget6_score50_box30_50_astar.out
    prefix=results/targeted_repairs/a3_cuda_p3budget6_score50_box30_50_astar
    name=target-a3b30-p6
    ;;
  *)
    echo "unknown TARGET=$TARGET (expected p4, p5, or p6)" >&2
    exit 2
    ;;
esac

design=benchmarks/ispd08/adaptec3.dragon70.3d.30.50.90.gr

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
    --job-name="$name" \
    --output="$ROOT/logs/%x_%j.log" \
    --error="$ROOT/logs/%x_%j.err" \
    --wrap="cd '$ROOT' && python3 scripts/targeted_astar_segment_repair.py --design '$design' --route '$route' --out '$out' --work-prefix '$prefix' --max-passes 10 --max-nets-per-edge 60 --radius 64 --allow-equal-displacement; apptainer exec router.sif python3 external/lab2-checker/verifier.py '$design' '$out' --json > '${out%.out}.metrics.json' || true; bash scripts/refresh_indexes.sh"
)

echo "$job" > "results/job_hooks/submitted_targeted_astar_cuda_a3_box30_${TARGET}.jobid"
nohup env WATCH_INTERVAL_SECONDS=20 WATCH_COMMAND="bash scripts/refresh_indexes.sh" \
  bash scripts/watch_job_then_run.sh "$job" "targeted_astar_cuda_a3_box30_${TARGET}-refresh" >/dev/null 2>&1 &
echo "$job"
