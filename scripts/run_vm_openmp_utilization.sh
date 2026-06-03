#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

RESULT_ROOT=${RESULT_ROOT:-"$ROOT/results/vm_openmp_utilization/$(date -u +%Y%m%dT%H%M%SZ)"}
BENCH_DIR=${BENCH_DIR:-"$ROOT/benchmarks/ispd08"}
BENCHES=${BENCHES:-"newblue2.fastplace90.3d.50.20.100.gr"}
THREADS_LIST=${THREADS_LIST:-"1 4 8 12"}
NTHU_DIR=${NTHU_DIR:-"$ROOT/external/nthu-route"}
BUILD_DIR=${BUILD_DIR:-"$NTHU_DIR/build-release-vm-openmp-util"}
EVALUATOR=${EVALUATOR:-lab2}
VERIFIER=${VERIFIER:-"$ROOT/external/lab2-checker/verifier.py"}
SAMPLE_INTERVAL=${SAMPLE_INTERVAL:-1}
NTHU_EXTRA_ARGS=${NTHU_EXTRA_ARGS:-}
OPENMP_PROC_BIND=${OPENMP_PROC_BIND:-close}
OPENMP_PLACES=${OPENMP_PLACES:-cores}

mkdir -p "$RESULT_ROOT"
read -r -a benches <<< "${BENCHES//,/ }"
read -r -a threads_values <<< "${THREADS_LIST//,/ }"
read -r -a nthu_extra_args <<< "$NTHU_EXTRA_ARGS"

{
  echo "result_root=$RESULT_ROOT"
  echo "bench_dir=$BENCH_DIR"
  echo "benches=$BENCHES"
  echo "threads_list=$THREADS_LIST"
  echo "nthu_dir=$NTHU_DIR"
  echo "build_dir=$BUILD_DIR"
  echo "sample_interval=$SAMPLE_INTERVAL"
  echo "openmp_proc_bind=$OPENMP_PROC_BIND"
  echo "openmp_places=$OPENMP_PLACES"
  echo "nthu_extra_args=$NTHU_EXTRA_ARGS"
  echo "git_head=$(git rev-parse --short HEAD 2>/dev/null || true)"
  echo
  lscpu || true
} > "$RESULT_ROOT/environment.txt"

cmake -S "$NTHU_DIR" -B "$BUILD_DIR" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DNTHU_ROUTE_ENABLE_OPENMP=ON \
  -DNTHU_ROUTE_ENABLE_CUDA=OFF
cmake --build "$BUILD_DIR" -j "${BUILD_JOBS:-4}"

SUMMARY="$RESULT_ROOT/summary.csv"
echo "benchmark,threads,status,seconds,avg_process_cpu,max_process_cpu,avg_live_threads,max_live_threads,evaluator,total_wirelength,total_overflow,max_overflow,overflowed_nets,overflowed_edges,output,log,samples" > "$SUMMARY"

sample_process() {
  local pid=$1
  local out=$2
  echo "elapsed_s,process_cpu,live_threads,thread_cpu_sum,max_thread_cpu" > "$out"
  local start_epoch
  start_epoch=$(date +%s)
  while kill -0 "$pid" >/dev/null 2>&1; do
    local now elapsed process_cpu live_threads thread_cpu_sum max_thread_cpu
    now=$(date +%s)
    elapsed=$((now - start_epoch))
    process_cpu=$(ps -p "$pid" -o pcpu= 2>/dev/null | awk '{print $1 + 0}')
    read -r live_threads thread_cpu_sum max_thread_cpu < <(
      ps -L -p "$pid" -o pcpu= 2>/dev/null \
        | awk 'BEGIN{n=0; sum=0; max=0} {v=$1+0; n++; sum+=v; if(v>max) max=v} END{printf "%d %.3f %.3f\n", n, sum, max}'
    )
    printf "%s,%s,%s,%s,%s\n" "$elapsed" "${process_cpu:-0}" "${live_threads:-0}" "${thread_cpu_sum:-0}" "${max_thread_cpu:-0}" >> "$out"
    sleep "$SAMPLE_INTERVAL"
  done
}

summarize_samples() {
  local sample_csv=$1
  python3 - "$sample_csv" <<'PY'
import csv
import sys

rows = []
try:
    with open(sys.argv[1], newline="") as f:
        rows = list(csv.DictReader(f))
except FileNotFoundError:
    rows = []
if not rows:
    print("0,0,0,0")
    raise SystemExit
def vals(name):
    out = []
    for row in rows:
        try:
            out.append(float(row[name]))
        except Exception:
            pass
    return out
pcpu = vals("process_cpu")
threads = vals("live_threads")
print(
    f"{(sum(pcpu)/len(pcpu) if pcpu else 0):.3f},"
    f"{(max(pcpu) if pcpu else 0):.3f},"
    f"{(sum(threads)/len(threads) if threads else 0):.3f},"
    f"{(max(threads) if threads else 0):.0f}"
)
PY
}

