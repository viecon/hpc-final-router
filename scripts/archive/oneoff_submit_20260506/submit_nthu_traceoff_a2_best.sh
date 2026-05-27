#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

mkdir -p logs results/job_hooks

RESULT_TAG=${RESULT_TAG:-traceoff_a2_best}
OUT=${OUT:-"$ROOT/results/nthu_${RESULT_TAG}_summary.csv"}
VARIANTS_FILE=${VARIANTS_FILE:-"$ROOT/results/job_hooks/${RESULT_TAG}.variants"}
BUILD_DIR=${BUILD_DIR:-"$ROOT/external/nthu-route/build-release-openmp-OFF-cuda-ON-traceoff"}

cat > "$VARIANTS_FILE" <<'EOF'
nthu_a2_traceoff_th243_p3_20_30_dog500|--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=243 --p3-init-box-size=20 --p3-box-expand-size=30|NTHU_DOGLEG_FASTPATH=1 NTHU_DOGLEG_MAX_EXTRA=0 NTHU_DOGLEG_MIN_SCORE=500
nthu_a2_traceoff_th240_plain|--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=240|
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
    --time=0-00:15:00 \
    --job-name=nthu-traceoff-a2 \
    --output="$ROOT/logs/%x_%j.log" \
    --error="$ROOT/logs/%x_%j.err" \
    --export=ALL,PROJECT_ROOT="$ROOT",CONTAINER_RUNTIME=apptainer,IMAGE=router.sif,EVALUATOR=lab2,OMP_NUM_THREADS=1,NTHU_OPENMP=OFF,NTHU_CUDA=ON,JOBS=4,BUILD_DIR="$BUILD_DIR",SKIP_INITIAL_BUILD=1,BENCH_PATTERN=adaptec2*.gr,RESULT_SUFFIX="$RESULT_TAG",OUT="$OUT",VARIANTS_FILE="$VARIANTS_FILE" \
    scripts/slurm_nthu_variant_sweep_job.sh
)

echo "$job" > "results/job_hooks/submitted_${RESULT_TAG}.jobid"
echo "$job"
