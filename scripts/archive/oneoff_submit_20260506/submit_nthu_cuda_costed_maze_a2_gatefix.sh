#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

mkdir -p logs results/job_hooks

RESULT_TAG=${RESULT_TAG:-cuda_costed_maze_a2_gatefix}
OUT=${OUT:-"$ROOT/results/nthu_${RESULT_TAG}_summary.csv"}
VARIANTS_FILE=${VARIANTS_FILE:-"$ROOT/results/job_hooks/${RESULT_TAG}.variants"}
BUILD_DIR=${BUILD_DIR:-"$ROOT/external/nthu-route/build-release-openmp-OFF-cuda-ON-gatefix"}

args="--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=240"
cuda_env="NTHU_CUDA_COSTED_MAZE_FASTPATH=1 NTHU_CUDA_MAZE_MAX_AREA=256"

cat > "$VARIANTS_FILE" <<EOF
nthu_a2_cuda_costed_maze_score1_gatefix|$args|$cuda_env NTHU_CUDA_MAZE_MIN_OVERFLOW_SCORE=1
nthu_a2_cuda_costed_maze_score5_gatefix|$args|$cuda_env NTHU_CUDA_MAZE_MIN_OVERFLOW_SCORE=5
nthu_a2_cuda_costed_maze_score10_gatefix|$args|$cuda_env NTHU_CUDA_MAZE_MIN_OVERFLOW_SCORE=10
nthu_a2_cuda_costed_maze_score25_gatefix|$args|$cuda_env NTHU_CUDA_MAZE_MIN_OVERFLOW_SCORE=25
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
    --job-name=nthu-cuda-a2gate \
    --output="$ROOT/logs/%x_%j.log" \
    --error="$ROOT/logs/%x_%j.err" \
    --export=ALL,PROJECT_ROOT="$ROOT",CONTAINER_RUNTIME=apptainer,IMAGE=router.sif,EVALUATOR=lab2,OMP_NUM_THREADS=1,NTHU_OPENMP=OFF,NTHU_CUDA=ON,JOBS=4,BUILD_DIR="$BUILD_DIR",SKIP_INITIAL_BUILD=0,BENCH_PATTERN=adaptec2*.gr,RESULT_SUFFIX="$RESULT_TAG",OUT="$OUT",VARIANTS_FILE="$VARIANTS_FILE" \
    scripts/slurm_nthu_variant_sweep_job.sh
)

echo "$job" > "results/job_hooks/submitted_${RESULT_TAG}.jobid"
echo "$job"
