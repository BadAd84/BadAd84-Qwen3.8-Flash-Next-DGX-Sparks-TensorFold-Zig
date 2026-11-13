#!/usr/bin/env python3
"""rfgrid.py LOG ROUNDS LABEL [NVFP4|INT4] - the expert launches of a run split by grid width.

One grid width is one call shape (the drafter's small item counts and the backbone's large ones land on different
widths), so this separates what the family table averages: bytes, time and GB a second a shape.
"""
import collections
import re
import sys


def main() -> None:
    log, rounds, label = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    fmt = sys.argv[4] if len(sys.argv) > 4 else "NVFP4"
    per_weight = 0.5625 if fmt == "NVFP4" else 0.5 + 2.0 / 128.0

    ex = collections.defaultdict(lambda: {"made": 0, "items": 0, "bytes": 0.0, "calls": 0, "name": "", "n": 0, "k": 0})
    kt = collections.defaultdict(lambda: [0.0, 0, ""])
    for line in open(log, errors="ignore"):
        m = re.search(r"expert log: (\S+) grid (\d+) items (\d+) made (-?\d+) mats (\d+) n (\d+) k (\d+)", line)
        if m:
            name, grid = m.group(1), int(m.group(2))
            items, made, mats = int(m.group(3)), int(m.group(4)), int(m.group(5))
            n, k = int(m.group(6)), int(m.group(7))
            e = ex[grid]
            real = made if made >= 0 else items
            e["made"] += real
            e["items"] += items
            e["bytes"] += real * n * k * mats * per_weight
            e["calls"] += 1
            e["name"], e["n"], e["k"] = name, n, k
            continue
        m = re.search(r"kernel log: ([\d.]+) ms (\d+) launches [\d.]+ us each grid (\d+) (.*)$", line)
        if m:
            grid = int(m.group(3))
            e = kt[grid]
            e[0] += float(m.group(1))
            e[1] += int(m.group(2))
            e[2] = m.group(4).strip()[:28]

    print("== %s: %d rounds, %s" % (label, rounds, fmt))
    print("   %-18s %6s %8s %7s %7s %9s %7s %8s %7s" % ("call", "grid", "launch/rd", "items", "made", "MB/rd", "ms/rd", "us/call", "GB/s"))
    for grid, e in sorted(ex.items(), key=lambda kv: -kv[1]["bytes"]):
        ms, calls, _sym = kt.get(grid, [0.0, 0, ""])
        gb = (e["bytes"] / 1e9) / (ms / 1000) if ms > 0 else 0.0
        us = (ms * 1000 / calls) if calls else 0.0
        print("   %-18s %6d %8.1f %7.0f %7.0f %9.1f %7.2f %8.0f %7.0f" % (
            e["name"], grid, e["calls"] / rounds, e["items"] / e["calls"], e["made"] / e["calls"],
            e["bytes"] / 1e6 / rounds, ms / rounds, us, gb))


if __name__ == "__main__":
    main()
