#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

TAG=${TAG:-vm_real_matrix}
RESULT_ROOT="$ROOT/results/$TAG"
BENCH_LIST="$RESULT_ROOT/benchmarks.list"
SUMMARY="$RESULT_ROOT/summary.csv"
GUARD="$RESULT_ROOT/overflow_guard.csv"
GUARD_ALL="$RESULT_ROOT/overflow_guard_all.csv"
GUARD_SUPPORTED="$RESULT_ROOT/overflow_guard_supported.csv"
JOBS=${JOBS:-4}
MAX_ROUTER_CORES=${MAX_ROUTER_CORES:-12}
OPENMP_THREADS=${OPENMP_THREADS:-4}
if ! [[ "$MAX_ROUTER_CORES" =~ ^[0-9]+$ ]] || (( MAX_ROUTER_CORES < 1 )); then
  MAX_ROUTER_CORES=12
fi
if ! [[ "$OPENMP_THREADS" =~ ^[0-9]+$ ]] || (( OPENMP_THREADS < 1 )); then
  OPENMP_THREADS=4
fi
PARALLEL_BENCH_JOBS=${PARALLEL_BENCH_JOBS:-$MAX_ROUTER_CORES}
CUDA_PARALLEL_BENCH_JOBS=${CUDA_PARALLEL_BENCH_JOBS:-1}
RUN_STRATEGIES=${RUN_STRATEGIES:-all}
if [[ -z "${OPENMP_PARALLEL_BENCH_JOBS:-}" ]]; then
  OPENMP_PARALLEL_BENCH_JOBS=$(( MAX_ROUTER_CORES / OPENMP_THREADS ))
  if (( OPENMP_PARALLEL_BENCH_JOBS < 1 )); then
    OPENMP_PARALLEL_BENCH_JOBS=1
  fi
fi

DEFAULT_BENCHES=(
  adaptec1.capo70.3d.35.50.90.gr
  adaptec2.mpl60.3d.35.20.100.gr
  adaptec3.dragon70.3d.30.50.90.gr
  adaptec4.aplace60.3d.30.50.90.gr
  adaptec5.mfar50.3d.50.20.100.gr
  bigblue1.capo60.3d.50.10.100.gr
  bigblue2.mpl60.3d.40.60.60.gr
  bigblue3.aplace70.3d.50.10.90.m8.gr
  newblue1.ntup50.3d.30.50.90.gr
  newblue2.fastplace90.3d.50.20.100.gr
  newblue5.ntup50.3d.40.10.100.gr
  newblue6.mfar80.3d.60.10.100.gr
)
if [[ -n "${VM_REAL_BENCHES:-}" ]]; then
  read -r -a BENCHES <<< "${VM_REAL_BENCHES//,/ }"
else
  BENCHES=("${DEFAULT_BENCHES[@]}")
fi

mkdir -p "$RESULT_ROOT"
printf '%s\n' "${BENCHES[@]}" > "$BENCH_LIST"

should_run_strategy() {
  local label=$1
  [[ "$RUN_STRATEGIES" == all ]] || [[ " $RUN_STRATEGIES " == *" $label "* ]]
}

build_and_run() {
  local label=$1
  local nthu_dir=$2
  local build_dir=$3
  local openmp=$4
  local cuda=$5
  local extra_args=$6
  local openmp_threads=$7
  local bench_jobs_override=$8
  shift 8
  if ! should_run_strategy "$label"; then
    echo "==> $label (skip by RUN_STRATEGIES=$RUN_STRATEGIES)"
    return
  fi
  local bench_jobs=$PARALLEL_BENCH_JOBS
  if [[ "$openmp" == "ON" ]]; then
    bench_jobs=$OPENMP_PARALLEL_BENCH_JOBS
  fi
  if [[ "$cuda" == "ON" ]]; then
    bench_jobs=$CUDA_PARALLEL_BENCH_JOBS
  fi
  if [[ -n "$bench_jobs_override" ]]; then
    bench_jobs=$bench_jobs_override
  fi

  echo "==> $label (parallel_bench_jobs=$bench_jobs)"
  env "$@" \
    ROUTER_LABEL="$label" \
    NTHU_DIR="$nthu_dir" \
    RESULT_DIR="$RESULT_ROOT/$label" \
    BENCH_LIST="$BENCH_LIST" \
    EVALUATOR=lab2 \
    OMP_NUM_THREADS="$openmp_threads" \
    NTHU_OPENMP="$openmp" \
    NTHU_CUDA="$cuda" \
    JOBS="$JOBS" \
    BUILD_DIR="$build_dir" \
    SKIP_BUILD=0 \
    RESUME_EXISTING=1 \
    PARALLEL_BENCH_JOBS="$bench_jobs" \
    NTHU_EXTRA_ARGS="$extra_args" \
      bash scripts/run_nthu_ispd08.sh
}

