#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

mkdir -p logs
log=${LOG:-"$ROOT/logs/construct-only-remaining-queue.log"}
retry_interval=${RETRY_INTERVAL_SECONDS:-60}

submit_retry() {
  local label=$1
  shift
  local attempt=1
  local out status
  while true; do
    echo "$(date -Is) submit attempt ${attempt}: ${label}" | tee -a "$log" >&2
    set +e
    out=$("$@" 2>&1)
    status=$?
    set -e
    if [[ "$status" == 0 ]]; then
      echo "$out" | tee -a "$log" >&2
      return 0
    fi
    echo "$out" | tee -a "$log" >&2
    sleep "$retry_interval"
    attempt=$((attempt + 1))
  done
}

submit_retry "A2 construct-only frontier" bash scripts/submit_nthu_construct_only_frontier_a2.sh
submit_retry "A3 construct-only frontier" bash scripts/submit_nthu_construct_only_frontier_a3.sh
