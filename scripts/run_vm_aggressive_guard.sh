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
ROUTER_THREADS=${ROUTER_THREADS:-1}
ROUTER_OPENMP=${ROUTER_OPENMP:-OFF}
ROUTER_CUDA=${ROUTER_CUDA:-OFF}

mkdir -p "$RESULT_DIR"

cat > "$RESULT_DIR/original_baseline.csv" <<'CSV'
benchmark,role,original_seconds,kill_after_seconds,original_wl,original_overflow,original_max_overflow
adaptec1.capo70.3d.35.50.90,legal7,441.962666,1326,5363235,0,0
adaptec3.dragon70.3d.30.50.90,legal7,479.186273,1438,13158101,0,0
adaptec4.aplace60.3d.30.50.90,legal7,130.666544,392,12207270,0,0
adaptec5.mfar50.3d.50.20.100,legal7,1240.592120,3722,15535357,0,0
adaptec2.mpl60.3d.35.20.100,original_overflow,173.992000,522,4857976,958172,2
bigblue1.capo60.3d.50.10.100,legal7,1206.306768,3619,5575865,0,0
bigblue2.mpl60.3d.40.60.60,original_overflow,1020.139000,3061,7886236,1928338,2
bigblue3.aplace70.3d.50.10.90.m8,original_overflow,907.876000,2724,12282111,1724140,2
newblue1.ntup50.3d.30.50.90,original_overflow,1043.267000,3130,4077044,839522,2
newblue2.fastplace90.3d.50.20.100,legal7,76.516170,230,7595602,0,0
newblue5.ntup50.3d.40.10.100,original_overflow,2296.878000,6891,21540842,3427158,2
newblue6.mfar80.3d.60.10.100,legal7,3278.214429,9835,17683846,0,0
CSV

declare -A kill_after_by_bench=()
while IFS=, read -r benchmark _role _original_seconds kill_after_seconds _rest; do
  [[ "$benchmark" == "benchmark" ]] && continue
  kill_after_by_bench["$benchmark"]="$kill_after_seconds"
