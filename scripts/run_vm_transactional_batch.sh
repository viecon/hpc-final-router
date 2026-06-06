#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

TAG=${TAG:-vm_transactional_virtual_ripup}
RUN_ID=${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}
RESULT_DIR=${RESULT_DIR:-"$ROOT/results/$TAG/multi_requested12_$RUN_ID"}
RUN_INDEX=${RUN_INDEX:-"$ROOT/results/$TAG/index.csv"}
BENCH_DIR=${BENCH_DIR:-"$ROOT/benchmarks/ispd08"}
NTHU_DIR=${NTHU_DIR:-"$ROOT/external/nthu-route"}
BUILD_DIR=${BUILD_DIR:-"$NTHU_DIR/build-transactional-openmp"}
MAX_ROUTER_CORES=${MAX_ROUTER_CORES:-14}
ROUTER_THREADS=${ROUTER_THREADS:-1}
PARALLEL_BENCH_JOBS=${PARALLEL_BENCH_JOBS:-}
BENCH_SET=${BENCH_SET:-requested12}
ROUTER_LABEL=${ROUTER_LABEL:-nthu_transactional_vripup_repair}
RUN_NOTES=${RUN_NOTES:-transactional virtual rip-up adaptive serial repair batch}
SKIP_BUILD=${SKIP_BUILD:-0}
JOBS=${JOBS:-$MAX_ROUTER_CORES}

NTHU_EXTRA_ARGS=${NTHU_EXTRA_ARGS:-"--p2-init-box-size=5 --p2-box-expand-size=5 --p2-max-iteration=6 --overflow-threshold=1800 --p3-max-iteration=24 --p3-init-box-size=80 --p3-box-expand-size=140"}

if ! [[ "$MAX_ROUTER_CORES" =~ ^[0-9]+$ ]] || (( MAX_ROUTER_CORES < 1 )); then
  MAX_ROUTER_CORES=14
fi
if ! [[ "$ROUTER_THREADS" =~ ^[0-9]+$ ]] || (( ROUTER_THREADS < 1 )); then
  ROUTER_THREADS=1
fi
if [[ -z "$PARALLEL_BENCH_JOBS" ]]; then
  PARALLEL_BENCH_JOBS=$(( MAX_ROUTER_CORES / ROUTER_THREADS ))
  if (( PARALLEL_BENCH_JOBS < 1 )); then
    PARALLEL_BENCH_JOBS=1
  fi
fi
if [[ -z "${OMP_PROC_BIND:-}" ]]; then
  if (( PARALLEL_BENCH_JOBS > 1 && ROUTER_THREADS == 1 )); then
    OMP_PROC_BIND=false
  else
    OMP_PROC_BIND=close
  fi
fi
if [[ -z "${OMP_PLACES:-}" ]]; then
  if [[ "$OMP_PROC_BIND" == "false" || "$OMP_PROC_BIND" == "FALSE" || "$OMP_PROC_BIND" == "0" ]]; then
    OMP_PLACES=
  else
    OMP_PLACES=cores
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

if [[ -n "${VM_TRANSACTIONAL_BENCHES:-}" ]]; then
  read -r -a BENCHES <<< "${VM_TRANSACTIONAL_BENCHES//,/ }"
else
  case "$BENCH_SET" in
    requested12|current12)
      BENCHES=("${REQUESTED12_BENCHES[@]}")
      ;;
    nthu11|best11)
      BENCHES=("${NTHU11_BENCHES[@]}")
      ;;
    all16|ispd16)
      BENCHES=("${ALL16_BENCHES[@]}")
      ;;
    *)
      echo "unknown BENCH_SET=$BENCH_SET; use requested12, nthu11, all16, or VM_TRANSACTIONAL_BENCHES" >&2
      exit 2
      ;;
  esac
fi

