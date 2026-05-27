#!/bin/bash
#SBATCH -J route-cpu
#SBATCH -p gp1d
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --gpus-per-node=1
#SBATCH --mem=32G
#SBATCH -t 00:30:00
#SBATCH -o logs/%x-%j.out
#SBATCH -e logs/%x-%j.err

set -euo pipefail

IMAGE=${IMAGE:-router.sif}
CONTAINER_RUNTIME=${CONTAINER_RUNTIME:-singularity}
GRID=${GRID:-256}
NETS=${NETS:-8000}
CAPACITY=${CAPACITY:-4}
OBSTACLES=${OBSTACLES:-0.01}
ITERATIONS=${ITERATIONS:-8}
REPEATS=${REPEATS:-5}
BATCH_FACTOR=${BATCH_FACTOR:-1}
THREADS_LIST=${THREADS_LIST:-"1 2 4"}

mkdir -p logs results build-cpu

"$CONTAINER_RUNTIME" exec "$IMAGE" cmake -S . -B build-cpu -G Ninja -DROUTER_ENABLE_CUDA=OFF -DCMAKE_BUILD_TYPE=Release
"$CONTAINER_RUNTIME" exec "$IMAGE" cmake --build build-cpu

OUT="results/cpu-${SLURM_JOB_ID:-manual}.csv"
: > "$OUT"
first=1

for threads in $THREADS_LIST; do
  if [ "$threads" -eq 1 ]; then
    mode=seq
  else
    mode=cpu
  fi
  "$CONTAINER_RUNTIME" exec "$IMAGE" ./build-cpu/router_bench \
    --mode "$mode" \
    --grid "$GRID" \
    --nets "$NETS" \
    --capacity "$CAPACITY" \
    --obstacles "$OBSTACLES" \
    --iterations "$ITERATIONS" \
    --threads "$threads" \
    --batch-factor "$BATCH_FACTOR" \
    --repeats "$REPEATS" \
    --seed 100 > results/.tmp_cpu.csv
  if [ "$first" -eq 1 ]; then
    cat results/.tmp_cpu.csv >> "$OUT"
    first=0
  else
    tail -n +2 results/.tmp_cpu.csv >> "$OUT"
  fi
done
rm -f results/.tmp_cpu.csv

echo "wrote $OUT"
