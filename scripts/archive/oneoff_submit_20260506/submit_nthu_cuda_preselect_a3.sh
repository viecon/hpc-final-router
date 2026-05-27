#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

mkdir -p logs results/job_hooks

DOGLEG_SCORE=${DOGLEG_SCORE:-10}
RESULT_TAG=${RESULT_TAG:-cuda_preselect_a3_score${DOGLEG_SCORE}}
OUT=${OUT:-"$ROOT/results/nthu_${RESULT_TAG}_summary.csv"}
CUDA_LEGAL_FILTER=${CUDA_LEGAL_FILTER:-0}
cuda_env="NTHU_DOGLEG_FASTPATH=1 NTHU_DOGLEG_MAX_EXTRA=0 NTHU_DOGLEG_MIN_SCORE=${DOGLEG_SCORE} NTHU_CUDA_DOGLEG_PRESELECT=1"
if [[ "$CUDA_LEGAL_FILTER" == 1 ]]; then
  cuda_env="$cuda_env NTHU_CUDA_DOGLEG_LEGAL_FILTER=1"
fi

variants_file="$ROOT/results/job_hooks/${RESULT_TAG}.variants"
{
  printf 'nthu_a3_dog_cpu_score%s|--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=4000|NTHU_DOGLEG_FASTPATH=1 NTHU_DOGLEG_MAX_EXTRA=0 NTHU_DOGLEG_MIN_SCORE=%s\n' "$DOGLEG_SCORE" "$DOGLEG_SCORE"
  printf 'nthu_a3_dog_cuda_score%s|--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=4000|%s\n' "$DOGLEG_SCORE" "$cuda_env"
} > "$variants_file"

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
    --job-name="nthu-cuda-a3s${DOGLEG_SCORE}" \
    --output="$ROOT/logs/%x_%j.log" \
    --error="$ROOT/logs/%x_%j.err" \
    --export=ALL,PROJECT_ROOT="$ROOT",CONTAINER_RUNTIME=apptainer,IMAGE=router.sif,EVALUATOR=lab2,OMP_NUM_THREADS=1,NTHU_OPENMP=OFF,NTHU_CUDA=ON,SKIP_INITIAL_BUILD=1,BENCH_PATTERN=adaptec3*.gr,RESULT_SUFFIX="$RESULT_TAG",OUT="$OUT",VARIANTS_FILE="$variants_file" \
    scripts/slurm_nthu_variant_sweep_job.sh
)

echo "$job" > "results/job_hooks/submitted_${RESULT_TAG}.jobid"
nohup env WATCH_INTERVAL_SECONDS=20 WATCH_COMMAND="python3 scripts/compare_variant_summary.py $OUT --baseline-router nthu_a3_dog_cpu_score${DOGLEG_SCORE} --out ${OUT%.csv}_compare.csv" \
  bash scripts/watch_job_then_run.sh "$job" "${RESULT_TAG}-compare" >/dev/null 2>&1 &
echo "$job"
