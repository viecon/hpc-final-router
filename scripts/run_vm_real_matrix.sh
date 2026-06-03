#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

TAG=${TAG:-vm_real_matrix}
RUN_ID=${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}
RESULT_ROOT=${RESULT_ROOT:-"$ROOT/results/$TAG/runs/$RUN_ID"}
RUN_INDEX=${RUN_INDEX:-"$ROOT/results/$TAG/index.csv"}
RUN_NOTES=${RUN_NOTES:-}
BENCH_LIST="$RESULT_ROOT/benchmarks.list"
SUMMARY="$RESULT_ROOT/summary.csv"
GUARD="$RESULT_ROOT/overflow_guard.csv"
GUARD_ALL="$RESULT_ROOT/overflow_guard_all.csv"
GUARD_SUPPORTED="$RESULT_ROOT/overflow_guard_supported.csv"
JOBS=${JOBS:-4}
MAX_ROUTER_CORES=${MAX_ROUTER_CORES:-12}
OPENMP_THREADS=${OPENMP_THREADS:-4}
OPENMP_PROC_BIND=${OPENMP_PROC_BIND:-close}
OPENMP_PLACES=${OPENMP_PLACES:-cores}
if ! [[ "$MAX_ROUTER_CORES" =~ ^[0-9]+$ ]] || (( MAX_ROUTER_CORES < 1 )); then
  MAX_ROUTER_CORES=12
fi
if ! [[ "$OPENMP_THREADS" =~ ^[0-9]+$ ]] || (( OPENMP_THREADS < 1 )); then
  OPENMP_THREADS=4
fi
PARALLEL_BENCH_JOBS=${PARALLEL_BENCH_JOBS:-$MAX_ROUTER_CORES}
CUDA_PARALLEL_BENCH_JOBS=${CUDA_PARALLEL_BENCH_JOBS:-1}
RUN_STRATEGIES=${RUN_STRATEGIES:-all}
BENCH_SET=${BENCH_SET:-nthu11}
if [[ -z "${OPENMP_PARALLEL_BENCH_JOBS:-}" ]]; then
  OPENMP_PARALLEL_BENCH_JOBS=$(( MAX_ROUTER_CORES / OPENMP_THREADS ))
  if (( OPENMP_PARALLEL_BENCH_JOBS < 1 )); then
    OPENMP_PARALLEL_BENCH_JOBS=1
  fi
fi

ALL16_BENCHES=(
  adaptec1.capo70.3d.35.50.90.gr
  adaptec2.mpl60.3d.35.20.100.gr
  adaptec3.dragon70.3d.30.50.90.gr
  adaptec4.aplace60.3d.30.50.90.gr
  adaptec5.mfar50.3d.50.20.100.gr
  bigblue1.capo60.3d.50.10.100.gr
  bigblue2.mpl60.3d.40.60.60.gr
  bigblue3.aplace70.3d.50.10.90.m8.gr
  bigblue4.fastplace70.3d.80.20.80.gr
  newblue1.ntup50.3d.30.50.90.gr
  newblue2.fastplace90.3d.50.20.100.gr
  newblue3.kraftwerk80.3d.40.50.90.gr
  newblue4.mpl50.3d.40.10.95.gr
  newblue5.ntup50.3d.40.10.100.gr
  newblue6.mfar80.3d.60.10.100.gr
  newblue7.kraftwerk70.3d.80.20.82.m8.gr
)

NTHU11_BENCHES=(
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
)

REQUESTED12_BENCHES=(
  "${NTHU11_BENCHES[@]}"
  newblue6.mfar80.3d.60.10.100.gr
)
if [[ -n "${VM_REAL_BENCHES:-}" ]]; then
  read -r -a BENCHES <<< "${VM_REAL_BENCHES//,/ }"
else
  case "$BENCH_SET" in
    nthu11|best11)
      BENCHES=("${NTHU11_BENCHES[@]}")
      ;;
    requested12|current12)
      BENCHES=("${REQUESTED12_BENCHES[@]}")
      ;;
    all16|ispd16)
      BENCHES=("${ALL16_BENCHES[@]}")
      ;;
    *)
      echo "unknown BENCH_SET=$BENCH_SET; use nthu11, requested12, all16, or VM_REAL_BENCHES" >&2
      exit 2
      ;;
  esac
