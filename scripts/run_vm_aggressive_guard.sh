#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

TAG=${TAG:-vm_aggressive_guard}
RUN_ID=${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)_$(git rev-parse --short HEAD)}
RESULT_DIR=${RESULT_DIR:-"$ROOT/results/$TAG/$RUN_ID"}
BENCH_DIR=${BENCH_DIR:-"$ROOT/benchmarks/ispd08"}
NTHU_DIR=${NTHU_DIR:-"$ROOT/external/nthu-route"}
BUILD_DIR=${BUILD_DIR:-"$NTHU_DIR/build-release-vm-strict-cpu"}
BENCH_SET=${BENCH_SET:-legal7}
STRATEGY=${STRATEGY:-frontier_edgecount_netguided_v2}
PARALLEL_BENCH_JOBS=${PARALLEL_BENCH_JOBS:-7}
SKIP_BUILD=${SKIP_BUILD:-1}
JOBS=${JOBS:-14}

mkdir -p "$RESULT_DIR"

cat > "$RESULT_DIR/original_baseline.csv" <<'CSV'
benchmark,role,original_seconds,original_wl,original_overflow,original_max_overflow
adaptec1.capo70.3d.35.50.90,legal7,441.962666,5363235,0,0
adaptec3.dragon70.3d.30.50.90,legal7,479.186273,13158101,0,0
adaptec4.aplace60.3d.30.50.90,legal7,130.666544,12207270,0,0
adaptec5.mfar50.3d.50.20.100,legal7,1240.592120,15535357,0,0
bigblue1.capo60.3d.50.10.100,legal7,1206.306768,5575865,0,0
newblue2.fastplace90.3d.50.20.100,legal7,76.516170,7595602,0,0
newblue6.mfar80.3d.60.10.100,legal7,3278.214429,17683846,0,0
CSV

case "$BENCH_SET" in
  legal7)
    benches=(
      adaptec1.capo70.3d.35.50.90.gr
      adaptec3.dragon70.3d.30.50.90.gr
      adaptec4.aplace60.3d.30.50.90.gr
      adaptec5.mfar50.3d.50.20.100.gr
      bigblue1.capo60.3d.50.10.100.gr
      newblue2.fastplace90.3d.50.20.100.gr
      newblue6.mfar80.3d.60.10.100.gr
    )
    ;;
  *)
    echo "unknown BENCH_SET=$BENCH_SET" >&2
    exit 2
    ;;
esac

printf '%s\n' "${benches[@]}" > "$RESULT_DIR/bench.list"

case "$STRATEGY" in
  frontier_edgecount_netguided_v2)
    strategy_args="--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=10000 --p2-max-iteration=5 --p3-max-iteration=2 --p3-init-box-size=54 --p3-box-expand-size=88"
    strategy_env=(
      NTHU_FAST_GREEDY_LAYER=1
      NTHU_FAST_GREEDY_LAYER_NET_GUIDED=1
      NTHU_NET_GUIDED_LOW_LAYER_FIRST=1
      NTHU_DOGLEG_FASTPATH=1
      NTHU_DOGLEG_MAX_EXTRA=0
      NTHU_DOGLEG_MIN_SCORE=1
      NTHU_DOGLEG_STEP=8
      NTHU_RANGE_SKIP_REMAINDER=1
      NTHU_REROUTE_SCORE_P2_ONLY=1
      NTHU_REROUTE_MIN_OVERFLOW_SCORE=5
      NTHU_REROUTE_LATE_SCORE_AFTER_ITER=4
      NTHU_REROUTE_LATE_MIN_OVERFLOW_SCORE=4
      NTHU_POST_SORT_MODE=edge_count
      NTHU_POST_OVERFLOW_LIMIT_AFTER_FIRST=80
    )
    ;;
  *)
    echo "unknown STRATEGY=$STRATEGY" >&2
    exit 2
    ;;
esac

