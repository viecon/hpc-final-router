#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

TAG=${TAG:-vm_aggressive_smoke}
RUN_ID=${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)_$(git rev-parse --short HEAD)}
RESULT_ROOT=${RESULT_ROOT:-"$ROOT/results/$TAG/$RUN_ID"}
BENCH_DIR=${BENCH_DIR:-"$ROOT/benchmarks/ispd08"}
NTHU_DIR=${NTHU_DIR:-"$ROOT/external/nthu-route"}
BUILD_DIR=${BUILD_DIR:-"$NTHU_DIR/build-release-vm-strict-cpu"}
SKIP_BUILD=${SKIP_BUILD:-1}
JOBS=${JOBS:-14}
PARALLEL_BENCH_JOBS=${PARALLEL_BENCH_JOBS:-1}
ROUTER_THREADS=${ROUTER_THREADS:-1}
RUN_STRATEGIES=${RUN_STRATEGIES:-prev_final aggressive_p3lite_v1}

COMMON_ARGS=${COMMON_ARGS:-"--p2-init-box-size=5 --p2-box-expand-size=5 --p2-max-iteration=6 --overflow-threshold=1800 --p3-max-iteration=24 --p3-init-box-size=80 --p3-box-expand-size=140"}

mkdir -p "$RESULT_ROOT"

cat > "$RESULT_ROOT/original_baseline.csv" <<'CSV'
benchmark,role,original_seconds,kill_after_seconds,original_wl,original_overflow,original_max_overflow
newblue2.fastplace90.3d.50.20.100,easy,76.516170,230,7595602,0,0
adaptec4.aplace60.3d.30.50.90,hard,130.666544,392,12207270,0,0
CSV

cat > "$RESULT_ROOT/strategy_catalog.csv" <<'CSV'
strategy,previous_strategy,optimization_logic,reference
prev_final,,final high-overflow adaptive P2 budget from reports/03-final-vm-strategy-results.md,internal prior result
aggressive_p3lite_v1,prev_final,aggressively reduce initial/repair P3 effort while keeping routing-state adaptive repair; tests whether early deep P3 was the bottleneck,internal follow-up; no new paper claim
CSV

{
  echo "run_id=$RUN_ID"
  echo "started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "git_branch=$(git branch --show-current || true)"
  echo "git_head=$(git rev-parse --short HEAD || true)"
  echo "result_root=$RESULT_ROOT"
  echo "bench_dir=$BENCH_DIR"
  echo "nthu_dir=$NTHU_DIR"
  echo "build_dir=$BUILD_DIR"
  echo "skip_build=$SKIP_BUILD"
  echo "common_args=$COMMON_ARGS"
  echo "run_strategies=$RUN_STRATEGIES"
  echo "parallel_bench_jobs=$PARALLEL_BENCH_JOBS"
  echo "router_threads=$ROUTER_THREADS"
  echo
  echo "== host =="
  hostname || true
  uname -a || true
  echo
  echo "== cpu =="
  lscpu || true
  echo
  echo "== git status =="
  git status --short || true
} > "$RESULT_ROOT/environment.txt"

write_bench_list() {
  local bench=$1
  local out=$2
  printf '%s\n' "$bench.gr" > "$out"
}

strategy_enabled() {
  local strategy=$1
  [[ " $RUN_STRATEGIES " == *" $strategy "* ]]
}

run_one() {
  local strategy=$1
  local role=$2
  local bench=$3
  local timeout_seconds=$4
  shift 4
  local result_dir="$RESULT_ROOT/$strategy/$bench"
  local bench_list="$result_dir/bench.list"
  mkdir -p "$result_dir"
  write_bench_list "$bench" "$bench_list"
  {
    echo "strategy=$strategy"
    echo "role=$role"
    echo "benchmark=$bench"
    echo "timeout_seconds=$timeout_seconds"
    echo "started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "env=$*"
  } > "$result_dir/run_meta.txt"
  set +e
  timeout --kill-after=20s "${timeout_seconds}s" \
    env "$@" \
      ROUTER_LABEL="$strategy" \
      NTHU_DIR="$NTHU_DIR" \
      BUILD_DIR="$BUILD_DIR" \
      RESULT_DIR="$result_dir" \
      BENCH_DIR="$BENCH_DIR" \
      BENCH_LIST="$bench_list" \
      EVALUATOR=lab2 \
      NTHU_OPENMP=OFF \
      NTHU_CUDA=OFF \
      SKIP_BUILD="$SKIP_BUILD" \
      JOBS="$JOBS" \
      PARALLEL_BENCH_JOBS="$PARALLEL_BENCH_JOBS" \
      OMP_NUM_THREADS="$ROUTER_THREADS" \
      NTHU_EXTRA_ARGS="$COMMON_ARGS" \
      bash scripts/run_nthu_ispd08.sh \
      > "$result_dir/runner.log" 2>&1
  local rc=$?
  set -e
  echo "ended_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$result_dir/run_meta.txt"
  echo "exit_code=$rc" >> "$result_dir/run_meta.txt"
  if [[ "$rc" == 124 || "$rc" == 137 ]]; then
    echo "timeout=1" >> "$result_dir/run_meta.txt"
  else
    echo "timeout=0" >> "$result_dir/run_meta.txt"
  fi
}

