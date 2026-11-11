#!/usr/bin/env python3
"""bench_sum.py [ROOT] - the overnight 1.2.6 sweep as one table set, from ~/work/target/bench/<arm>/c<C>/arm.log.

Per arm and level: decode aggregate tok/s (prose, code; median of the passes), per-stream median, cold TTFT at
1k/8k/32k/120k thinking off (idle, and the bracketed under-load value), the warm 2k next turn, boot seconds and
the self-check line. Prints a decode table, a TTFT table for thinking off and on, and boot/golden lines.
"""
from __future__ import annotations
import glob
import os
import re
import statistics as st
import sys


def main() -> None:
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/work/target")
    arms = {}
    for log in sorted(glob.glob(os.path.join(root, "bench", "*", "c*", "arm.log"))):
        arm = log.split(os.sep)[-3]
        c = int(re.search(r"c(\d+)$", os.path.dirname(log))[1])
        text = open(log, encoding="utf-8", errors="replace").read()
        dec = {}
        ttft = {}
        boot = None
        check = ""
        for line in text.splitlines():
            m = re.match(r"DEC .*? C=(\d+) (\w+) pass(\d+): per-stream med ([\d.]+) min [\d.]+ agg ([\d.]+)", line)
            if m:
                d = dec.setdefault(m[2], {"agg": [], "med": []})
                d["agg"].append(float(m[5]))
                d["med"].append(float(m[4]))
            m = re.match(r"TTFT summary (\S+) (\S+) n (\d+) ttft med ([\d.]+)", line)
            if m and int(m[3]) > 0:
                ttft[(m[1], m[2])] = float(m[4])
            m = re.match(r"^BOOT seconds (\d+)", line, re.M)
            if m:
                boot = int(m[1])
            m = re.search(r"^BOOTLOG .*?(self-check: .*|widths [0-9-]+ are row-equal.*)", text, re.M)
            if m:
                check = m[1][:90]
        arms.setdefault(arm, {})[c] = {"dec": dec, "ttft": ttft, "boot": boot, "check": check}

    levels = sorted({c for a in arms.values() for c in a})
    print("### Decode, aggregate tok/s (per-stream median in brackets)\n")
    print("| arm | " + " | ".join(f"C={c} prose" for c in levels) + " | " + " | ".join(f"C={c} code" for c in levels) + " |")
    print("|---|" + "---|" * (2 * len(levels)))
    for arm in sorted(arms):
        cells = []
        for kind in ("prose", "code"):
            for c in levels:
                d = arms[arm].get(c, {}).get("dec", {}).get(kind)
                cells.append("-" if not d else f"{st.median(d['agg']):.1f} ({st.median(d['med']):.1f})")
        print(f"| {arm} | " + " | ".join(cells) + " |")

    print("\n### Cold TTFT thinking off, s (idle; bracket = under C-1 streams)\n")
    cases = ["cold1k-off", "cold8k-off", "cold32k-off", "cold120k-off", "warm2k"]
    print("| arm | C | " + " | ".join(cases) + " |")
    print("|---|---|" + "---|" * len(cases))
    for arm in sorted(arms):
        for c in levels:
            t = arms[arm].get(c, {}).get("ttft", {})
            if not t:
                continue
            cells = []
            for case in cases:
                idle = t.get((case, "idle"))
                load = None
                for (kase, load_), v in t.items():
                    if kase == case and load_ != "idle":
                        load = v
                cells.append("-" if idle is None else (f"{idle:.3f}" + (f" ({load:.3f})" if load else "")))
            print(f"| {arm} | {c} | " + " | ".join(cells) + " |")

    print("\n### Boot, self-check, golden\n")
    print("| arm | C | boot s | self-check |")
    print("|---|---|---|---|")
    for arm in sorted(arms):
        for c in levels:
            a = arms[arm].get(c, {})
            print(f"| {arm} | {c} | {a.get('boot', '-')} | {a.get('check', '')} |")


if __name__ == "__main__":
    main()
