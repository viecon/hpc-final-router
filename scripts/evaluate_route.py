#!/usr/bin/env python3
"""Evaluate an ISPD08 global-routing output with a selectable checker."""

from __future__ import annotations

import argparse
import importlib.util
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]


def _load_lab2_verifier(path: Path) -> Any:
    spec = importlib.util.spec_from_file_location("lab2_verifier", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import verifier from {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def _eval_lab2(verifier_path: Path, design: Path, route: Path) -> dict[str, Any]:
    verifier = _load_lab2_verifier(verifier_path)
    result = verifier.verify(design, route)
    return {
        "evaluator": "lab2-verifier.py",
        "total_wirelength": result["wl"],
        "total_overflow": result["tof"],
        "max_overflow": result["mof"],
        "overflowed_nets": result["overflowed_nets"],
        "overflowed_edges": result["overflowed_edges"],
    }


def _match_metric(pattern: str, text: str) -> int:
    matches = re.findall(pattern, text, flags=re.IGNORECASE)
    if not matches:
        raise RuntimeError(f"missing evaluator metric: {pattern}")
    return int(matches[-1])


def _eval_perl(nthu_dir: Path, design: Path, route: Path) -> dict[str, Any]:
    eval2008 = nthu_dir / "eval2008.pl"
    if not eval2008.exists():
        raise FileNotFoundError(f"missing {eval2008}")
    proc = subprocess.run(
        ["perl", str(eval2008), str(design), str(route)],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    text = proc.stdout
    return {
        "evaluator": "eval2008.pl",
        "total_wirelength": _match_metric(r"total net length\s*=\s*(\d+)", text),
        "total_overflow": _match_metric(r"total overflow\s*=\s*(\d+)", text),
        "max_overflow": _match_metric(r"max overflow\s*=\s*(\d+)", text),
        "overflowed_nets": None,
        "overflowed_edges": None,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("design", type=Path)
    parser.add_argument("route", type=Path)
    parser.add_argument(
        "--evaluator",
        choices=("auto", "lab2", "perl"),
        default="auto",
        help="Checker to use. auto prefers the Lab2 Python verifier.",
    )
    parser.add_argument(
        "--verifier",
        type=Path,
        default=ROOT / "external" / "lab2-checker" / "verifier.py",
        help="Path to Lab2 verifier.py",
    )
    parser.add_argument(
        "--nthu-dir",
        type=Path,
        default=ROOT / "external" / "nthu-route",
        help="NTHU-Route directory containing eval2008.pl",
    )
    args = parser.parse_args()

    evaluator = args.evaluator
    if evaluator == "auto":
        evaluator = "lab2" if args.verifier.exists() else "perl"

    try:
        if evaluator == "lab2":
            metrics = _eval_lab2(args.verifier, args.design, args.route)
        else:
            metrics = _eval_perl(args.nthu_dir, args.design, args.route)
    except Exception as exc:
        print(f"evaluate_route.py: {exc}", file=sys.stderr)
        return 2

    print(json.dumps(metrics, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