done < "$RESULT_DIR/original_baseline.csv"

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
  requested12|current12)
    benches=(
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
    ;;
  *)
    echo "unknown BENCH_SET=$BENCH_SET; use legal7 or requested12" >&2
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
  frontier_netguided_adaptive_repair_v3)
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
      NTHU_ADAPTIVE_LEGAL_REPAIR=1
      NTHU_ADAPTIVE_POST_ONLY_OVERFLOW_LIMIT=10
      NTHU_ADAPTIVE_REPAIR_P2_MAX_ITER=8
      NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_TRIGGER=200
      NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_MAX_ITER=16
      NTHU_ADAPTIVE_SMALL_OVERFLOW_P2_LIMIT=50
      NTHU_ADAPTIVE_SMALL_OVERFLOW_P2_ROUNDS=1
      NTHU_ADAPTIVE_INITIAL_P3_MAX_ITER=2
      NTHU_ADAPTIVE_INITIAL_P3_INIT_BOX=54
      NTHU_ADAPTIVE_INITIAL_P3_BOX_INC=88
      NTHU_ADAPTIVE_REPAIR_P3_MAX_ITER=12
      NTHU_ADAPTIVE_REPAIR_P3_INIT_BOX=66
      NTHU_ADAPTIVE_REPAIR_P3_BOX_INC=122
      NTHU_FINAL_FULL_REMAINDER_REPAIR_LIMIT=20
      NTHU_FINAL_FULL_REMAINDER_REPAIR_ROUNDS=2
    )
    ;;
  frontier_adaptive_late_score1_v4)
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
      NTHU_REROUTE_LATE_MIN_OVERFLOW_SCORE=1
      NTHU_POST_SORT_MODE=edge_count
      NTHU_POST_OVERFLOW_LIMIT_AFTER_FIRST=240
      NTHU_ADAPTIVE_LEGAL_REPAIR=1
      NTHU_ADAPTIVE_POST_ONLY_OVERFLOW_LIMIT=10
      NTHU_ADAPTIVE_REPAIR_P2_MAX_ITER=8
      NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_TRIGGER=200
      NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_MAX_ITER=16
      NTHU_ADAPTIVE_SMALL_OVERFLOW_P2_LIMIT=50
      NTHU_ADAPTIVE_SMALL_OVERFLOW_P2_ROUNDS=1
      NTHU_ADAPTIVE_INITIAL_P3_MAX_ITER=2
      NTHU_ADAPTIVE_INITIAL_P3_INIT_BOX=54
      NTHU_ADAPTIVE_INITIAL_P3_BOX_INC=88
      NTHU_ADAPTIVE_REPAIR_P3_MAX_ITER=12
      NTHU_ADAPTIVE_REPAIR_P3_INIT_BOX=66
      NTHU_ADAPTIVE_REPAIR_P3_BOX_INC=122
      NTHU_FINAL_FULL_REMAINDER_REPAIR_LIMIT=80
      NTHU_FINAL_FULL_REMAINDER_REPAIR_ROUNDS=6
    )
    ;;
  frontier_openmp_control_v5a)
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
      NTHU_REROUTE_LATE_MIN_OVERFLOW_SCORE=1
      NTHU_POST_SORT_MODE=edge_count
      NTHU_POST_OVERFLOW_LIMIT_AFTER_FIRST=240
      NTHU_ADAPTIVE_LEGAL_REPAIR=1
      NTHU_ADAPTIVE_POST_ONLY_OVERFLOW_LIMIT=10
      NTHU_ADAPTIVE_REPAIR_P2_MAX_ITER=8
      NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_TRIGGER=200
      NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_MAX_ITER=16
      NTHU_ADAPTIVE_SMALL_OVERFLOW_P2_LIMIT=50
      NTHU_ADAPTIVE_SMALL_OVERFLOW_P2_ROUNDS=1
      NTHU_ADAPTIVE_INITIAL_P3_MAX_ITER=2
      NTHU_ADAPTIVE_INITIAL_P3_INIT_BOX=54
      NTHU_ADAPTIVE_INITIAL_P3_BOX_INC=88
      NTHU_ADAPTIVE_REPAIR_P3_MAX_ITER=12
      NTHU_ADAPTIVE_REPAIR_P3_INIT_BOX=66
      NTHU_ADAPTIVE_REPAIR_P3_BOX_INC=122
      NTHU_FINAL_FULL_REMAINDER_REPAIR_LIMIT=80
      NTHU_FINAL_FULL_REMAINDER_REPAIR_ROUNDS=6
    )
    ;;
  frontier_direct_residual_v6)
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
      NTHU_REROUTE_LATE_MIN_OVERFLOW_SCORE=1
      NTHU_POST_SORT_MODE=edge_count
      NTHU_POST_OVERFLOW_LIMIT_AFTER_FIRST=240
      NTHU_ADAPTIVE_LEGAL_REPAIR=1
      NTHU_ADAPTIVE_POST_ONLY_OVERFLOW_LIMIT=10
      NTHU_ADAPTIVE_REPAIR_P2_MAX_ITER=8
      NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_TRIGGER=200
      NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_MAX_ITER=16
      NTHU_ADAPTIVE_SMALL_OVERFLOW_P2_LIMIT=50
      NTHU_ADAPTIVE_SMALL_OVERFLOW_P2_ROUNDS=1
      NTHU_ADAPTIVE_INITIAL_P3_MAX_ITER=2
      NTHU_ADAPTIVE_INITIAL_P3_INIT_BOX=54
      NTHU_ADAPTIVE_INITIAL_P3_BOX_INC=88
      NTHU_ADAPTIVE_REPAIR_P3_MAX_ITER=12
      NTHU_ADAPTIVE_REPAIR_P3_INIT_BOX=66
      NTHU_ADAPTIVE_REPAIR_P3_BOX_INC=122
      NTHU_FINAL_FULL_REMAINDER_REPAIR_LIMIT=80
      NTHU_FINAL_FULL_REMAINDER_REPAIR_ROUNDS=6
      NTHU_ADAPTIVE_DIRECT_OVERFLOW_LIMIT=80
      NTHU_FINAL_DIRECT_OVERFLOW_REPAIR_LIMIT=80
      NTHU_FINAL_DIRECT_OVERFLOW_REPAIR_ROUNDS=3
    )
    ;;
  frontier_proposal_reroute_v7)
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
      NTHU_REROUTE_LATE_MIN_OVERFLOW_SCORE=1
      NTHU_POST_SORT_MODE=edge_count
      NTHU_POST_OVERFLOW_LIMIT_AFTER_FIRST=240
      NTHU_ADAPTIVE_LEGAL_REPAIR=1
      NTHU_ADAPTIVE_POST_ONLY_OVERFLOW_LIMIT=10
      NTHU_ADAPTIVE_REPAIR_P2_MAX_ITER=8
      NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_TRIGGER=200
      NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_MAX_ITER=16
      NTHU_ADAPTIVE_SMALL_OVERFLOW_P2_LIMIT=50
      NTHU_ADAPTIVE_SMALL_OVERFLOW_P2_ROUNDS=1
      NTHU_ADAPTIVE_INITIAL_P3_MAX_ITER=2
      NTHU_ADAPTIVE_INITIAL_P3_INIT_BOX=54
      NTHU_ADAPTIVE_INITIAL_P3_BOX_INC=88
      NTHU_ADAPTIVE_REPAIR_P3_MAX_ITER=12
      NTHU_ADAPTIVE_REPAIR_P3_INIT_BOX=66
      NTHU_ADAPTIVE_REPAIR_P3_BOX_INC=122
      NTHU_FINAL_FULL_REMAINDER_REPAIR_LIMIT=80
      NTHU_FINAL_FULL_REMAINDER_REPAIR_ROUNDS=6
      NTHU_PROPOSAL_REROUTE_BATCHES=1
      NTHU_PROPOSAL_REROUTE_MAZE=1
      NTHU_PROPOSAL_REROUTE_LOG=1
      NTHU_PROPOSAL_REROUTE_MAX_CANDIDATES=0
    )
    ;;
  frontier_openmp_conflict_batch_v5)
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
      NTHU_REROUTE_LATE_MIN_OVERFLOW_SCORE=1
      NTHU_POST_SORT_MODE=edge_count
      NTHU_POST_OVERFLOW_LIMIT_AFTER_FIRST=240
      NTHU_ADAPTIVE_LEGAL_REPAIR=1
      NTHU_ADAPTIVE_POST_ONLY_OVERFLOW_LIMIT=10
      NTHU_ADAPTIVE_REPAIR_P2_MAX_ITER=8
      NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_TRIGGER=200
      NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_MAX_ITER=16
      NTHU_ADAPTIVE_SMALL_OVERFLOW_P2_LIMIT=50
      NTHU_ADAPTIVE_SMALL_OVERFLOW_P2_ROUNDS=1
      NTHU_ADAPTIVE_INITIAL_P3_MAX_ITER=2
      NTHU_ADAPTIVE_INITIAL_P3_INIT_BOX=54
      NTHU_ADAPTIVE_INITIAL_P3_BOX_INC=88
      NTHU_ADAPTIVE_REPAIR_P3_MAX_ITER=12
      NTHU_ADAPTIVE_REPAIR_P3_INIT_BOX=66
      NTHU_ADAPTIVE_REPAIR_P3_BOX_INC=122
      NTHU_FINAL_FULL_REMAINDER_REPAIR_LIMIT=80
      NTHU_FINAL_FULL_REMAINDER_REPAIR_ROUNDS=6
      NTHU_PARALLEL_REROUTE_BATCHES=1
      NTHU_PARALLEL_REROUTE_BATCH_LIMIT=${OPENMP_BATCH_LIMIT:-4}
      NTHU_PARALLEL_REROUTE_MAX_CANDIDATES=${OPENMP_MAX_CANDIDATES:-512}
      NTHU_PARALLEL_REROUTE_LOG=1
      NTHU_PROFILE=1
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
  echo "router_threads=$ROUTER_THREADS"
  echo "router_openmp=$ROUTER_OPENMP"
  echo "router_cuda=$ROUTER_CUDA"
  echo "strategy_args=$strategy_args"
  echo "strategy_env=${strategy_env[*]}"
  echo
  hostname || true
  uname -a || true
  lscpu || true
  git status --short || true
  echo "kill_gate=3x original runtime per benchmark"
} > "$RESULT_DIR/environment.txt"

