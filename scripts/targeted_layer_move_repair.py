#!/usr/bin/env python3
"""Greedy output-level repair by moving overflowed segments to another layer.

This is an experimental post-processor for near-legal outputs. It preserves
connectivity by replacing one XY segment with via + moved XY segment + via.
"""

import argparse
import csv
import shutil
import subprocess
from pathlib import Path

import dump_overflow_edges as dump


def parse_route(path):
    lines = dump.non_empty_lines(dump.read_text(path))
    blocks = []
    i = 0
    while i < len(lines):
        header = lines[i]
        name = header.split()[0]
        segs = []
        i += 1
        while i < len(lines) and lines[i] != "!":
            segs.append(lines[i])
            i += 1
        i += 1
        blocks.append([header, name, segs])
    return blocks


def write_route(blocks, path):
    with Path(path).open("w", encoding="utf-8") as f:
        for header, _name, segs in blocks:
            parts = header.split()
            if len(parts) >= 3:
                parts[2] = str(len(segs))
                f.write("{}\n".format(" ".join(parts)))
            else:
                f.write("{} {}\n".format(header, len(segs)))
            for seg in segs:
                f.write("{}\n".format(seg))
            f.write("!\n")


def parse_seg(seg):
    nums = []
    cur = ""
    for ch in seg:
        if ch.isdigit():
            cur += ch
        elif cur:
            nums.append(int(cur))
            cur = ""
    if cur:
        nums.append(int(cur))
    return nums


def format_seg(a):
    return "({},{},{})-({},{},{})".format(a[0], a[1], a[2], a[3], a[4], a[5])


def segment_covers(design, seg_nums, edge):
    direction, x, y, layer = edge
    x1, y1, l1, x2, y2, l2 = seg_nums
    if l1 != layer or l2 != layer:
        return False
    x1g, y1g = dump.xytogrid(design, x1, y1)
    x2g, y2g = dump.xytogrid(design, x2, y2)
    if direction == "H" and y1g == y and y2g == y and x1g != x2g:
        lo, hi = sorted((x1g, x2g))
        return lo <= x and x + 1 <= hi
    if direction == "V" and x1g == x and x2g == x and y1g != y2g:
        lo, hi = sorted((y1g, y2g))
        return lo <= y and y + 1 <= hi
    return False


def candidate_layers(current_layer, layer_count):
    layers = []
    for delta in (1, -1, 2, -2, 3, -3):
        layer = current_layer + delta
        if 1 <= layer <= layer_count:
            layers.append(layer)
    return layers


def move_segment(segs, index, new_layer):
    x1, y1, l1, x2, y2, l2 = parse_seg(segs[index])
    moved = [
        format_seg((x1, y1, l1, x1, y1, new_layer)),
        format_seg((x1, y1, new_layer, x2, y2, new_layer)),
        format_seg((x2, y2, new_layer, x2, y2, l2)),
    ]
    return segs[:index] + moved + segs[index + 1 :]


def run_dump(design, route, prefix):
    cmd = [
        "python3",
        "scripts/dump_overflow_edges.py",
        "--design",
        str(design),
        "--route",
        str(route),
        "--out-prefix",
        str(prefix),
    ]
    out = subprocess.check_output(cmd, universal_newlines=True)
    edges = 0
    for line in out.splitlines():
        if line.startswith("overflow_edges="):
            edges = int(line.split("=", 1)[1])
    total = 0
    edges_csv = Path(str(prefix) + ".edges.csv")
    with edges_csv.open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            total += int(row["overflow"])
    return edges, total


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--design", required=True)
    parser.add_argument("--route", required=True)
    parser.add_argument("--overflow-edges", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--work-prefix", required=True)
    parser.add_argument("--max-nets-per-edge", type=int, default=8)
    parser.add_argument("--max-trials", type=int, default=80)
    args = parser.parse_args()

    design = dump.parse_design(args.design)
    blocks = parse_route(args.route)
    block_by_name = {block[1]: block for block in blocks}
    work_prefix = Path(args.work_prefix)
    work_prefix.parent.mkdir(parents=True, exist_ok=True)

    current = Path(str(work_prefix) + ".current.out")
    shutil.copyfile(args.route, current)
    best_edges, best_total = run_dump(args.design, current, Path(str(work_prefix) + ".current"))

    with Path(args.overflow_edges).open(newline="", encoding="utf-8") as f:
        overflow_rows = list(csv.DictReader(f))

    applied = []
    trials = 0
    for edge_i, row in enumerate(overflow_rows):
        edge = (row["dir"], int(row["x"]), int(row["y"]), int(row["layer"]))
        best_trial = None
        nets = [n for n in row["nets"].split(";") if n]
        for net in nets[: args.max_nets_per_edge]:
            if net not in block_by_name:
                continue
            block = block_by_name[net]
            for seg_i, seg in enumerate(block[2]):
                nums = parse_seg(seg)
                if len(nums) != 6 or not segment_covers(design, nums, edge):
                    continue
                for new_layer in candidate_layers(edge[3], design["layers"]):
                    if trials >= args.max_trials:
                        break
                    trials += 1
                    trial_blocks = [[b[0], b[1], list(b[2])] for b in blocks]
                    trial_by_name = {b[1]: b for b in trial_blocks}
                    trial_block = trial_by_name[net]
                    trial_block[2] = move_segment(trial_block[2], seg_i, new_layer)
                    trial_path = Path("{}_e{}_{}_l{}.out".format(work_prefix, edge_i, net, new_layer))
                    write_route(trial_blocks, trial_path)
                    trial_edges, trial_total = run_dump(
                        args.design, trial_path, Path(str(trial_path) + ".dump")
                    )
                    if trial_total < best_total and (
                        best_trial is None or trial_total < best_trial[0]
                    ):
                        best_trial = (trial_total, trial_edges, trial_blocks, net, new_layer, trial_path)
                if trials >= args.max_trials:
                    break
            if trials >= args.max_trials:
                break
        if best_trial is not None:
            best_total, best_edges, blocks, net, new_layer, trial_path = best_trial
            block_by_name = {block[1]: block for block in blocks}
            write_route(blocks, current)
            applied.append((edge_i, net, new_layer, best_total, best_edges))
            if best_total == 0:
                break
        if trials >= args.max_trials:
            break

    write_route(blocks, args.out)
    final_edges, final_total = run_dump(args.design, args.out, Path(str(work_prefix) + ".final"))
    print("applied={}".format(applied))
    print("final_overflow_edges={}".format(final_edges))
    print("final_total_overflow={}".format(final_total))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
