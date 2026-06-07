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
ROUTER_OPENMP=${ROUTER_OPENMP:-OFF}
ROUTER_CUDA=${ROUTER_CUDA:-OFF}
SMOKE_ROLES=${SMOKE_ROLES:-"easy hard"}
RUN_STRATEGIES=${RUN_STRATEGIES:-prev_final aggressive_p3lite_v1 aggressive_p3lite_v2_postonly frontier_edgecount_shortp3_v1 frontier_edgecount_netguided_v2 frontier_netguided_adaptive_repair_v3 frontier_adaptive_late_score1_v4}

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
aggressive_p3lite_v2_postonly,aggressive_p3lite_v1,same P3-lite logic but route tiny residual overflow through post-only repair before P2 repair; fixes v1 support issue where 3-4 overflow entered P2,internal follow-up; no new paper claim
frontier_edgecount_shortp3_v1,prev_final,aggressive runtime frontier using dogleg fast path range-skip edge-count post ordering and short P3 budget; expected to expose speed/legality tradeoff,internal frontier follow-up; no new paper claim
frontier_edgecount_netguided_v2,frontier_edgecount_shortp3_v1,same short-P3 edge-count frontier plus net-guided low-layer assignment to control WL,internal frontier follow-up; no new paper claim
frontier_netguided_adaptive_repair_v3,frontier_edgecount_netguided_v2,same fast frontier but restores routing-state adaptive legal repair when measured overflow remains after post-processing,internal legality repair follow-up; no new paper claim
frontier_adaptive_late_score1_v4,frontier_netguided_adaptive_repair_v3,same adaptive frontier but allows late P2 repair to reroute score-1 residual overflow and gives final full-remainder repair more rounds,internal legality repair follow-up; no new paper claim
frontier_openmp_control_v5a,frontier_adaptive_late_score1_v4,run the v4 frontier on a current-source OpenMP build without conflict-batch reroute; isolates safe OpenMP loop speedup from batching effects,OpenMP control experiment
frontier_direct_residual_v6,frontier_adaptive_late_score1_v4,add routing-state residual direct-overflow repair before full-remainder fallback to reduce low-overflow repair cost,NCTU-GR/SPRoute-style conflict-aware repair narrowing without benchmark-specific branching
frontier_proposal_reroute_v7,frontier_adaptive_late_score1_v4,replace in-place serial reroute calls with collect/propose/deterministic-commit phases using local per-thread routing proposals,NCTU-GR collision-aware task scheduling; SPRoute adaptive proposal/commit direction
frontier_v8_direct_proposal,frontier_proposal_reroute_v7,bypass NTHU interval/range expansion during P2 by scanning overflowed two-pin paths directly and feeding them into proposal-only deterministic commit,NCTU-GR collision-aware task scheduling; DSD 2013 parallel search/exclusive update; SPRoute adaptive batching direction
frontier_openmp_conflict_batch_v5,frontier_adaptive_late_score1_v4,enable OpenMP conflict-box reroute batching on the v4 frontier to test in-process parallelism without benchmark-specific routing changes,NCTU-GR 2.0 collision-aware task scheduling; Shintani et al. overlapped-region candidate/commit model
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
  echo "router_openmp=$ROUTER_OPENMP"
  echo "router_cuda=$ROUTER_CUDA"
  echo "smoke_roles=$SMOKE_ROLES"
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

role_enabled() {
  local role=$1
  [[ " $SMOKE_ROLES " == *" $role "* ]]
}

