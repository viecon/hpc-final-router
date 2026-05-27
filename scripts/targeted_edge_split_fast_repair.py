#!/usr/bin/env python3
"""Fast targeted edge-split repair using an in-memory demand model."""

import argparse
from collections import defaultdict
from pathlib import Path

import dump_overflow_edges as dump
import targeted_edge_split_repair as split


def segment_demand(design, net_name, layer):
    net = design["nets"][net_name]
    idx = layer - 1
    return max(net["min_width"], design["minw"][idx]) + design["mins"][idx]


def capacity(design, direction, x, y, layer):
    key = (x, y, layer - 1)
    if direction == "H":
        return dump.cap_h(design, key)
    return dump.cap_v(design, key)


def compute_usage(design, blocks):
    demand = defaultdict(int)
    edge_nets = defaultdict(set)
    for _header, net_name, segs in blocks:
        for seg in segs:
            nums = split.parse_seg(seg)
            if len(nums) != 6:
                continue
            x1, y1, l1, x2, y2, _l2 = nums
            x1g, y1g = dump.xytogrid(design, x1, y1)
            x2g, y2g = dump.xytogrid(design, x2, y2)
            amount = segment_demand(design, net_name, l1)
            if x1g != x2g:
                lo, hi = sorted((x1g, x2g))
                for x in range(lo, hi):
                    key = ("H", x, y1g, l1)
                    demand[key] += amount
                    edge_nets[key].add(net_name)
            elif y1g != y2g:
                lo, hi = sorted((y1g, y2g))
                for y in range(lo, hi):
                    key = ("V", x1g, y, l1)
                    demand[key] += amount
                    edge_nets[key].add(net_name)
    return demand, edge_nets


def overflow_rows(design, demand, edge_nets):
    rows = []
    total = 0
    for key, used in demand.items():
        direction, x, y, layer = key
        over = used - capacity(design, direction, x, y, layer)
        if over > 0:
            total += over
            rows.append(
                {
                    "key": key,
                    "dir": direction,
                    "x": x,
                    "y": y,
                    "layer": layer,
                    "demand": used,
                    "capacity": capacity(design, direction, x, y, layer),
                    "overflow": over,
                    "nets": sorted(edge_nets[key]),
                }
            )
    rows.sort(key=lambda r: (-r["overflow"], r["dir"], r["x"], r["y"], r["layer"]))
    return rows, total


def best_move(design, blocks, block_by_name, demand, rows, max_nets_per_edge):
    current_total = sum(row["overflow"] for row in rows)
    current_edges = len(rows)
    best = None
    for edge_i, row in enumerate(rows):
        edge = (row["dir"], row["x"], row["y"], row["layer"])
        old_key = row["key"]
        old_cap = row["capacity"]
        old_used = row["demand"]
        for net in row["nets"][:max_nets_per_edge]:
            block = block_by_name.get(net)
            if block is None:
                continue
            old_amount = segment_demand(design, net, row["layer"])
            for seg_i, seg in enumerate(block[2]):
                nums = split.parse_seg(seg)
                if len(nums) != 6 or not split.segment_covers(design, nums, edge):
                    continue
                for new_layer in split.candidate_layers(design, row["dir"], row["layer"]):
                    new_key = (row["dir"], row["x"], row["y"], new_layer)
                    new_used = demand.get(new_key, 0)
                    new_cap = capacity(design, row["dir"], row["x"], row["y"], new_layer)
                    new_amount = segment_demand(design, net, new_layer)

                    old_before = max(0, old_used - old_cap)
                    old_after = max(0, old_used - old_amount - old_cap)
                    new_before = max(0, new_used - new_cap)
                    new_after = max(0, new_used + new_amount - new_cap)
                    total_after = current_total - old_before - new_before + old_after + new_after
                    edge_after = current_edges
                    if old_before > 0 and old_after == 0:
                        edge_after -= 1
                    if new_before == 0 and new_after > 0:
                        edge_after += 1

                    if (total_after, edge_after) >= (current_total, current_edges):
                        continue
                    cand = {
                        "score": (total_after, edge_after),
                        "edge_i": edge_i,
                        "edge": edge,
                        "net": net,
                        "seg_i": seg_i,
                        "new_layer": new_layer,
                        "segs": split.split_one_edge(design, seg, edge, new_layer),
                    }
                    if best is None or cand["score"] < best["score"]:
                        best = cand
    return best


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--design", required=True)
    parser.add_argument("--route", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--work-prefix", required=True)
    parser.add_argument("--max-passes", type=int, default=8)
    parser.add_argument("--max-nets-per-edge", type=int, default=24)
    args = parser.parse_args()

    design = dump.parse_design(args.design)
    blocks = split.parse_route(args.route)
    block_by_name = {block[1]: block for block in blocks}
    applied = []

    for pass_i in range(args.max_passes):
        demand, edge_nets = compute_usage(design, blocks)
        rows, total = overflow_rows(design, demand, edge_nets)
        print(
            "pass={} overflow_edges={} total_overflow={}".format(
                pass_i, len(rows), total
            ),
            flush=True,
        )
        if total == 0:
            break
        move = best_move(design, blocks, block_by_name, demand, rows, args.max_nets_per_edge)
        if move is None:
            print("pass={} no_improvement".format(pass_i), flush=True)
            break
        block = block_by_name[move["net"]]
        seg_i = move["seg_i"]
        block[2] = block[2][:seg_i] + move["segs"] + block[2][seg_i + 1 :]
        applied.append(
            (
                pass_i,
                move["edge"],
                move["net"],
                move["new_layer"],
                move["score"][0],
                move["score"][1],
            )
        )
        print("pass={} applied={}".format(pass_i, applied[-1]), flush=True)

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    split.write_route(blocks, out)
    final_prefix = Path(args.work_prefix + ".final")
    final_edges, final_total, _rows = split.run_dump(args.design, out, final_prefix)
    print("applied={}".format(applied), flush=True)
    print("final_overflow_edges={}".format(final_edges), flush=True)
    print("final_total_overflow={}".format(final_total), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
