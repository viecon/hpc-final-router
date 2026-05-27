#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

mkdir -p logs results/job_hooks

RESULT_TAG=${RESULT_TAG:-traceoff_a1a2_best}
BUILD_DIR=${BUILD_DIR:-"$ROOT/external/nthu-route/build-release-openmp-OFF-cuda-ON-traceoff"}

submit_one() {
  local bench=$1
  local job_name=$2
  local variants_file="$ROOT/results/job_hooks/${RESULT_TAG}_${bench}.variants"
  local out="$ROOT/results/nthu_${RESULT_TAG}_${bench}_summary.csv"
  local pattern
  case "$bench" in
    a1)
      pattern='adaptec1*.gr'
      cat > "$variants_file" <<'EOF'
nthu_a1_traceoff_th1700_p3box20_30|--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=1700 --p3-init-box-size=20 --p3-box-expand-size=30|
EOF
      ;;
    a2)
      pattern='adaptec2*.gr'
      cat > "$variants_file" <<'EOF'
nthu_a2_traceoff_th243_p3_20_30_dog500|--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=243 --p3-init-box-size=20 --p3-box-expand-size=30|NTHU_DOGLEG_FASTPATH=1 NTHU_DOGLEG_MAX_EXTRA=0 NTHU_DOGLEG_MIN_SCORE=500
nthu_a2_traceoff_th240_plain|--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=240|
EOF
      ;;
    *)
      echo "unknown bench: $bench" >&2
      exit 2
      ;;
  esac

  sbatch --parsable \
    --account=ACD115058 \
    --partition=nycugpu_queue \
    --nodes=1 \
    --ntasks-per-node=1 \
    --cpus-per-task=4 \
    --gpus-per-node=1 \
    --mem=64G \
    --time=0-00:25:00 \
    --job-name="$job_name" \
    --output="$ROOT/logs/%x_%j.log" \
    --error="$ROOT/logs/%x_%j.err" \
    --export=ALL,PROJECT_ROOT="$ROOT",CONTAINER_RUNTIME=apptainer,IMAGE=router.sif,EVALUATOR=lab2,OMP_NUM_THREADS=1,NTHU_OPENMP=OFF,NTHU_CUDA=ON,JOBS=4,BUILD_DIR="$BUILD_DIR",SKIP_INITIAL_BUILD=1,BENCH_PATTERN="$pattern",RESULT_SUFFIX="${RESULT_TAG}_${bench}",OUT="$out",VARIANTS_FILE="$variants_file" \
    scripts/slurm_nthu_variant_sweep_job.sh
}

submit_one a1 nthu-traceoff-a1
submit_one a2 nthu-traceoff-a2
