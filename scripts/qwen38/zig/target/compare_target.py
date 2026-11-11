#!/usr/bin/env python3
"""compare_target.py [ROOT] [ARM...] - our cells against the target document's measured rows.

Reads ~/work/target/bench/<arm>/c<C>/arm.log (the same files bench_sum.py reads), takes the median of the three
passes per kind, and prints one table per arm with the target figure and the delta. The target rows are copied from
docs/SPEED-TARGET-1.2.6.md, measured on the older production stack at fp8 KV and 262,144-token windows.
"""
from __future__ import annotations

import glob
import os
import re
import statistics as st
import sys

# docs/SPEED-TARGET-1.2.6.md, decode: aggregate tok/s (prose, code) and the per-stream median in brackets.
TARGET_DEC = {
    1: ((70.9, 113.0), (71.0, 113.4)),
    2: ((103.3, 173.7), (60.0, 100.9)),
    4: ((162.3, 254.0), (42.9, 66.4)),
    6: ((202.2, 311.8), (34.8, 53.2)),
}
# docs/SPEED-TARGET-1.2.6.md, cold TTFT seconds at C=1 (thinking off), idle.
TARGET_TTFT = {"1k": 0.42, "8k": 2.65, "32k": 10.77, "120k": 42.76}


def cells(root: str, arm: str) -> dict[int, dict]:
    out: dict[int, dict] = {}
    for log in sorted(glob.glob(os.path.join(root, "bench", arm, "c*", "arm.log"))):
        c = int(re.search(r"c(\d+)$", os.path.dirname(log))[1])
        agg: dict[str, list[float]] = {"prose": [], "code": []}
        med: dict[str, list[float]] = {"prose": [], "code": []}
        ttft: dict[str, float] = {}
        for line in open(log, encoding="utf-8", errors="replace"):
            m = re.match(r"DEC .*? C=(\d+) (\w+) pass\d+: per-stream med ([\d.]+) min [\d.]+ agg ([\d.]+)", line)
            if m and m[2] in agg:
                agg[m[2]].append(float(m[4]))
                med[m[2]].append(float(m[3]))
            m = re.match(r"TTFT summary (\S+) (\S+) n (\d+) ttft med ([\d.]+)", line)
            if m and int(m[3]) > 0 and m[2] == "off":
                ttft[m[1]] = float(m[4])
        out[c] = {
            "agg": {k: (st.median(v) if v else None) for k, v in agg.items()},
            "med": {k: (st.median(v) if v else None) for k, v in med.items()},
            "ttft": ttft,
        }
    return out


def pct(ours: float | None, target: float | None) -> str:
    if not ours or not target:
        return "  -"
    return f"{(ours / target - 1) * 100:+5.1f}%"


def main() -> None:
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/work/target")
    arms = sys.argv[2:] or ["catchup-stack", "prod2"]
    for arm in arms:
        data = cells(root, arm)
        if not data:
            continue
        print(f"\n## {arm}")
        print("| streams | prose agg | target | delta | code agg | target | delta | per-stream prose | target |")
        print("|---|---|---|---|---|---|---|---|---|")
        for c in sorted(data):
            d = data[c]
            t = TARGET_DEC.get(c)
            ta, tm = (t if t else ((None, None), (None, None)))
            print(
                f"| {c} | {d['agg']['prose'] or float('nan'):.1f} | {ta[0] or '-'} | "
                f"{pct(d['agg']['prose'], ta[0])} | {d['agg']['code'] or float('nan'):.1f} | {ta[1] or '-'} | "
                f"{pct(d['agg']['code'], ta[1])} | {d['med']['prose'] or float('nan'):.1f} | {tm[0] or '-'} |"
            )
        d = data.get(1, {}).get("ttft", {})
        if d:
            print("\n| cold TTFT C=1 off | ours s | target s | delta |")
            print("|---|---|---|---|")
            for k in ("1k", "8k", "32k", "120k"):
                if k in d:
                    print(f"| {k} | {d[k]:.2f} | {TARGET_TTFT[k]:.2f} | {pct(TARGET_TTFT[k], d[k])} |")


if __name__ == "__main__":
    main()
