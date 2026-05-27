#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
NTHU_DIR=${NTHU_DIR:-"$ROOT/external/nthu-route"}
BENCH_DIR=${BENCH_DIR:-"$ROOT/benchmarks/ispd08"}
RESULT_DIR=${RESULT_DIR:-"$ROOT/results/nthu"}
JOBS=${JOBS:-$(nproc)}
BENCH_PATTERN=${BENCH_PATTERN:-*.gr}
BENCH_LIST=${BENCH_LIST:-}
EVALUATOR=${EVALUATOR:-auto}
VERIFIER=${VERIFIER:-"$ROOT/external/lab2-checker/verifier.py"}
NTHU_OPENMP=${NTHU_OPENMP:-ON}
NTHU_CUDA=${NTHU_CUDA:-OFF}
NTHU_EXTRA_ARGS=${NTHU_EXTRA_ARGS:-}
NTHU_DIR=$(cd "$NTHU_DIR" && pwd)
BENCH_DIR=$(cd "$BENCH_DIR" && pwd)
mkdir -p "$RESULT_DIR"
RESULT_DIR=$(cd "$RESULT_DIR" && pwd)
if [[ -z "${BUILD_DIR:-}" ]]; then
  if [[ "$NTHU_CUDA" == "ON" ]]; then
    BUILD_DIR="$NTHU_DIR/build-release-openmp-${NTHU_OPENMP}-cuda-${NTHU_CUDA}"
  else
    BUILD_DIR="$NTHU_DIR/build-release-openmp-${NTHU_OPENMP}"
  fi
fi
if [[ -z "${ROUTER_LABEL:-}" ]]; then
  if [[ "$NTHU_OPENMP" == "ON" ]]; then
    ROUTER_LABEL=nthu_openmp
  else
    ROUTER_LABEL=nthu_openmp_off
  fi
fi

if [[ "$NTHU_OPENMP" == "ON" ]]; then
  export OMP_NUM_THREADS=${OMP_NUM_THREADS:-${SLURM_CPUS_PER_TASK:-$JOBS}}
fi

read -r -a nthu_extra_args <<< "$NTHU_EXTRA_ARGS"

mkdir -p "$RESULT_DIR" "$BUILD_DIR"

if [[ "${SKIP_BUILD:-0}" != 1 ]]; then
  cmake_args=(-S "$NTHU_DIR" -B "$BUILD_DIR" -G Ninja -DCMAKE_BUILD_TYPE=Release)
  if grep -q "NTHU_ROUTE_ENABLE_OPENMP" "$NTHU_DIR/CMakeLists.txt"; then
    cmake_args+=(-DNTHU_ROUTE_ENABLE_OPENMP="$NTHU_OPENMP")
  fi
  if grep -q "NTHU_ROUTE_ENABLE_CUDA" "$NTHU_DIR/CMakeLists.txt"; then
    cmake_args+=(-DNTHU_ROUTE_ENABLE_CUDA="$NTHU_CUDA")
  fi
  cmake "${cmake_args[@]}"
  cmake --build "$BUILD_DIR" -j "$JOBS"
elif [[ ! -x "$BUILD_DIR/NthuRoute" ]]; then
  echo "SKIP_BUILD=1 but $BUILD_DIR/NthuRoute is missing" >&2
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
  out="$RESULT_DIR/$name.nthu.out"
  log="$RESULT_DIR/$name.nthu.log"
  eval_log="$RESULT_DIR/$name.nthu.eval"
  metrics_json="$RESULT_DIR/$name.nthu.metrics.json"
  echo "$ROUTER_LABEL $name"
  start=$(python3 - <<'PY'
import time
print(time.time())
PY
)
  status=ok
  (cd "$BUILD_DIR" && ./NthuRoute "${nthu_extra_args[@]}" --input="$bench" --output="$out") > "$log" 2>&1 || status=fail
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
  total_wirelength=NA
  total_overflow=NA
  max_overflow=NA
  overflowed_nets=NA
  overflowed_edges=NA
  metric_evaluator=NA
  if [[ "$status" == ok ]]; then
    if python3 "$ROOT/scripts/evaluate_route.py" "$bench" "$out" \
        --evaluator "$EVALUATOR" \
        --verifier "$VERIFIER" \
        --nthu-dir "$NTHU_DIR" \
        > "$metrics_json" 2> "$eval_log"; then
      read -r metric_evaluator total_wirelength total_overflow max_overflow overflowed_nets overflowed_edges < <(
        python3 - "$metrics_json" <<'PY'
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
  echo "$ROUTER_LABEL,$name,$status,$seconds,$metric_evaluator,${total_wirelength:-NA},${total_overflow:-NA},${max_overflow:-NA},${overflowed_nets:-NA},${overflowed_edges:-NA},$out" >> "$CSV"
done

echo "wrote $CSV"
