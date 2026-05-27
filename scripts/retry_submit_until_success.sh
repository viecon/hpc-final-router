#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 TAG SUBMIT_SCRIPT [SUBMIT_ARGS...]" >&2
  exit 2
fi

TAG=$1
shift

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

mkdir -p logs results/job_hooks

INTERVAL_SECONDS=${INTERVAL_SECONDS:-60}
SUBMIT_TIMEOUT_SECONDS=${SUBMIT_TIMEOUT_SECONDS:-60}
LOG=${LOG:-"$ROOT/logs/retry_${TAG}.log"}
JOBID_FILE=${JOBID_FILE:-"$ROOT/results/job_hooks/submitted_${TAG}.jobid"}

echo "[$(date '+%F %T')] retry submit started: tag=$TAG command=$*" >> "$LOG"

while true; do
  if [[ -s "$JOBID_FILE" ]]; then
    job=$(tail -n 1 "$JOBID_FILE" | tr -cd '0-9')
    if [[ -n "$job" ]]; then
      echo "[$(date '+%F %T')] existing job id found: $job" >> "$LOG"
      echo "$job"
      exit 0
    fi
  fi

  tmp=$(mktemp)
  if timeout "${SUBMIT_TIMEOUT_SECONDS}s" "$@" >"$tmp" 2>&1; then
    cat "$tmp" >> "$LOG"
    job=$(tail -n 1 "$tmp" | tr -cd '0-9')
    rm -f "$tmp"
    if [[ -n "$job" ]]; then
      echo "$job" > "$JOBID_FILE"
      echo "[$(date '+%F %T')] submit succeeded: $job" >> "$LOG"
      echo "$job"
      exit 0
    fi
    echo "[$(date '+%F %T')] submit returned without job id" >> "$LOG"
  else
    status=$?
    cat "$tmp" >> "$LOG"
    rm -f "$tmp"
    echo "[$(date '+%F %T')] submit failed or timed out: status=$status" >> "$LOG"
  fi

  sleep "$INTERVAL_SECONDS"
done
