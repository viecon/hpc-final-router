#!/usr/bin/env python3
import argparse
import csv
from pathlib import Path
from typing import Dict, List, Optional


def short_benchmark(name: str) -> str:
    return name.split(".", 1)[0]


def read_rows(path: Path) -> List[Dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def as_float(value: str) -> Optional[float]:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--catalog", default="results/all_summaries_catalog.csv")
    parser.add_argument("--baseline", default="results/real_baselines_summary.csv")
    parser.add_argument("--out", default="results/legal_runtime_ranking.csv")
    args = parser.parse_args()

    catalog_path = Path(args.catalog)
    baseline_path = Path(args.baseline)
    out_path = Path(args.out)

    rows = read_rows(catalog_path)
    baseline_rows = read_rows(baseline_path) if baseline_path.exists() else []

    nthu_original_seconds: Dict[str, float] = {}
    nctu_seconds: Dict[str, float] = {}
    for row in baseline_rows:
        bench = short_benchmark(row.get("benchmark", ""))
        seconds = as_float(row.get("seconds", ""))
        if seconds is None:
            continue
        if row.get("router") == "nthu_original":
            nthu_original_seconds[bench] = seconds
        elif row.get("router") == "nctu":
            nctu_seconds[bench] = seconds

    legal_rows: List[Dict[str, str]] = []
    for row in rows:
        if row.get("status") != "ok":
            continue
        if row.get("total_overflow") != "0":
            continue
        seconds = as_float(row.get("seconds", ""))
        if seconds is None:
            continue
        bench = short_benchmark(row.get("benchmark", ""))
        out = dict(row)
        out["benchmark_short"] = bench
        out["seconds_float"] = f"{seconds:.6f}"
        if bench in nthu_original_seconds:
            out["speedup_vs_nthu_original"] = f"{nthu_original_seconds[bench] / seconds:.6f}"
        else:
            out["speedup_vs_nthu_original"] = ""
        if bench in nctu_seconds:
            out["speedup_vs_nctu"] = f"{nctu_seconds[bench] / seconds:.6f}"
        else:
            out["speedup_vs_nctu"] = ""
        legal_rows.append(out)

    legal_rows.sort(key=lambda r: (r["benchmark_short"], float(r["seconds_float"])))
    unique_rows: List[Dict[str, str]] = []
    seen_keys = set()
    for row in legal_rows:
        key = (
            row.get("benchmark_short", ""),
            row.get("router", ""),
            row.get("seconds_float", ""),
            row.get("total_wirelength", ""),
            row.get("total_overflow", ""),
            row.get("output", ""),
        )
        if key in seen_keys:
            continue
        seen_keys.add(key)
        unique_rows.append(row)
    fieldnames = [
        "benchmark_short",
        "router",
        "seconds_float",
        "speedup_vs_nthu_original",
        "speedup_vs_nctu",
        "total_wirelength",
        "source_file",
        "benchmark",
        "output",
    ]
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in unique_rows:
            writer.writerow({name: row.get(name, "") for name in fieldnames})
    print(f"wrote {out_path}")


if __name__ == "__main__":
    main()
