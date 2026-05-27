#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

RESULT_TAG=${RESULT_TAG:-nctu_param_sweep_a3}
BENCH_PATTERN=${BENCH_PATTERN:-adaptec3*.gr}
PARAM_DIR=${PARAM_DIR:-"$ROOT/results/job_hooks/${RESULT_TAG}_params"}
OUT=${OUT:-"$ROOT/results/${RESULT_TAG}_summary.csv"}
mkdir -p "$PARAM_DIR" "$(dirname "$OUT")"

write_param() {
  local path=$1
  local wl=$2
  local pattern=$3
  local mono=$4
  local maze=$5
  local post=$6
  local la=$7
  local avoid=${8:-1}
  cat > "$path" <<EOF
Via_Cost = 1
Wirelength_Optimization_Level = $wl
Output_Routing_Result = Yes
Output_Overflow_Information = No
Pin_Blockage_Factor = 0
Placement_Iteration = 2
Rounds_Per_Iteration = 4
Local_Detailed_Placement = 4
Avoiding_Blockage_Factor = $avoid
Blockage_Expanding = 0
Pattern_Routing_Iteration = $pattern
Monotonic_Routing_Iteration = $mono
Maze_Routing_Iteration = $maze
Maze_Routing_Timeout = -1
Post_Routing_Iteration = $post
Layer_Assignment_Algorithm = $la
3D_Optimization_Iteration = 0
EOF
}

write_param "$PARAM_DIR/wl10_m1_greedy.set" 10 1 1 1 1 1 1
write_param "$PARAM_DIR/wl10_m1_dp.set" 10 1 1 1 1 2 1
write_param "$PARAM_DIR/wl20_m5_greedy.set" 20 1 1 5 1 1 1
write_param "$PARAM_DIR/wl20_m10_dp.set" 20 1 1 10 1 2 1
write_param "$PARAM_DIR/wl50_m20_greedy.set" 50 2 2 20 1 1 3.5
write_param "$PARAM_DIR/wl50_m20_dp.set" 50 2 2 20 1 2 3.5

echo "router,benchmark,status,seconds,evaluator,total_wirelength,total_overflow,max_overflow,overflowed_nets,overflowed_edges,output" > "$OUT"

for param in "$PARAM_DIR"/*.set; do
  tag=$(basename "$param" .set)
  result_dir="$ROOT/results/${RESULT_TAG}_${tag}"
  PARAM="$param" RESULT_DIR="$result_dir" BENCH_PATTERN="$BENCH_PATTERN" EVALUATOR=lab2 PYTHON="apptainer exec router.sif python3" \
    bash scripts/run_nctugr_ispd08.sh
  awk -F, -v tag="$tag" 'NR == 1 { next } { $1 = "nctu_" tag; print }' OFS=, "$result_dir/summary.csv" >> "$OUT"
done

bash scripts/refresh_indexes.sh || true
echo "wrote $OUT"
