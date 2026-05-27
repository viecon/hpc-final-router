#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

mkdir -p logs results/job_hooks

RESULT_TAG=${RESULT_TAG:-fast_greedy_layer_a1_high_threshold}
OUT=${OUT:-"$ROOT/results/nthu_${RESULT_TAG}_summary.csv"}
VARIANTS_FILE=${VARIANTS_FILE:-"$ROOT/results/job_hooks/${RESULT_TAG}.variants"}
BUILD_DIR=${BUILD_DIR:-"$ROOT/external/nthu-route/build-release-openmp-OFF-fast-greedy-layer"}

cat > "$VARIANTS_FILE" <<'EOF'
nthu_a1_fast_layer_th1800|--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=1800 --p3-init-box-size=20 --p3-box-expand-size=30|NTHU_FAST_GREEDY_LAYER=1
nthu_a1_fast_layer_th2000|--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=2000 --p3-init-box-size=20 --p3-box-expand-size=30|NTHU_FAST_GREEDY_LAYER=1
nthu_a1_fast_layer_th2400|--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=2400 --p3-init-box-size=20 --p3-box-expand-size=30|NTHU_FAST_GREEDY_LAYER=1
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
    --job-name=nthu-fast-la-a1hi \
    --output="$ROOT/logs/%x_%j.log" \
    --error="$ROOT/logs/%x_%j.err" \
    --export=ALL,PROJECT_ROOT="$ROOT",CONTAINER_RUNTIME=apptainer,IMAGE=router.sif,EVALUATOR=lab2,OMP_NUM_THREADS=1,NTHU_OPENMP=OFF,NTHU_CUDA=OFF,JOBS=4,BUILD_DIR="$BUILD_DIR",SKIP_INITIAL_BUILD=1,BENCH_PATTERN=adaptec1*.gr,RESULT_SUFFIX="$RESULT_TAG",OUT="$OUT",VARIANTS_FILE="$VARIANTS_FILE" \
    scripts/slurm_nthu_variant_sweep_job.sh
)

echo "$job" > "results/job_hooks/submitted_${RESULT_TAG}.jobid"
nohup env WATCH_INTERVAL_SECONDS=20 WATCH_COMMAND="bash scripts/refresh_indexes.sh" \
  bash scripts/watch_job_then_run.sh "$job" "${RESULT_TAG}-refresh" >/dev/null 2>&1 &
echo "$job"
