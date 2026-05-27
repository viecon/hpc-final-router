#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

mkdir -p logs results/job_hooks

RESULT_TAG=${RESULT_TAG:-nthu_fallback_p2_serial_final_r9}
OUT=${OUT:-"$ROOT/results/${RESULT_TAG}_summary.csv"}
ATTEMPTS_OUT=${ATTEMPTS_OUT:-"$ROOT/results/${RESULT_TAG}_attempts_summary.csv"}
VARIANTS_FILE=${VARIANTS_FILE:-"$ROOT/results/job_hooks/${RESULT_TAG}.variants"}

cat > "$VARIANTS_FILE" <<'EOF'
nthu_adaptive_p2|adaptec1*.gr|--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=1400;;--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=1200;;--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=800;;--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=240|
nthu_adaptive_p2_fast|adaptec2*.gr|--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=240;;--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=242 --p3-init-box-size=20 --p3-box-expand-size=30;;--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=225|
nthu_adaptive_p2_dogleg|adaptec3*.gr|--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=4000;;--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=3200;;--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=2800;;--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=2400;;--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=1200|NTHU_DOGLEG_FASTPATH=1 NTHU_DOGLEG_MAX_EXTRA=0 NTHU_DOGLEG_MIN_SCORE=1 NTHU_DOGLEG_STEP=6
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
    --time=0-00:20:00 \
    --job-name=nthu-final-r9 \
    --output="$ROOT/logs/%x_%j.log" \
    --error="$ROOT/logs/%x_%j.err" \
    --export=ALL,PROJECT_ROOT="$ROOT",CONTAINER_RUNTIME=apptainer,IMAGE=router.sif,EVALUATOR=lab2,OMP_NUM_THREADS=1,NTHU_OPENMP=OFF,NTHU_CUDA=OFF,BUILD_DIR="$ROOT/external/nthu-route/build-release-openmp-OFF-cuda-OFF",SKIP_INITIAL_BUILD=1,RUN_TAG="${RESULT_TAG}_summary",OUT="$OUT",ATTEMPTS_OUT="$ATTEMPTS_OUT",ADAPTIVE_VARIANTS_FILE="$VARIANTS_FILE" \
    scripts/slurm_nthu_adaptive_p2_job.sh
)

echo "$job" > "results/job_hooks/submitted_${RESULT_TAG}.jobid"
nohup env WATCH_INTERVAL_SECONDS=20 WATCH_COMMAND="bash scripts/refresh_indexes.sh" \
  bash scripts/watch_job_then_run.sh "$job" "${RESULT_TAG}-refresh" >/dev/null 2>&1 &
echo "$job"
