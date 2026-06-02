#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

if [[ $# -lt 3 ]]; then
  echo "usage: $0 INPUT_TAG STRATEGY BENCHMARK.gr [REPAIR_KIND]" >&2
  exit 2
fi

INPUT_TAG=$1
STRATEGY=$2
BENCH=$3
REPAIR_KIND=${4:-astar_segment}
BENCH_STEM=${BENCH%.gr}
SAFE_BENCH=${BENCH_STEM//[^A-Za-z0-9_]/_}

DESIGN="$ROOT/benchmarks/ispd08/$BENCH"
INPUT_DIR="$ROOT/results/${INPUT_TAG}/${STRATEGY}/${SAFE_BENCH}"
INPUT_ROUTE="$INPUT_DIR/${BENCH_STEM}.nthu.out"
OUT_TAG=${OUT_TAG:-"${INPUT_TAG}_output_repair"}
OUT_STRATEGY="${STRATEGY}_${REPAIR_KIND}"
OUT_DIR="$ROOT/results/${OUT_TAG}/${OUT_STRATEGY}/${SAFE_BENCH}"
OUT_ROUTE="$OUT_DIR/${BENCH_STEM}.nthu.out"
WORK_PREFIX="$OUT_DIR/${BENCH_STEM}.${REPAIR_KIND}"
SUMMARY="$OUT_DIR/summary.csv"
METRICS="$OUT_DIR/${BENCH_STEM}.nthu.metrics.json"
LOG="$OUT_DIR/${BENCH_STEM}.repair.log"

PASSES=${PASSES:-16}
MAX_NETS=${MAX_NETS:-32}
RADIUS=${RADIUS:-16}
MAX_OFFSET=${MAX_OFFSET:-2}

mkdir -p "$OUT_DIR"
echo "router,benchmark,status,seconds,evaluator,total_wirelength,total_overflow,max_overflow,overflowed_nets,overflowed_edges,output" > "$SUMMARY"

if [[ ! -f "$DESIGN" ]]; then
  echo "missing design: $DESIGN" >&2
  exit 1
fi
if [[ ! -f "$INPUT_ROUTE" ]]; then
  echo "missing input route: $INPUT_ROUTE" >&2
  exit 1
fi

start=$(python3 - <<'PY'
import time
print(time.time())
PY
)
status=ok
case "$REPAIR_KIND" in
  astar_segment)
    python3 scripts/targeted_astar_segment_repair.py \
      --design "$DESIGN" \
      --route "$INPUT_ROUTE" \
      --out "$OUT_ROUTE" \
      --work-prefix "$WORK_PREFIX" \
      --max-passes "$PASSES" \
      --max-nets-per-edge "$MAX_NETS" \
      --radius "$RADIUS" \
      --allow-equal-displacement \
      > "$LOG" 2>&1 || status=fail
    ;;
  edge_split_fast)
    python3 scripts/targeted_edge_split_fast_repair.py \
      --design "$DESIGN" \
      --route "$INPUT_ROUTE" \
      --out "$OUT_ROUTE" \
      --work-prefix "$WORK_PREFIX" \
      --max-passes "$PASSES" \
      --max-nets-per-edge "$MAX_NETS" \
      > "$LOG" 2>&1 || status=fail
    ;;
  local_detour_fast)
    python3 scripts/targeted_local_detour_fast_repair.py \
      --design "$DESIGN" \
      --route "$INPUT_ROUTE" \
      --out "$OUT_ROUTE" \
      --work-prefix "$WORK_PREFIX" \
      --max-passes "$PASSES" \
      --max-nets-per-edge "$MAX_NETS" \
      --max-offset "$MAX_OFFSET" \
      > "$LOG" 2>&1 || status=fail
    ;;
  *)
    echo "unknown REPAIR_KIND=$REPAIR_KIND" >&2
    exit 2
    ;;
esac
end=$(python3 - <<'PY'
import time
print(time.time())
PY
)
seconds=$(python3 - "$start" "$end" <<'PY'
import sys
print(f"{float(sys.argv[2]) - float(sys.argv[1]):.6f}")
PY
)

evaluator=NA
wl=NA
tof=NA
mof=NA
nets=NA
edges=NA
if [[ "$status" == ok ]]; then
  if python3 scripts/evaluate_route.py "$DESIGN" "$OUT_ROUTE" \
      --evaluator lab2 \
      --verifier "$ROOT/external/lab2-checker/verifier.py" \
      --nthu-dir "$ROOT/external/nthu-route" \
      > "$METRICS" 2>> "$LOG"; then
    read -r evaluator wl tof mof nets edges < <(
      python3 - "$METRICS" <<'PY'
import json
import sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
print(
    data.get("evaluator", "NA"),
    data.get("total_wirelength", "NA"),
    data.get("total_overflow", "NA"),
    data.get("max_overflow", "NA"),
    data.get("overflowed_nets", "NA"),
    data.get("overflowed_edges", "NA"),
)
PY
    )
  else
    status=eval_fail
  fi
fi

echo "${OUT_STRATEGY},${BENCH_STEM},${status},${seconds},${evaluator},${wl},${tof},${mof},${nets},${edges},${OUT_ROUTE}" >> "$SUMMARY"
echo "wrote $SUMMARY"
