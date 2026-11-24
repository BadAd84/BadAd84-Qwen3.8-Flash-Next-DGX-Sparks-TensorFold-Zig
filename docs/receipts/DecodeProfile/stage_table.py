#!/usr/bin/env python3
"""stage_table.py DIR [DIR2 ...]

Read each arm directory's rounds.txt (the engine's own TF_FLASHNEXT_PROFILE=1 decode-round table) and
print a per-stage table: stage, ms a round, share of the round, and - when two or more arms are given -
the delta against the first arm.

rounds.txt lines look like:
  rounds rank 0 decode: 122 rounds, wall 42.41 ms a round, GPU timeline 42.41 ms a round (main 37.20, MTP head 5.20)
  rounds rank 0 decode   stage               0.939 ms a round    2.2%
  rounds rank 0 decode   gdn_proj            7.313 ms a round   17.2%
  rounds rank 0 decode   mtp level 0 (absorb)    1.543 ms a round
"""
import os
import re
import sys

HDR = re.compile(r"rounds rank (\d+) decode: (\d+) rounds, wall ([\d.]+) ms a round, "
                 r"GPU timeline ([\d.]+) ms a round \(main ([\d.]+), MTP head ([\d.]+)\)")
ROW = re.compile(r"rounds rank \d+ decode\s+(\S+)\s+([\d.]+) ms a round\s+([\d.]+)%")
LVL = re.compile(r"rounds rank \d+ decode\s+mtp level (\d+)(?: \(absorb\))?\s+([\d.]+) ms a round")


def read(d):
    p = os.path.join(d, "rounds.txt")
    hdr = None
    rows = {}
    lvls = {}
    if not os.path.exists(p):
        return None
    for line in open(p, encoding="utf-8", errors="replace"):
        m = HDR.search(line)
        if m:
            hdr = {"rank": m.group(1), "rounds": int(m.group(2)), "wall": float(m.group(3)),
                   "gpu": float(m.group(4)), "main": float(m.group(5)), "mtp": float(m.group(6))}
            continue
        m = ROW.search(line)
        if m:
            rows[m.group(1)] = (float(m.group(2)), float(m.group(3)))
            continue
        m = LVL.search(line)
        if m:
            lvls[int(m.group(1))] = float(m.group(2))
    return {"header": hdr, "rows": rows, "levels": lvls, "path": p}


def main():
    arms = sys.argv[1:]
    data = {}
    for a in arms:
        r = read(a)
        if r is None:
            print("MISSING %s/rounds.txt" % a)
            continue
        data[os.path.basename(os.path.normpath(a))] = r
    names = list(data.keys())
    if not names:
        return 1
    print("== headers ==")
    for n in names:
        h = data[n]["header"]
        if h:
            print("  %-8s rounds %d  wall %.2f ms  GPU %.2f ms  main %.2f  MTP %.2f" %
                  (n, h["rounds"], h["wall"], h["gpu"], h["main"], h["mtp"]))
    # union of stages
    stages = []
    for n in names:
        for s in data[n]["rows"]:
            if s not in stages:
                stages.append(s)
    base = names[0]
    print("\n== per-stage: ms a round (share of the GPU timeline) ==")
    hdr = "  %-18s" % "stage" + "".join("%18s" % n for n in names)
    if len(names) > 1:
        hdr += "%14s" % ("delta vs " + base)
    print(hdr)
    for s in stages:
        cells = []
        for n in names:
            v = data[n]["rows"].get(s)
            cells.append("%9.3f (%4.1f%%)" % v if v else "%18s" % "-")
        line = "  %-18s" % s + "".join("%18s" % c for c in cells)
        if len(names) > 1:
            v0 = data[base]["rows"].get(s, (0,))[0]
            deltas = [data[n]["rows"].get(s, (0,))[0] - v0 for n in names]
            line += "%+14.3f" % deltas[-1]
        print(line)
    # totals
    print("\n  %-18s" % "SUM(stages)" + "".join("%18.3f" % sum(v[0] for v in data[n]["rows"].values()) for n in names))
    print("\n== MTP head by draft level (ms a round) ==")
    levels = sorted({l for n in names for l in data[n]["levels"]})
    print("  %-8s" % "level" + "".join("%14s" % n for n in names))
    for l in levels:
        print("  %-8d" % l + "".join("%14.3f" % data[n]["levels"].get(l, 0.0) for n in names))
    return 0


if __name__ == "__main__":
    sys.exit(main())