mkdir -p "$RESULT_DIR" "$(dirname "$RUN_INDEX")"
RESULT_DIR=$(cd "$RESULT_DIR" && pwd)
BENCH_LIST="$RESULT_DIR/benchmarks.list"
printf '%s\n' "${BENCHES[@]}" > "$BENCH_LIST"

STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
SOURCE_COMMIT=$(git rev-parse --short HEAD)
SOURCE_BRANCH=$(git branch --show-current)

{
  echo "run_id=$RUN_ID"
  echo "started_at=$STARTED_AT"
  echo "tag=$TAG"
  echo "result_dir=$RESULT_DIR"
  echo "source_branch=$SOURCE_BRANCH"
  echo "source_commit=$SOURCE_COMMIT"
  echo "bench_set=$BENCH_SET"
  echo "bench_count=${#BENCHES[@]}"
  echo "max_router_cores=$MAX_ROUTER_CORES"
  echo "router_threads=$ROUTER_THREADS"
  echo "parallel_bench_jobs=$PARALLEL_BENCH_JOBS"
  echo "omp_proc_bind=$OMP_PROC_BIND"
  echo "omp_places=${OMP_PLACES:-unset}"
  echo "router_label=$ROUTER_LABEL"
  echo "nthu_dir=$NTHU_DIR"
  echo "build_dir=$BUILD_DIR"
  echo "skip_build=$SKIP_BUILD"
  echo "nthu_extra_args=$NTHU_EXTRA_ARGS"
  echo "notes=$RUN_NOTES"
  echo "NTHU_TRANSACTIONAL_REROUTE_BATCHES=${NTHU_TRANSACTIONAL_REROUTE_BATCHES:-1}"
  echo "NTHU_TRANSACTIONAL_BATCH_LIMIT=${NTHU_TRANSACTIONAL_BATCH_LIMIT:-$MAX_ROUTER_CORES}"
  echo "NTHU_TRANSACTIONAL_PROPOSAL_WAVE_BATCHES=${NTHU_TRANSACTIONAL_PROPOSAL_WAVE_BATCHES:-16}"
  echo "NTHU_TRANSACTIONAL_SERIAL_REPAIR=${NTHU_TRANSACTIONAL_SERIAL_REPAIR:-1}"
  echo "NTHU_TRANSACTIONAL_SERIAL_REPAIR_MAX_CANDIDATES=${NTHU_TRANSACTIONAL_SERIAL_REPAIR_MAX_CANDIDATES:-5000}"
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
} > "$RESULT_DIR/environment.txt"

{
  echo "benchmark,input,log,eval_log,metrics_json,output"
  for bench in "${BENCHES[@]}"; do
    name=$(basename "$bench" .gr)
    echo "$name,$BENCH_DIR/$bench,$RESULT_DIR/$name.nthu.log,$RESULT_DIR/$name.nthu.eval,$RESULT_DIR/$name.nthu.metrics.json,$RESULT_DIR/$name.nthu.out"
  done
} > "$RESULT_DIR/log_index.csv"

export OMP_NUM_THREADS="$ROUTER_THREADS"
export OMP_PROC_BIND
if [[ -n "$OMP_PLACES" ]]; then
  export OMP_PLACES
else
  unset OMP_PLACES
fi
export NTHU_TRANSACTIONAL_REROUTE_BATCHES=${NTHU_TRANSACTIONAL_REROUTE_BATCHES:-1}
export NTHU_TRANSACTIONAL_BATCH_LIMIT=${NTHU_TRANSACTIONAL_BATCH_LIMIT:-$MAX_ROUTER_CORES}
export NTHU_TRANSACTIONAL_PROPOSAL_WAVE_BATCHES=${NTHU_TRANSACTIONAL_PROPOSAL_WAVE_BATCHES:-16}
export NTHU_TRANSACTIONAL_SERIAL_REPAIR=${NTHU_TRANSACTIONAL_SERIAL_REPAIR:-1}
export NTHU_TRANSACTIONAL_SERIAL_REPAIR_MAX_CANDIDATES=${NTHU_TRANSACTIONAL_SERIAL_REPAIR_MAX_CANDIDATES:-5000}