CSV_HEADER="router,benchmark,status,seconds,evaluator,total_wirelength,total_overflow,max_overflow,overflowed_nets,overflowed_edges,output"

run_one_guard() {
  local bench_entry=$1
  local name
  name=$(basename "$bench_entry" .gr)
  local timeout_seconds=${kill_after_by_bench[$name]:-}
  if [[ -z "$timeout_seconds" ]]; then
    echo "missing original timeout baseline for $name" >&2
    return 2
  fi

  local bench_result_dir="$RESULT_DIR/$name"
  local bench_list="$bench_result_dir/bench.list"
  mkdir -p "$bench_result_dir"
  printf '%s\n' "$bench_entry" > "$bench_list"
  {
    echo "strategy=$STRATEGY"
    echo "benchmark=$name"
    echo "timeout_seconds=$timeout_seconds"
    echo "strategy_args=$strategy_args"
    echo "started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "env=${strategy_env[*]}"
  } > "$bench_result_dir/run_meta.txt"

  set +e
  timeout --kill-after=20s "${timeout_seconds}s" \
    env "${strategy_env[@]}" \
      ROUTER_LABEL="$STRATEGY" \
      NTHU_DIR="$NTHU_DIR" \
      BUILD_DIR="$BUILD_DIR" \
      RESULT_DIR="$bench_result_dir" \
      BENCH_DIR="$BENCH_DIR" \
      BENCH_LIST="$bench_list" \
      EVALUATOR=lab2 \
      NTHU_OPENMP="$ROUTER_OPENMP" \
      NTHU_CUDA="$ROUTER_CUDA" \
      SKIP_BUILD="$SKIP_BUILD" \
      JOBS="$JOBS" \
      PARALLEL_BENCH_JOBS=1 \
      OMP_NUM_THREADS="$ROUTER_THREADS" \
      NTHU_EXTRA_ARGS="$strategy_args" \
      bash scripts/run_nthu_ispd08.sh \
      > "$bench_result_dir/runner.log" 2>&1
  local rc=$?
  set -e

  echo "ended_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$bench_result_dir/run_meta.txt"
  echo "exit_code=$rc" >> "$bench_result_dir/run_meta.txt"
  if [[ "$rc" == 124 || "$rc" == 137 ]]; then
    echo "timeout=1" >> "$bench_result_dir/run_meta.txt"
    if [[ ! -f "$bench_result_dir/summary.csv" ]] || [[ $(wc -l < "$bench_result_dir/summary.csv") -le 1 ]]; then
      echo "$CSV_HEADER" > "$bench_result_dir/summary.csv"
      echo "$STRATEGY,$name,timeout,$timeout_seconds,NA,NA,NA,NA,NA,NA,$bench_result_dir/$name.nthu.out" >> "$bench_result_dir/summary.csv"
    fi
  else
    echo "timeout=0" >> "$bench_result_dir/run_meta.txt"
  fi
}

