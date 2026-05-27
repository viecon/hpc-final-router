#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

mkdir -p logs results/job_hooks

log=${LOG:-"$ROOT/logs/aggressive-experiment-queue.log"}
retry_interval=${RETRY_INTERVAL_SECONDS:-60}
watch_interval=${WATCH_INTERVAL_SECONDS:-60}

submit_with_retry_capture_job() {
  local label=$1
  shift
  local attempt=1
  local out status job

  while true; do
    echo "$(date -Is) submit attempt ${attempt}: ${label}" | tee -a "$log" >&2
    set +e
    out=$("$@" 2>&1)
    status=$?
    set -e

    if [[ "$status" == 0 ]]; then
      job=$(printf '%s\n' "$out" | awk 'NF {last=$0} END {print last}')
      if [[ "$job" =~ ^[0-9]+$ ]]; then
        echo "$(date -Is) submitted ${label}: ${job}" | tee -a "$log" >&2
        printf '%s\n' "$job"
        return 0
      fi
      echo "$(date -Is) ${label} returned success but no numeric job id: ${out}" | tee -a "$log" >&2
    else
      echo "$out" | tee -a "$log" >&2
      echo "$(date -Is) ${label} submit failed with ${status}; retry in ${retry_interval}s" | tee -a "$log" >&2
    fi

    sleep "$retry_interval"
    attempt=$((attempt + 1))
  done
}

wait_for_job_done() {
  local job=$1
  local label=$2
  local state

  echo "$(date -Is) waiting for ${label}: ${job}" | tee -a "$log" >&2
  while true; do
    state=$(
      sacct -n -j "$job" --format=State -P 2>/dev/null |
        awk -F'|' 'NF && $1 !~ /\.(batch|extern)$/ {print $1; exit}'
    )
    case "$state" in
      RUNNING|PENDING|CONFIGURING|COMPLETING|"")
        sleep "$watch_interval"
        ;;
      *)
        echo "$(date -Is) ${label} ${job} ended with state ${state}" | tee -a "$log" >&2
        sacct -j "$job" --format=JobID,JobName%30,State,Elapsed,ExitCode -P >> "$log" 2>/dev/null || true
        bash scripts/refresh_indexes.sh >> "$log" 2>&1 || true
        return 0
        ;;
    esac
  done
}

run_one() {
  local label=$1
  shift
  local job
  job=$(submit_with_retry_capture_job "$label" "$@")
  wait_for_job_done "$job" "$label"
}

echo "$(date -Is) aggressive experiment queue started" | tee -a "$log" >&2

run_one "A1 fast construct probe" bash scripts/submit_nthu_fast_construct_probe.sh
run_one "A3 fast construct probe" bash scripts/submit_nthu_fast_construct_probe_a3.sh
run_one "A2 micro threshold sweep" bash scripts/submit_nthu_a2_micro_threshold_sweep.sh

echo "$(date -Is) aggressive experiment queue completed" | tee -a "$log" >&2
