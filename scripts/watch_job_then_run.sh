#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 JOB_ID [LABEL]" >&2
  echo "optional env: WATCH_COMMAND='command to run after the job finishes'" >&2
  echo "optional env: WATCH_INTERVAL_SECONDS=30" >&2
  exit 2
fi

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

JOB_ID=$1
LABEL=${2:-job_${JOB_ID}}
SAFE_LABEL=${LABEL//[^[:alnum:]_.-]/_}
WATCH_COMMAND=${WATCH_COMMAND:-}
WATCH_INTERVAL_SECONDS=${WATCH_INTERVAL_SECONDS:-30}

mkdir -p results/job_hooks logs

done_file="results/job_hooks/${JOB_ID}_${SAFE_LABEL}.done"
status_file="results/job_hooks/${JOB_ID}_${SAFE_LABEL}.sacct"
command_log="results/job_hooks/${JOB_ID}_${SAFE_LABEL}.command.log"
watch_log="logs/watch-${SAFE_LABEL}.log"

{
  echo "$(date -Is) watching $JOB_ID ($SAFE_LABEL)"
  while true; do
    state=$(
      (sacct -n -j "$JOB_ID" --format=State -P 2>/dev/null |
        awk -F'|' 'NF && $1 !~ /\.(batch|extern)$/ {print $1; exit}') || true
    )
    if [[ "$state" != RUNNING && "$state" != PENDING && "$state" != CONFIGURING && "$state" != COMPLETING ]]; then
      if [[ -n "$state" ]]; then
        break
      fi
      if ! squeue -h -j "$JOB_ID" >/dev/null 2>&1 || [[ -z "$(squeue -h -j "$JOB_ID")" ]]; then
        break
      fi
    fi
    sleep "$WATCH_INTERVAL_SECONDS"
  done

  date -Is > "$done_file"
  sacct -j "$JOB_ID" --format=JobID,JobName%30,State,Elapsed,ExitCode -P > "$status_file" 2>/dev/null || true

  if [[ -n "$WATCH_COMMAND" ]]; then
    bash -lc "$WATCH_COMMAND" > "$command_log" 2>&1 || echo "WATCH_COMMAND failed with $?" >> "$command_log"
  fi

  bash scripts/refresh_indexes.sh || true
  echo "$(date -Is) watcher completed for $JOB_ID ($SAFE_LABEL)"
} >> "$watch_log" 2>&1
