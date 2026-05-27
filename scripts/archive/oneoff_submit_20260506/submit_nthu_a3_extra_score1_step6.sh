#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

mkdir -p logs results/job_hooks

RESULT_TAG=${RESULT_TAG:-a3_extra_score1_step6}
OUT=${OUT:-"$ROOT/results/nthu_${RESULT_TAG}_summary.csv"}
VARIANTS_FILE=${VARIANTS_FILE:-"$ROOT/results/job_hooks/${RESULT_TAG}.variants"}

cat > "$VARIANTS_FILE" <<'EOF'
nthu_a3_score1_step6_extra0|--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=4000|NTHU_DOGLEG_FASTPATH=1 NTHU_DOGLEG_MAX_EXTRA=0 NTHU_DOGLEG_MIN_SCORE=1 NTHU_DOGLEG_STEP=6
nthu_a3_score1_step6_extra1|--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=4000|NTHU_DOGLEG_FASTPATH=1 NTHU_DOGLEG_MAX_EXTRA=1 NTHU_DOGLEG_MIN_SCORE=1 NTHU_DOGLEG_STEP=6
nthu_a3_score1_step6_extra2|--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=4000|NTHU_DOGLEG_FASTPATH=1 NTHU_DOGLEG_MAX_EXTRA=2 NTHU_DOGLEG_MIN_SCORE=1 NTHU_DOGLEG_STEP=6
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
    --time=0-00:18:00 \
    --job-name=nthu-a3-extra \
    --output="$ROOT/logs/%x_%j.log" \
    --error="$ROOT/logs/%x_%j.err" \
    --export=ALL,PROJECT_ROOT="$ROOT",CONTAINER_RUNTIME=apptainer,IMAGE=router.sif,EVALUATOR=lab2,OMP_NUM_THREADS=1,NTHU_OPENMP=OFF,NTHU_CUDA=OFF,BUILD_DIR="$ROOT/external/nthu-route/build-release-openmp-OFF-cuda-OFF",SKIP_INITIAL_BUILD=1,BENCH_PATTERN=adaptec3*.gr,RESULT_SUFFIX="$RESULT_TAG",OUT="$OUT",VARIANTS_FILE="$VARIANTS_FILE" \
    scripts/slurm_nthu_variant_sweep_job.sh
)

echo "$job" > "results/job_hooks/submitted_${RESULT_TAG}.jobid"
nohup env WATCH_INTERVAL_SECONDS=20 WATCH_COMMAND="python3 scripts/compare_variant_summary.py $OUT --out ${OUT%.csv}_compare.csv && bash scripts/refresh_indexes.sh" \
  bash scripts/watch_job_then_run.sh "$job" "${RESULT_TAG}-compare" >/dev/null 2>&1 &
echo "$job"
