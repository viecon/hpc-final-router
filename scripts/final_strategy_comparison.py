#!/usr/bin/env python3
"""Merge all benchmark strategy runs into final legality/speedup tables."""

import csv
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RESULTS = ROOT / "results"
BENCH_LIST = ROOT / "results/job_hooks/ispd08_all16.list"

SOURCES = [
    RESULTS / "bench16_strategy_matrix_r2_summary.csv",
    RESULTS / "bench16_strategy_matrix_r3_legal_repair_summary.csv",
    RESULTS / "bench16_strategy_matrix_r4_overflow_fix_summary.csv",
    RESULTS / "bench16_strategy_matrix_r4_output_repair_summary.csv",
    RESULTS / "bench16_strategy_matrix_r5_best_illegal_summary.csv",
    RESULTS / "bench16_strategy_matrix_r5_best_illegal_output_repair_summary.csv",
    RESULTS / "bench16_strategy_matrix_r6_best_illegal_now_summary.csv",
    RESULTS / "bench16_strategy_matrix_r6_best_illegal_astar_repair_summary.csv",
    RESULTS / "bench16_strategy_matrix_r6_best_illegal_edge_split_repair_summary.csv",
    RESULTS / "bench16_strategy_matrix_r7_best_illegal_compat_summary.csv",
    RESULTS / "bench16_strategy_matrix_r7_best_illegal_astar_repair_summary.csv",
    RESULTS / "bench16_strategy_matrix_r7_best_illegal_edge_split_repair_summary.csv",
    RESULTS / "bench16_strategy_matrix_r8_best_illegal_compat_summary.csv",
    RESULTS / "bench16_strategy_matrix_r8_best_illegal_astar_repair_summary.csv",
    RESULTS / "bench16_strategy_matrix_r8_best_illegal_edge_split_repair_summary.csv",
    RESULTS / "bench16_strategy_matrix_r9_best_illegal_astar_repair_summary.csv",
    RESULTS / "bench16_strategy_matrix_r9_best_illegal_edge_split_repair_summary.csv",
    RESULTS / "bench16_strategy_matrix_r10_best_illegal_local_detour_repair_summary.csv",
    RESULTS / "bench16_strategy_matrix_r11_best_illegal_local_detour_center_repair_summary.csv",
    RESULTS / "bench16_strategy_matrix_r12_best_illegal_edge_split_center_repair_summary.csv",
]

OUT_ALL = RESULTS / "final_strategy_comparison_all_rows.csv"
OUT_BEST = RESULTS / "final_best_legal_by_benchmark.csv"
OUT_MATRIX = RESULTS / "final_legality_matrix.csv"
OUT_UNRESOLVED = RESULTS / "final_unresolved_overflow.csv"


def to_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def to_int(value):
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return None


def read_benches():
    benches = []
    if BENCH_LIST.exists():
        for line in BENCH_LIST.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line:
                benches.append(line[:-3] if line.endswith(".gr") else line)
    return benches


def read_rows():
    rows = []
    for source in SOURCES:
        if not source.exists():
            continue
        with source.open(newline="", encoding="utf-8") as f:
            for row in csv.DictReader(f):
                if not row.get("benchmark"):
                    continue
                row["aggregate_source"] = source.name
                if not row.get("strategy"):
                    row["strategy"] = row.get("router", "")
                rows.append(row)
    return rows


def legal(row):
    return row.get("status") == "ok" and to_int(row.get("total_overflow")) == 0


def rank_key(row):
    # Prefer legal, then lower runtime, then lower overflow. Keep deterministic
    # order for report tables.
    sec = to_float(row.get("seconds"))
    ov = to_int(row.get("total_overflow"))
    return (
        0 if legal(row) else 1,
        sec if sec is not None else float("inf"),
        ov if ov is not None else 10**18,
        row.get("strategy", ""),
        row.get("aggregate_source", ""),
    )


