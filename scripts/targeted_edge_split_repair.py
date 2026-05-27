#!/usr/bin/env python3
"""Targeted output-level repair by moving one overflowed grid edge.

This is intentionally narrower than targeted_layer_move_repair.py: it splits
only the single overflowed grid edge out of a longer segment, moves that one
edge to another legal layer, and reconnects it with two vias. The aim is to
legalize near-legal routes without creating broad collateral congestion.
"""

import argparse
import csv
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


def format_seg(values):
    return "({},{},{})-({},{},{})".format(
        values[0], values[1], values[2], values[3], values[4], values[5]
    )


def grid_xy(design, gx, gy):
    return (
        design["llx"] + gx * design["xsize"],
        design["lly"] + gy * design["ysize"],
    )


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


def layer_supports(design, direction, layer):
    idx = layer - 1
    if direction == "H":
        return design["hcap"][idx] > 0
    return design["vcap"][idx] > 0


def candidate_layers(design, direction, current_layer):
    layers = []
    for delta in (1, -1, 2, -2, 3, -3, 4, -4, 5, -5):
        layer = current_layer + delta
        if 1 <= layer <= design["layers"] and layer_supports(design, direction, layer):
            layers.append(layer)
    return layers


def add_if_nonzero(out, x1, y1, l1, x2, y2, l2):
    if x1 == x2 and y1 == y2 and l1 == l2:
        return
    out.append(format_seg((x1, y1, l1, x2, y2, l2)))


def split_one_edge(design, seg, edge, new_layer):
    direction, x, y, layer = edge
    x1, y1, l1, x2, y2, l2 = parse_seg(seg)
    x1g, y1g = dump.xytogrid(design, x1, y1)
    x2g, y2g = dump.xytogrid(design, x2, y2)
    out = []

    if direction == "H":
        left_x, center_y = grid_xy(design, x, y)
        right_x, _ = grid_xy(design, x + 1, y)
        if x1g <= x2g:
            sx, ex = left_x, right_x
        else:
            sx, ex = right_x, left_x
        sy = y1
        add_if_nonzero(out, x1, y1, l1, sx, sy, layer)
        add_if_nonzero(out, sx, sy, layer, sx, sy, new_layer)
        add_if_nonzero(out, sx, sy, new_layer, ex, sy, new_layer)
        add_if_nonzero(out, ex, sy, new_layer, ex, sy, layer)
        add_if_nonzero(out, ex, sy, layer, x2, y2, l2)
        return out

    center_x, low_y = grid_xy(design, x, y)
    _, high_y = grid_xy(design, x, y + 1)
    if y1g <= y2g:
        sy, ey = low_y, high_y
    else:
        sy, ey = high_y, low_y
    sx = x1
    add_if_nonzero(out, x1, y1, l1, sx, sy, layer)
    add_if_nonzero(out, sx, sy, layer, sx, sy, new_layer)
    add_if_nonzero(out, sx, sy, new_layer, sx, ey, new_layer)
    add_if_nonzero(out, sx, ey, new_layer, sx, ey, layer)
    add_if_nonzero(out, sx, ey, layer, x2, y2, l2)
    return out