bash scripts/fetch_ispd08.sh

build_and_run \
  true_original \
  "$ROOT/external/nthu-route-original" \
  "$ROOT/external/nthu-route-original/build-release-vm-original" \
  OFF OFF \
  "" \
  1 ""

build_and_run \
  nthu_openmp_t4 \
  "$ROOT/external/nthu-route" \
  "$ROOT/external/nthu-route/build-release-vm-openmp-t4" \
  ON OFF \
  "" \
  4 ""

build_and_run \
  nthu_openmp_t12 \
  "$ROOT/external/nthu-route" \
  "$ROOT/external/nthu-route/build-release-vm-openmp-t12" \
  ON OFF \
  "" \
  12 1

build_and_run \
  nthu_fast_layer \
  "$ROOT/external/nthu-route" \
  "$ROOT/external/nthu-route/build-release-vm-cpu" \
  OFF OFF \
  "--p2-init-box-size=5 --p2-box-expand-size=5" \
  1 "" \
  NTHU_FAST_GREEDY_LAYER=1

build_and_run \
  nthu_fast_layer_repair \
  "$ROOT/external/nthu-route" \
  "$ROOT/external/nthu-route/build-release-vm-cpu" \
  OFF OFF \
  "--p2-init-box-size=5 --p2-box-expand-size=5 --p2-max-iteration=10 --overflow-threshold=0 --p3-max-iteration=20 --p3-init-box-size=66 --p3-box-expand-size=122" \
  1 "" \
  NTHU_FAST_GREEDY_LAYER=1 \
  NTHU_POST_SORT_MODE=edge_count

build_and_run \
  nthu_p2p3_budget \
  "$ROOT/external/nthu-route" \
  "$ROOT/external/nthu-route/build-release-vm-cpu" \
  OFF OFF \
  "--p2-init-box-size=5 --p2-box-expand-size=5 --p2-max-iteration=6 --overflow-threshold=1800 --p3-init-box-size=66 --p3-box-expand-size=122" \
  1 "" \
  NTHU_FAST_GREEDY_LAYER=1

build_and_run \
  nthu_cuda_score \
  "$ROOT/external/nthu-route" \
  "$ROOT/external/nthu-route/build-release-vm-cuda" \
  OFF ON \
  "--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=300000 --p2-max-iteration=4 --p3-max-iteration=8 --p3-init-box-size=35 --p3-box-expand-size=50" \
  1 "" \
  NTHU_FAST_GREEDY_LAYER=1 \
  NTHU_DOGLEG_FASTPATH=1 \
  NTHU_DOGLEG_MAX_EXTRA=0 \
  NTHU_DOGLEG_MIN_SCORE=1 \
  NTHU_DOGLEG_STEP=8 \
  NTHU_RANGE_SKIP_REMAINDER=1 \
  NTHU_CUDA_COSTED_MAZE_FASTPATH=1 \
  NTHU_CUDA_MAZE_MAX_AREA=256 \
  NTHU_CUDA_MAZE_MIN_OVERFLOW_SCORE=42

build_and_run \
  nthu_edgecount_post \
  "$ROOT/external/nthu-route" \
  "$ROOT/external/nthu-route/build-release-vm-cuda" \
  OFF ON \
  "--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=10000 --p2-max-iteration=5 --p3-max-iteration=2 --p3-init-box-size=54 --p3-box-expand-size=88" \
  1 "" \
  NTHU_FAST_GREEDY_LAYER=1 \
  NTHU_DOGLEG_FASTPATH=1 \
  NTHU_DOGLEG_MAX_EXTRA=0 \
  NTHU_DOGLEG_MIN_SCORE=1 \
  NTHU_DOGLEG_STEP=8 \
  NTHU_RANGE_SKIP_REMAINDER=1 \
  NTHU_REROUTE_SCORE_P2_ONLY=1 \
  NTHU_REROUTE_MIN_OVERFLOW_SCORE=5 \
  NTHU_REROUTE_LATE_SCORE_AFTER_ITER=4 \
  NTHU_REROUTE_LATE_MIN_OVERFLOW_SCORE=4 \
  NTHU_POST_SORT_MODE=edge_count \
  NTHU_POST_OVERFLOW_LIMIT_AFTER_FIRST=80

