#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$ROOT"

TAG=${TAG:-vm_wl_guard}
RUN_ID=${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}
RESULT_ROOT=${RESULT_ROOT:-"$ROOT/results/$TAG/runs/$RUN_ID"}
RUN_INDEX=${RUN_INDEX:-"$ROOT/results/$TAG/index.csv"}
BASELINE_CSV=${BASELINE_CSV:-"$ROOT/results/vm_real_matrix/summary_live.csv"}
BENCH_SET=${BENCH_SET:-legal7}
MAX_ROUTER_CORES=${MAX_ROUTER_CORES:-12}
PARALLEL_BENCH_JOBS=${PARALLEL_BENCH_JOBS:-$MAX_ROUTER_CORES}
JOBS=${JOBS:-$(nproc)}
RUN_VARIANTS=${RUN_VARIANTS:-all}
WL_THRESHOLDS=${WL_THRESHOLDS:-"1.10 1.25 1.50 1.75 2.00"}
RUN_NOTES=${RUN_NOTES:-}

CPU_BUILD="$ROOT/external/nthu-route/build-release-vm-wl-guard-cpu"
BENCH_LIST="$RESULT_ROOT/benchmarks.list"
SUMMARY="$RESULT_ROOT/summary.csv"

LEGAL7_BENCHES=(
  adaptec1.capo70.3d.35.50.90.gr
  adaptec3.dragon70.3d.30.50.90.gr
  adaptec4.aplace60.3d.30.50.90.gr
  adaptec5.mfar50.3d.50.20.100.gr
  bigblue1.capo60.3d.50.10.100.gr
  newblue2.fastplace90.3d.50.20.100.gr
  newblue6.mfar80.3d.60.10.100.gr
)

REQUESTED12_BENCHES=(
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

if [[ -n "${VM_WL_BENCHES:-}" ]]; then
  read -r -a BENCHES <<< "${VM_WL_BENCHES//,/ }"
else
  case "$BENCH_SET" in
    legal7)
      BENCHES=("${LEGAL7_BENCHES[@]}")
      ;;
    requested12|current12)
      BENCHES=("${REQUESTED12_BENCHES[@]}")
      ;;
    *)
      echo "unknown BENCH_SET=$BENCH_SET; use legal7, requested12, or VM_WL_BENCHES" >&2
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
    echo "baseline_csv=$BASELINE_CSV"
    echo "bench_set=$BENCH_SET"
    echo "bench_count=${#BENCHES[@]}"
    echo "run_variants=$RUN_VARIANTS"
    echo "max_router_cores=$MAX_ROUTER_CORES"
    echo "parallel_bench_jobs=$PARALLEL_BENCH_JOBS"
    echo "wl_thresholds=$WL_THRESHOLDS"
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
    cmake --version || true
    ninja --version || true
  } > "$RESULT_ROOT/environment.txt"
}

write_catalog() {
  cat > "$RESULT_ROOT/variant_catalog.csv" <<'EOF'
strategy,kind,description
orig_layer_p2p3_budget,cpu_budget,Original KLAT/DP layer assignment with reduced P2/P3 effort.
orig_layer_p2p3_legal_repair,cpu_repair,Original KLAT/DP layer assignment with conservative repair and edge-count post sort.
orig_layer_edgecount_post_cpu,cpu_frontier,Original KLAT/DP layer assignment with edge-count post-processing budget.
fast_layer_netguided_budget,cpu_layer,Net-guided fast greedy layer assignment with reduced P2/P3 effort.
fast_layer_netguided_repair,cpu_layer_repair,Net-guided fast greedy layer assignment with conservative repair.
EOF
}

variant_enabled() {
  local label=$1
  [[ "$RUN_VARIANTS" == all ]] || [[ " $RUN_VARIANTS " == *" $label "* ]]
}

build_cpu() {
  cmake -S "$ROOT/external/nthu-route" -B "$CPU_BUILD" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DNTHU_ROUTE_ENABLE_OPENMP=OFF \
    -DNTHU_ROUTE_ENABLE_CUDA=OFF
  cmake --build "$CPU_BUILD" -j "$JOBS"
}

