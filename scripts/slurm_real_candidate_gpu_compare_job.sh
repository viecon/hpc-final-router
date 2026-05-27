#!/usr/bin/env bash
#SBATCH -J gpu-real-candidates
#SBATCH --account=ACD115058
#SBATCH --partition=nycugpu_queue
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --gpus-per-node=1
#SBATCH --mem=32G
#SBATCH -t 00:20:00
#SBATCH -o logs/%x_%j.log
#SBATCH -e logs/%x_%j.err

set -euo pipefail

if [[ -n "${PROJECT_ROOT:-}" ]]; then
  ROOT=$(cd "$PROJECT_ROOT" && pwd)
elif [[ -n "${SLURM_SUBMIT_DIR:-}" && -f "$SLURM_SUBMIT_DIR/CMakeLists.txt" ]]; then
  ROOT=$(cd "$SLURM_SUBMIT_DIR" && pwd)
else
  ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fi
cd "$ROOT"

CONTAINER_RUNTIME=${CONTAINER_RUNTIME:-apptainer}
IMAGE=${IMAGE:-router.sif}
CANDIDATE_CSV=${CANDIDATE_CSV:?set CANDIDATE_CSV to a NTHU reroute candidate CSV}
BENCH_LABEL=${BENCH_LABEL:-$(basename "$CANDIDATE_CSV" .csv)}
GR_FILE=${GR_FILE:-}
CAPACITY=${CAPACITY:-2}
REPEATS=${REPEATS:-3}
THREADS=${THREADS:-${SLURM_CPUS_PER_TASK:-4}}
SUMMARY_OUT=${SUMMARY_OUT:-results/gpu_real_candidate_summary.csv}
CPU_MODE=${CPU_MODE:-candidate_cpu}
CUDA_MODE=${CUDA_MODE:-cuda}
RESULT_TAG=${RESULT_TAG:-}
SUMMARY_CPU_PREFIX=${SUMMARY_CPU_PREFIX:-real_candidate_cpu_}
SUMMARY_CUDA_PREFIX=${SUMMARY_CUDA_PREFIX:-real_candidate_cuda_}
GR_ARGS=()
if [[ -n "$GR_FILE" ]]; then
  GR_ARGS=(--gr "$GR_FILE")
fi

mkdir -p logs results build-gpu

"$CONTAINER_RUNTIME" exec --nv "$IMAGE" nvidia-smi
"$CONTAINER_RUNTIME" exec --nv "$IMAGE" cmake -S . -B build-gpu -G Ninja \
  -DROUTER_ENABLE_CUDA=ON \
  -DCMAKE_BUILD_TYPE=Release
"$CONTAINER_RUNTIME" exec --nv "$IMAGE" cmake --build build-gpu

if [[ -n "$RESULT_TAG" ]]; then
  CPU_OUT="results/real_candidate_cpu_${RESULT_TAG}_${BENCH_LABEL}.csv"
  CUDA_OUT="results/real_candidate_cuda_${RESULT_TAG}_${BENCH_LABEL}.csv"
else
  CPU_OUT="results/real_candidate_cpu_${BENCH_LABEL}.csv"
  CUDA_OUT="results/real_candidate_cuda_${BENCH_LABEL}.csv"
fi

"$CONTAINER_RUNTIME" exec --nv "$IMAGE" ./build-gpu/router_bench \
  --mode "$CPU_MODE" \
  --candidate-csv "$CANDIDATE_CSV" \
  "${GR_ARGS[@]}" \
  --capacity "$CAPACITY" \
  --threads "$THREADS" \
  --repeats "$REPEATS" > "$CPU_OUT"

"$CONTAINER_RUNTIME" exec --nv "$IMAGE" ./build-gpu/router_bench \
  --mode "$CUDA_MODE" \
  --candidate-csv "$CANDIDATE_CSV" \
  "${GR_ARGS[@]}" \
  --capacity "$CAPACITY" \
  --threads "$THREADS" \
  --repeats "$REPEATS" > "$CUDA_OUT"

python3 scripts/summarize_gpu_real_candidates.py \
  --out "$SUMMARY_OUT" \
  --cpu-prefix "$SUMMARY_CPU_PREFIX" \
  --cuda-prefix "$SUMMARY_CUDA_PREFIX"
bash scripts/refresh_indexes.sh || true

echo "wrote $CPU_OUT"
echo "wrote $CUDA_OUT"
echo "updated $SUMMARY_OUT"