fi

mkdir -p "$RESULT_ROOT" "$(dirname "$RUN_INDEX")"
printf '%s\n' "${BENCHES[@]}" > "$BENCH_LIST"
STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

write_environment() {
  {
    echo "run_id=$RUN_ID"
    echo "started_at=$STARTED_AT"
    echo "tag=$TAG"
    echo "result_root=$RESULT_ROOT"
    echo "bench_set=$BENCH_SET"
    echo "bench_count=${#BENCHES[@]}"
    echo "run_strategies=$RUN_STRATEGIES"
    echo "max_router_cores=$MAX_ROUTER_CORES"
    echo "parallel_bench_jobs=$PARALLEL_BENCH_JOBS"
    echo "openmp_threads=$OPENMP_THREADS"
    echo "openmp_parallel_bench_jobs=$OPENMP_PARALLEL_BENCH_JOBS"
    echo "openmp_proc_bind=$OPENMP_PROC_BIND"
    echo "openmp_places=$OPENMP_PLACES"
    echo "cuda_parallel_bench_jobs=$CUDA_PARALLEL_BENCH_JOBS"
    echo "notes=$RUN_NOTES"
    echo
    echo "== git =="
    git branch --show-current || true
    git rev-parse --short HEAD || true
    git status --short || true
    echo
    echo "== host =="
    hostname || true
    uname -a || true
    echo
    echo "== cpu =="
    lscpu || true
    echo
    echo "== memory =="
    free -h || true
    echo
    echo "== gpu =="
    nvidia-smi || true
    echo
    echo "== tools =="
    apptainer --version || true
    cmake --version || true
    ninja --version || true
  } > "$RESULT_ROOT/environment.txt"
}

write_strategy_catalog() {
  cat > "$RESULT_ROOT/strategy_catalog.csv" <<'EOF'
strategy,kind,openmp,cuda,description
true_original,baseline,OFF,OFF,Original NTHU-Route baseline from external/nthu-route-original
nthu_openmp_t4,diagnostic,ON,OFF,OpenMP analysis kernels with 4 threads
nthu_openmp_t12,diagnostic,ON,OFF,OpenMP analysis kernels with 12 threads
nthu_fast_layer,cpu_single_core,OFF,OFF,Fast greedy layer assignment with small P2 box
nthu_fast_layer_continuity,cpu_single_core,OFF,OFF,Fast greedy layer assignment with continuity preference
nthu_fast_layer_repair,cpu_single_core_guarded,OFF,OFF,Fast layer plus conservative legal repair budget
nthu_p2p3_budget,cpu_single_core_guarded,OFF,OFF,Faster P2/P3 budget tuned for legal original cases
nthu_cuda_score,gpu_candidate,OFF,ON,CUDA costed maze scorer and dogleg fast path
nthu_edgecount_post,cpu_single_core_frontier,OFF,ON,Fast edge-count post strategy; CUDA build but no CUDA maze scorer
nthu_edgecount_post_cpu,cpu_single_core_frontier,OFF,OFF,CPU-only build of edge-count post strategy for parallel single-core throughput
nthu_p2p3_legal_repair,cpu_single_core_guarded,OFF,OFF,Conservative legal repair fallback
EOF
}

write_environment
write_strategy_catalog

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
    OMP_PROC_BIND="$OPENMP_PROC_BIND" \
    OMP_PLACES="$OPENMP_PLACES" \
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
  nthu_fast_layer_continuity \
  "$ROOT/external/nthu-route" \
  "$ROOT/external/nthu-route/build-release-vm-cpu" \
  OFF OFF \
  "--p2-init-box-size=5 --p2-box-expand-size=5" \
  1 "" \
  NTHU_FAST_GREEDY_LAYER=1 \
  NTHU_FAST_GREEDY_LAYER_CONTINUITY=1

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
  nthu_edgecount_post_cpu \
  "$ROOT/external/nthu-route" \
  "$ROOT/external/nthu-route/build-release-vm-cpu" \
  OFF OFF \
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

python3 scripts/summarize_vm_real_matrix.py "$RESULT_ROOT"