build_and_run \
  nthu_p2p3_legal_repair \
  "$ROOT/external/nthu-route" \
  "$ROOT/external/nthu-route/build-release-vm-cpu" \
  OFF OFF \
  "--p2-init-box-size=5 --p2-box-expand-size=5 --p2-max-iteration=12 --overflow-threshold=0 --p3-max-iteration=30 --p3-init-box-size=80 --p3-box-expand-size=140" \
  1 "" \
  NTHU_FAST_GREEDY_LAYER=1 \
  NTHU_POST_SORT_MODE=edge_count

python3 - "$RESULT_ROOT" "$SUMMARY" "$GUARD" "$GUARD_ALL" "$GUARD_SUPPORTED" <<'PY'
import csv
import sys
from pathlib import Path

root = Path(sys.argv[1])
summary = Path(sys.argv[2])
guard = Path(sys.argv[3])
guard_all = Path(sys.argv[4])
guard_supported = Path(sys.argv[5])
supported_strategies = {
    "nthu_openmp_t4",
    "nthu_openmp_t12",
    "nthu_fast_layer",
    "nthu_fast_layer_repair",
    "nthu_p2p3_legal_repair",
}
rows = []
for path in sorted(root.glob("*/summary.csv")):
    strategy = path.parent.name
    with path.open(newline="") as f:
        for row in csv.DictReader(f):
            row = dict(row)
            row["strategy"] = strategy
            rows.append(row)

fieldnames = [
    "strategy",
    "router",
    "benchmark",
    "status",
    "seconds",
    "evaluator",
    "total_wirelength",
    "total_overflow",
    "max_overflow",
    "overflowed_nets",
    "overflowed_edges",
    "output",
]
with summary.open("w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(rows)

by_bench = {}
for row in rows:
    by_bench.setdefault(row["benchmark"], {})[row["strategy"]] = row

guard_rows = []
for bench, strategy_rows in sorted(by_bench.items()):
    original = strategy_rows.get("true_original")
    if not original:
        continue
    try:
        original_overflow = int(original["total_overflow"])
    except Exception:
        continue
    if original_overflow != 0:
        continue
    for strategy, row in sorted(strategy_rows.items()):
        if strategy == "true_original":
            continue
        try:
            overflow = int(row["total_overflow"])
            max_overflow = int(row["max_overflow"])
        except Exception:
            overflow = -1
            max_overflow = -1
        guard_rows.append({
            "benchmark": bench,
            "strategy": strategy,
            "status": row["status"],
            "total_overflow": overflow,
            "max_overflow": max_overflow,
            "supported_claim": strategy in supported_strategies,
            "passes": row["status"] == "ok" and overflow == 0 and max_overflow == 0,
        })

guard_fieldnames = [
    "benchmark",
    "strategy",
    "status",
    "total_overflow",
    "max_overflow",
    "supported_claim",
    "passes",
]

with guard_all.open("w", newline="") as f:
    writer = csv.DictWriter(
        f,
        fieldnames=guard_fieldnames,
    )
    writer.writeheader()
    writer.writerows(guard_rows)

supported_rows = [row for row in guard_rows if row["supported_claim"]]
with guard_supported.open("w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=guard_fieldnames)
    writer.writeheader()
    writer.writerows(supported_rows)

with guard.open("w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=guard_fieldnames)
    writer.writeheader()
    writer.writerows(supported_rows)

bad = [row for row in supported_rows if not row["passes"]]
bad_all = [row for row in guard_rows if not row["passes"]]
print(f"wrote {summary}")
print(f"wrote {guard}")
print(f"wrote {guard_all}")
print(f"wrote {guard_supported}")
print(f"supported_overflow_guard_failures={len(bad)}")
print(f"all_strategy_overflow_guard_failures={len(bad_all)}")
for row in bad[:20]:
    print(row)
PY
