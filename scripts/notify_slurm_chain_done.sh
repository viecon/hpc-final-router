#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

LAST_JOB=${LAST_JOB:?set LAST_JOB to the final Slurm job id}
TAG=${TAG:-bench16_strategy_matrix_r3_legal_repair}
NTFY_TOPIC=${NTFY_TOPIC:-hpc-final-router-viecon-20260602}
NTFY_URL=${NTFY_URL:-https://ntfy.sh/${NTFY_TOPIC}}
INTERVAL_SECONDS=${INTERVAL_SECONDS:-120}
LOG=${LOG:-"$ROOT/logs/notify_${TAG}_${LAST_JOB}.log"}

mkdir -p logs results/job_hooks

log() {
  echo "[$(date '+%F %T')] $*" | tee -a "$LOG"
}

job_active() {
  squeue -j "$LAST_JOB" -h 2>/dev/null | grep -q .
}

job_state() {
  sacct -j "$LAST_JOB" --format=State -n -P 2>/dev/null \
    | awk -F'|' 'NF && $1 !~ /\.(batch|extern)$/ {print $1; exit}'
}

summarize() {
  TAG="$TAG" python3 scripts/aggregate_bench16_strategy_matrix.py >/tmp/ntfy_aggregate_${TAG}.log 2>&1 || true

  python3 - <<'PY'
import csv
from pathlib import Path

root = Path.cwd()
benches = [line.strip()[:-3] for line in (root / "results/job_hooks/ispd08_all16.list").read_text().splitlines() if line.strip()]
sources = [
    root / "results/bench16_strategy_matrix_r2_summary.csv",
    root / "results/bench16_strategy_matrix_r3_legal_repair_summary.csv",
]

rows = []
for path in sources:
    if not path.exists():
        continue
    with path.open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            row["_source"] = path.name
            rows.append(row)

def to_int(value):
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return None

def to_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None

legal_by_bench = {}
repair_rows = []
for row in rows:
    bench = row.get("benchmark", "")
    ov = to_int(row.get("total_overflow"))
    sec = to_float(row.get("seconds"))
    legal = row.get("status") == "ok" and ov == 0
    if row.get("_source") == "bench16_strategy_matrix_r3_legal_repair_summary.csv":
        repair_rows.append((bench, row.get("strategy") or row.get("router"), sec, ov, legal))
    if legal and bench in benches:
        cur = legal_by_bench.get(bench)
        if cur is None or (sec is not None and sec < cur[1]):
            legal_by_bench[bench] = (row.get("strategy") or row.get("router"), sec)

missing = [b for b in benches if b not in legal_by_bench]
repair_done = len(repair_rows)
repair_legal = sum(1 for *_, legal in repair_rows if legal)

print(f"legal testcases: {len(legal_by_bench)}/16")
print(f"r3 repair rows: {repair_done}, legal: {repair_legal}")
if missing:
    print("still no legal NTHU row: " + ", ".join(b.split(".")[0] for b in missing))
else:
    print("all 16 have at least one legal NTHU row")

if repair_rows:
    print("repair results:")
    for bench, strategy, sec, ov, legal in repair_rows:
        status = "legal" if legal else f"overflow={ov}"
        sec_s = f"{sec:.3f}s" if sec is not None else "NA"
        print(f"- {bench}: {strategy} {sec_s} {status}")
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

log "watching last_job=$LAST_JOB tag=$TAG ntfy_topic=$NTFY_TOPIC"

while job_active; do
  log "job $LAST_JOB still active"
  sleep "$INTERVAL_SECONDS"
done

for _ in {1..20}; do
  state=$(job_state || true)
  if [[ -n "${state:-}" && "$state" != RUNNING* && "$state" != PENDING* && "$state" != CONFIGURING* && "$state" != COMPLETING* ]]; then
    break
  fi
  sleep 15
done

state=${state:-unknown}
log "job $LAST_JOB final state=$state; summarizing"
summary=$(summarize)
log "$summary"

send_ntfy "HPC router jobs finished (${state})" "$summary"
log "ntfy sent to $NTFY_URL"