ENDED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
ROW_COUNT=$(tail -n +2 "$RESULT_ROOT/summary_live.csv" 2>/dev/null | wc -l | tr -d ' ')
BEST_ROWS=$(tail -n +2 "$RESULT_ROOT/best_per_benchmark_live.csv" 2>/dev/null | wc -l | tr -d ' ')
GUARD_FAILURES=$(python3 - "$RESULT_ROOT/overflow_guard_live.csv" <<'PY'
import csv
import sys
path = sys.argv[1]
try:
    with open(path, newline="") as f:
        print(sum(1 for row in csv.DictReader(f) if row.get("passes") != "True"))
except FileNotFoundError:
    print("NA")
PY
)
RUN_INDEX_PATH="$RUN_INDEX" \
RUN_ID_VALUE="$RUN_ID" \
STARTED_AT_VALUE="$STARTED_AT" \
ENDED_AT_VALUE="$ENDED_AT" \
TAG_VALUE="$TAG" \
RESULT_ROOT_VALUE="$RESULT_ROOT" \
GIT_BRANCH_VALUE="$(git branch --show-current || true)" \
GIT_HEAD_VALUE="$(git rev-parse --short HEAD || true)" \
BENCH_SET_VALUE="$BENCH_SET" \
BENCH_COUNT_VALUE="${#BENCHES[@]}" \
RUN_STRATEGIES_VALUE="$RUN_STRATEGIES" \
MAX_ROUTER_CORES_VALUE="$MAX_ROUTER_CORES" \
PARALLEL_BENCH_JOBS_VALUE="$PARALLEL_BENCH_JOBS" \
OPENMP_THREADS_VALUE="$OPENMP_THREADS" \
CUDA_PARALLEL_BENCH_JOBS_VALUE="$CUDA_PARALLEL_BENCH_JOBS" \
ROW_COUNT_VALUE="$ROW_COUNT" \
BEST_ROWS_VALUE="$BEST_ROWS" \
GUARD_FAILURES_VALUE="$GUARD_FAILURES" \
RUN_NOTES_VALUE="$RUN_NOTES" \
python3 - <<'PY'
import csv
import os

path = os.environ["RUN_INDEX_PATH"]
fieldnames = [
    "run_id",
    "started_at",
    "ended_at",
    "tag",
    "result_root",
    "git_branch",
    "git_head",
    "bench_set",
    "bench_count",
    "run_strategies",
    "max_router_cores",
    "parallel_bench_jobs",
    "openmp_threads",
    "cuda_parallel_bench_jobs",
    "row_count",
    "best_rows",
    "guard_failures",
    "notes",
]
row = {
    "run_id": os.environ["RUN_ID_VALUE"],
    "started_at": os.environ["STARTED_AT_VALUE"],
    "ended_at": os.environ["ENDED_AT_VALUE"],
    "tag": os.environ["TAG_VALUE"],
    "result_root": os.environ["RESULT_ROOT_VALUE"],
    "git_branch": os.environ["GIT_BRANCH_VALUE"],
    "git_head": os.environ["GIT_HEAD_VALUE"],
    "bench_set": os.environ["BENCH_SET_VALUE"],
    "bench_count": os.environ["BENCH_COUNT_VALUE"],
    "run_strategies": os.environ["RUN_STRATEGIES_VALUE"],
    "max_router_cores": os.environ["MAX_ROUTER_CORES_VALUE"],
    "parallel_bench_jobs": os.environ["PARALLEL_BENCH_JOBS_VALUE"],
    "openmp_threads": os.environ["OPENMP_THREADS_VALUE"],
    "cuda_parallel_bench_jobs": os.environ["CUDA_PARALLEL_BENCH_JOBS_VALUE"],
    "row_count": os.environ["ROW_COUNT_VALUE"],
    "best_rows": os.environ["BEST_ROWS_VALUE"],
    "guard_failures": os.environ["GUARD_FAILURES_VALUE"],
    "notes": os.environ["RUN_NOTES_VALUE"],
}
exists = os.path.exists(path)
with open(path, "a", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    if not exists:
        writer.writeheader()
    writer.writerow(row)
PY
echo "wrote $RUN_INDEX"
