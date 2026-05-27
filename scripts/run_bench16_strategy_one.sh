#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

if [[ $# -lt 2 ]]; then
  echo "usage: $0 STRATEGY BENCHMARK.gr" >&2
  exit 2
fi

STRATEGY=$1
BENCH=$2
TAG=${TAG:-bench16_strategy_matrix}
BENCH_STEM=${BENCH%.gr}
SAFE_BENCH=${BENCH_STEM//[^A-Za-z0-9_]/_}
RESULT_DIR="$ROOT/results/${TAG}/${STRATEGY}/${SAFE_BENCH}"
BENCH_LIST="$ROOT/results/job_hooks/${TAG}_${STRATEGY}_${SAFE_BENCH}.list"

mkdir -p "$(dirname "$BENCH_LIST")" "$RESULT_DIR"
printf '%s\n' "$BENCH" > "$BENCH_LIST"

case "$STRATEGY" in
  nthu_original)
    ROUTER_LABEL="nthu_original"
    NTHU_OPENMP=OFF
    NTHU_CUDA=OFF
    BUILD_DIR="$ROOT/external/nthu-route/build-release-openmp-OFF"
    NTHU_EXTRA_ARGS=""
    ENV_ASSIGNMENTS=()
    ;;
  nthu_openmp_t4)
    ROUTER_LABEL="nthu_openmp_t4"
    NTHU_OPENMP=ON
    NTHU_CUDA=OFF
    BUILD_DIR="$ROOT/external/nthu-route/build-release-openmp-ON"
    NTHU_EXTRA_ARGS=""
    ENV_ASSIGNMENTS=(OMP_NUM_THREADS=4)
    ;;
  nthu_fast_layer)
    ROUTER_LABEL="nthu_fast_layer"
    NTHU_OPENMP=OFF
    NTHU_CUDA=OFF
    BUILD_DIR="$ROOT/external/nthu-route/build-release-openmp-OFF"
    NTHU_EXTRA_ARGS="--p2-init-box-size=5 --p2-box-expand-size=5"
    ENV_ASSIGNMENTS=(NTHU_FAST_GREEDY_LAYER=1)
    ;;
  nthu_p2p3_budget)
    ROUTER_LABEL="nthu_p2p3_budget"
    NTHU_OPENMP=OFF
    NTHU_CUDA=OFF
    BUILD_DIR="$ROOT/external/nthu-route/build-release-openmp-OFF"
    NTHU_EXTRA_ARGS="--p2-init-box-size=5 --p2-box-expand-size=5 --p2-max-iteration=6 --overflow-threshold=1800 --p3-init-box-size=66 --p3-box-expand-size=122"
    ENV_ASSIGNMENTS=(NTHU_FAST_GREEDY_LAYER=1)
    ;;
  nthu_cuda_score)
    ROUTER_LABEL="nthu_cuda_score"
    NTHU_OPENMP=OFF
    NTHU_CUDA=ON
    BUILD_DIR="$ROOT/external/nthu-route/build-release-openmp-OFF-cuda-ON"
    NTHU_EXTRA_ARGS="--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=300000 --p2-max-iteration=4 --p3-max-iteration=8 --p3-init-box-size=35 --p3-box-expand-size=50"
    ENV_ASSIGNMENTS=(
      NTHU_FAST_GREEDY_LAYER=1
      NTHU_DOGLEG_FASTPATH=1
      NTHU_DOGLEG_MAX_EXTRA=0
      NTHU_DOGLEG_MIN_SCORE=1
      NTHU_DOGLEG_STEP=8
      NTHU_RANGE_SKIP_REMAINDER=1
      NTHU_CUDA_COSTED_MAZE_FASTPATH=1
      NTHU_CUDA_MAZE_MAX_AREA=256
      NTHU_CUDA_MAZE_MIN_OVERFLOW_SCORE=42
    )
    ;;
  nthu_edgecount_post)
    ROUTER_LABEL="nthu_edgecount_post"
    NTHU_OPENMP=OFF
    NTHU_CUDA=ON
    BUILD_DIR="$ROOT/external/nthu-route/build-release-openmp-OFF-cuda-ON-post-hot-sort"
    NTHU_EXTRA_ARGS="--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=10000 --p2-max-iteration=5 --p3-max-iteration=2 --p3-init-box-size=54 --p3-box-expand-size=88"
    ENV_ASSIGNMENTS=(
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
    ;;
  nctu_default)
    ROUTER_LABEL="nctu"
    PARAM="$ROOT/external/nctu-gr/Parameter_Files/RegularDefault.set"
    ;;
  nctu_tuned_wl50_m20)
    ROUTER_LABEL="nctu"
    PARAM="$ROOT/results/job_hooks/nctu_wl50_p2m2_maze20_greedy.set"
    ;;
  *)
    echo "unknown STRATEGY=$STRATEGY" >&2
    exit 2
    ;;
esac

if [[ "$STRATEGY" == nctu_* ]]; then
  ROUTER_LABEL="$ROUTER_LABEL" \
  RESULT_DIR="$RESULT_DIR" \
  BENCH_LIST="$BENCH_LIST" \
  PARAM="$PARAM" \
  EVALUATOR="${EVALUATOR:-lab2}" \
    bash scripts/run_nctugr_ispd08.sh
else
  env "${ENV_ASSIGNMENTS[@]}" \
    ROUTER_LABEL="$ROUTER_LABEL" \
    RESULT_DIR="$RESULT_DIR" \
    BENCH_LIST="$BENCH_LIST" \
    EVALUATOR="${EVALUATOR:-lab2}" \
    OMP_NUM_THREADS="${OMP_NUM_THREADS:-4}" \
    NTHU_OPENMP="$NTHU_OPENMP" \
    NTHU_CUDA="$NTHU_CUDA" \
    JOBS="${JOBS:-4}" \
    BUILD_DIR="$BUILD_DIR" \
    SKIP_BUILD="${SKIP_BUILD:-1}" \
    NTHU_EXTRA_ARGS="$NTHU_EXTRA_ARGS" \
      bash scripts/run_nthu_ispd08.sh
fi
