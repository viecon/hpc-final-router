#!/usr/bin/env python3
import argparse
import csv
from pathlib import Path


def read_runs(path):
    with path.open(newline="") as f:
        rows = list(csv.DictReader(f))
    if not rows:
        raise ValueError(f"{path} has no data rows")
    return rows


def avg_excluding_warmup(values):
    tail = values[1:] if len(values) > 1 else values
    return sum(tail) / len(tail)


def fmt(value):
    return f"{value:.3f}"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--results-dir", default="results")
    parser.add_argument("--out", default="results/gpu_real_candidate_summary.csv")
    parser.add_argument("--cpu-prefix", default="real_candidate_cpu_")
    parser.add_argument("--cuda-prefix", default="real_candidate_cuda_")
    parser.add_argument("--exclude-label-prefix", default="dogleg")
    args = parser.parse_args()

    results_dir = Path(args.results_dir)
    cpu_files = sorted(results_dir.glob(f"{args.cpu_prefix}*.csv"))

    records = []
    for cpu_path in cpu_files:
        name = cpu_path.name
        bench = name[len(args.cpu_prefix):-len(".csv")]
        if args.exclude_label_prefix and bench.startswith(args.exclude_label_prefix):
            continue
        cuda_path = results_dir / f"{args.cuda_prefix}{bench}.csv"
        if not cuda_path.exists():
            continue

        cpu_rows = read_runs(cpu_path)
        cuda_rows = read_runs(cuda_path)
        cpu_ms = [float(row["milliseconds"]) for row in cpu_rows]
        cuda_ms = [float(row["milliseconds"]) for row in cuda_rows]
        cpu_avg = avg_excluding_warmup(cpu_ms)
        cuda_avg = avg_excluding_warmup(cuda_ms)
        speedup = cpu_avg / cuda_avg if cuda_avg else 0.0

        record = {
            "benchmark": bench,
            "candidate_rows": cpu_rows[0]["nets"],
            "cpu_ms_run1": cpu_ms[0] if len(cpu_ms) > 0 else "",
            "cpu_ms_run2": cpu_ms[1] if len(cpu_ms) > 1 else "",
            "cpu_ms_run3": cpu_ms[2] if len(cpu_ms) > 2 else "",
            "cuda_ms_run1": cuda_ms[0] if len(cuda_ms) > 0 else "",
            "cuda_ms_run2": cuda_ms[1] if len(cuda_ms) > 1 else "",
            "cuda_ms_run3": cuda_ms[2] if len(cuda_ms) > 2 else "",
            "cpu_avg_excl_warmup": cpu_avg,
            "cuda_avg_excl_warmup": cuda_avg,
            "speedup_excl_warmup": speedup,
        }
        records.append(record)

    fieldnames = [
        "benchmark",
        "candidate_rows",
        "cpu_ms_run1",
        "cpu_ms_run2",
        "cpu_ms_run3",
        "cuda_ms_run1",
        "cuda_ms_run2",
        "cuda_ms_run3",
        "cpu_avg_excl_warmup",
        "cuda_avg_excl_warmup",
        "speedup_excl_warmup",
    ]
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for record in records:
            for key in fieldnames:
                if isinstance(record[key], float):
                    record[key] = fmt(record[key])
            writer.writerow(record)


if __name__ == "__main__":
    main()
