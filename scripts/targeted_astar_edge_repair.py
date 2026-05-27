#!/usr/bin/env python3
"""Capacity-aware A* repair for one overflowed grid edge at a time."""

import argparse
from pathlib import Path

import dump_overflow_edges as dump
import targeted_astar_segment_repair as astar_seg
import targeted_edge_split_repair as split
import targeted_edge_split_fast_repair as fast


def edge_endpoints(edge):
    direction, x, y, layer = edge
    if direction == "H":
        return (x, y, layer), (x + 1, y, layer)
    return (x, y, layer), (x, y + 1, layer)


def add_if_nonzero(out, values):
    x1, y1, l1, x2, y2, l2 = values
    if x1 == x2 and y1 == y2 and l1 == l2:
        return
    out.append(split.format_seg(values))


def path_to_gridline_segments(design, path):
    coords = []
    for gx, gy, layer in path:
        x, y = split.grid_xy(design, gx, gy)
        coords.append((x, y, layer))

    out = []
    start = coords[0]
    last = coords[0]
    last_axis = None
    for cur in coords[1:]:
        if cur[2] != last[2]:
            axis = "L"
        elif cur[0] != last[0]:
            axis = "X"
        elif cur[1] != last[1]:
            axis = "Y"
        else:
            axis = "Z"
        if last_axis is None:
            last_axis = axis
        elif axis != last_axis:
            add_if_nonzero(out, start + last)
            start = last
            last_axis = axis
        last = cur
    add_if_nonzero(out, start + last)
    return out


def split_segment_with_edge_path(design, seg, edge, path):
    direction, x, y, layer = edge
    x1, y1, l1, x2, y2, l2 = split.parse_seg(seg)
    a, b = edge_endpoints(edge)
    ax, ay = split.grid_xy(design, a[0], a[1])
    bx, by = split.grid_xy(design, b[0], b[1])

    out = []
    if direction == "H":
        x1g, _ = dump.xytogrid(design, x1, y1)
        x2g, _ = dump.xytogrid(design, x2, y2)
        if x1g <= x2g:
            sx, sy, ex, ey = ax, ay, bx, by
            path_nodes = path
        else:
            sx, sy, ex, ey = bx, by, ax, ay
            path_nodes = list(reversed(path))
    else:
        _, y1g = dump.xytogrid(design, x1, y1)
        _, y2g = dump.xytogrid(design, x2, y2)
        if y1g <= y2g:
            sx, sy, ex, ey = ax, ay, bx, by
            path_nodes = path
        else:
            sx, sy, ex, ey = bx, by, ax, ay
            path_nodes = list(reversed(path))

    add_if_nonzero(out, (x1, y1, l1, sx, sy, layer))
    out.extend(path_to_gridline_segments(design, path_nodes))
    add_if_nonzero(out, (ex, ey, layer, x2, y2, l2))
    return out


def find_best_edge_astar(design, blocks, block_by_name, demand, rows, max_nets_per_edge, radius):
    current_total = sum(row["overflow"] for row in rows)
    current_edges = len(rows)
    best = None
    for row in rows:
        edge = (row["dir"], row["x"], row["y"], row["layer"])
        start, goal = edge_endpoints(edge)
        old_keys = [edge]
        for net in row["nets"][:max_nets_per_edge]:
            block = block_by_name.get(net)
            if block is None:
                continue
            demand_without_old = dict(demand)
            demand_without_old[edge] = demand_without_old.get(edge, 0) - fast.segment_demand(design, net, edge[3])
            minx = max(0, min(start[0], goal[0]) - radius)
            maxx = min(design["gridx"] - 1, max(start[0], goal[0]) + radius)
            miny = max(0, min(start[1], goal[1]) - radius)
            maxy = min(design["gridy"] - 1, max(start[1], goal[1]) + radius)
            path = astar_seg.astar(design, demand_without_old, net, start, goal, (minx, maxx, miny, maxy))
            if path is None:
                continue
            new_keys = astar_seg.path_edge_keys(path)
            before_total, before_edges, after_total, after_edges = astar_seg.score_replacement(
                design, demand, net, old_keys, new_keys
            )
            total_after = current_total - before_total + after_total
            edges_after = current_edges - before_edges + after_edges
            if (total_after, edges_after) >= (current_total, current_edges):
                continue
            for seg_i, seg in enumerate(block[2]):
                nums = split.parse_seg(seg)
                if len(nums) == 6 and split.segment_covers(design, nums, edge):
                    cand = {
                        "score": (total_after, edges_after),
                        "edge": edge,
                        "net": net,
                        "seg_i": seg_i,
                        "path": path,
                        "segs": split_segment_with_edge_path(design, seg, edge, path),
                    }
                    if best is None or cand["score"] < best["score"]:
                        best = cand
                    break
    return best


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--design", required=True)
    parser.add_argument("--route", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--work-prefix", required=True)
    parser.add_argument("--max-passes", type=int, default=8)
    parser.add_argument("--max-nets-per-edge", type=int, default=64)
    parser.add_argument("--radius", type=int, default=20)
    args = parser.parse_args()

    design = dump.parse_design(args.design)
    blocks = split.parse_route(args.route)
    block_by_name = {block[1]: block for block in blocks}
    applied = []
    for pass_i in range(args.max_passes):
        demand, edge_nets = fast.compute_usage(design, blocks)
        rows, total = fast.overflow_rows(design, demand, edge_nets)
        print("pass={} overflow_edges={} total_overflow={}".format(pass_i, len(rows), total), flush=True)
        if total == 0:
            break
        move = find_best_edge_astar(design, blocks, block_by_name, demand, rows, args.max_nets_per_edge, args.radius)
        if move is None:
            print("pass={} no_improvement".format(pass_i), flush=True)
            break
        block = block_by_name[move["net"]]
        seg_i = move["seg_i"]
        block[2] = block[2][:seg_i] + move["segs"] + block[2][seg_i + 1 :]
        applied.append((pass_i, move["edge"], move["net"], len(move["path"]), move["score"][0], move["score"][1]))
        print("pass={} applied={}".format(pass_i, applied[-1]), flush=True)

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    split.write_route(blocks, out)
    final_edges, final_total, _rows = split.run_dump(args.design, out, Path(args.work_prefix + ".final"))
    print("applied={}".format(applied), flush=True)
    print("final_overflow_edges={}".format(final_edges), flush=True)
    print("final_total_overflow={}".format(final_total), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