{
  echo "run_id=$RUN_ID"
  echo "started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "git_branch=$(git branch --show-current || true)"
  echo "git_head=$(git rev-parse --short HEAD || true)"
  echo "result_dir=$RESULT_DIR"
  echo "bench_set=$BENCH_SET"
  echo "strategy=$STRATEGY"
  echo "parallel_bench_jobs=$PARALLEL_BENCH_JOBS"
  echo "strategy_args=$strategy_args"
  echo "strategy_env=${strategy_env[*]}"
  echo
  hostname || true
  uname -a || true
  lscpu || true
  git status --short || true
} > "$RESULT_DIR/environment.txt"

env "${strategy_env[@]}" \
  ROUTER_LABEL="$STRATEGY" \
  NTHU_DIR="$NTHU_DIR" \
  BUILD_DIR="$BUILD_DIR" \
  RESULT_DIR="$RESULT_DIR" \
  BENCH_DIR="$BENCH_DIR" \
  BENCH_LIST="$RESULT_DIR/bench.list" \
  EVALUATOR=lab2 \
  NTHU_OPENMP=OFF \
  NTHU_CUDA=OFF \
  SKIP_BUILD="$SKIP_BUILD" \
  JOBS="$JOBS" \
  PARALLEL_BENCH_JOBS="$PARALLEL_BENCH_JOBS" \
  NTHU_EXTRA_ARGS="$strategy_args" \
  bash scripts/run_nthu_ispd08.sh

python3 - "$RESULT_DIR" <<'PY'
import csv
import sys
from pathlib import Path

root = Path(sys.argv[1])
baseline = {}
with (root / "original_baseline.csv").open(newline="", encoding="utf-8") as f:
    for row in csv.DictReader(f):
        baseline[row["benchmark"]] = row

rows = []
with (root / "summary.csv").open(newline="", encoding="utf-8") as f:
    for row in csv.DictReader(f):
        row = dict(row)
        base = baseline[row["benchmark"]]
        original_seconds = float(base["original_seconds"])
        original_wl = float(base["original_wl"])
        seconds = float(row["seconds"])
        wl = float(row["total_wirelength"])
        row["role"] = base["role"]
        row["original_seconds"] = f"{original_seconds:.6f}"
        row["speedup_vs_original"] = f"{original_seconds / seconds:.6f}"
        row["original_wl"] = base["original_wl"]
        row["wl_ratio_vs_original"] = f"{wl / original_wl:.6f}"
        row["passes_original_legal_guard"] = (
            row["status"] == "ok" and row["total_overflow"] == "0" and row["max_overflow"] == "0"
        )
        rows.append(row)

fieldnames = [
    "router",
    "role",
    "benchmark",
    "status",
    "seconds",
    "original_seconds",
    "speedup_vs_original",
    "total_wirelength",
    "original_wl",
    "wl_ratio_vs_original",
    "total_overflow",
    "max_overflow",
    "overflowed_nets",
    "overflowed_edges",
    "passes_original_legal_guard",
    "output",
]
with (root / "summary_with_baseline.csv").open("w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
    writer.writeheader()
    writer.writerows(rows)

total_original = sum(float(row["original_seconds"]) for row in rows)
total_seconds = sum(float(row["seconds"]) for row in rows)
legal = sum(1 for row in rows if row["passes_original_legal_guard"])
with (root / "aggregate.txt").open("w", encoding="utf-8") as f:
    f.write(f"rows={len(rows)}\n")
    f.write(f"legal={legal}/{len(rows)}\n")
    f.write(f"original_seconds={total_original:.6f}\n")
    f.write(f"candidate_seconds={total_seconds:.6f}\n")
    f.write(f"suite_speedup={total_original / total_seconds:.6f}\n")
print(root / "summary_with_baseline.csv")
PY

echo "ended_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$RESULT_DIR/environment.txt"
echo "wrote $RESULT_DIR/summary_with_baseline.csv"