for bench_entry in "${benches[@]}"; do
  run_one_guard "$bench_entry" &
  while (( $(jobs -pr | wc -l) >= PARALLEL_BENCH_JOBS )); do
    sleep 1
  done
done

wait

echo "$CSV_HEADER" > "$RESULT_DIR/summary.csv"
for bench_entry in "${benches[@]}"; do
  name=$(basename "$bench_entry" .gr)
  if [[ -f "$RESULT_DIR/$name/summary.csv" ]]; then
    tail -n +2 "$RESULT_DIR/$name/summary.csv" >> "$RESULT_DIR/summary.csv"
  else
    timeout_seconds=${kill_after_by_bench[$name]:-NA}
    echo "$STRATEGY,$name,missing,$timeout_seconds,NA,NA,NA,NA,NA,NA,$RESULT_DIR/$name/$name.nthu.out" >> "$RESULT_DIR/summary.csv"
  fi
done

python3 - "$RESULT_DIR" <<'PY'
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
with (root / "summary.csv").open(newline="", encoding="utf-8") as f:
    for row in csv.DictReader(f):
        row = dict(row)
        base = baseline[row["benchmark"]]
        original_seconds = float(base["original_seconds"])
        original_wl = float(base["original_wl"])
        row["role"] = base["role"]
        row["original_seconds"] = f"{original_seconds:.6f}"
        row["kill_after_seconds"] = base["kill_after_seconds"]
        row["original_overflow"] = base["original_overflow"]
        row["original_max_overflow"] = base["original_max_overflow"]
        original_legal = base["original_overflow"] == "0" and base["original_max_overflow"] == "0"
        row["original_legal"] = original_legal
        try:
            seconds = float(row["seconds"])
            row["speedup_vs_original"] = f"{original_seconds / seconds:.6f}"
        except Exception:
            seconds = None
            row["speedup_vs_original"] = "NA"
        row["original_wl"] = base["original_wl"]
        try:
            wl = float(row["total_wirelength"])
            row["wl_ratio_vs_original"] = f"{wl / original_wl:.6f}"
        except Exception:
            row["wl_ratio_vs_original"] = "NA"
        row["candidate_legal"] = (
            row["status"] == "ok" and row["total_overflow"] == "0" and row["max_overflow"] == "0"
        )
        row["passes_original_legal_guard"] = (not original_legal) or row["candidate_legal"]
        row["timed_out"] = row["status"] == "timeout"
        rows.append(row)

