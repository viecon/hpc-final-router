#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

RESULT_ROOT=${RESULT_ROOT:-"$ROOT/results/vm_cuda_utilization/$(date -u +%Y%m%dT%H%M%SZ)"}
RUN_INDEX=${RUN_INDEX:-"$ROOT/results/vm_cuda_utilization/index.csv"}
BENCH_DIR=${BENCH_DIR:-"$ROOT/benchmarks/ispd08"}
NTHU_DIR=${NTHU_DIR:-"$ROOT/external/nthu-route"}
BUILD_DIR=${BUILD_DIR:-"$NTHU_DIR/build-release-vm-cuda-util"}
EVALUATOR=${EVALUATOR:-lab2}
VERIFIER=${VERIFIER:-"$ROOT/external/lab2-checker/verifier.py"}
JOBS=${JOBS:-4}
SAMPLE_INTERVAL=${SAMPLE_INTERVAL:-1}
GPU0=${GPU0:-0}
GPU1=${GPU1:-1}
DUAL_VISIBLE_DEVICES=${DUAL_VISIBLE_DEVICES:-"$GPU0,$GPU1"}
RUN_SCENARIOS=${RUN_SCENARIOS:-"single_costed dual_visible_costed single_preselect dual_multigpu_preselect dual_parallel_costed"}
BENCHES=${BENCHES:-"adaptec3.dragon70.3d.30.50.90.gr"}
DUAL_PARALLEL_BENCHES=${DUAL_PARALLEL_BENCHES:-"adaptec3.dragon70.3d.30.50.90.gr newblue2.fastplace90.3d.50.20.100.gr"}
NTHU_EXTRA_ARGS=${NTHU_EXTRA_ARGS:-"--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=300000 --p2-max-iteration=4 --p3-max-iteration=8 --p3-init-box-size=35 --p3-box-expand-size=50"}

mkdir -p "$RESULT_ROOT" "$(dirname "$RUN_INDEX")"
SUMMARY="$RESULT_ROOT/summary.csv"
GPU_SUMMARY="$RESULT_ROOT/gpu_summary.csv"
PROFILE_BREAKDOWN="$RESULT_ROOT/profile_breakdown.csv"
RUN_ID=$(basename "$RESULT_ROOT")
STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

read -r -a scenarios <<< "${RUN_SCENARIOS//,/ }"
read -r -a benches <<< "${BENCHES//,/ }"
read -r -a dual_parallel_benches <<< "${DUAL_PARALLEL_BENCHES//,/ }"
read -r -a nthu_extra_args <<< "$NTHU_EXTRA_ARGS"

write_environment() {
  {
    echo "result_root=$RESULT_ROOT"
    echo "run_id=$RUN_ID"
    echo "started_at=$STARTED_AT"
    echo "bench_dir=$BENCH_DIR"
    echo "benches=$BENCHES"
    echo "dual_parallel_benches=$DUAL_PARALLEL_BENCHES"
    echo "run_scenarios=$RUN_SCENARIOS"
    echo "gpu0=$GPU0"
    echo "gpu1=$GPU1"
    echo "dual_visible_devices=$DUAL_VISIBLE_DEVICES"
    echo "nthu_dir=$NTHU_DIR"
    echo "build_dir=$BUILD_DIR"
    echo "nthu_extra_args=$NTHU_EXTRA_ARGS"
    echo "sample_interval=$SAMPLE_INTERVAL"
    echo "git_head=$(git rev-parse --short HEAD 2>/dev/null || true)"
    echo
    echo "== git =="
    git branch --show-current || true
    git log -1 --oneline --decorate || true
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
    cmake --version || true
    ninja --version || true
  } > "$RESULT_ROOT/environment.txt"
}

write_strategy_index() {
  cat > "$RESULT_ROOT/strategy_index.csv" <<'EOF'
scenario,kind,visible_devices,description
single_costed,single_gpu_latency,GPU0,One NTHU route sees one GPU and uses CUDA costed-maze fastpath.
dual_visible_costed,single_process_dual_visible,GPU0+GPU1,One NTHU route sees two GPUs; this checks whether current code naturally uses both.
single_preselect,single_gpu_latency,GPU0,One NTHU route sees one GPU and enables CUDA dogleg preselect.
dual_multigpu_preselect,single_process_explicit_multigpu,GPU0+GPU1,One NTHU route sees two GPUs and enables opt-in dogleg preselect input splitting.
dual_parallel_costed,dual_gpu_throughput,GPU0/GPU1,Two independent NTHU routes run concurrently, one pinned to each GPU; throughput only.
EOF
}

