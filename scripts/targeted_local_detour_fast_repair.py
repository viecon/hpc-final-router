#!/usr/bin/env python3
"""Fast near-legal repair by dogleg-routing one overflowed grid edge."""

import argparse
from pathlib import Path

import dump_overflow_edges as dump
import targeted_edge_split_repair as split
import targeted_edge_split_fast_repair as fast


def supported_layers(design, direction):
    return [layer for layer in range(1, design["layers"] + 1) if split.layer_supports(design, direction, layer)]


def edge_overflow(design, demand, key):
    direction, x, y, layer = key
    return max(0, demand.get(key, 0) - fast.capacity(design, direction, x, y, layer))


def apply_delta_score(design, demand, deltas, current_total, current_edges):
    touched = sorted(deltas)
    before_total = 0
    after_total = 0
    before_edges = 0
    after_edges = 0
    for key in touched:
        before = edge_overflow(design, demand, key)
        after_used = demand.get(key, 0) + deltas[key]
        direction, x, y, layer = key
        after = max(0, after_used - fast.capacity(design, direction, x, y, layer))
        before_total += before
        after_total += after
        before_edges += 1 if before > 0 else 0
        after_edges += 1 if after > 0 else 0
    return (current_total - before_total + after_total, current_edges - before_edges + after_edges)


def add_segment_deltas(design, net, direction, layer, fixed, lo, hi, deltas, sign):
    amount = fast.segment_demand(design, net, layer) * sign
    if direction == "H":
        y = fixed
        for x in range(min(lo, hi), max(lo, hi)):
            deltas[("H", x, y, layer)] = deltas.get(("H", x, y, layer), 0) + amount
    else:
        x = fixed
        for y in range(min(lo, hi), max(lo, hi)):
            deltas[("V", x, y, layer)] = deltas.get(("V", x, y, layer), 0) + amount


def add_if_nonzero(out, values):
    x1, y1, l1, x2, y2, l2 = values
    if x1 == x2 and y1 == y2 and l1 == l2:
        return
    out.append(split.format_seg(values))


def build_detour(design, seg, edge, offset, main_layer, side_layer):
    direction, x, y, old_layer = edge
    x1, y1, l1, x2, y2, l2 = split.parse_seg(seg)
    x1g, y1g = dump.xytogrid(design, x1, y1)
    x2g, y2g = dump.xytogrid(design, x2, y2)
    out = []

    if direction == "H":
        if y + offset < 0 or y + offset >= design["gridy"]:
            return None
        ax0, ay = split.grid_xy(design, x, y)
        bx0, _ = split.grid_xy(design, x + 1, y)
        _cx_unused, cy = split.grid_xy(design, x, y + offset)
        if x1g <= x2g:
            ax, bx = ax0, bx0
        else:
            ax, bx = bx0, ax0
        add_if_nonzero(out, (x1, y1, l1, ax, ay, old_layer))
        add_if_nonzero(out, (ax, ay, old_layer, ax, ay, side_layer))
        add_if_nonzero(out, (ax, ay, side_layer, ax, cy, side_layer))
        add_if_nonzero(out, (ax, cy, side_layer, ax, cy, main_layer))
        add_if_nonzero(out, (ax, cy, main_layer, bx, cy, main_layer))
        add_if_nonzero(out, (bx, cy, main_layer, bx, cy, side_layer))
        add_if_nonzero(out, (bx, cy, side_layer, bx, ay, side_layer))
        add_if_nonzero(out, (bx, ay, side_layer, bx, ay, old_layer))
        add_if_nonzero(out, (bx, ay, old_layer, x2, y2, l2))
        return out

    if x + offset < 0 or x + offset >= design["gridx"]:
        return None
    ax, ay0 = split.grid_xy(design, x, y)
    _unused, by0 = split.grid_xy(design, x, y + 1)
    cx, _cy_unused = split.grid_xy(design, x + offset, y)
    if y1g <= y2g:
        ay, by = ay0, by0
    else:
        ay, by = by0, ay0
    add_if_nonzero(out, (x1, y1, l1, ax, ay, old_layer))
    add_if_nonzero(out, (ax, ay, old_layer, ax, ay, side_layer))
    add_if_nonzero(out, (ax, ay, side_layer, cx, ay, side_layer))
    add_if_nonzero(out, (cx, ay, side_layer, cx, ay, main_layer))
    add_if_nonzero(out, (cx, ay, main_layer, cx, by, main_layer))
    add_if_nonzero(out, (cx, by, main_layer, cx, by, side_layer))
    add_if_nonzero(out, (cx, by, side_layer, ax, by, side_layer))
    add_if_nonzero(out, (ax, by, side_layer, ax, by, old_layer))
    add_if_nonzero(out, (ax, by, old_layer, x2, y2, l2))
    return out


