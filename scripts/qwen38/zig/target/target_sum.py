#!/usr/bin/env python3
"""target_sum.py RUNS_DIR - the production target table from a target_queue.sh run.

Reads every runs/c<C>/arm.log and prints, as markdown:
  decode aggregate and per-stream median per kind at each concurrency (median of the 3 passes),
  cold TTFT at 1k/8k/32k/120k thinking off and on, idle and under C-1 streams (median of 2 reps),
  the warm +2k next turn on the kept 100k conversation,
  boot time, sequence memory, the golden line and the RigMark summary when a rigmark.log sits beside the runs.
Usage: python3 target_sum.py ~/work/target
"""
from __future__ import annotations
import glob
import os
import re
import statistics as st
import sys


def med(xs):
    xs = [x for x in xs if x is not None]
    return st.median(xs) if xs else None


def fmt(x, nd=1):
    return "-" if x is None else f"{x:.{nd}f}"


def main() -> None:
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/work/target")
    dec = {}          # (C, kind) -> dict of lists
    ttft = {}         # (case, load, C) -> med
    boot = {}
    mem = {}
    gold = {}
    cs = sorted(int(re.search(r"c(\d+)$", d)[1]) for d in glob.glob(os.path.join(root, "runs", "c*")))
    for c in cs:
        log = os.path.join(root, "runs", f"c{c}", "arm.log")
        if not os.path.exists(log):
            continue
        text = open(log, encoding="utf-8", errors="replace").read()
        m = re.search(r"^BOOT seconds (\d+)", text, re.M)
        if m:
            boot[c] = int(m[1])
        m = re.search(r"^BOOTLOG info: sequence memory: ([^\n]+)", text, re.M)
        if m:
            mem[c] = m[1].strip()
        for line in text.splitlines():
            m = re.match(r"DEC .*? C=(\d+) (\w+) pass(\d+): per-stream med ([\d.]+) min ([\d.]+) agg ([\d.]+) "
                         r"tok/wall ([\d.]+)", line)
            if m:
                d = dec.setdefault((int(m[1]), m[2]), {"med": [], "agg": [], "wall": []})
                d["med"].append(float(m[4]))
                d["agg"].append(float(m[6]))
                d["wall"].append(float(m[7]))
            m = re.match(r"TTFT summary (\S+) (\S+) n (\d+) ttft med ([\d.]+)", line)
            if m and int(m[3]) > 0:
                ttft[(m[1], m[2], c)] = float(m[4])
        m = re.search(r"^GOLD (\S+): (\S+)", text, re.M)
        if m:
            gold[c] = m[2]
    levels = cs
    cases = sorted({k[0] for k in ttft}, key=lambda s: (s.startswith("warm"), s))
    loads = sorted({k[1] for k in ttft}, key=lambda s: (s != "idle", s))

    print("### Decode, aggregate tok/s (per-stream median in brackets), median of 3 passes\n")
    print("| concurrency | prose | code |")
    print("|---|---|---|")
    for c in levels:
        row = [f"{c}"]
        for kind in ("prose", "code"):
            d = dec.get((c, kind))
            row.append(fmt(med(d["agg"])) + f" ({fmt(med(d['med']))})" if d else "-")
        print("| " + " | ".join(row) + " |")

    print("\n### Decode, tokens per wall second\n")
    print("| concurrency | prose | code |")
    print("|---|---|---|")
    for c in levels:
        vals = []
        for kind in ("prose", "code"):
            d = dec.get((c, kind))
            vals.append(fmt(med(d["wall"])) if d else "-")
        print(f"| {c} | {vals[0]} | {vals[1]} |")

    for load in loads:
        print(f"\n### Cold TTFT, {load} (s, median of 2 reps)\n")
        print("| case | " + " | ".join(str(c) for c in levels) + " |")
        print("|---|" + "---|" * len(levels))
        for case in cases:
            if case.startswith("warm"):
                continue
            row = [f"| {case} "]
            for c in levels:
                row.append(" " + fmt(ttft.get((case, load, c)), 3) + " ")
            print("|".join(row) + "|")
        warm = [case for case in cases if case.startswith("warm")]
        if warm:
            row = [f"| {warm[0]} (next turn, 100k kept) "]
            for c in levels:
                row.append(" " + fmt(ttft.get((warm[0], load, c)), 3) + " ")
            print("|".join(row) + "|")

    print("\n### Boot and memory\n")
    print("| concurrency | boot s | sequence memory | golden |")
    print("|---|---|---|---|")
    for c in levels:
        print(f"| {c} | {boot.get(c, '-')} | {mem.get(c, '-')} | {gold.get(c, '-')} |")

    rig = os.path.join(root, "rigmark.log")
    if os.path.exists(rig):
        text = open(rig, encoding="utf-8", errors="replace").read()
        s = re.search(r"^summary (\{.*\})$", text, re.M)
        r = re.search(r"^receipt (\S+)$", text, re.M)
        print("\n### RigMark\n")
        if s:
            print("```json\n" + s[1] + "\n```")
        if r:
            print(f"receipt: {r[1]}")


if __name__ == "__main__":
    main()