def run_dump(design_path, route, prefix):
    cmd = [
        "python3",
        "scripts/dump_overflow_edges.py",
        "--design",
        str(design_path),
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
    rows = []
    with edges_csv.open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            total += int(row["overflow"])
            rows.append(row)
    return edges, total, rows


def score(edges, total):
    return (total, edges)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--design", required=True)
    parser.add_argument("--route", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--work-prefix", required=True)
    parser.add_argument("--max-passes", type=int, default=4)
    parser.add_argument("--max-nets-per-edge", type=int, default=18)
    parser.add_argument("--max-trials", type=int, default=200)
    args = parser.parse_args()

    design = dump.parse_design(args.design)
    blocks = parse_route(args.route)
    block_by_name = {block[1]: block for block in blocks}
    work_prefix = Path(args.work_prefix)
    work_prefix.parent.mkdir(parents=True, exist_ok=True)
    current_path = Path(str(work_prefix) + ".current.out")
    trial_path = Path(str(work_prefix) + ".trial.out")

    applied = []
    trials = 0
    write_route(blocks, current_path)
    best_edges, best_total, overflow_rows = run_dump(
        args.design, current_path, Path(str(work_prefix) + ".current")
    )
    print(
        "initial_overflow_edges={} initial_total_overflow={}".format(
            best_edges, best_total
        ),
        flush=True,
    )

    for pass_i in range(args.max_passes):
        if best_total == 0 or trials >= args.max_trials:
            break
        pass_best = None
        for edge_i, row in enumerate(overflow_rows):
            edge = (row["dir"], int(row["x"]), int(row["y"]), int(row["layer"]))
            nets = [n for n in row["nets"].split(";") if n]
            for net in nets[: args.max_nets_per_edge]:
                block = block_by_name.get(net)
                if block is None:
                    continue
                for seg_i, seg in enumerate(block[2]):
                    nums = parse_seg(seg)
                    if len(nums) != 6 or not segment_covers(design, nums, edge):
                        continue
                    for new_layer in candidate_layers(design, edge[0], edge[3]):
                        if trials >= args.max_trials:
                            break
                        trials += 1
                        original_segs = block[2]
                        candidate_segs = split_one_edge(design, seg, edge, new_layer)
                        block[2] = original_segs[:seg_i] + candidate_segs + original_segs[seg_i + 1 :]
                        write_route(blocks, trial_path)
                        trial_edges, trial_total, _rows = run_dump(
                            args.design,
                            trial_path,
                            Path(str(work_prefix) + ".trial"),
                        )
                        block[2] = original_segs
                        if score(trial_edges, trial_total) < score(best_edges, best_total):
                            if pass_best is None or score(trial_edges, trial_total) < score(
                                pass_best["edges"], pass_best["total"]
                            ):
                                pass_best = {
                                    "edge_i": edge_i,
                                    "edge": edge,
                                    "net": net,
                                    "seg_i": seg_i,
                                    "new_layer": new_layer,
                                    "segs": candidate_segs,
                                    "edges": trial_edges,
                                    "total": trial_total,
                                }
                        if trial_total == 0:
                            break
                    if trials >= args.max_trials or (pass_best and pass_best["total"] == 0):
                        break
                if trials >= args.max_trials or (pass_best and pass_best["total"] == 0):
                    break
            if trials >= args.max_trials or (pass_best and pass_best["total"] == 0):
                break

        if pass_best is None:
            print("pass={} no_improvement trials={}".format(pass_i, trials), flush=True)
            break

        block = block_by_name[pass_best["net"]]
        seg_i = pass_best["seg_i"]
        block[2] = block[2][:seg_i] + pass_best["segs"] + block[2][seg_i + 1 :]
        applied.append(
            (
                pass_i,
                pass_best["edge"],
                pass_best["net"],
                pass_best["new_layer"],
                pass_best["total"],
                pass_best["edges"],
            )
        )
        write_route(blocks, current_path)
        best_edges, best_total, overflow_rows = run_dump(
            args.design, current_path, Path(str(work_prefix) + ".current")
        )
        print(
            "pass={} applied={} overflow_edges={} total_overflow={} trials={}".format(
                pass_i, applied[-1], best_edges, best_total, trials
            ),
            flush=True,
        )

    write_route(blocks, args.out)
    final_edges, final_total, _rows = run_dump(
        args.design, args.out, Path(str(work_prefix) + ".final")
    )
    print("applied={}".format(applied), flush=True)
    print("final_overflow_edges={}".format(final_edges), flush=True)
    print("final_total_overflow={}".format(final_total), flush=True)
    print("trials={}".format(trials), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
