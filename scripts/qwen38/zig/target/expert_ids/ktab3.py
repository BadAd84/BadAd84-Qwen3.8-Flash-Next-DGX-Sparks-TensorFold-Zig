#!/usr/bin/env python3
"""ktab3.py LOGS [LOGS...] - the kernel log's decode window a round, by kernel family and by kernel.

The decode window is the second table (the first is the boot self-check; a trailing request closes the decode
window). Rounds are the server's own `done` lines between the two tables. Families by symbol: experts, dense
projections (vocab-wide launches split out as the head), hyper-connection, attention and DeltaNet, routing, rest.
"""
import collections
import re
import sys

HEAD = re.compile(r"^kernel log: window ([\d.]+) ms wall, ([\d.]+) ms in kernels, (\d+) launches")
ROW = re.compile(r"^kernel log: ([\d.]+) ms (\d+) launches ([\d.]+) us each grid (\d+) (.*)$")
DONE = re.compile(r"done chatcmpl-\S+ .* rounds=(\d+)")


def family(sym, grid):
    s = sym.lower()
    if any(k in s for k in ("expert", "int4_kernel", "fact_")):
        return "experts"
    if any(k in s for k in ("route", "router", "topk", "plan_kernel")):
        return "routing"
    if "qmm" in s or "mm" in s.split("_")[-1] or "_b16mm" in s or "_fp4mm" in s:
        return "head (vocab-wide)" if grid >= 3000 else "dense projections"
    if "hc" in s:
        return "hyper-connection"
    if any(k in s for k in ("gdn", "attn", "fa_", "flash", "tree_kernel", "chunks")):
        return "attention and DeltaNet"
    return "rest"


def main():
    for path in sys.argv[1:]:
        tables, rounds, rows = 0, 0, []
        wall = kern = 0.0
        for line in open(path, errors="replace"):
            m = HEAD.match(line)
            if m:
                tables += 1
                if tables == 2:
                    wall, kern = float(m.group(1)), float(m.group(2))
                continue
            m = ROW.match(line)
            if m and tables == 2:
                rows.append((float(m.group(1)), int(m.group(2)), float(m.group(3)), int(m.group(4)), m.group(5).strip()))
                continue
            m = DONE.search(line)
            if m and tables == 1:
                rounds += int(m.group(1))
        R = max(rounds, 1)
        fam = collections.defaultdict(float)
        for ms, n, us, grid, sym in rows:
            fam[family(sym, grid)] += ms
        print(f"== {path}: rounds {rounds}, decode window {wall/R:.2f} ms wall and {kern/R:.2f} ms in kernels a round")
        for f, ms in sorted(fam.items(), key=lambda x: -x[1]):
            print(f"   {f:24s} {ms/R:7.2f} ms a round")
        print(f"   {'(rows under 0.5 ms not printed)':24s} {(kern - sum(fam.values()))/R:7.2f}")
        for ms, n, us, grid, sym in rows[:14]:
            print(f"   {ms/R:6.2f} ms {n/R:6.1f}/round {us:7.1f} us grid {grid:5d} {sym[:70]}")


if __name__ == "__main__":
    main()
