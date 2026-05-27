#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

summary="$ROOT/results/nthu_fast_greedy_layer_continuity_a3_summary.csv"
jobid_file="$ROOT/results/job_hooks/submitted_fast_greedy_layer_continuity_a3.jobid"

submit_with_retry() {
  local label=$1
  shift
  local attempt
  for attempt in $(seq 1 240); do
    echo "submit attempt ${attempt}: ${label}"
    if "$@"; then
      return 0
    fi
    sleep 60
  done
  echo "failed to submit ${label} after retry window" >&2
  return 1
}

if [[ -f "$summary" ]] && awk -F, 'NR > 1 && $3 == "ok" && $7 == 0 { found = 1 } END { exit(found ? 0 : 1) }' "$summary"; then
  echo "A3 continuity legal; submitting CUDA continuity follow-up"
  submit_with_retry "CUDA continuity A3" bash scripts/submit_nthu_cuda_fast_greedy_layer_continuity_a3.sh
elif [[ -f "$summary" ]] && awk -F, 'NR > 1 { found = 1 } END { exit(found ? 0 : 1) }' "$summary"; then
  echo "A3 continuity completed but was not legal; submitting A1 high-threshold fast-layer follow-up"
  submit_with_retry "A1 high-threshold fast layer" bash scripts/submit_nthu_fast_greedy_layer_a1_high_threshold.sh
else
  if [[ -f "$jobid_file" ]]; then
    job_id=$(cat "$jobid_file")
    if squeue -h -j "$job_id" >/dev/null 2>&1 && [[ -n "$(squeue -h -j "$job_id" 2>/dev/null)" ]]; then
      echo "A3 continuity job ${job_id} is still queued/running; no follow-up submission"
      exit 0
    fi
  fi
  echo "A3 continuity produced no summary, likely cancelled by maintenance; resubmitting A3 continuity"
  submit_with_retry "A3 continuity" bash scripts/submit_nthu_fast_greedy_layer_continuity_a3.sh
fi
