#!/usr/bin/env python3
import csv
import os
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
TAG = os.environ.get("TAG", "bench16_strategy_matrix")
BASE = ROOT / "results" / TAG
OUT = ROOT / "results" / f"{TAG}_summary.csv"
COMPARE = ROOT / "results" / f"{TAG}_speedups.csv"


def read_rows():
    rows = []
    for path in sorted(BASE.glob("*/*/summary.csv")):
        with path.open(newline="", encoding="utf-8") as f:
            for row in csv.DictReader(f):
                row["source_file"] = str(path.relative_to(ROOT))
                parts = path.relative_to(BASE).parts
                row["strategy"] = parts[0] if parts else row.get("router", "")
                rows.append(row)
    return rows


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


def main():
    rows = read_rows()
    OUT.parent.mkdir(parents=True, exist_ok=True)
    summary_fields = [
        "strategy",
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
        "source_file",
    ]
    with OUT.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=summary_fields)
        w.writeheader()
        for row in rows:
            w.writerow({k: row.get(k, "") for k in summary_fields})

    baselines = {}
    for row in rows:
        if row.get("strategy") == "nthu_original":
            baselines[row.get("benchmark", "")] = row

    compare_rows = []
    for row in rows:
        bench = row.get("benchmark", "")
        sec = to_float(row.get("seconds"))
        ov = to_int(row.get("total_overflow"))
        wl = to_int(row.get("total_wirelength"))
        base = baselines.get(bench)
        base_sec = to_float(base.get("seconds")) if base else None
        base_ov = to_int(base.get("total_overflow")) if base else None
        base_wl = to_int(base.get("total_wirelength")) if base else None
        speedup = base_sec / sec if base_sec and sec else None
        legal = row.get("status") == "ok" and ov == 0
        compare_rows.append({
            "strategy": row.get("strategy", ""),
            "router": row.get("router", ""),
            "benchmark": bench,
            "status": row.get("status", ""),
            "legal": "yes" if legal else "no",
            "seconds": f"{sec:.6f}" if sec is not None else "",
            "baseline_seconds": f"{base_sec:.6f}" if base_sec is not None else "",
            "speedup_vs_nthu_original": f"{speedup:.6f}" if speedup is not None else "",
            "total_wirelength": str(wl) if wl is not None else "",
            "baseline_wirelength": str(base_wl) if base_wl is not None else "",
            "wirelength_delta": str(wl - base_wl) if wl is not None and base_wl is not None else "",
            "total_overflow": str(ov) if ov is not None else "",
            "baseline_overflow": str(base_ov) if base_ov is not None else "",
            "source_file": row.get("source_file", ""),
        })

    compare_fields = [
        "strategy",
        "router",
        "benchmark",
        "status",
        "legal",
        "seconds",
        "baseline_seconds",
        "speedup_vs_nthu_original",
        "total_wirelength",
        "baseline_wirelength",
        "wirelength_delta",
        "total_overflow",
        "baseline_overflow",
        "source_file",
    ]
    with COMPARE.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=compare_fields)
        w.writeheader()
        w.writerows(compare_rows)

    print(f"wrote {OUT.relative_to(ROOT)}")
    print(f"wrote {COMPARE.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