run_one() {
  local strategy=$1
  local role=$2
  local bench=$3
  local timeout_seconds=$4
  local strategy_args=$5
  shift 5
  if ! role_enabled "$role"; then
    return 0
  fi
  local result_dir="$RESULT_ROOT/$strategy/$bench"
  local bench_list="$result_dir/bench.list"
  mkdir -p "$result_dir"
  write_bench_list "$bench" "$bench_list"
  {
    echo "strategy=$strategy"
    echo "role=$role"
    echo "benchmark=$bench"
    echo "timeout_seconds=$timeout_seconds"
    echo "strategy_args=$strategy_args"
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
      NTHU_OPENMP="$ROUTER_OPENMP" \
      NTHU_CUDA="$ROUTER_CUDA" \
      SKIP_BUILD="$SKIP_BUILD" \
      JOBS="$JOBS" \
      PARALLEL_BENCH_JOBS="$PARALLEL_BENCH_JOBS" \
      OMP_NUM_THREADS="$ROUTER_THREADS" \
      NTHU_EXTRA_ARGS="$strategy_args" \
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
  run_one prev_final easy newblue2.fastplace90.3d.50.20.100 230 "$COMMON_ARGS" "${common_prev[@]}"
  run_one prev_final hard adaptec4.aplace60.3d.30.50.90 392 "$COMMON_ARGS" "${common_prev[@]}"
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
  run_one aggressive_p3lite_v1 easy newblue2.fastplace90.3d.50.20.100 230 "$COMMON_ARGS" "${common_candidate[@]}"
  run_one aggressive_p3lite_v1 hard adaptec4.aplace60.3d.30.50.90 392 "$COMMON_ARGS" "${common_candidate[@]}"
fi

if strategy_enabled aggressive_p3lite_v2_postonly; then
  common_candidate=(
    NTHU_FAST_GREEDY_LAYER=1
    NTHU_FAST_GREEDY_LAYER_NET_GUIDED=1
    NTHU_NET_GUIDED_LOW_LAYER_FIRST=1
    NTHU_ADAPTIVE_LEGAL_REPAIR=1
    NTHU_ADAPTIVE_POST_ONLY_OVERFLOW_LIMIT=10
    NTHU_ADAPTIVE_REPAIR_P2_MAX_ITER=8
    NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_TRIGGER=200
    NTHU_ADAPTIVE_HIGH_OVERFLOW_P2_MAX_ITER=16
    NTHU_ADAPTIVE_SMALL_OVERFLOW_P2_LIMIT=50
    NTHU_ADAPTIVE_SMALL_OVERFLOW_P2_ROUNDS=1
    NTHU_ADAPTIVE_INITIAL_P3_MAX_ITER=1
    NTHU_ADAPTIVE_INITIAL_P3_INIT_BOX=54
    NTHU_ADAPTIVE_INITIAL_P3_BOX_INC=88
    NTHU_ADAPTIVE_REPAIR_P3_MAX_ITER=4
    NTHU_ADAPTIVE_REPAIR_P3_INIT_BOX=66
    NTHU_ADAPTIVE_REPAIR_P3_BOX_INC=122
    NTHU_POST_SORT_MODE=edge_count
    NTHU_POST_OVERFLOW_LIMIT_AFTER_FIRST=80
  )
  run_one aggressive_p3lite_v2_postonly easy newblue2.fastplace90.3d.50.20.100 230 "$COMMON_ARGS" "${common_candidate[@]}"
  run_one aggressive_p3lite_v2_postonly hard adaptec4.aplace60.3d.30.50.90 392 "$COMMON_ARGS" "${common_candidate[@]}"
fi

if strategy_enabled frontier_edgecount_shortp3_v1; then
  frontier_args="--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=10000 --p2-max-iteration=5 --p3-max-iteration=2 --p3-init-box-size=54 --p3-box-expand-size=88"
  common_candidate=(
    NTHU_FAST_GREEDY_LAYER=1
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
  run_one frontier_edgecount_shortp3_v1 easy newblue2.fastplace90.3d.50.20.100 230 "$frontier_args" "${common_candidate[@]}"
  run_one frontier_edgecount_shortp3_v1 hard adaptec4.aplace60.3d.30.50.90 392 "$frontier_args" "${common_candidate[@]}"
fi

if strategy_enabled frontier_edgecount_netguided_v2; then
  frontier_args="--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=10000 --p2-max-iteration=5 --p3-max-iteration=2 --p3-init-box-size=54 --p3-box-expand-size=88"
  common_candidate=(
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
  run_one frontier_edgecount_netguided_v2 easy newblue2.fastplace90.3d.50.20.100 230 "$frontier_args" "${common_candidate[@]}"
  run_one frontier_edgecount_netguided_v2 hard adaptec4.aplace60.3d.30.50.90 392 "$frontier_args" "${common_candidate[@]}"
fi

if strategy_enabled frontier_netguided_adaptive_repair_v3; then
  frontier_args="--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=10000 --p2-max-iteration=5 --p3-max-iteration=2 --p3-init-box-size=54 --p3-box-expand-size=88"
  common_candidate=(
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
  run_one frontier_netguided_adaptive_repair_v3 easy newblue2.fastplace90.3d.50.20.100 230 "$frontier_args" "${common_candidate[@]}"
  run_one frontier_netguided_adaptive_repair_v3 hard adaptec4.aplace60.3d.30.50.90 392 "$frontier_args" "${common_candidate[@]}"
fi

if strategy_enabled frontier_adaptive_late_score1_v4; then
  frontier_args="--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=10000 --p2-max-iteration=5 --p3-max-iteration=2 --p3-init-box-size=54 --p3-box-expand-size=88"
  common_candidate=(
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
  run_one frontier_adaptive_late_score1_v4 easy newblue2.fastplace90.3d.50.20.100 230 "$frontier_args" "${common_candidate[@]}"
  run_one frontier_adaptive_late_score1_v4 hard adaptec4.aplace60.3d.30.50.90 392 "$frontier_args" "${common_candidate[@]}"
fi

if strategy_enabled frontier_openmp_control_v5a; then
  frontier_args="--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=10000 --p2-max-iteration=5 --p3-max-iteration=2 --p3-init-box-size=54 --p3-box-expand-size=88"
  common_candidate=(
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
  run_one frontier_openmp_control_v5a easy newblue2.fastplace90.3d.50.20.100 230 "$frontier_args" "${common_candidate[@]}"
  run_one frontier_openmp_control_v5a hard adaptec4.aplace60.3d.30.50.90 392 "$frontier_args" "${common_candidate[@]}"
fi

if strategy_enabled frontier_direct_residual_v6; then
  frontier_args="--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=10000 --p2-max-iteration=5 --p3-max-iteration=2 --p3-init-box-size=54 --p3-box-expand-size=88"
  common_candidate=(
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
  run_one frontier_direct_residual_v6 easy newblue2.fastplace90.3d.50.20.100 230 "$frontier_args" "${common_candidate[@]}"
  run_one frontier_direct_residual_v6 hard adaptec4.aplace60.3d.30.50.90 392 "$frontier_args" "${common_candidate[@]}"
fi

if strategy_enabled frontier_proposal_reroute_v7; then
  frontier_args="--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=10000 --p2-max-iteration=5 --p3-max-iteration=2 --p3-init-box-size=54 --p3-box-expand-size=88"
  common_candidate=(
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
    NTHU_PROPOSAL_REROUTE_MAX_CANDIDATES=16384
    NTHU_PROPOSAL_REROUTE_BATCH_SIZE=4096
    NTHU_PROPOSAL_REROUTE_MAX_ROUNDS=6
    NTHU_PROPOSAL_REROUTE_CONFLICT_AWARE=1
    NTHU_PROPOSAL_REROUTE_OVERFLOW_EDGE_CONFLICT=1
    NTHU_PROPOSAL_REROUTE_OVERFLOW_EDGE_QUOTA=8
    NTHU_PROPOSAL_REROUTE_IMPROVEMENT_COMMIT=1
    NTHU_PROPOSAL_REROUTE_RIPUP_BEFORE_PROPOSE=1
    NTHU_PROPOSAL_REROUTE_ADAPTIVE_ROUNDS=1
    NTHU_PROPOSAL_REROUTE_LOW_OVERFLOW_LIMIT=1000
    NTHU_PROPOSAL_REROUTE_LOW_MAX_ROUNDS=2
  )
  run_one frontier_proposal_reroute_v7 easy newblue2.fastplace90.3d.50.20.100 230 "$frontier_args" "${common_candidate[@]}"
  run_one frontier_proposal_reroute_v7 hard adaptec4.aplace60.3d.30.50.90 392 "$frontier_args" "${common_candidate[@]}"
fi

if strategy_enabled frontier_v8_direct_proposal; then
  frontier_args="--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=10000 --p2-max-iteration=5 --p3-max-iteration=2 --p3-init-box-size=54 --p3-box-expand-size=88"
  common_candidate=(
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
    NTHU_PROPOSAL_REROUTE_MAX_CANDIDATES=${V8_PROPOSAL_MAX_CANDIDATES:-16384}
    NTHU_PROPOSAL_REROUTE_BATCH_SIZE=${V8_PROPOSAL_BATCH_SIZE:-4096}
    NTHU_PROPOSAL_REROUTE_MAX_ROUNDS=${V8_PROPOSAL_MAX_ROUNDS:-6}
    NTHU_PROPOSAL_REROUTE_CONFLICT_AWARE=1
    NTHU_PROPOSAL_REROUTE_OVERFLOW_EDGE_CONFLICT=1
    NTHU_PROPOSAL_REROUTE_OVERFLOW_EDGE_QUOTA=${V8_PROPOSAL_EDGE_QUOTA:-8}
    NTHU_PROPOSAL_REROUTE_IMPROVEMENT_COMMIT=1
    NTHU_PROPOSAL_REROUTE_RIPUP_BEFORE_PROPOSE=1
    NTHU_PROPOSAL_REROUTE_ADAPTIVE_ROUNDS=1
    NTHU_PROPOSAL_REROUTE_LOW_OVERFLOW_LIMIT=1000
    NTHU_PROPOSAL_REROUTE_LOW_MAX_ROUNDS=2
    NTHU_V8_REJECT_COOLDOWN=1
    NTHU_V8_LOW_TAIL_GLOBAL_REPAIR=1
    NTHU_V8_LOW_TAIL_GLOBAL_REPAIR_LIMIT=${V8_LOW_TAIL_GLOBAL_REPAIR_LIMIT:-16}
    NTHU_V8_LOW_TAIL_GLOBAL_REPAIR_MAX_CANDIDATES=${V8_LOW_TAIL_GLOBAL_REPAIR_MAX_CANDIDATES:-128}
    NTHU_V8_LOW_TAIL_GLOBAL_REPAIR_ROUNDS=${V8_LOW_TAIL_GLOBAL_REPAIR_ROUNDS:-4}
    NTHU_V8_LOW_TAIL_BOX_INC=${V8_LOW_TAIL_BOX_INC:-66}
    NTHU_V8_DIRECT_ROUTE_ALL=1
    NTHU_V8_DIRECT_ROUTE_ALL_LOG=1
    NTHU_V8_DIRECT_ROUTE_ALL_LIMIT=${V8_DIRECT_ROUTE_ALL_LIMIT:-16384}
    NTHU_V8_DIRECT_ROUTE_ALL_MIN_SCORE=${V8_DIRECT_ROUTE_ALL_MIN_SCORE:-1}
  )
  run_one frontier_v8_direct_proposal easy newblue2.fastplace90.3d.50.20.100 230 "$frontier_args" "${common_candidate[@]}"
  run_one frontier_v8_direct_proposal hard adaptec4.aplace60.3d.30.50.90 392 "$frontier_args" "${common_candidate[@]}"
fi

if strategy_enabled frontier_openmp_conflict_batch_v5; then
  frontier_args="--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=10000 --p2-max-iteration=5 --p3-max-iteration=2 --p3-init-box-size=54 --p3-box-expand-size=88"
  common_candidate=(
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
  run_one frontier_openmp_conflict_batch_v5 easy newblue2.fastplace90.3d.50.20.100 230 "$frontier_args" "${common_candidate[@]}"
  run_one frontier_openmp_conflict_batch_v5 hard adaptec4.aplace60.3d.30.50.90 392 "$frontier_args" "${common_candidate[@]}"
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