env \
  ROUTER_LABEL="$ROUTER_LABEL" \
  NTHU_DIR="$NTHU_DIR" \
  BUILD_DIR="$BUILD_DIR" \
  RESULT_DIR="$RESULT_DIR" \
  BENCH_LIST="$BENCH_LIST" \
  EVALUATOR=lab2 \
  NTHU_OPENMP=ON \
  NTHU_CUDA=OFF \
  JOBS="$JOBS" \
  SKIP_BUILD="$SKIP_BUILD" \
  RESUME_EXISTING=1 \
  PARALLEL_BENCH_JOBS="$PARALLEL_BENCH_JOBS" \
  OMP_NUM_THREADS="$ROUTER_THREADS" \
  NTHU_EXTRA_ARGS="$NTHU_EXTRA_ARGS" \
  bash scripts/run_nthu_ispd08.sh

ENDED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
ROW_COUNT=$(tail -n +2 "$RESULT_DIR/summary.csv" 2>/dev/null | wc -l | tr -d ' ')
{
  echo "ended_at=$ENDED_AT"
  echo "row_count=$ROW_COUNT"
} >> "$RESULT_DIR/environment.txt"

RUN_INDEX_PATH="$RUN_INDEX" \
RUN_ID_VALUE="$RUN_ID" \
STARTED_AT_VALUE="$STARTED_AT" \
ENDED_AT_VALUE="$ENDED_AT" \
RESULT_DIR_VALUE="$RESULT_DIR" \
SOURCE_BRANCH_VALUE="$SOURCE_BRANCH" \
SOURCE_COMMIT_VALUE="$SOURCE_COMMIT" \
BENCH_SET_VALUE="$BENCH_SET" \
BENCH_COUNT_VALUE="${#BENCHES[@]}" \
ROUTER_THREADS_VALUE="$ROUTER_THREADS" \
PARALLEL_BENCH_JOBS_VALUE="$PARALLEL_BENCH_JOBS" \
ROW_COUNT_VALUE="$ROW_COUNT" \
RUN_NOTES_VALUE="$RUN_NOTES" \
python3 - <<'PY'
import csv
import os
from pathlib import Path

path = Path(os.environ["RUN_INDEX_PATH"])
path.parent.mkdir(parents=True, exist_ok=True)
fieldnames = [
    "run_id",
    "started_at",
    "ended_at",
    "result_dir",
    "source_branch",
    "source_commit",
    "bench_set",
    "bench_count",
    "router_threads",
    "parallel_bench_jobs",
    "row_count",
    "notes",
]
row = {
    "run_id": os.environ["RUN_ID_VALUE"],
    "started_at": os.environ["STARTED_AT_VALUE"],
    "ended_at": os.environ["ENDED_AT_VALUE"],
    "result_dir": os.environ["RESULT_DIR_VALUE"],
    "source_branch": os.environ["SOURCE_BRANCH_VALUE"],
    "source_commit": os.environ["SOURCE_COMMIT_VALUE"],
    "bench_set": os.environ["BENCH_SET_VALUE"],
    "bench_count": os.environ["BENCH_COUNT_VALUE"],
    "router_threads": os.environ["ROUTER_THREADS_VALUE"],
    "parallel_bench_jobs": os.environ["PARALLEL_BENCH_JOBS_VALUE"],
    "row_count": os.environ["ROW_COUNT_VALUE"],
    "notes": os.environ["RUN_NOTES_VALUE"],
}
exists = path.exists()
with path.open("a", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    if not exists:
        writer.writeheader()
    writer.writerow(row)
PY

echo "wrote $RESULT_DIR/summary.csv"
echo "wrote $RESULT_DIR/log_index.csv"
echo "wrote $RUN_INDEX"
