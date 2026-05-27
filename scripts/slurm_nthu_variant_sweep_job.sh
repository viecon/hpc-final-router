#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${PROJECT_ROOT:-}" ]]; then
  ROOT=$(cd "$PROJECT_ROOT" && pwd)
elif [[ -n "${SLURM_SUBMIT_DIR:-}" && -f "$SLURM_SUBMIT_DIR/scripts/run_nthu_variant_sweep.sh" ]]; then
  ROOT=$(cd "$SLURM_SUBMIT_DIR" && pwd)
else
  ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
fi
cd "$ROOT"

CONTAINER_RUNTIME=${CONTAINER_RUNTIME:-apptainer}
IMAGE=${IMAGE:-router.sif}
container_exec=(exec)
if [[ "${NTHU_CUDA:-OFF}" == "ON" || "${CONTAINER_NV:-0}" == 1 ]]; then
  container_exec+=(--nv)
fi

mkdir -p logs results

status=0
"$CONTAINER_RUNTIME" "${container_exec[@]}" "$IMAGE" bash scripts/fetch_ispd08.sh || status=$?
if [[ "$status" == 0 ]]; then
  if [[ "${NTHU_CUDA:-OFF}" == "ON" || "${CONTAINER_NV:-0}" == 1 ]]; then
    "$CONTAINER_RUNTIME" "${container_exec[@]}" "$IMAGE" nvidia-smi || true
  fi
  "$CONTAINER_RUNTIME" "${container_exec[@]}" "$IMAGE" bash scripts/run_nthu_variant_sweep.sh || status=$?
fi

bash scripts/refresh_indexes.sh || true
exit "$status"
