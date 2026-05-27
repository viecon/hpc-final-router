#!/usr/bin/env python3
"""Capacity-aware local A* reroute for near-legal overflow segments."""

import argparse
import heapq
from pathlib import Path

import dump_overflow_edges as dump
import targeted_edge_split_repair as split
import targeted_edge_split_fast_repair as fast


def key_capacity(design, key):
    direction, x, y, layer = key
    return fast.capacity(design, direction, x, y, layer)


def segment_edge_keys(design, seg):
    nums = split.parse_seg(seg)
    if len(nums) != 6:
        return []
    x1, y1, l1, x2, y2, _l2 = nums
    x1g, y1g = dump.xytogrid(design, x1, y1)
    x2g, y2g = dump.xytogrid(design, x2, y2)
    keys = []
    if x1g != x2g:
        for x in range(min(x1g, x2g), max(x1g, x2g)):
            keys.append(("H", x, y1g, l1))
    elif y1g != y2g:
        for y in range(min(y1g, y2g), max(y1g, y2g)):
            keys.append(("V", x1g, y, l1))
    return keys


def path_edge_keys(path):
    keys = []
    for a, b in zip(path, path[1:]):
        x1, y1, l1 = a
        x2, y2, l2 = b
        if l1 != l2:
            continue
        if x1 != x2:
            keys.append(("H", min(x1, x2), y1, l1))
        elif y1 != y2:
            keys.append(("V", x1, min(y1, y2), l1))
    return keys


def overflow_total_for_keys(design, demand, keys):
    total = 0
    edges = 0
    for key in set(keys):
        over = max(0, demand.get(key, 0) - key_capacity(design, key))
        total += over
        edges += 1 if over > 0 else 0
    return total, edges


def replacement_amounts(design, net, old_keys, new_keys):
    old_amounts = {}
    for key in old_keys:
        old_amounts[key] = old_amounts.get(key, 0) + fast.segment_demand(design, net, key[3])
    new_amounts = {}
    for key in new_keys:
        new_amounts[key] = new_amounts.get(key, 0) + fast.segment_demand(design, net, key[3])
    return old_amounts, new_amounts


def score_replacement(design, demand, net, old_keys, new_keys):
    touched = set(old_keys) | set(new_keys)
    old_amounts, new_amounts = replacement_amounts(design, net, old_keys, new_keys)

    before_total = 0
    before_edges = 0
    after_total = 0
    after_edges = 0
    for key in touched:
        before = max(0, demand.get(key, 0) - key_capacity(design, key))
        after_used = demand.get(key, 0) - old_amounts.get(key, 0) + new_amounts.get(key, 0)
        after = max(0, after_used - key_capacity(design, key))
        before_total += before
        before_edges += 1 if before > 0 else 0
        after_total += after
        after_edges += 1 if after > 0 else 0
    return before_total, before_edges, after_total, after_edges


def key_after_overflow(design, demand, key, old_amounts, new_amounts):
    after_used = demand.get(key, 0) - old_amounts.get(key, 0) + new_amounts.get(key, 0)
    return max(0, after_used - key_capacity(design, key))


def move_cost(design, demand_without_old, net, a, b):
    x1, y1, l1 = a
    x2, y2, l2 = b
    if l1 != l2:
        return 3
    if x1 != x2:
        key = ("H", min(x1, x2), y1, l1)
    elif y1 != y2:
        key = ("V", x1, min(y1, y2), l1)
    else:
        return 0
    cap = key_capacity(design, key)
    if cap <= 0:
        return None
    amount = fast.segment_demand(design, net, l1)
    used_after = demand_without_old.get(key, 0) + amount
    overflow_after = max(0, used_after - cap)
    spare = cap - demand_without_old.get(key, 0)
    return 1 + overflow_after * 1000 + max(0, 3 - spare)


def astar(design, demand_without_old, net, start, goal, bounds):
    minx, maxx, miny, maxy = bounds
    h = lambda n: abs(n[0] - goal[0]) + abs(n[1] - goal[1]) + (0 if n[2] == goal[2] else 1)
    pq = [(h(start), 0, start)]
    prev = {}
    best = {start: 0}
    while pq:
        _prio, cost, node = heapq.heappop(pq)
        if node == goal:
            path = [node]
            while node in prev:
                node = prev[node]
                path.append(node)
            path.reverse()
            return path
        if cost != best.get(node):
            continue
        x, y, layer = node
        neigh = []
        if x > minx:
            neigh.append((x - 1, y, layer))
        if x < maxx:
            neigh.append((x + 1, y, layer))
        if y > miny:
            neigh.append((x, y - 1, layer))
        if y < maxy:
            neigh.append((x, y + 1, layer))
        if layer > 1:
            neigh.append((x, y, layer - 1))
        if layer < design["layers"]:
            neigh.append((x, y, layer + 1))
        for nxt in neigh:
            step = move_cost(design, demand_without_old, net, node, nxt)
            if step is None:
                continue
            new_cost = cost + step
            if new_cost < best.get(nxt, 10**18):
                best[nxt] = new_cost
                prev[nxt] = node
                heapq.heappush(pq, (new_cost + h(nxt), new_cost, nxt))
    return None


