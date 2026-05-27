#!/usr/bin/env python3
"""Dump overflowed 3D edges and nets from an ISPD route output.

Python 3.6-compatible on Taiwania login nodes.
"""

import argparse
import csv
import gzip
import re
from collections import defaultdict
from pathlib import Path


def read_text(path):
    path = Path(path)
    if path.suffix == ".gz":
        with gzip.open(str(path), "rt") as f:
            return f.read()
    with path.open("r", encoding="utf-8", errors="replace") as f:
        return f.read()


def non_empty_lines(text):
    return [line.strip() for line in text.splitlines() if line.strip()]


def prefixed_ints(line, prefix, count):
    m = re.match(r"^\s*" + re.escape(prefix) + r"\s+(.*)\s*$", line)
    if not m:
        raise RuntimeError("expected '{}': {}".format(prefix, line))
    values = [int(v) for v in m.group(1).split()]
    if len(values) != count:
        raise RuntimeError("bad {} count".format(prefix))
    return values


def parse_design(path):
    lines = non_empty_lines(read_text(path))
    i = 0
    m = re.match(r"^grid\s+(\d+)\s+(\d+)\s+(\d+)\s*$", lines[i])
    if not m:
        raise RuntimeError("bad grid line")
    gridx, gridy, layers = [int(v) for v in m.groups()]
    i += 1
    vcap = prefixed_ints(lines[i], "vertical capacity", layers)
    i += 1
    hcap = prefixed_ints(lines[i], "horizontal capacity", layers)
    i += 1
    minw = prefixed_ints(lines[i], "minimum width", layers)
    i += 1
    mins = prefixed_ints(lines[i], "minimum spacing", layers)
    i += 1
    prefixed_ints(lines[i], "via spacing", layers)
    i += 1
    llx, lly, xsize, ysize = [int(v) for v in lines[i].split()]
    i += 1
    m = re.match(r"^num\s+net\s+(\d+)\s*$", lines[i])
    if not m:
        raise RuntimeError("bad num net line")
    net_count = int(m.group(1))
    i += 1

    nets = {}
    for _ in range(net_count):
        parts = lines[i].split()
        name = parts[0]
        net_id = int(parts[1])
        pin_count = int(parts[2])
        net_min_width = int(parts[3])
        i += 1
        i += pin_count
        nets[name] = {"id": net_id, "min_width": net_min_width}

    h_override = {}
    v_override = {}
    while i < len(lines):
        block_count = int(lines[i])
        i += 1
        for _ in range(block_count):
            x1, y1, l1, x2, y2, l2, cap = [int(v) for v in lines[i].split()]
            l1 -= 1
            l2 -= 1
            if x1 != x2:
                h_override[(min(x1, x2), y1, l1)] = cap
            elif y1 != y2:
                v_override[(x1, min(y1, y2), l1)] = cap
            i += 1

    return {
        "gridx": gridx,
        "gridy": gridy,
        "layers": layers,
        "vcap": vcap,
        "hcap": hcap,
        "minw": minw,
        "mins": mins,
        "llx": llx,
        "lly": lly,
        "xsize": xsize,
        "ysize": ysize,
        "nets": nets,
        "h_override": h_override,
        "v_override": v_override,
    }


def xytogrid(design, x, y):
    return (x - design["llx"]) // design["xsize"], (y - design["lly"]) // design["ysize"]


def cap_h(design, key):
    return design["h_override"].get(key, design["hcap"][key[2]])


def cap_v(design, key):
    return design["v_override"].get(key, design["vcap"][key[2]])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--design", required=True)
    parser.add_argument("--route", required=True)
    parser.add_argument("--out-prefix", required=True)
    args = parser.parse_args()

    design = parse_design(args.design)
    lines = non_empty_lines(read_text(args.route))
    demand_h = defaultdict(int)
    demand_v = defaultdict(int)
    edge_nets_h = defaultdict(set)
    edge_nets_v = defaultdict(set)

    i = 0
    while i < len(lines):
        m = re.match(r"^(\S+)\s+(\d+)(?:\s+(\d+))?\s*$", lines[i])
        if not m:
            raise RuntimeError("bad route net header: {}".format(lines[i]))
        net_name = m.group(1)
        net = design["nets"][net_name]
        i += 1
        while i < len(lines) and lines[i] != "!":
            m = re.match(r"^\((\d+),(\d+),(\d+)\)-\((\d+),(\d+),(\d+)\)\s*$", lines[i])
            if not m:
                raise RuntimeError("bad route segment: {}".format(lines[i]))
            x1, y1, l1, x2, y2, l2 = [int(v) for v in m.groups()]
            l1 -= 1
            l2 -= 1
            x1g, y1g = xytogrid(design, x1, y1)
            x2g, y2g = xytogrid(design, x2, y2)
            width = max(net["min_width"], design["minw"][l1])
            demand = width + design["mins"][l1]
            if x1g != x2g:
                if x2g < x1g:
                    x1g, x2g = x2g, x1g
                for x in range(x1g, x2g):
                    key = (x, y1g, l1)
                    demand_h[key] += demand
                    edge_nets_h[key].add(net_name)
            elif y1g != y2g:
                if y2g < y1g:
                    y1g, y2g = y2g, y1g
                for y in range(y1g, y2g):
                    key = (x1g, y, l1)
                    demand_v[key] += demand
                    edge_nets_v[key].add(net_name)
            i += 1
        i += 1

    out_prefix = Path(args.out_prefix)
    out_prefix.parent.mkdir(parents=True, exist_ok=True)
    edges_path = Path(str(out_prefix) + ".edges.csv")
    nets_path = Path(str(out_prefix) + ".nets.csv")
    net_overflow = defaultdict(int)
    rows = []

    for key, demand in demand_h.items():
        cap = cap_h(design, key)
        overflow = demand - cap
        if overflow > 0:
            nets = sorted(edge_nets_h[key])
            for net in nets:
                net_overflow[net] += overflow
            rows.append(("H", key[0], key[1], key[2] + 1, demand, cap, overflow, ";".join(nets)))
    for key, demand in demand_v.items():
        cap = cap_v(design, key)
        overflow = demand - cap
        if overflow > 0:
            nets = sorted(edge_nets_v[key])
            for net in nets:
                net_overflow[net] += overflow
            rows.append(("V", key[0], key[1], key[2] + 1, demand, cap, overflow, ";".join(nets)))

    rows.sort(key=lambda r: (-r[6], r[0], r[1], r[2], r[3]))
    with edges_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["dir", "x", "y", "layer", "demand", "capacity", "overflow", "nets"])
        writer.writerows(rows)

    with nets_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["net", "overflow_score"])
        for net, score in sorted(net_overflow.items(), key=lambda kv: (-kv[1], kv[0])):
            writer.writerow([net, score])

    print("wrote {}".format(edges_path))
    print("wrote {}".format(nets_path))
    print("overflow_edges={}".format(len(rows)))
    print("overflow_nets={}".format(len(net_overflow)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