def candidate_deltas(design, net, edge, offset, main_layer, side_layer):
    direction, x, y, old_layer = edge
    deltas = {}
    add_segment_deltas(design, net, direction, old_layer, y if direction == "H" else x, x if direction == "H" else y, (x + 1) if direction == "H" else (y + 1), deltas, -1)
    if direction == "H":
        add_segment_deltas(design, net, "V", side_layer, x, y, y + offset, deltas, 1)
        add_segment_deltas(design, net, "H", main_layer, y + offset, x, x + 1, deltas, 1)
        add_segment_deltas(design, net, "V", side_layer, x + 1, y + offset, y, deltas, 1)
    else:
        add_segment_deltas(design, net, "H", side_layer, y, x, x + offset, deltas, 1)
        add_segment_deltas(design, net, "V", main_layer, x + offset, y, y + 1, deltas, 1)
        add_segment_deltas(design, net, "H", side_layer, y + 1, x + offset, x, deltas, 1)
    return deltas


def find_best_detour(design, blocks, block_by_name, demand, rows, max_nets_per_edge, max_offset):
    current_total = sum(row["overflow"] for row in rows)
    current_edges = len(rows)
    h_layers = supported_layers(design, "H")
    v_layers = supported_layers(design, "V")
    best = None
    for edge_i, row in enumerate(rows):
        edge = (row["dir"], row["x"], row["y"], row["layer"])
        main_layers = h_layers if row["dir"] == "H" else v_layers
        side_layers = v_layers if row["dir"] == "H" else h_layers
        for net in row["nets"][:max_nets_per_edge]:
            block = block_by_name.get(net)
            if block is None:
                continue
            for seg_i, seg in enumerate(block[2]):
                nums = split.parse_seg(seg)
                if len(nums) != 6 or not split.segment_covers(design, nums, edge):
                    continue
                for offset_abs in range(1, max_offset + 1):
                    for offset in (-offset_abs, offset_abs):
                        for main_layer in main_layers:
                            for side_layer in side_layers:
                                detour = build_detour(design, seg, edge, offset, main_layer, side_layer)
                                if detour is None:
                                    continue
                                deltas = candidate_deltas(
                                    design, net, edge, offset, main_layer, side_layer
                                )
                                score = apply_delta_score(
                                    design, demand, deltas, current_total, current_edges
                                )
                                if score >= (current_total, current_edges):
                                    continue
                                cand = {
                                    "score": score,
                                    "edge_i": edge_i,
                                    "edge": edge,
                                    "net": net,
                                    "seg_i": seg_i,
                                    "offset": offset,
                                    "main_layer": main_layer,
                                    "side_layer": side_layer,
                                    "segs": detour,
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
    parser.add_argument("--max-nets-per-edge", type=int, default=16)
    parser.add_argument("--max-offset", type=int, default=2)
    args = parser.parse_args()

    design = dump.parse_design(args.design)
    blocks = split.parse_route(args.route)
    block_by_name = {block[1]: block for block in blocks}
    applied = []

    for pass_i in range(args.max_passes):
        demand, edge_nets = fast.compute_usage(design, blocks)
        rows, total = fast.overflow_rows(design, demand, edge_nets)
        print(
            "pass={} overflow_edges={} total_overflow={}".format(
                pass_i, len(rows), total
            ),
            flush=True,
        )
        if total == 0:
            break
        move = find_best_detour(
            design, blocks, block_by_name, demand, rows, args.max_nets_per_edge, args.max_offset
        )
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
                move["offset"],
                move["main_layer"],
                move["side_layer"],
                move["score"][0],
                move["score"][1],
            )
        )
        print("pass={} applied={}".format(pass_i, applied[-1]), flush=True)

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    split.write_route(blocks, out)
    final_edges, final_total, _rows = split.run_dump(
        args.design, out, Path(args.work_prefix + ".final")
    )
    print("applied={}".format(applied), flush=True)
    print("final_overflow_edges={}".format(final_edges), flush=True)
    print("final_total_overflow={}".format(final_total), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
