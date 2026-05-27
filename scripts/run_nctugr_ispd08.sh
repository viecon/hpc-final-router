#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
NCTU_DIR=${NCTU_DIR:-"$ROOT/external/nctu-gr"}
NTHU_DIR=${NTHU_DIR:-"$ROOT/external/nthu-route"}
BENCH_DIR=${BENCH_DIR:-"$ROOT/benchmarks/ispd08"}
RESULT_DIR=${RESULT_DIR:-"$ROOT/results/nctu"}
PARAM_INPUT=${PARAM:-}
BENCH_PATTERN=${BENCH_PATTERN:-*.gr}
BENCH_LIST=${BENCH_LIST:-}
EVALUATOR=${EVALUATOR:-auto}
VERIFIER=${VERIFIER:-"$ROOT/external/lab2-checker/verifier.py"}
PYTHON=${PYTHON:-python3}
NCTU_DIR=$(cd "$NCTU_DIR" && pwd)
NTHU_DIR=$(cd "$NTHU_DIR" && pwd)
BENCH_DIR=$(cd "$BENCH_DIR" && pwd)
mkdir -p "$RESULT_DIR"
RESULT_DIR=$(cd "$RESULT_DIR" && pwd)
if [[ -n "$PARAM_INPUT" ]]; then
  PARAM=$PARAM_INPUT
else
  PARAM="$NCTU_DIR/Parameter_Files/RegularDefault.set"
fi

mkdir -p "$RESULT_DIR"

if [[ ! -x "$NCTU_DIR/NCTUgr" ]]; then
  echo "missing $NCTU_DIR/NCTUgr; run scripts/fetch_nctugr.sh first" >&2
  exit 1
fi

CSV="$RESULT_DIR/summary.csv"
echo "router,benchmark,status,seconds,evaluator,total_wirelength,total_overflow,max_overflow,overflowed_nets,overflowed_edges,output" > "$CSV"

shopt -s nullglob
if [[ -n "$BENCH_LIST" ]]; then
  benches=()
  while IFS= read -r bench_entry; do
    [[ -n "$bench_entry" ]] || continue
    if [[ "$bench_entry" = /* ]]; then
      benches+=( "$bench_entry" )
    else
      benches+=( "$BENCH_DIR/$bench_entry" )
    fi
  done < "$BENCH_LIST"
else
  benches=( "$BENCH_DIR"/$BENCH_PATTERN )
fi
if [[ "${INCLUDE_NTHU_SAMPLE:-0}" == 1 ]]; then
  benches+=( "$NTHU_DIR"/adaptec1.capo70.3d.35.50.90.gr )
fi

for bench in "${benches[@]}"; do
  [[ -f "$bench" ]] || continue
  name=$(basename "$bench" .gr)
  out="$RESULT_DIR/$name.nctu.out"
  log="$RESULT_DIR/$name.nctu.log"
  eval_log="$RESULT_DIR/$name.nctu.eval"
  metrics_json="$RESULT_DIR/$name.nctu.metrics.json"
  echo "NCTU-GR $name"
  start=$($PYTHON - <<'PY'
import time
print(time.time())
PY
)
  status=ok
  (cd "$NCTU_DIR" && ./NCTUgr REGULAR_ISPD "$bench" "$PARAM" "$out") > "$log" 2>&1 || status=fail
  end=$($PYTHON - <<'PY'
import time
print(time.time())
PY
)
  seconds=$($PYTHON - "$start" "$end" <<'PY'
import sys
print(f"{float(sys.argv[2]) - float(sys.argv[1]):.6f}")
PY
)
  total_wirelength=NA
  total_overflow=NA
  max_overflow=NA
  overflowed_nets=NA
  overflowed_edges=NA
  metric_evaluator=NA
  if [[ "$status" == ok ]]; then
    if $PYTHON "$ROOT/scripts/evaluate_route.py" "$bench" "$out" \
        --evaluator "$EVALUATOR" \
        --verifier "$VERIFIER" \
        --nthu-dir "$NTHU_DIR" \
        > "$metrics_json" 2> "$eval_log"; then
      read -r metric_evaluator total_wirelength total_overflow max_overflow overflowed_nets overflowed_edges < <(
        $PYTHON - "$metrics_json" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as f:
    data = json.load(f)
print(
    data.get("evaluator", "NA"),
    data.get("total_wirelength", "NA"),
    data.get("total_overflow", "NA"),
    data.get("max_overflow", "NA"),
    data.get("overflowed_nets") if data.get("overflowed_nets") is not None else "NA",
    data.get("overflowed_edges") if data.get("overflowed_edges") is not None else "NA",
)
PY
      )
    else
      status=eval_fail
    fi
  fi
  echo "nctu,$name,$status,$seconds,$metric_evaluator,${total_wirelength:-NA},${total_overflow:-NA},${max_overflow:-NA},${overflowed_nets:-NA},${overflowed_edges:-NA},$out" >> "$CSV"
done

echo "wrote $CSV"
