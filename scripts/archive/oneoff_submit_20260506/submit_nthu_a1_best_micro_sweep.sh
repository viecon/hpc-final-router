#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

mkdir -p logs results/job_hooks

RESULT_TAG=${RESULT_TAG:-a1_best_micro_sweep}
OUT=${OUT:-"$ROOT/results/nthu_${RESULT_TAG}_summary.csv"}
VARIANTS_FILE=${VARIANTS_FILE:-"$ROOT/results/job_hooks/${RESULT_TAG}.variants"}

cat > "$VARIANTS_FILE" <<'EOF'
nthu_a1_th1680_p3box18_28|--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=1680 --p3-init-box-size=18 --p3-box-expand-size=28|
nthu_a1_th1680_p3box20_30|--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=1680 --p3-init-box-size=20 --p3-box-expand-size=30|
nthu_a1_th1700_p3box18_28|--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=1700 --p3-init-box-size=18 --p3-box-expand-size=28|
nthu_a1_th1720_p3box20_30|--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=1720 --p3-init-box-size=20 --p3-box-expand-size=30|
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
    --time=0-00:25:00 \
    --job-name=nthu-a1-micro \
    --output="$ROOT/logs/%x_%j.log" \
    --error="$ROOT/logs/%x_%j.err" \
    --export=ALL,PROJECT_ROOT="$ROOT",CONTAINER_RUNTIME=apptainer,IMAGE=router.sif,EVALUATOR=lab2,OMP_NUM_THREADS=1,NTHU_OPENMP=OFF,NTHU_CUDA=OFF,JOBS=4,BUILD_DIR="$ROOT/external/nthu-route/build-release-openmp-OFF-maze-sanity",SKIP_INITIAL_BUILD=1,BENCH_PATTERN=adaptec1*.gr,RESULT_SUFFIX="$RESULT_TAG",OUT="$OUT",VARIANTS_FILE="$VARIANTS_FILE" \
    scripts/slurm_nthu_variant_sweep_job.sh
)

echo "$job" > "results/job_hooks/submitted_${RESULT_TAG}.jobid"
echo "$job"