fieldnames = [
    "router",
    "role",
    "benchmark",
    "status",
    "seconds",
    "original_seconds",
    "kill_after_seconds",
    "speedup_vs_original",
    "total_wirelength",
    "original_wl",
    "wl_ratio_vs_original",
    "original_overflow",
    "original_max_overflow",
    "original_legal",
    "total_overflow",
    "max_overflow",
    "overflowed_nets",
    "overflowed_edges",
    "candidate_legal",
    "passes_original_legal_guard",
    "timed_out",
    "output",
]
with (root / "summary_with_baseline.csv").open("w", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
    writer.writeheader()
    writer.writerows(rows)

total_original = sum(float(row["original_seconds"]) for row in rows)
total_seconds = sum(float(row["seconds"]) for row in rows if row["seconds"] not in ("NA", ""))
legal = sum(1 for row in rows if row["candidate_legal"])
original_legal_rows = sum(1 for row in rows if row["original_legal"])
original_legal_pass = sum(1 for row in rows if row["original_legal"] and row["candidate_legal"])
guard_pass = sum(1 for row in rows if row["passes_original_legal_guard"])
timeouts = sum(1 for row in rows if row["timed_out"])
with (root / "aggregate.txt").open("w", encoding="utf-8") as f:
    f.write(f"rows={len(rows)}\n")
    f.write(f"legal={legal}/{len(rows)}\n")
    f.write(f"original_legal_guard={original_legal_pass}/{original_legal_rows}\n")
    f.write(f"guard_pass={guard_pass}/{len(rows)}\n")
    f.write(f"timeouts={timeouts}\n")
    f.write(f"original_seconds={total_original:.6f}\n")
    f.write(f"candidate_seconds={total_seconds:.6f}\n")
    f.write(f"suite_speedup={total_original / total_seconds:.6f}\n" if total_seconds else "suite_speedup=NA\n")
with (root / "timeouts.json").open("w", encoding="utf-8") as f:
    json.dump([row for row in rows if row["timed_out"]], f, indent=2)
print(root / "summary_with_baseline.csv")
PY

echo "ended_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$RESULT_DIR/environment.txt"
echo "wrote $RESULT_DIR/summary_with_baseline.csv"
