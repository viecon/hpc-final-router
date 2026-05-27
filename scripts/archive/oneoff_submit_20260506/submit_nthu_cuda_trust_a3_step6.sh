#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

mkdir -p logs results/job_hooks

RESULT_TAG=${RESULT_TAG:-cuda_trust_a3_step6}
OUT=${OUT:-"$ROOT/results/nthu_${RESULT_TAG}_summary.csv"}
variants_file="$ROOT/results/job_hooks/${RESULT_TAG}.variants"

cat > "$variants_file" <<'EOF'
nthu_a3_cpu_score1_step6|--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=4000|NTHU_DOGLEG_FASTPATH=1 NTHU_DOGLEG_MAX_EXTRA=0 NTHU_DOGLEG_MIN_SCORE=1 NTHU_DOGLEG_STEP=6
nthu_a3_cuda_legal_score1_step6|--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=4000|NTHU_DOGLEG_FASTPATH=1 NTHU_DOGLEG_MAX_EXTRA=0 NTHU_DOGLEG_MIN_SCORE=1 NTHU_DOGLEG_STEP=6 NTHU_CUDA_DOGLEG_PRESELECT=1 NTHU_CUDA_DOGLEG_LEGAL_FILTER=1
nthu_a3_cuda_trust_score1_step6|--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=4000|NTHU_DOGLEG_FASTPATH=1 NTHU_DOGLEG_MAX_EXTRA=0 NTHU_DOGLEG_MIN_SCORE=1 NTHU_DOGLEG_STEP=6 NTHU_CUDA_DOGLEG_PRESELECT=1 NTHU_CUDA_DOGLEG_LEGAL_FILTER=1 NTHU_CUDA_DOGLEG_TRUST_LEGAL_FILTER=1
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
    --job-name=nthu-cuda-trust \
    --output="$ROOT/logs/%x_%j.log" \
    --error="$ROOT/logs/%x_%j.err" \
    --export=ALL,PROJECT_ROOT="$ROOT",CONTAINER_RUNTIME=apptainer,IMAGE=router.sif,EVALUATOR=lab2,OMP_NUM_THREADS=1,NTHU_OPENMP=OFF,NTHU_CUDA=ON,SKIP_INITIAL_BUILD=0,BENCH_PATTERN=adaptec3*.gr,RESULT_SUFFIX="$RESULT_TAG",OUT="$OUT",VARIANTS_FILE="$variants_file" \
    scripts/slurm_nthu_variant_sweep_job.sh
)

echo "$job" > "results/job_hooks/submitted_${RESULT_TAG}.jobid"
nohup env WATCH_INTERVAL_SECONDS=20 WATCH_COMMAND="python3 scripts/compare_variant_summary.py $OUT --baseline-router nthu_a3_cpu_score1_step6 --out ${OUT%.csv}_compare.csv && bash scripts/refresh_indexes.sh" \
  bash scripts/watch_job_then_run.sh "$job" "${RESULT_TAG}-compare" >/dev/null 2>&1 &
echo "$job"
