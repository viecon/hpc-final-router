#!/bin/bash
#SBATCH -J route-sweep
#SBATCH -p gp1d
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --gpus-per-node=1
#SBATCH --mem=48G
#SBATCH -t 01:00:00
#SBATCH -o logs/%x-%j.out
#SBATCH -e logs/%x-%j.err

set -euo pipefail

IMAGE=${IMAGE:-router.sif}
CONTAINER_RUNTIME=${CONTAINER_RUNTIME:-singularity}
mkdir -p logs results build-sweep

"$CONTAINER_RUNTIME" exec --nv "$IMAGE" cmake -S . -B build-sweep -G Ninja -DROUTER_ENABLE_CUDA=ON -DCMAKE_BUILD_TYPE=Release
"$CONTAINER_RUNTIME" exec --nv "$IMAGE" cmake --build build-sweep

OUT="results/sweep-${SLURM_JOB_ID:-manual}.csv"
: > "$OUT"
first=1

for grid in 128 256 512; do
  for nets in 2000 8000 20000; do
    for mode_threads in "seq 1" "cpu 2" "cpu 4" "cuda 4"; do
      set -- $mode_threads
      mode=$1
      threads=$2
      "$CONTAINER_RUNTIME" exec --nv "$IMAGE" ./build-sweep/router_bench \
        --mode "$mode" \
        --grid "$grid" \
        --nets "$nets" \
        --capacity 4 \
        --obstacles 0.01 \
        --iterations 8 \
        --threads "$threads" \
        --batch-factor 1 \
        --repeats 3 \
        --seed 100 > results/.tmp_sweep.csv
      if [ "$first" -eq 1 ]; then
        cat results/.tmp_sweep.csv >> "$OUT"
        first=0
      else
        tail -n +2 results/.tmp_sweep.csv >> "$OUT"
      fi
    done
  done
done
rm -f results/.tmp_sweep.csv

echo "wrote $OUT"
