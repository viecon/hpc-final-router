#!/bin/bash
#SBATCH -J route-gpu
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

IMAGE=${IMAGE:-router.sif}
CONTAINER_RUNTIME=${CONTAINER_RUNTIME:-apptainer}
GRID=${GRID:-256}
NETS=${NETS:-8000}
CAPACITY=${CAPACITY:-4}
OBSTACLES=${OBSTACLES:-0.01}
ITERATIONS=${ITERATIONS:-8}
REPEATS=${REPEATS:-5}

mkdir -p logs results build-gpu

"$CONTAINER_RUNTIME" exec --nv "$IMAGE" nvidia-smi
"$CONTAINER_RUNTIME" exec --nv "$IMAGE" cmake -S . -B build-gpu -G Ninja -DROUTER_ENABLE_CUDA=ON -DCMAKE_BUILD_TYPE=Release
"$CONTAINER_RUNTIME" exec --nv "$IMAGE" cmake --build build-gpu

OUT="results/gpu-${SLURM_JOB_ID:-manual}.csv"
"$CONTAINER_RUNTIME" exec --nv "$IMAGE" ./build-gpu/router_bench \
  --mode cuda \
  --grid "$GRID" \
  --nets "$NETS" \
  --capacity "$CAPACITY" \
  --obstacles "$OBSTACLES" \
  --iterations "$ITERATIONS" \
  --threads "${SLURM_CPUS_PER_TASK:-4}" \
  --repeats "$REPEATS" \
  --seed 100 > "$OUT"

echo "wrote $OUT"