for bench_name in "${benches[@]}"; do
  bench_path="$bench_name"
  if [[ "$bench_path" != /* ]]; then
    bench_path="$BENCH_DIR/$bench_name"
  fi
  [[ -f "$bench_path" ]] || {
    echo "missing benchmark: $bench_path" >&2
    continue
  }
  bench_base=$(basename "$bench_path" .gr)
  for threads in "${threads_values[@]}"; do
    case "$threads" in
      ''|*[!0-9]*) echo "skip invalid thread count: $threads" >&2; continue ;;
    esac
    label="${bench_base}_t${threads}"
    out="$RESULT_ROOT/$label.nthu.out"
    log="$RESULT_ROOT/$label.nthu.log"
    eval_log="$RESULT_ROOT/$label.nthu.eval"
    metrics_json="$RESULT_ROOT/$label.nthu.metrics.json"
    samples="$RESULT_ROOT/$label.samples.csv"

    start=$(python3 - <<'PY'
import time
print(time.time())
PY
)
    status=ok
    (
      cd "$BUILD_DIR"
      exec env \
        OMP_NUM_THREADS="$threads" \
        OMP_PROC_BIND="$OPENMP_PROC_BIND" \
        OMP_PLACES="$OPENMP_PLACES" \
        NTHU_PROFILE=1 \
        ./NthuRoute "${nthu_extra_args[@]}" --input="$bench_path" --output="$out"
    ) > "$log" 2>&1 &
    router_pid=$!
    sample_process "$router_pid" "$samples" &
    sampler_pid=$!
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

    metric_evaluator=NA
    total_wirelength=NA
    total_overflow=NA
    max_overflow=NA
    overflowed_nets=NA
    overflowed_edges=NA
    if [[ "$status" == ok ]]; then
      if python3 "$ROOT/scripts/evaluate_route.py" "$bench_path" "$out" \
          --evaluator "$EVALUATOR" \
          --verifier "$VERIFIER" \
          --nthu-dir "$NTHU_DIR" \
          > "$metrics_json" 2> "$eval_log"; then
        read -r metric_evaluator total_wirelength total_overflow max_overflow overflowed_nets overflowed_edges < <(
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
        )
      else
        status=eval_fail
      fi
    fi
    IFS=, read -r avg_cpu max_cpu avg_threads max_threads < <(summarize_samples "$samples")
    echo "$bench_base,$threads,$status,$seconds,$avg_cpu,$max_cpu,$avg_threads,$max_threads,$metric_evaluator,${total_wirelength:-NA},${total_overflow:-NA},${max_overflow:-NA},${overflowed_nets:-NA},${overflowed_edges:-NA},$out,$log,$samples" >> "$SUMMARY"
  done
done

python3 - "$SUMMARY" "$RESULT_ROOT/profile_breakdown.csv" <<'PY'
import csv
import re
import sys
from pathlib import Path

summary = Path(sys.argv[1])
out = Path(sys.argv[2])
fields = [
    "benchmark",
    "threads",
    "iter_count",
    "pre_eval_ms",
    "route_all_ms",
    "overflow_ms",
    "wirelength_ms",
    "route_all_share",
    "specify_all_range_ms",
    "specify_share_of_route_all",
]

rows = []
for row in csv.DictReader(summary.open(newline="")):
    log = Path(row["log"])
    pre = route = overflow = wire = specify = 0.0
    iters = 0
    if log.exists():
        for line in log.read_text(errors="replace").splitlines():
            m = re.search(r"profile iter=.*pre_eval_ms=([0-9.]+) route_all_ms=([0-9.]+) overflow_ms=([0-9.]+) wirelength_ms=([0-9.]+)", line)
            if m:
                iters += 1
                pre += float(m.group(1))
                route += float(m.group(2))
                overflow += float(m.group(3))
                wire += float(m.group(4))
            m = re.search(r"profile route_all .*specify_all_range_ms=([0-9.]+)", line)
            if m:
                specify += float(m.group(1))
    denom = pre + route + overflow + wire
    rows.append({
        "benchmark": row["benchmark"],
        "threads": row["threads"],
        "iter_count": iters,
        "pre_eval_ms": f"{pre:.3f}",
        "route_all_ms": f"{route:.3f}",
        "overflow_ms": f"{overflow:.3f}",
        "wirelength_ms": f"{wire:.3f}",
        "route_all_share": f"{(route / denom if denom else 0):.6f}",
        "specify_all_range_ms": f"{specify:.3f}",
        "specify_share_of_route_all": f"{(specify / route if route else 0):.6f}",
    })
with out.open("w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=fields)
    writer.writeheader()
    writer.writerows(rows)
print(f"wrote {summary}")
print(f"wrote {out}")
PY
