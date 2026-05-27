#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

RESULT_TAG=${RESULT_TAG:-nctu_a3_greedy_maze_refine}
PARAM_DIR=${PARAM_DIR:-"$ROOT/results/job_hooks/${RESULT_TAG}_params"}
OUT=${OUT:-"$ROOT/results/${RESULT_TAG}_summary.csv"}
mkdir -p "$PARAM_DIR" "$(dirname "$OUT")"

write_param() {
  local path=$1
  local wl=$2
  local pattern=$3
  local mono=$4
  local maze=$5
  local avoid=$6
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
Post_Routing_Iteration = 1
Layer_Assignment_Algorithm = 1
3D_Optimization_Iteration = 0
EOF
}

for maze in 6 7 8 10 12; do
  write_param "$PARAM_DIR/wl20_p1m1_maze${maze}_greedy.set" 20 1 1 "$maze" 1
done
for maze in 8 10 12 15; do
  write_param "$PARAM_DIR/wl50_p2m2_maze${maze}_greedy.set" 50 2 2 "$maze" 3.5
done

echo "router,benchmark,status,seconds,evaluator,total_wirelength,total_overflow,max_overflow,overflowed_nets,overflowed_edges,output" > "$OUT"

for param in "$PARAM_DIR"/*.set; do
  tag=$(basename "$param" .set)
  result_dir="$ROOT/results/${RESULT_TAG}_${tag}"
  PARAM="$param" RESULT_DIR="$result_dir" BENCH_PATTERN="adaptec3*.gr" EVALUATOR=lab2 PYTHON="apptainer exec router.sif python3" \
    bash scripts/run_nctugr_ispd08.sh
  awk -F, -v tag="$tag" 'NR == 1 { next } { $1 = "nctu_" tag; print }' OFS=, "$result_dir/summary.csv" >> "$OUT"
done

bash scripts/refresh_indexes.sh || true
echo "wrote $OUT"
