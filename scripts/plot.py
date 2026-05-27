#!/usr/bin/env python3
import argparse
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd


def short_benchmark(name: str) -> str:
    return name.split(".", 1)[0]


def router_label(name: str) -> str:
    labels = {
        "nthu_original": "NTHU original",
        "nthu_openmp": "NTHU OpenMP",
        "nctu": "NCTU-GR",
        "nthu_adaptive_p2": "NTHU adaptive P2",
        "nthu_adaptive_p2_dogleg": "NTHU adaptive P2 + dogleg",
        "nthu_p2_box5_5": "NTHU P2 box 5/5",
        "nthu_p2_box5_5_th240": "NTHU P2 th240",
    }
    return labels.get(name, name)


def plot_real_baselines(df: pd.DataFrame, outdir: Path) -> None:
    df = df.copy()
    df = df[df["status"] == "ok"].copy()
    df["benchmark_short"] = df["benchmark"].map(short_benchmark)
    df["router_label"] = df["router"].map(router_label)
    for column in ["seconds", "total_wirelength", "total_overflow", "max_overflow"]:
        df[column] = pd.to_numeric(df[column], errors="coerce")

    preferred_order = ["nthu_original", "nthu_openmp", "nthu_adaptive_p2", "nthu_adaptive_p2_dogleg", "nctu"]
    seen = list(dict.fromkeys(df["router"].tolist()))
    order = [router for router in preferred_order if router in seen]
    order += sorted(router for router in seen if router not in order)
    benches = sorted(df["benchmark_short"].unique())
    x = range(len(benches))
    width = min(0.8 / max(len(order), 1), 0.24)

    def grouped_bars(metric: str, ylabel: str, filename: str, log: bool = False) -> None:
        plt.figure(figsize=(9, 4.8))
        for idx, router in enumerate(order):
            sub = df[df["router"] == router].set_index("benchmark_short")
            values = [sub.loc[bench, metric] if bench in sub.index else float("nan") for bench in benches]
            center_offset = (idx - (len(order) - 1) / 2) * width
            offsets = [pos + center_offset for pos in x]
            plt.bar(offsets, values, width=width, label=router_label(router))
        plt.xticks(list(x), benches)
        plt.ylabel(ylabel)
        if log:
            plt.yscale("symlog", linthresh=1)
        plt.legend()
        plt.tight_layout()
        plt.savefig(outdir / filename, dpi=180)
        plt.close()

    grouped_bars("seconds", "Runtime (s)", "real_runtime.png")
    grouped_bars("total_wirelength", "Total wirelength", "real_wirelength.png")
    grouped_bars("total_overflow", "Total overflow", "real_overflow.png", log=True)

    pivot = df.pivot_table(index="benchmark_short", columns="router", values="seconds", aggfunc="first")
    if "nthu_original" in pivot:
        speedup = pd.DataFrame(index=pivot.index)
        for router in pivot.columns:
            speedup[f"{router}_speedup_vs_nthu_original"] = pivot["nthu_original"] / pivot[router]
        speedup.to_csv(outdir / "real_speedup_vs_nthu_original.csv")

    df.sort_values(["benchmark_short", "router"]).to_csv(outdir / "real_summary.csv", index=False)


def plot_mini_router(df: pd.DataFrame, outdir: Path) -> None:
    grouped = (
        df.groupby(["mode", "grid_width", "nets", "threads"], as_index=False)
        .agg(milliseconds=("milliseconds", "mean"), overflow=("overflow", "mean"), wirelength=("wirelength", "mean"))
    )

    for (grid, nets), sub in grouped.groupby(["grid_width", "nets"]):
        baseline = sub[(sub["mode"] == "seq") & (sub["threads"] == 1)]
        if baseline.empty:
            continue
        base_ms = float(baseline.iloc[0]["milliseconds"])
        sub = sub.copy()
        sub["speedup"] = base_ms / sub["milliseconds"]
        labels = [f"{row.mode}-{int(row.threads)}" for row in sub.itertuples()]

        plt.figure(figsize=(8, 4))
        plt.bar(labels, sub["speedup"])
        plt.xticks(rotation=30, ha="right")
        plt.ylabel("Speedup vs seq")
        plt.title(f"Grid {grid}x{grid}, nets={nets}")
        plt.tight_layout()
        plt.savefig(outdir / f"speedup_g{grid}_n{nets}.png", dpi=180)
        plt.close()

        plt.figure(figsize=(8, 4))
        plt.bar(labels, sub["overflow"])
        plt.xticks(rotation=30, ha="right")
        plt.ylabel("Total overflow")
        plt.title(f"Routing quality: grid {grid}x{grid}, nets={nets}")
        plt.tight_layout()
        plt.savefig(outdir / f"overflow_g{grid}_n{nets}.png", dpi=180)
        plt.close()

    grouped.to_csv(outdir / "summary.csv", index=False)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("csv", nargs="+", help="benchmark CSV files")
    parser.add_argument("--outdir", default="results/plots")
    args = parser.parse_args()

    frames = [pd.read_csv(path) for path in args.csv]
    df = pd.concat(frames, ignore_index=True)
    outdir = Path(args.outdir)
    outdir.mkdir(parents=True, exist_ok=True)

    if {"router", "benchmark", "seconds"}.issubset(df.columns):
        plot_real_baselines(df, outdir)
        print(f"wrote real baseline plots and {outdir / 'real_summary.csv'}")
    elif {"mode", "grid_width", "nets", "threads"}.issubset(df.columns):
        plot_mini_router(df, outdir)
        print(f"wrote mini-router plots and {outdir / 'summary.csv'}")
    else:
        raise SystemExit("unsupported CSV schema")


if __name__ == "__main__":
    main()
