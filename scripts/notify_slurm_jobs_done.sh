#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

JOB_IDS=${JOB_IDS:?set JOB_IDS to a comma-separated Slurm job-id list}
AGG_TAGS=${AGG_TAGS:-}
NTFY_TOPIC=${NTFY_TOPIC:-hpc-final-router-viecon-20260602}
NTFY_URL=${NTFY_URL:-https://ntfy.sh/${NTFY_TOPIC}}
INTERVAL_SECONDS=${INTERVAL_SECONDS:-120}
LOG=${LOG:-"$ROOT/logs/notify_jobs_done.log"}
EMPTY_POLLS_TO_FINISH=${EMPTY_POLLS_TO_FINISH:-3}

mkdir -p logs results/job_hooks

log() {
  echo "[$(date '+%F %T')] $*" | tee -a "$LOG"
}

active_jobs() {
  squeue -j "$JOB_IDS" -h -o '%i %T %R' 2>/dev/null || true
}

summarize() {
  if [[ -n "$AGG_TAGS" ]]; then
    IFS=',' read -r -a tags <<< "$AGG_TAGS"
    for tag in "${tags[@]}"; do
      [[ -n "$tag" ]] || continue
      TAG="$tag" python3 scripts/aggregate_bench16_strategy_matrix.py \
        >"/tmp/ntfy_aggregate_${tag}.log" 2>&1 || true
    done
  fi

  python3 scripts/final_strategy_comparison.py >/tmp/ntfy_final_strategy_comparison.log 2>&1 || true

  python3 - <<'PY'
import csv
from pathlib import Path

root = Path.cwd()
best = root / "results/final_best_legal_by_benchmark.csv"
unresolved = root / "results/final_unresolved_overflow.csv"

best_rows = []
if best.exists():
    with best.open(newline="", encoding="utf-8") as f:
        best_rows = list(csv.DictReader(f))

unresolved_rows = []
if unresolved.exists():
    with unresolved.open(newline="", encoding="utf-8") as f:
        unresolved_rows = list(csv.DictReader(f))

print(f"legal testcases: {len(best_rows)}/16")
print(f"unresolved testcases: {len(unresolved_rows)}/16")

if unresolved_rows:
    print("still unresolved:")
    for row in unresolved_rows:
        bench = row.get("benchmark", "").split(".")[0]
        strategy = row.get("best_illegal_strategy", "")
        overflow = row.get("best_illegal_total_overflow", "")
        print(f"- {bench}: {strategy} overflow={overflow}")
else:
    print("all 16 have at least one legal NTHU strategy row")

if best_rows:
    print("best legal rows:")
    for row in best_rows:
        bench = row.get("benchmark", "").split(".")[0]
        strategy = row.get("best_strategy", "")
        sec = row.get("seconds", "")
        speedup = row.get("speedup_vs_nthu_original", "")
        suffix = f", speedup={speedup}x" if speedup else ""
        print(f"- {bench}: {strategy} {sec}s{suffix}")
PY
}

send_ntfy() {
  local title=$1
  local body=$2
  curl -fsS \
    -H "Title: ${title}" \
    -H "Tags: checkered_flag" \
    -H "Priority: default" \
    -d "$body" \
    "$NTFY_URL" >/dev/null
}

log "watching job_ids=$JOB_IDS tags=${AGG_TAGS:-none} ntfy_topic=$NTFY_TOPIC"

empty_polls=0
while true; do
  active=$(active_jobs)
  if [[ -z "$active" ]]; then
    empty_polls=$((empty_polls + 1))
    log "no active jobs visible (${empty_polls}/${EMPTY_POLLS_TO_FINISH})"
    if (( empty_polls >= EMPTY_POLLS_TO_FINISH )); then
      break
    fi
    sleep "$INTERVAL_SECONDS"
    continue
  fi
  empty_polls=0
  log "active jobs:"
  log "$active"
  sleep "$INTERVAL_SECONDS"
done

log "all watched jobs inactive; summarizing"
summary=$(summarize)
log "$summary"

send_ntfy "HPC router watched jobs finished" "$summary"
log "ntfy sent to $NTFY_URL"
