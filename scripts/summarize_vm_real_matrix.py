#!/usr/bin/env python3
import argparse
import csv
from pathlib import Path


FIELDS = [
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


def read_rows(result_root):
    rows_by_key = {}
    for strategy_dir in sorted(p for p in result_root.iterdir() if p.is_dir()):
        strategy = strategy_dir.name
        summary = strategy_dir / "summary.csv"
        if summary.exists():
            with summary.open(newline="") as f:
                for row in csv.DictReader(f):
                    if not row:
                        continue
                    row = {field: row.get(field, "") for field in FIELDS}
                    row["strategy"] = strategy
                    rows_by_key[(strategy, row["benchmark"])] = row
        row_dir = strategy_dir / ".rows"
        for path in sorted(row_dir.glob("*.csvrow")) if row_dir.exists() else []:
            with path.open(newline="") as f:
                for row in csv.DictReader(f, fieldnames=FIELDS):
                    if not row:
                        continue
                    row = {field: row.get(field, "") for field in FIELDS}
                    row["strategy"] = strategy
                    rows_by_key[(strategy, row["benchmark"])] = row
    return list(rows_by_key.values())


def is_ok(row):
    return row.get("status") == "ok" and as_float(row.get("seconds")) is not None


def overflow_zero(row):
    return as_int(row.get("total_overflow")) == 0 and as_int(row.get("max_overflow")) == 0


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("result_root", nargs="?", default="results/vm_real_matrix")
    args = parser.parse_args()

    result_root = Path(args.result_root)
    rows = read_rows(result_root)
    rows.sort(key=lambda row: (row["benchmark"], row["strategy"]))

    summary_path = result_root / "summary_live.csv"
    with summary_path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["strategy"] + FIELDS)
        writer.writeheader()
        writer.writerows(rows)

    by_bench = {}
    for row in rows:
        by_bench.setdefault(row["benchmark"], {})[row["strategy"]] = row

    best_rows = []
    guard_rows = []
    for bench in sorted(by_bench):
        strategy_rows = by_bench[bench]
        original = strategy_rows.get("true_original")
        if not original or not is_ok(original):
            continue
        original_seconds = as_float(original["seconds"])
        original_legal = overflow_zero(original)
        candidates = [
            row for strategy, row in strategy_rows.items()
            if strategy != "true_original" and is_ok(row)
        ]
        if not candidates:
            continue

        def passes_guard(row):
            return (not original_legal) or overflow_zero(row)

        fastest_any = min(candidates, key=lambda row: as_float(row["seconds"]))
        guarded_candidates = [row for row in candidates if passes_guard(row)]
        fastest_guarded = (
            min(guarded_candidates, key=lambda row: as_float(row["seconds"]))
            if guarded_candidates else None
        )

        for row in candidates:
            if original_legal:
                guard_rows.append({
                    "benchmark": bench,
                    "strategy": row["strategy"],
                    "status": row["status"],
                    "seconds": row["seconds"],
                    "total_overflow": row["total_overflow"],
                    "max_overflow": row["max_overflow"],
                    "passes": passes_guard(row),
                })

        best = fastest_guarded or fastest_any
        best_seconds = as_float(best["seconds"])
        any_seconds = as_float(fastest_any["seconds"])
        best_rows.append({
            "benchmark": bench,
            "original_seconds": f"{original_seconds:.6f}",
            "original_overflow": original["total_overflow"],
            "original_legal": original_legal,
            "best_strategy": best["strategy"],
            "best_seconds": f"{best_seconds:.6f}",
            "best_speedup": f"{original_seconds / best_seconds:.6f}" if best_seconds else "",
            "best_overflow": best["total_overflow"],
            "best_max_overflow": best["max_overflow"],
            "best_guard_pass": passes_guard(best),
            "fastest_any_strategy": fastest_any["strategy"],
            "fastest_any_seconds": f"{any_seconds:.6f}",
            "fastest_any_speedup": f"{original_seconds / any_seconds:.6f}" if any_seconds else "",
            "fastest_any_overflow": fastest_any["total_overflow"],
            "fastest_any_max_overflow": fastest_any["max_overflow"],
            "fastest_any_guard_pass": passes_guard(fastest_any),
        })

    best_path = result_root / "best_per_benchmark_live.csv"
    with best_path.open("w", newline="") as f:
        fieldnames = [
            "benchmark",
            "original_seconds",
            "original_overflow",
            "original_legal",
            "best_strategy",
            "best_seconds",
            "best_speedup",
            "best_overflow",
            "best_max_overflow",
            "best_guard_pass",
            "fastest_any_strategy",
            "fastest_any_seconds",
            "fastest_any_speedup",
            "fastest_any_overflow",
            "fastest_any_max_overflow",
            "fastest_any_guard_pass",
        ]
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(best_rows)

    guard_path = result_root / "overflow_guard_live.csv"
    with guard_path.open("w", newline="") as f:
        fieldnames = [
            "benchmark",
            "strategy",
            "status",
            "seconds",
            "total_overflow",
            "max_overflow",
            "passes",
        ]
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(guard_rows)

    guard_failures = sum(1 for row in guard_rows if not row["passes"])
    print(f"wrote {summary_path}")
    print(f"wrote {best_path}")
    print(f"wrote {guard_path}")
    print(f"rows={len(rows)} best_rows={len(best_rows)} guard_failures={guard_failures}")


if __name__ == "__main__":
    main()
