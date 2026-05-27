#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

mkdir -p logs

log=${LOG:-"$ROOT/logs/repair-experiment-queue.log"}
retry_interval=${RETRY_INTERVAL_SECONDS:-60}

echo "$(date -Is) repair experiment queue started" | tee -a "$log" >&2

attempt=1
while true; do
  echo "$(date -Is) submit attempt ${attempt}: A1 fast construct repair sweep" | tee -a "$log" >&2
  set +e
  out=$(bash scripts/submit_nthu_a1_fast_construct_repair_sweep.sh 2>&1)
  status=$?
  set -e
  if [[ "$status" == 0 ]]; then
    echo "$out" | tee -a "$log" >&2
    echo "$(date -Is) repair experiment queue submitted successfully" | tee -a "$log" >&2
    exit 0
  fi
  echo "$out" | tee -a "$log" >&2
  echo "$(date -Is) submit failed with ${status}; retry in ${retry_interval}s" | tee -a "$log" >&2
  sleep "$retry_interval"
  attempt=$((attempt + 1))
done
