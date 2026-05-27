#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

mkdir -p logs results/job_hooks

RESULT_TAG=${RESULT_TAG:-nthu_b1_second_p3_fine_gate}
OUT=${OUT:-"$ROOT/results/${RESULT_TAG}_summary.csv"}
VARIANTS_FILE=${VARIANTS_FILE:-"$ROOT/results/job_hooks/${RESULT_TAG}.variants"}
BUILD_DIR=${BUILD_DIR:-"$ROOT/external/nthu-route/build-release-openmp-OFF-cuda-ON-post-hot-sort"}
ACCOUNT=${ACCOUNT:-ACD115058}
QOS=${QOS:-contest_v100}
PARTITION=${PARTITION:-}

base_args="--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=10000 --p2-max-iteration=5 --p3-max-iteration=2 --p3-init-box-size=54 --p3-box-expand-size=88"
base_env="NTHU_FAST_GREEDY_LAYER=1 NTHU_DOGLEG_FASTPATH=1 NTHU_DOGLEG_MAX_EXTRA=0 NTHU_DOGLEG_MIN_SCORE=1 NTHU_DOGLEG_STEP=8 NTHU_RANGE_SKIP_REMAINDER=1 NTHU_REROUTE_SCORE_P2_ONLY=1 NTHU_REROUTE_MIN_OVERFLOW_SCORE=5 NTHU_REROUTE_LATE_SCORE_AFTER_ITER=4 NTHU_REROUTE_LATE_MIN_OVERFLOW_SCORE=4 NTHU_POST_SORT_MODE=short_first"

cat > "$VARIANTS_FILE" <<EOF
nthu_b1_late4_p3box54_88_p3m2_limit60|$base_args|$base_env NTHU_POST_OVERFLOW_LIMIT_AFTER_FIRST=60
nthu_b1_late4_p3box54_88_p3m2_limit70|$base_args|$base_env NTHU_POST_OVERFLOW_LIMIT_AFTER_FIRST=70
nthu_b1_late4_p3box54_88_p3m2_limit80|$base_args|$base_env NTHU_POST_OVERFLOW_LIMIT_AFTER_FIRST=80
nthu_b1_late4_p3box54_88_p3m2_limit90|$base_args|$base_env NTHU_POST_OVERFLOW_LIMIT_AFTER_FIRST=90
nthu_b1_late4_p3box54_88_p3m2_score6_limit100|$base_args|$base_env NTHU_POST_OVERFLOW_LIMIT_AFTER_FIRST=100 NTHU_POST_MIN_OVERFLOW_SCORE_AFTER_FIRST=6
nthu_b1_late4_p3box54_88_p3m2_score8_limit100|$base_args|$base_env NTHU_POST_OVERFLOW_LIMIT_AFTER_FIRST=100 NTHU_POST_MIN_OVERFLOW_SCORE_AFTER_FIRST=8
nthu_b1_late4_p3box54_88_p3m2_score10_limit100|$base_args|$base_env NTHU_POST_OVERFLOW_LIMIT_AFTER_FIRST=100 NTHU_POST_MIN_OVERFLOW_SCORE_AFTER_FIRST=10
nthu_b1_late4_p3box54_88_p3m2_score8_limit150|$base_args|$base_env NTHU_POST_OVERFLOW_LIMIT_AFTER_FIRST=150 NTHU_POST_MIN_OVERFLOW_SCORE_AFTER_FIRST=8
EOF

sbatch_args=(
  --parsable
  --account="$ACCOUNT"
)
if [[ -n "$QOS" ]]; then
  sbatch_args+=(--qos="$QOS")
fi
if [[ -n "$PARTITION" ]]; then
  sbatch_args+=(--partition="$PARTITION")
fi

job=$(
  sbatch "${sbatch_args[@]}" \
    --nodes=1 \
    --ntasks-per-node=1 \
    --cpus-per-task=4 \
    --gpus-per-node=1 \
    --mem=64G \
    --time=0-00:30:00 \
    --job-name=nthu-b1-p3fine \
    --output="$ROOT/logs/%x_%j.log" \
    --error="$ROOT/logs/%x_%j.err" \
    --export=ALL,PROJECT_ROOT="$ROOT",CONTAINER_RUNTIME=apptainer,IMAGE=router.sif,EVALUATOR=lab2,OMP_NUM_THREADS=1,NTHU_OPENMP=OFF,NTHU_CUDA=ON,JOBS=4,BUILD_DIR="$BUILD_DIR",SKIP_INITIAL_BUILD=1,BENCH_PATTERN=bigblue1*.gr,RESULT_SUFFIX="$RESULT_TAG",OUT="$OUT",VARIANTS_FILE="$VARIANTS_FILE" \
    scripts/slurm_nthu_variant_sweep_job.sh
)

echo "$job" > "results/job_hooks/submitted_${RESULT_TAG}.jobid"
nohup env WATCH_INTERVAL_SECONDS=20 WATCH_COMMAND="bash scripts/refresh_indexes.sh" \
  bash scripts/watch_job_then_run.sh "$job" "${RESULT_TAG}-refresh" >/dev/null 2>&1 &
echo "$job"