if strategy_enabled prev_final; then
  common_prev=(
    NTHU_FAST_GREEDY_LAYER=1
    NTHU_FAST_GREEDY_LAYER_NET_GUIDED=1
    NTHU_NET_GUIDED_LOW_LAYER_FIRST=1
    NTHU_ADAPTIVE_LEGAL_REPAIR=1
    NTHU_ADAPTIVE_REPAIR_P2_MAX_ITER=10
    NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_TRIGGER=200
    NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_MAX_ITER=24
    NTHU_ADAPTIVE_SMALL_OVERFLOW_P2_LIMIT=50
    NTHU_ADAPTIVE_SMALL_OVERFLOW_P2_ROUNDS=1
    NTHU_ADAPTIVE_INITIAL_P3_MAX_ITER=4
    NTHU_ADAPTIVE_INITIAL_P3_INIT_BOX=66
    NTHU_ADAPTIVE_INITIAL_P3_BOX_INC=122
    NTHU_ADAPTIVE_REPAIR_P3_MAX_ITER=24
    NTHU_ADAPTIVE_REPAIR_P3_INIT_BOX=80
    NTHU_ADAPTIVE_REPAIR_P3_BOX_INC=140
    NTHU_POST_SORT_MODE=edge_count
  )
  run_one prev_final easy newblue2.fastplace90.3d.50.20.100 230 "${common_prev[@]}"
  run_one prev_final hard adaptec4.aplace60.3d.30.50.90 392 "${common_prev[@]}"
fi

if strategy_enabled aggressive_p3lite_v1; then
  common_candidate=(
    NTHU_FAST_GREEDY_LAYER=1
    NTHU_FAST_GREEDY_LAYER_NET_GUIDED=1
    NTHU_NET_GUIDED_LOW_LAYER_FIRST=1
    NTHU_ADAPTIVE_LEGAL_REPAIR=1
    NTHU_ADAPTIVE_REPAIR_P2_MAX_ITER=8
    NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_TRIGGER=200
    NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_MAX_ITER=16
    NTHU_ADAPTIVE_SMALL_OVERFLOW_P2_LIMIT=50
    NTHU_ADAPTIVE_SMALL_OVERFLOW_P2_ROUNDS=1
    NTHU_ADAPTIVE_INITIAL_P3_MAX_ITER=1
    NTHU_ADAPTIVE_INITIAL_P3_INIT_BOX=54
    NTHU_ADAPTIVE_INITIAL_P3_BOX_INC=88
    NTHU_ADAPTIVE_REPAIR_P3_MAX_ITER=12
    NTHU_ADAPTIVE_REPAIR_P3_INIT_BOX=66
    NTHU_ADAPTIVE_REPAIR_P3_BOX_INC=122
    NTHU_POST_SORT_MODE=edge_count
    NTHU_POST_OVERFLOW_LIMIT_AFTER_FIRST=80
  )
  run_one aggressive_p3lite_v1 easy newblue2.fastplace90.3d.50.20.100 230 "${common_candidate[@]}"
  run_one aggressive_p3lite_v1 hard adaptec4.aplace60.3d.30.50.90 392 "${common_candidate[@]}"
fi

python3 - "$RESULT_ROOT" <<'PY'
import csv
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
baseline = {}
with (root / "original_baseline.csv").open(newline="", encoding="utf-8") as f:
    for row in csv.DictReader(f):
        baseline[row["benchmark"]] = row

rows = []
for summary in sorted(root.glob("*/*/summary.csv")):
    strategy = summary.parent.parent.name
    with summary.open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            row = dict(row)
            row["strategy"] = strategy
            row["role"] = baseline.get(row["benchmark"], {}).get("role", "")
            base = baseline.get(row["benchmark"], {})
            if base:
                orig_s = float(base["original_seconds"])
                row["original_seconds"] = f"{orig_s:.6f}"
                try:
                    seconds = float(row["seconds"])
                    row["speedup_vs_original"] = f"{orig_s / seconds:.6f}"
                except Exception:
                    row["speedup_vs_original"] = "NA"
                try:
                    wl = float(row["total_wirelength"])
                    orig_wl = float(base["original_wl"])
                    row["wl_ratio_vs_original"] = f"{wl / orig_wl:.6f}"
                except Exception:
                    row["wl_ratio_vs_original"] = "NA"
                row["kill_after_seconds"] = base["kill_after_seconds"]
            rows.append(row)

fieldnames = [
    "strategy",
    "role",
    "benchmark",
    "status",
    "seconds",
    "original_seconds",
    "speedup_vs_original",
    "total_wirelength",
    "wl_ratio_vs_original",
    "total_overflow",
    "max_overflow",
    "overflowed_nets",
    "overflowed_edges",
    "kill_after_seconds",
    "output",
]
with (root / "smoke_summary.csv").open("w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
    writer.writeheader()
    writer.writerows(rows)

timeouts = []
for meta in sorted(root.glob("*/*/run_meta.txt")):
    data = {}
    for line in meta.read_text(encoding="utf-8").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            data[key] = value
    if data.get("timeout") == "1":
        timeouts.append({
            "strategy": meta.parent.parent.name,
            "benchmark": data.get("benchmark", meta.parent.name),
            "role": data.get("role", ""),
            "timeout_seconds": data.get("timeout_seconds", ""),
        })
with (root / "timeouts.json").open("w", encoding="utf-8") as f:
    json.dump(timeouts, f, indent=2)

print(root / "smoke_summary.csv")
if timeouts:
    print("timeouts:")
    for row in timeouts:
        print(row)
PY

echo "ended_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$RESULT_ROOT/environment.txt"
echo "wrote $RESULT_ROOT/smoke_summary.csv"