run_cpu_variant() {
  local label=$1
  local extra_args=$2
  shift 2
  if ! variant_enabled "$label"; then
    echo "==> $label (skip)"
    return
  fi
  echo "==> $label"
  env "$@" \
    ROUTER_LABEL="$label" \
    NTHU_DIR="$ROOT/external/nthu-route" \
    RESULT_DIR="$RESULT_ROOT/$label" \
    BENCH_LIST="$BENCH_LIST" \
    EVALUATOR=lab2 \
    NTHU_OPENMP=OFF \
    NTHU_CUDA=OFF \
    JOBS="$JOBS" \
    BUILD_DIR="$CPU_BUILD" \
    SKIP_BUILD=1 \
    RESUME_EXISTING=1 \
    PARALLEL_BENCH_JOBS="$PARALLEL_BENCH_JOBS" \
    NTHU_EXTRA_ARGS="$extra_args" \
      bash scripts/run_nthu_ispd08.sh
}

summarize() {
  WL_THRESHOLDS_VALUE="$WL_THRESHOLDS" python3 - "$RESULT_ROOT" "$BASELINE_CSV" "$SUMMARY" <<'PY'
import csv
import os
import sys
from pathlib import Path

result_root = Path(sys.argv[1])
baseline_csv = Path(sys.argv[2])
summary_path = Path(sys.argv[3])
thresholds = [float(x) for x in os.environ["WL_THRESHOLDS_VALUE"].split()]

fields = [
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

def as_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None

def as_int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return None

def is_ok(row):
    return row.get("status") == "ok" and as_float(row.get("seconds")) is not None

def is_legal(row):
    return as_int(row.get("total_overflow")) == 0 and as_int(row.get("max_overflow")) == 0

def normalized(row, strategy):
    out = {field: row.get(field, "") for field in fields}
    out["strategy"] = strategy
    return out

rows = []
original = {}
if baseline_csv.exists():
    with baseline_csv.open(newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            strategy = row.get("strategy", row.get("router", ""))
            if strategy == "true_original":
                item = normalized(row, "true_original")
                original[item["benchmark"]] = item
                rows.append(item)
else:
    print(f"warning: missing baseline {baseline_csv}", file=sys.stderr)

for summary in sorted(result_root.glob("*/summary.csv")):
    strategy = summary.parent.name
    with summary.open(newline="") as f:
        for row in csv.DictReader(f):
            rows.append(normalized(row, strategy))

rows.sort(key=lambda row: (row["benchmark"], row["strategy"]))
with summary_path.open("w", newline="") as f:
    writer = csv.DictWriter(f, fieldnames=["strategy"] + fields)
    writer.writeheader()
    writer.writerows(rows)

candidate_rows = []
by_bench = {}
for row in rows:
    by_bench.setdefault(row["benchmark"], {})[row["strategy"]] = row

for bench, strategy_rows in sorted(by_bench.items()):
    orig = original.get(bench)
    if not orig or not is_ok(orig):
        continue
    orig_seconds = as_float(orig["seconds"])
    orig_wl = as_float(orig["total_wirelength"])
    orig_legal = is_legal(orig)
    for strategy, row in sorted(strategy_rows.items()):
        if strategy == "true_original":
            continue
        seconds = as_float(row.get("seconds"))
        wl = as_float(row.get("total_wirelength"))
        speedup = orig_seconds / seconds if seconds else None
        wl_ratio = wl / orig_wl if wl is not None and orig_wl else None
        legal_guard = (not orig_legal) or is_legal(row)
        candidate_rows.append({
            "benchmark": bench,
            "strategy": strategy,
            "status": row.get("status", ""),
            "seconds": row.get("seconds", ""),
            "speedup": f"{speedup:.6f}" if speedup else "",
            "wirelength": row.get("total_wirelength", ""),
            "wirelength_ratio": f"{wl_ratio:.6f}" if wl_ratio else "",
            "total_overflow": row.get("total_overflow", ""),
            "max_overflow": row.get("max_overflow", ""),
            "original_seconds": f"{orig_seconds:.6f}",
            "original_wirelength": f"{orig_wl:.0f}" if orig_wl is not None else "",
            "original_legal": orig_legal,
            "legal_guard_pass": legal_guard,
        })

candidate_path = result_root / "wl_guard_candidates.csv"
with candidate_path.open("w", newline="") as f:
    fieldnames = [
        "benchmark",
        "strategy",
        "status",
        "seconds",
        "speedup",
        "wirelength",
        "wirelength_ratio",
        "total_overflow",
        "max_overflow",
        "original_seconds",
        "original_wirelength",
        "original_legal",
        "legal_guard_pass",
    ]
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(candidate_rows)

best_rows = []
portfolio_rows = []
for threshold in thresholds:
    total_orig = 0.0
    total_selected = 0.0
    selected_optimized = 0
    worst_wl_ratio = 1.0
    selected_rows = []
    for bench, orig in sorted(original.items()):
        if bench not in by_bench or not is_ok(orig):
            continue
        orig_seconds = as_float(orig["seconds"])
        orig_wl = as_float(orig["total_wirelength"])
        orig_legal = is_legal(orig)
        candidates = []
        for strategy, row in by_bench[bench].items():
            if strategy == "true_original" or not is_ok(row):
                continue
            wl = as_float(row.get("total_wirelength"))
            if wl is None or not orig_wl:
                continue
            if (wl / orig_wl) > threshold:
                continue
            if orig_legal and not is_legal(row):
                continue
            candidates.append(row)
        selected = min(candidates, key=lambda row: as_float(row["seconds"])) if candidates else orig
        selected_strategy = selected["strategy"]
        selected_seconds = as_float(selected["seconds"])
        selected_wl = as_float(selected["total_wirelength"])
        wl_ratio = selected_wl / orig_wl if selected_wl is not None and orig_wl else 1.0
        speedup = orig_seconds / selected_seconds if selected_seconds else 1.0
        total_orig += orig_seconds
        total_selected += selected_seconds
        if selected_strategy != "true_original":
            selected_optimized += 1
        worst_wl_ratio = max(worst_wl_ratio, wl_ratio)
        selected_rows.append({
            "threshold": f"{threshold:.2f}",
            "benchmark": bench,
            "selected_strategy": selected_strategy,
            "original_seconds": f"{orig_seconds:.6f}",
            "selected_seconds": f"{selected_seconds:.6f}",
            "speedup": f"{speedup:.6f}",
            "original_wirelength": f"{orig_wl:.0f}" if orig_wl is not None else "",
            "selected_wirelength": f"{selected_wl:.0f}" if selected_wl is not None else "",
            "wirelength_ratio": f"{wl_ratio:.6f}",
            "selected_overflow": selected.get("total_overflow", ""),
            "selected_max_overflow": selected.get("max_overflow", ""),
        })
    best_rows.extend(selected_rows)
    portfolio_rows.append({
        "threshold": f"{threshold:.2f}",
        "cases": len(selected_rows),
        "optimized_cases": selected_optimized,
        "original_total_seconds": f"{total_orig:.6f}",
        "selected_total_seconds": f"{total_selected:.6f}",
        "portfolio_speedup": f"{(total_orig / total_selected):.6f}" if total_selected else "",
        "worst_wirelength_ratio": f"{worst_wl_ratio:.6f}",
    })

best_path = result_root / "best_by_wl_threshold.csv"
with best_path.open("w", newline="") as f:
    fieldnames = [
        "threshold",
        "benchmark",
        "selected_strategy",
        "original_seconds",
        "selected_seconds",
        "speedup",
        "original_wirelength",
        "selected_wirelength",
        "wirelength_ratio",
        "selected_overflow",
        "selected_max_overflow",
    ]
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(best_rows)

portfolio_path = result_root / "portfolio_by_wl_threshold.csv"
with portfolio_path.open("w", newline="") as f:
    fieldnames = [
        "threshold",
        "cases",
        "optimized_cases",
        "original_total_seconds",
        "selected_total_seconds",
        "portfolio_speedup",
        "worst_wirelength_ratio",
    ]
    writer = csv.DictWriter(f, fieldnames=fieldnames)
    writer.writeheader()
    writer.writerows(portfolio_rows)

strategies = sorted({row["strategy"] for row in rows if row["strategy"] != "true_original"})
method_families = [
    "OpenMP analysis-kernel parallelism",
    "Fast greedy layer assignment",
    "Net-guided fast greedy layer assignment",
    "P2/P3 routing budget tuning",
    "Conservative legal repair",
    "Edge-count post-processing and reroute pruning",
    "CUDA costed-maze/dogleg scoring",
]
methods_path = result_root / "method_count.txt"
with methods_path.open("w", encoding="utf-8") as f:
    f.write(f"observed_strategy_count={len(strategies)}\n")
    f.write(f"method_family_count={len(method_families)}\n")
    f.write("method_families=\n")
    for item in method_families:
        f.write(f"- {item}\n")
    f.write("strategies_in_this_summary=\n")
    for strategy in strategies:
        f.write(f"- {strategy}\n")

report_path = result_root / "run_report.md"
with report_path.open("w", encoding="utf-8") as f:
    f.write("# Wirelength-Guard Variant Run\n\n")
    f.write(f"- Result root: `{result_root}`\n")
    f.write(f"- Baseline CSV: `{baseline_csv}`\n")
    f.write(f"- Rows: {len(rows)}\n")
    f.write(f"- Strategies in this summary: {len(strategies)}\n")
    f.write(f"- Method families tracked: {len(method_families)}\n\n")
    f.write("## Portfolio By Wirelength Threshold\n\n")
    f.write("| WL threshold | Cases | Optimized cases | Speedup | Worst WL ratio |\n")
    f.write("| ---: | ---: | ---: | ---: | ---: |\n")
    for row in portfolio_rows:
        f.write(
            f"| {row['threshold']} | {row['cases']} | {row['optimized_cases']} | "
            f"{row['portfolio_speedup']} | {row['worst_wirelength_ratio']} |\n"
        )
    f.write("\n## Best Rows At Largest Threshold\n\n")
    if thresholds:
        largest = f"{max(thresholds):.2f}"
        f.write("| Benchmark | Selected | Speedup | WL ratio | Overflow / Max |\n")
        f.write("| --- | --- | ---: | ---: | ---: |\n")
        for row in best_rows:
            if row["threshold"] == largest:
                f.write(
                    f"| {row['benchmark']} | `{row['selected_strategy']}` | {row['speedup']} | "
                    f"{row['wirelength_ratio']} | {row['selected_overflow']} / {row['selected_max_overflow']} |\n"
                )

print(f"wrote {summary_path}")
print(f"wrote {candidate_path}")
print(f"wrote {best_path}")
print(f"wrote {portfolio_path}")
print(f"wrote {methods_path}")
print(f"wrote {report_path}")
PY
}

append_index() {
  local finished_at
  finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  if [[ ! -f "$RUN_INDEX" ]]; then
    echo "run_id,started_at,finished_at,commit,bench_set,bench_count,variants,result_root,notes" > "$RUN_INDEX"
  fi
  local commit
  commit=$(git rev-parse --short HEAD || true)
  local variants_for_csv=${RUN_VARIANTS//,/;}
  variants_for_csv=${variants_for_csv// /;}
  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$RUN_ID" "$STARTED_AT" "$finished_at" "$commit" "$BENCH_SET" "${#BENCHES[@]}" \
    "$variants_for_csv" "$RESULT_ROOT" "$RUN_NOTES" >> "$RUN_INDEX"
}

write_environment
write_catalog
bash scripts/fetch_ispd08.sh
build_cpu

run_cpu_variant \
  orig_layer_p2p3_budget \
  "--p2-init-box-size=5 --p2-box-expand-size=5 --p2-max-iteration=6 --overflow-threshold=1800 --p3-init-box-size=66 --p3-box-expand-size=122"

run_cpu_variant \
  orig_layer_p2p3_legal_repair \
  "--p2-init-box-size=5 --p2-box-expand-size=5 --p2-max-iteration=12 --overflow-threshold=0 --p3-max-iteration=30 --p3-init-box-size=80 --p3-box-expand-size=140" \
  NTHU_POST_SORT_MODE=edge_count

run_cpu_variant \
  orig_layer_edgecount_post_cpu \
  "--p2-init-box-size=5 --p2-box-expand-size=5 --overflow-threshold=10000 --p2-max-iteration=5 --p3-max-iteration=2 --p3-init-box-size=54 --p3-box-expand-size=88" \
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

run_cpu_variant \
  fast_layer_netguided_budget \
  "--p2-init-box-size=5 --p2-box-expand-size=5 --p2-max-iteration=6 --overflow-threshold=1800 --p3-init-box-size=66 --p3-box-expand-size=122" \
  NTHU_FAST_GREEDY_LAYER=1 \
  NTHU_FAST_GREEDY_LAYER_NET_GUIDED=1

run_cpu_variant \
  fast_layer_netguided_repair \
  "--p2-init-box-size=5 --p2-box-expand-size=5 --p2-max-iteration=12 --overflow-threshold=0 --p3-max-iteration=30 --p3-init-box-size=80 --p3-box-expand-size=140" \
  NTHU_FAST_GREEDY_LAYER=1 \
  NTHU_FAST_GREEDY_LAYER_NET_GUIDED=1 \
  NTHU_POST_SORT_MODE=edge_count

summarize
append_index