def main():
    benches = read_benches()
    rows = read_rows()

    baselines = {}
    for row in rows:
        if row.get("strategy") == "nthu_original":
            cur = baselines.get(row["benchmark"])
            if cur is None or rank_key(row) < rank_key(cur):
                baselines[row["benchmark"]] = row

    all_fields = [
        "aggregate_source",
        "strategy",
        "router",
        "benchmark",
        "status",
        "legal",
        "seconds",
        "baseline_seconds",
        "speedup_vs_nthu_original",
        "total_wirelength",
        "total_overflow",
        "max_overflow",
        "overflowed_nets",
        "overflowed_edges",
        "output",
        "source_file",
    ]
    enriched = []
    for row in rows:
        base = baselines.get(row["benchmark"])
        sec = to_float(row.get("seconds"))
        base_sec = to_float(base.get("seconds")) if base else None
        speedup = base_sec / sec if base_sec and sec else None
        enriched.append(
            {
                **row,
                "legal": "yes" if legal(row) else "no",
                "baseline_seconds": f"{base_sec:.6f}" if base_sec is not None else "",
                "speedup_vs_nthu_original": f"{speedup:.6f}" if speedup is not None else "",
            }
        )

    with OUT_ALL.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=all_fields, extrasaction="ignore")
        w.writeheader()
        w.writerows(enriched)

    best_rows = []
    unresolved_rows = []
    strategies = sorted({row.get("strategy", "") for row in rows if row.get("strategy")})
    by_bench_strategy = {(row["benchmark"], row.get("strategy", "")): row for row in rows}

    for bench in benches:
        bench_rows = [row for row in enriched if row["benchmark"] == bench]
        legal_rows = [row for row in bench_rows if row["legal"] == "yes"]
        if legal_rows:
            best = min(legal_rows, key=lambda row: to_float(row.get("seconds")) or float("inf"))
            best_rows.append(
                {
                    "benchmark": bench,
                    "best_strategy": best.get("strategy", ""),
                    "seconds": best.get("seconds", ""),
                    "speedup_vs_nthu_original": best.get("speedup_vs_nthu_original", ""),
                    "total_wirelength": best.get("total_wirelength", ""),
                    "total_overflow": best.get("total_overflow", ""),
                    "aggregate_source": best.get("aggregate_source", ""),
                }
            )
        else:
            # Pick the lowest-overflow row as the next repair target.
            candidates = [row for row in bench_rows if to_int(row.get("total_overflow")) is not None]
            best_illegal = min(
                candidates,
                key=lambda row: (
                    to_int(row.get("total_overflow")) if to_int(row.get("total_overflow")) is not None else 10**18,
                    to_float(row.get("seconds")) if to_float(row.get("seconds")) is not None else float("inf"),
                ),
            ) if candidates else None
            unresolved_rows.append(
                {
                    "benchmark": bench,
                    "best_illegal_strategy": best_illegal.get("strategy", "") if best_illegal else "",
                    "best_illegal_seconds": best_illegal.get("seconds", "") if best_illegal else "",
                    "best_illegal_total_overflow": best_illegal.get("total_overflow", "") if best_illegal else "",
                    "best_illegal_source": best_illegal.get("aggregate_source", "") if best_illegal else "",
                    "completed_rows": str(len(bench_rows)),
                }
            )

    with OUT_BEST.open("w", newline="", encoding="utf-8") as f:
        fields = [
            "benchmark",
            "best_strategy",
            "seconds",
            "speedup_vs_nthu_original",
            "total_wirelength",
            "total_overflow",
            "aggregate_source",
        ]
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(best_rows)

    with OUT_UNRESOLVED.open("w", newline="", encoding="utf-8") as f:
        fields = [
            "benchmark",
            "best_illegal_strategy",
            "best_illegal_seconds",
            "best_illegal_total_overflow",
            "best_illegal_source",
            "completed_rows",
        ]
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(unresolved_rows)

    with OUT_MATRIX.open("w", newline="", encoding="utf-8") as f:
        fields = ["benchmark"] + strategies
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        for bench in benches:
            out = {"benchmark": bench}
            for strategy in strategies:
                row = by_bench_strategy.get((bench, strategy))
                if row is None:
                    out[strategy] = "missing"
                    continue
                sec = to_float(row.get("seconds"))
                ov = to_int(row.get("total_overflow"))
                if legal(row):
                    out[strategy] = f"legal {sec:.3f}s" if sec is not None else "legal"
                elif ov is not None:
                    out[strategy] = f"overflow {ov}"
                else:
                    out[strategy] = row.get("status", "unknown")
            w.writerow(out)

    print(f"wrote {OUT_ALL.relative_to(ROOT)}")
    print(f"wrote {OUT_BEST.relative_to(ROOT)}")
    print(f"wrote {OUT_MATRIX.relative_to(ROOT)}")
    print(f"wrote {OUT_UNRESOLVED.relative_to(ROOT)}")
    print(f"legal testcases: {len(best_rows)}/{len(benches)}")
    print(f"unresolved testcases: {len(unresolved_rows)}/{len(benches)}")


if __name__ == "__main__":
    main()