def path_to_segments(design, path, start_xy, end_xy):
    coords = []
    for i, (gx, gy, layer) in enumerate(path):
        if i == 0:
            coords.append((start_xy[0], start_xy[1], layer))
        elif i == len(path) - 1:
            coords.append((end_xy[0], end_xy[1], layer))
        else:
            x, y = split.grid_xy(design, gx, gy)
            coords.append((x, y, layer))

    if len(coords) < 2:
        return []
    segs = []
    seg_start = coords[0]
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
            segs.append(split.format_seg(seg_start + last))
            seg_start = last
            last_axis = axis
        last = cur
    segs.append(split.format_seg(seg_start + last))
    return [seg for seg in segs if split.parse_seg(seg)[:3] != split.parse_seg(seg)[3:]]


def find_best_astar(
    design,
    blocks,
    block_by_name,
    demand,
    rows,
    max_nets_per_edge,
    radius,
    allow_equal_displacement,
):
    current_total = sum(row["overflow"] for row in rows)
    current_edges = len(rows)
    best = None
    for row in rows:
        edge = (row["dir"], row["x"], row["y"], row["layer"])
        for net in row["nets"][:max_nets_per_edge]:
            block = block_by_name.get(net)
            if block is None:
                continue
            for seg_i, seg in enumerate(block[2]):
                nums = split.parse_seg(seg)
                if len(nums) != 6 or not split.segment_covers(design, nums, edge):
                    continue
                old_keys = segment_edge_keys(design, seg)
                if not old_keys:
                    continue
                demand_without_old = dict(demand)
                for key in old_keys:
                    demand_without_old[key] = demand_without_old.get(key, 0) - fast.segment_demand(
                        design, net, key[3]
                    )
                x1, y1, l1, x2, y2, l2 = nums
                sx, sy = dump.xytogrid(design, x1, y1)
                gx, gy = dump.xytogrid(design, x2, y2)
                minx = max(0, min(sx, gx, edge[1]) - radius)
                maxx = min(design["gridx"] - 1, max(sx, gx, edge[1] + 1) + radius)
                miny = max(0, min(sy, gy, edge[2]) - radius)
                maxy = min(design["gridy"] - 1, max(sy, gy, edge[2] + 1) + radius)
                path = astar(
                    design,
                    demand_without_old,
                    net,
                    (sx, sy, l1),
                    (gx, gy, l2),
                    (minx, maxx, miny, maxy),
                )
                if path is None:
                    continue
                new_keys = path_edge_keys(path)
                before_total, before_edges, after_total, after_edges = score_replacement(
                    design, demand, net, old_keys, new_keys
                )
                total_after = current_total - before_total + after_total
                edges_after = current_edges - before_edges + after_edges
                old_amounts, new_amounts = replacement_amounts(design, net, old_keys, new_keys)
                old_hotspot_key = (row["dir"], row["x"], row["y"], row["layer"])
                clears_hotspot = (
                    key_after_overflow(
                        design, demand, old_hotspot_key, old_amounts, new_amounts
                    )
                    == 0
                )
                improves = (total_after, edges_after) < (current_total, current_edges)
                displaces = (
                    allow_equal_displacement
                    and clears_hotspot
                    and (total_after, edges_after) <= (current_total, current_edges)
                )
                if not improves and not displaces:
                    continue
                segs = path_to_segments(design, path, (x1, y1), (x2, y2))
                cand = {
                    "score": (total_after, edges_after, 0 if improves else 1),
                    "edge": edge,
                    "net": net,
                    "seg_i": seg_i,
                    "segs": segs,
                    "path_len": len(path),
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
    parser.add_argument("--radius", type=int, default=10)
    parser.add_argument("--allow-equal-displacement", action="store_true")
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
        move = find_best_astar(
            design,
            blocks,
            block_by_name,
            demand,
            rows,
            args.max_nets_per_edge,
            args.radius,
            args.allow_equal_displacement,
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
                move["path_len"],
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