resolve_bench() {
  local bench=$1
  if [[ "$bench" = /* ]]; then
    printf "%s" "$bench"
  else
    printf "%s/%s" "$BENCH_DIR" "$bench"
  fi
}

visible_for_scenario() {
  local scenario=$1
  case "$scenario" in
    single_costed|single_preselect)
      printf "%s" "$GPU0"
      ;;
    dual_visible_costed|dual_multigpu_preselect)
      printf "%s" "$DUAL_VISIBLE_DEVICES"
      ;;
    *)
      printf "%s" "$GPU0"
      ;;
  esac
}

scenario_env() {
  local scenario=$1
  local visible=$2
  printf "%s\n" \
    "CUDA_VISIBLE_DEVICES=$visible" \
    "NTHU_PROFILE=1" \
    "NTHU_FAST_GREEDY_LAYER=1" \
    "NTHU_DOGLEG_FASTPATH=1" \
    "NTHU_DOGLEG_MAX_EXTRA=0" \
    "NTHU_DOGLEG_MIN_SCORE=1" \
    "NTHU_DOGLEG_STEP=8" \
    "NTHU_RANGE_SKIP_REMAINDER=1" \
    "NTHU_CUDA_COSTED_MAZE_FASTPATH=1" \
    "NTHU_CUDA_MAZE_MAX_AREA=256" \
    "NTHU_CUDA_MAZE_MIN_OVERFLOW_SCORE=42"
  case "$scenario" in
    single_preselect|dual_multigpu_preselect)
      printf "%s\n" \
        "NTHU_CUDA_DOGLEG_PRESELECT=1" \
        "NTHU_CUDA_DOGLEG_MIN_BATCH=1"
      ;;
  esac
  case "$scenario" in
    dual_multigpu_preselect)
      printf "%s\n" \
        "NTHU_CUDA_DOGLEG_MULTI_GPU=1" \
        "NTHU_CUDA_DOGLEG_MULTI_GPU_MIN_INPUTS=1" \
        "NTHU_CUDA_DOGLEG_MULTI_GPU_MAX_DEVICES=2"
      ;;
  esac
}

sample_gpu() {
  local out=$1
  shift
  echo "elapsed_s,timestamp,gpu_index,gpu_util,mem_util,mem_used_mib,power_w" > "$out"
  local start_epoch
  start_epoch=$(date +%s)
  while true; do
    local alive=0
    for pid in "$@"; do
      if kill -0 "$pid" >/dev/null 2>&1; then
        alive=1
        break
      fi
    done
    (( alive == 1 )) || break

    local now elapsed
    now=$(date +%s)
    elapsed=$((now - start_epoch))
    nvidia-smi --query-gpu=timestamp,index,utilization.gpu,utilization.memory,memory.used,power.draw \
      --format=csv,noheader,nounits 2>/dev/null \
      | awk -F, -v elapsed="$elapsed" '{
          for (i = 1; i <= NF; ++i) {
            gsub(/^ +| +$/, "", $i)
          }
          printf "%s,%s,%s,%s,%s,%s,%s\n", elapsed, $1, $2, $3 + 0, $4 + 0, $5 + 0, $6 + 0
        }' >> "$out" || true
    sleep "$SAMPLE_INTERVAL"
  done
}

append_summary_row() {
  local scenario=$1
  local benchmark=$2
  local visible=$3
  local status=$4
  local seconds=$5
  local metric_evaluator=$6
  local total_wirelength=$7
  local total_overflow=$8
  local max_overflow=$9
  local overflowed_nets=${10}
  local overflowed_edges=${11}
  local output=${12}
  local log=${13}
  local samples=${14}
  local visible_csv=${visible//,/;}
  echo "$scenario,$benchmark,$visible_csv,$status,$seconds,$metric_evaluator,$total_wirelength,$total_overflow,$max_overflow,$overflowed_nets,$overflowed_edges,$output,$log,$samples" >> "$SUMMARY"
}

evaluate_output() {
  local bench_path=$1
  local out=$2
  local metrics_json=$3
  local eval_log=$4
  if python3 "$ROOT/scripts/evaluate_route.py" "$bench_path" "$out" \
      --evaluator "$EVALUATOR" \
      --verifier "$VERIFIER" \
      --nthu-dir "$NTHU_DIR" \
      > "$metrics_json" 2> "$eval_log"; then
    python3 - "$metrics_json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as f:
    data = json.load(f)
print(
    data.get("evaluator", "NA"),
    data.get("total_wirelength", "NA"),
    data.get("total_overflow", "NA"),
    data.get("max_overflow", "NA"),
    data.get("overflowed_nets") if data.get("overflowed_nets") is not None else "NA",
    data.get("overflowed_edges") if data.get("overflowed_edges") is not None else "NA",
)
PY
  else
    echo "NA NA NA NA NA NA"
    return 1
  fi
}

run_one() {
  local scenario=$1
  local bench_path=$2
  local visible=$3
  local label=$4
  local bench_base
  bench_base=$(basename "$bench_path" .gr)
  local out="$RESULT_ROOT/$label.nthu.out"
  local log="$RESULT_ROOT/$label.nthu.log"
  local eval_log="$RESULT_ROOT/$label.nthu.eval"
  local metrics_json="$RESULT_ROOT/$label.nthu.metrics.json"
  local samples="$RESULT_ROOT/$label.gpu_samples.csv"

  local start end seconds status
  start=$(python3 - <<'PY'
import time
print(time.time())
PY
)
  status=ok
  mapfile -t env_args < <(scenario_env "$scenario" "$visible")
  (
    cd "$BUILD_DIR"
    exec env "${env_args[@]}" ./NthuRoute "${nthu_extra_args[@]}" --input="$bench_path" --output="$out"
  ) > "$log" 2>&1 &
  local router_pid=$!
  sample_gpu "$samples" "$router_pid" &
  local sampler_pid=$!
  wait "$router_pid" || status=fail
  wait "$sampler_pid" || true
  end=$(python3 - <<'PY'
import time
print(time.time())
PY
)
  seconds=$(python3 - "$start" "$end" <<'PY'
import sys
print(f"{float(sys.argv[2]) - float(sys.argv[1]):.6f}")
PY
)

  local metric_evaluator total_wirelength total_overflow max_overflow overflowed_nets overflowed_edges
  metric_evaluator=NA
  total_wirelength=NA
  total_overflow=NA
  max_overflow=NA
  overflowed_nets=NA
  overflowed_edges=NA
  if [[ "$status" == ok ]]; then
    read -r metric_evaluator total_wirelength total_overflow max_overflow overflowed_nets overflowed_edges < <(
      evaluate_output "$bench_path" "$out" "$metrics_json" "$eval_log"
    ) || status=eval_fail
  fi
  append_summary_row "$scenario" "$bench_base" "$visible" "$status" "$seconds" \
    "$metric_evaluator" "${total_wirelength:-NA}" "${total_overflow:-NA}" \
    "${max_overflow:-NA}" "${overflowed_nets:-NA}" "${overflowed_edges:-NA}" \
    "$out" "$log" "$samples"
}

run_dual_parallel() {
  local scenario=dual_parallel_costed
  local bench_a=${dual_parallel_benches[0]:-}
  local bench_b=${dual_parallel_benches[1]:-}
  [[ -n "$bench_a" && -n "$bench_b" ]] || return 0
  local bench_a_path bench_b_path
  bench_a_path=$(resolve_bench "$bench_a")
  bench_b_path=$(resolve_bench "$bench_b")
  [[ -f "$bench_a_path" && -f "$bench_b_path" ]] || return 0

  local bench_a_base bench_b_base
  bench_a_base=$(basename "$bench_a_path" .gr)
  bench_b_base=$(basename "$bench_b_path" .gr)
  local label_a="${scenario}_${bench_a_base}_gpu${GPU0}"
  local label_b="${scenario}_${bench_b_base}_gpu${GPU1}"
  local group_label="${scenario}_${bench_a_base}_${bench_b_base}"
  local samples="$RESULT_ROOT/$group_label.gpu_samples.csv"

  local out_a="$RESULT_ROOT/$label_a.nthu.out"
  local out_b="$RESULT_ROOT/$label_b.nthu.out"
  local log_a="$RESULT_ROOT/$label_a.nthu.log"
  local log_b="$RESULT_ROOT/$label_b.nthu.log"

  local start end seconds status_a status_b
  start=$(python3 - <<'PY'
import time
print(time.time())
PY
)
  status_a=ok
  status_b=ok

  mapfile -t env_a < <(scenario_env "single_costed" "$GPU0")
  mapfile -t env_b < <(scenario_env "single_costed" "$GPU1")
  (
    cd "$BUILD_DIR"
    exec env "${env_a[@]}" ./NthuRoute "${nthu_extra_args[@]}" --input="$bench_a_path" --output="$out_a"
  ) > "$log_a" 2>&1 &
  local pid_a=$!
  (
    cd "$BUILD_DIR"
    exec env "${env_b[@]}" ./NthuRoute "${nthu_extra_args[@]}" --input="$bench_b_path" --output="$out_b"
  ) > "$log_b" 2>&1 &
  local pid_b=$!

  sample_gpu "$samples" "$pid_a" "$pid_b" &
  local sampler_pid=$!
  wait "$pid_a" || status_a=fail
  wait "$pid_b" || status_b=fail
  wait "$sampler_pid" || true
  end=$(python3 - <<'PY'
import time
print(time.time())
PY
)
  seconds=$(python3 - "$start" "$end" <<'PY'
import sys
print(f"{float(sys.argv[2]) - float(sys.argv[1]):.6f}")
PY
)

  local eval_log metrics_json metric_evaluator total_wirelength total_overflow max_overflow overflowed_nets overflowed_edges
  eval_log="$RESULT_ROOT/$label_a.nthu.eval"
  metrics_json="$RESULT_ROOT/$label_a.nthu.metrics.json"
  metric_evaluator=NA
  total_wirelength=NA
  total_overflow=NA
  max_overflow=NA
  overflowed_nets=NA
  overflowed_edges=NA
  if [[ "$status_a" == ok ]]; then
    read -r metric_evaluator total_wirelength total_overflow max_overflow overflowed_nets overflowed_edges < <(
      evaluate_output "$bench_a_path" "$out_a" "$metrics_json" "$eval_log"
    ) || status_a=eval_fail
  fi
  append_summary_row "$scenario" "$bench_a_base" "$GPU0" "$status_a" "$seconds" \
    "$metric_evaluator" "${total_wirelength:-NA}" "${total_overflow:-NA}" \
    "${max_overflow:-NA}" "${overflowed_nets:-NA}" "${overflowed_edges:-NA}" \
    "$out_a" "$log_a" "$samples"

  eval_log="$RESULT_ROOT/$label_b.nthu.eval"
  metrics_json="$RESULT_ROOT/$label_b.nthu.metrics.json"
  metric_evaluator=NA
  total_wirelength=NA
  total_overflow=NA
  max_overflow=NA
  overflowed_nets=NA
  overflowed_edges=NA
  if [[ "$status_b" == ok ]]; then
    read -r metric_evaluator total_wirelength total_overflow max_overflow overflowed_nets overflowed_edges < <(
      evaluate_output "$bench_b_path" "$out_b" "$metrics_json" "$eval_log"
    ) || status_b=eval_fail
  fi
  append_summary_row "$scenario" "$bench_b_base" "$GPU1" "$status_b" "$seconds" \
    "$metric_evaluator" "${total_wirelength:-NA}" "${total_overflow:-NA}" \
    "${max_overflow:-NA}" "${overflowed_nets:-NA}" "${overflowed_edges:-NA}" \
    "$out_b" "$log_b" "$samples"
}

write_environment
write_strategy_index

bash scripts/fetch_ispd08.sh

cmake -S "$NTHU_DIR" -B "$BUILD_DIR" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DNTHU_ROUTE_ENABLE_OPENMP=OFF \
  -DNTHU_ROUTE_ENABLE_CUDA=ON
cmake --build "$BUILD_DIR" -j "$JOBS"

echo "scenario,benchmark,visible_devices,status,seconds,evaluator,total_wirelength,total_overflow,max_overflow,overflowed_nets,overflowed_edges,output,log,samples" > "$SUMMARY"

for scenario in "${scenarios[@]}"; do
  [[ -n "$scenario" ]] || continue
  if [[ "$scenario" == "dual_parallel_costed" ]]; then
    run_dual_parallel
    continue
  fi
  visible=$(visible_for_scenario "$scenario")
  for bench in "${benches[@]}"; do
    bench_path=$(resolve_bench "$bench")
    [[ -f "$bench_path" ]] || {
      echo "missing benchmark: $bench_path" >&2
      continue
    }
    bench_base=$(basename "$bench_path" .gr)
    label="${scenario}_${bench_base}"
    run_one "$scenario" "$bench_path" "$visible" "$label"
  done
done

python3 - "$SUMMARY" "$GPU_SUMMARY" "$PROFILE_BREAKDOWN" <<'PY'
import csv
import re
import sys
from pathlib import Path

summary = Path(sys.argv[1])
gpu_summary = Path(sys.argv[2])
profile_out = Path(sys.argv[3])

summary_rows = list(csv.DictReader(summary.open(newline="")))

gpu_rows = []
seen = set()
for row in summary_rows:
    key = (row["scenario"], row["benchmark"], row["samples"])
    if key in seen:
        continue
    seen.add(key)
    sample_path = Path(row["samples"])
    samples = []
    if sample_path.exists():
        with sample_path.open(newline="") as f:
            samples = list(csv.DictReader(f))
    by_gpu = {}
    for sample in samples:
        by_gpu.setdefault(sample["gpu_index"], []).append(sample)
    for gpu_index, rows in sorted(by_gpu.items(), key=lambda item: int(item[0])):
        def values(name):
            out = []
            for item in rows:
                try:
                    out.append(float(item[name]))
                except Exception:
                    pass
            return out
        gpu_util = values("gpu_util")
        mem_util = values("mem_util")
        mem_used = values("mem_used_mib")
        power = values("power_w")
        gpu_rows.append({
            "scenario": row["scenario"],
            "benchmark": row["benchmark"],
            "gpu_index": gpu_index,
            "sample_count": len(rows),
            "avg_gpu_util": f"{(sum(gpu_util) / len(gpu_util) if gpu_util else 0):.3f}",
            "max_gpu_util": f"{(max(gpu_util) if gpu_util else 0):.3f}",
            "avg_mem_util": f"{(sum(mem_util) / len(mem_util) if mem_util else 0):.3f}",
            "max_mem_util": f"{(max(mem_util) if mem_util else 0):.3f}",
            "avg_mem_used_mib": f"{(sum(mem_used) / len(mem_used) if mem_used else 0):.3f}",
            "max_mem_used_mib": f"{(max(mem_used) if mem_used else 0):.3f}",
            "avg_power_w": f"{(sum(power) / len(power) if power else 0):.3f}",
            "max_power_w": f"{(max(power) if power else 0):.3f}",
        })

with gpu_summary.open("w", newline="") as f:
    fields = [
        "scenario", "benchmark", "gpu_index", "sample_count",
        "avg_gpu_util", "max_gpu_util", "avg_mem_util", "max_mem_util",
        "avg_mem_used_mib", "max_mem_used_mib", "avg_power_w", "max_power_w",
    ]
    writer = csv.DictWriter(f, fieldnames=fields)
    writer.writeheader()
    writer.writerows(gpu_rows)

profile_rows = []
for row in summary_rows:
    log = Path(row["log"])
    pre = route = overflow = wire = specify = 0.0
    range_values = {
        "cuda_batches": 0,
        "cuda_skipped_small_batches": 0,
        "cuda_inputs": 0,
        "cuda_valid_choices": 0,
        "cuda_maze_attempts": 0,
        "cuda_maze_success": 0,
        "cuda_maze_area_skips": 0,
        "cuda_maze_score_skips": 0,
        "cuda_maze_call_limit_skips": 0,
        "cuda_prepare_ms": 0.0,
        "cuda_maze_ms": 0.0,
        "reroute_ms": 0.0,
        "maze_ms": 0.0,
    }
    iter_count = 0
    range_profile_lines = 0
    if log.exists():
        for line in log.read_text(errors="replace").splitlines():
            m = re.search(r"profile iter=.*pre_eval_ms=([0-9.]+) route_all_ms=([0-9.]+) overflow_ms=([0-9.]+) wirelength_ms=([0-9.]+)", line)
            if m:
                iter_count += 1
                pre += float(m.group(1))
                route += float(m.group(2))
                overflow += float(m.group(3))
                wire += float(m.group(4))
            m = re.search(r"profile route_all .*specify_all_range_ms=([0-9.]+)", line)
            if m:
                specify += float(m.group(1))
            if "profile range " in line:
                range_profile_lines += 1
                for key in range_values:
                    m = re.search(rf"{key}=([0-9.]+)", line)
                    if m:
                        if key.endswith("_ms"):
                            range_values[key] += float(m.group(1))
                        else:
                            range_values[key] += int(float(m.group(1)))
    denom = pre + route + overflow + wire
    out = {
        "scenario": row["scenario"],
        "benchmark": row["benchmark"],
        "iter_count": iter_count,
        "pre_eval_ms": f"{pre:.3f}",
        "route_all_ms": f"{route:.3f}",
        "overflow_ms": f"{overflow:.3f}",
        "wirelength_ms": f"{wire:.3f}",
        "route_all_share": f"{(route / denom if denom else 0):.6f}",
        "specify_all_range_ms": f"{specify:.3f}",
        "specify_share_of_route_all": f"{(specify / route if route else 0):.6f}",
        "range_profile_lines": range_profile_lines,
    }
    for key, value in range_values.items():
        out[key] = f"{value:.3f}" if key.endswith("_ms") else value
    profile_rows.append(out)

with profile_out.open("w", newline="") as f:
    fields = [
        "scenario", "benchmark", "iter_count", "pre_eval_ms", "route_all_ms",
        "overflow_ms", "wirelength_ms", "route_all_share",
        "specify_all_range_ms", "specify_share_of_route_all",
        "range_profile_lines", "cuda_batches", "cuda_skipped_small_batches",
        "cuda_inputs", "cuda_valid_choices", "cuda_maze_attempts",
        "cuda_maze_success", "cuda_maze_area_skips", "cuda_maze_score_skips",
        "cuda_maze_call_limit_skips", "cuda_prepare_ms", "cuda_maze_ms",
        "reroute_ms", "maze_ms",
    ]
    writer = csv.DictWriter(f, fieldnames=fields)
    writer.writeheader()
    writer.writerows(profile_rows)

print(f"wrote {summary}")
print(f"wrote {gpu_summary}")
print(f"wrote {profile_out}")
PY

ENDED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
RUN_INDEX_PATH="$RUN_INDEX" \
RUN_ID_VALUE="$RUN_ID" \
STARTED_AT_VALUE="$STARTED_AT" \
ENDED_AT_VALUE="$ENDED_AT" \
RESULT_ROOT_VALUE="$RESULT_ROOT" \
GIT_BRANCH_VALUE="$(git branch --show-current || true)" \
GIT_HEAD_VALUE="$(git rev-parse --short HEAD || true)" \
RUN_SCENARIOS_VALUE="$RUN_SCENARIOS" \
BENCHES_VALUE="$BENCHES" \
DUAL_PARALLEL_BENCHES_VALUE="$DUAL_PARALLEL_BENCHES" \
python3 - <<'PY'
import csv
import os

path = os.environ["RUN_INDEX_PATH"]
fields = [
    "run_id", "started_at", "ended_at", "result_root", "git_branch", "git_head",
    "run_scenarios", "benches", "dual_parallel_benches",
]
row = {
    "run_id": os.environ["RUN_ID_VALUE"],
    "started_at": os.environ["STARTED_AT_VALUE"],
    "ended_at": os.environ["ENDED_AT_VALUE"],
    "result_root": os.environ["RESULT_ROOT_VALUE"],
    "git_branch": os.environ["GIT_BRANCH_VALUE"],
    "git_head": os.environ["GIT_HEAD_VALUE"],
    "run_scenarios": os.environ["RUN_SCENARIOS_VALUE"],
    "benches": os.environ["BENCHES_VALUE"],
    "dual_parallel_benches": os.environ["DUAL_PARALLEL_BENCHES_VALUE"],
}
exists = os.path.exists(path)
with open(path, "a", newline="", encoding="utf-8") as f:
    writer = csv.DictWriter(f, fieldnames=fields)
    if not exists:
        writer.writeheader()
    writer.writerow(row)
PY

echo "wrote $RUN_INDEX"
