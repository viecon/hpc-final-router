#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

mkdir -p logs results/job_hooks

RESULT_TAG=${RESULT_TAG:-a1_p2max_repair_refine}
OUT=${OUT:-"$ROOT/results/nthu_${RESULT_TAG}_summary.csv"}
VARIANTS_FILE=${VARIANTS_FILE:-"$ROOT/results/job_hooks/${RESULT_TAG}.variants"}
BUILD_DIR=${BUILD_DIR:-"$ROOT/external/nthu-route/build-release-openmp-OFF-fast-greedy-layer"}

base_env="NTHU_FAST_GREEDY_LAYER=1"

cat > "$VARIANTS_FILE" <<'EOF'
nthu_a1_th1800_p2max6_p3box25_40|--p2-init-box-size=5 --p2-box-expand-size=5 --p2-max-iteration=6 --overflow-threshold=1800 --p3-init-box-size=25 --p3-box-expand-size=40|NTHU_FAST_GREEDY_LAYER=1
nthu_a1_th1800_p2max6_p3box30_50|--p2-init-box-size=5 --p2-box-expand-size=5 --p2-max-iteration=6 --overflow-threshold=1800 --p3-init-box-size=30 --p3-box-expand-size=50|NTHU_FAST_GREEDY_LAYER=1
nthu_a1_th1800_p2max5_p3box30_50|--p2-init-box-size=5 --p2-box-expand-size=5 --p2-max-iteration=5 --overflow-threshold=1800 --p3-init-box-size=30 --p3-box-expand-size=50|NTHU_FAST_GREEDY_LAYER=1
nthu_a1_th1700_p2max6_p3box30_50|--p2-init-box-size=5 --p2-box-expand-size=5 --p2-max-iteration=6 --overflow-threshold=1700 --p3-init-box-size=30 --p3-box-expand-size=50|NTHU_FAST_GREEDY_LAYER=1
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
    --job-name=nthu-a1-p2repair \
    --output="$ROOT/logs/%x_%j.log" \
    --error="$ROOT/logs/%x_%j.err" \
    --export=ALL,PROJECT_ROOT="$ROOT",CONTAINER_RUNTIME=apptainer,IMAGE=router.sif,EVALUATOR=lab2,OMP_NUM_THREADS=1,NTHU_OPENMP=OFF,NTHU_CUDA=OFF,JOBS=4,BUILD_DIR="$BUILD_DIR",SKIP_INITIAL_BUILD=1,BENCH_PATTERN=adaptec1*.gr,RESULT_SUFFIX="$RESULT_TAG",OUT="$OUT",VARIANTS_FILE="$VARIANTS_FILE" \
    scripts/slurm_nthu_variant_sweep_job.sh
)

echo "$job" > "results/job_hooks/submitted_${RESULT_TAG}.jobid"
nohup env WATCH_INTERVAL_SECONDS=20 WATCH_COMMAND="bash scripts/refresh_indexes.sh" \
  bash scripts/watch_job_then_run.sh "$job" "${RESULT_TAG}-refresh" >/dev/null 2>&1 &
echo "$job"
