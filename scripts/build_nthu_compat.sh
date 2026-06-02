#!/usr/bin/env bash
set -euxo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CPU_BUILD=${1:?cpu build dir}
CUDA_BUILD=${2:?cuda build dir}

cd "$ROOT"

if [[ -f /etc/profile.d/modules.sh ]]; then
  # Taiwania compute nodes provide cmake/cuda through Lmod modules.
  # shellcheck disable=SC1091
  source /etc/profile.d/modules.sh
fi

module load cmake/3.23.2
module load cuda/11.7

which cmake
cmake --version
which nvcc || true
nvcc --version || true

cmake -S external/nthu-route -B "$CPU_BUILD" -G "Unix Makefiles" \
  -DCMAKE_BUILD_TYPE=Release \
  -DNTHU_ROUTE_ENABLE_OPENMP=OFF \
  -DNTHU_ROUTE_ENABLE_CUDA=OFF
cmake --build "$CPU_BUILD" --target clean || true
cmake --build "$CPU_BUILD" -j "${SLURM_CPUS_PER_TASK:-4}"

cmake -S external/nthu-route -B "$CUDA_BUILD" -G "Unix Makefiles" \
  -DCMAKE_BUILD_TYPE=Release \
  -DNTHU_ROUTE_ENABLE_OPENMP=OFF \
  -DNTHU_ROUTE_ENABLE_CUDA=ON
cmake --build "$CUDA_BUILD" --target clean || true
cmake --build "$CUDA_BUILD" -j "${SLURM_CPUS_PER_TASK:-4}"
