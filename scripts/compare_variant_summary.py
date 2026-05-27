#!/usr/bin/env python3
import argparse
import csv
from pathlib import Path


def to_float(value):
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def to_int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("summary")
    parser.add_argument("--baseline-router", default="")
    parser.add_argument("--out", default="")
    args = parser.parse_args()

    with Path(args.summary).open(newline="") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        raise SystemExit(f"no rows in {args.summary}")

    baseline = None
    if args.baseline_router:
      baseline = next((row for row in rows if row.get("router") == args.baseline_router), None)
    if baseline is None:
        baseline = rows[0]

    base_seconds = to_float(baseline.get("seconds"))
    base_wl = to_int(baseline.get("total_wirelength"))
    if base_seconds is None or base_wl is None:
        raise SystemExit("baseline row does not contain numeric seconds/wirelength")

    out_rows = []
    for row in rows:
        seconds = to_float(row.get("seconds"))
        wl = to_int(row.get("total_wirelength"))
        overflow = to_int(row.get("total_overflow"))
        legal = row.get("status") == "ok" and overflow == 0
        speedup = base_seconds / seconds if seconds else None
        wl_delta = wl - base_wl if wl is not None else None
        out_rows.append({
            "router": row.get("router", ""),
            "benchmark": row.get("benchmark", ""),
            "legal": "yes" if legal else "no",
            "seconds": f"{seconds:.6f}" if seconds is not None else "",
            "speedup_vs_baseline": f"{speedup:.6f}" if speedup is not None else "",
            "wirelength": str(wl) if wl is not None else "",
            "wirelength_delta": str(wl_delta) if wl_delta is not None else "",
            "total_overflow": row.get("total_overflow", ""),
        })

    fieldnames = [
        "router",
        "benchmark",
        "legal",
        "seconds",
        "speedup_vs_baseline",
        "wirelength",
        "wirelength_delta",
        "total_overflow",
    ]
    if args.out:
        out_path = Path(args.out)
        out_path.parent.mkdir(parents=True, exist_ok=True)
        with out_path.open("w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            writer.writerows(out_rows)
    else:
        writer = csv.DictWriter(__import__("sys").stdout, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(out_rows)


if __name__ == "__main__":
    main()
