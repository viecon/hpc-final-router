#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

mkdir -p logs results/job_hooks

RESULT_TAG=${RESULT_TAG:-nthu_b1_p3_after_first_hotedge_probe}
OUT=${OUT:-"$ROOT/results/${RESULT_TAG}_summary.csv"}
VARIANTS_FILE=${VARIANTS_FILE:-"$ROOT/results/job_hooks/${RESULT_TAG}.variants"}
BUILD_DIR=${BUILD_DIR:-"$ROOT/external/nthu-route/build-release-openmp-OFF-cuda-ON-post-hotedge"}

base_args="--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=10000 --p2-max-iteration=5 --p3-max-iteration=2"
base_env="NTHU_FAST_GREEDY_LAYER=1 NTHU_DOGLEG_FASTPATH=1 NTHU_DOGLEG_MAX_EXTRA=0 NTHU_DOGLEG_MIN_SCORE=1 NTHU_DOGLEG_STEP=8 NTHU_RANGE_SKIP_REMAINDER=1 NTHU_REROUTE_SCORE_P2_ONLY=1 NTHU_POST_EXCESS_EDGE_REPAIR_AFTER_FIRST=1"

cat > "$VARIANTS_FILE" <<EOF
nthu_b1_rscore4_p3m2_box48_75_hotedge_m1|$base_args --p3-init-box-size=48 --p3-box-expand-size=75|$base_env NTHU_REROUTE_MIN_OVERFLOW_SCORE=4 NTHU_POST_EXCESS_EDGE_REPAIR_MULT=1
nthu_b1_rscore4_p3m2_box48_75_hotedge_m2|$base_args --p3-init-box-size=48 --p3-box-expand-size=75|$base_env NTHU_REROUTE_MIN_OVERFLOW_SCORE=4 NTHU_POST_EXCESS_EDGE_REPAIR_MULT=2
nthu_b1_rscore5_p3m2_box57_92_hotedge_m1|$base_args --p3-init-box-size=57 --p3-box-expand-size=92|$base_env NTHU_REROUTE_MIN_OVERFLOW_SCORE=5 NTHU_POST_EXCESS_EDGE_REPAIR_MULT=1
nthu_b1_rscore5_p3m2_box57_92_hotedge_m2|$base_args --p3-init-box-size=57 --p3-box-expand-size=92|$base_env NTHU_REROUTE_MIN_OVERFLOW_SCORE=5 NTHU_POST_EXCESS_EDGE_REPAIR_MULT=2
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
    --time=0-00:30:00 \
    --job-name=nthu-b1-hotedge \
    --output="$ROOT/logs/%x_%j.log" \
    --error="$ROOT/logs/%x_%j.err" \
    --export=ALL,PROJECT_ROOT="$ROOT",CONTAINER_RUNTIME=apptainer,IMAGE=router.sif,EVALUATOR=lab2,OMP_NUM_THREADS=1,NTHU_OPENMP=OFF,NTHU_CUDA=ON,JOBS=4,BUILD_DIR="$BUILD_DIR",SKIP_INITIAL_BUILD=0,BENCH_PATTERN=bigblue1*.gr,RESULT_SUFFIX="$RESULT_TAG",OUT="$OUT",VARIANTS_FILE="$VARIANTS_FILE" \
    scripts/slurm_nthu_variant_sweep_job.sh
)

echo "$job" > "results/job_hooks/submitted_${RESULT_TAG}.jobid"
nohup env WATCH_INTERVAL_SECONDS=20 WATCH_COMMAND="bash scripts/refresh_indexes.sh" \
  bash scripts/watch_job_then_run.sh "$job" "${RESULT_TAG}-refresh" >/dev/null 2>&1 &
echo "$job"
