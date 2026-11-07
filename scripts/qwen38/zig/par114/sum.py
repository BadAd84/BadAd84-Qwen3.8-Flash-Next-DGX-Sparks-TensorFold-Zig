#!/usr/bin/env python3
"""sum.py [RUNS_DIR]: the par114 matrix (stock = recipe v1.1.4 on NVIDIA FP4, ours = zmerge8-kfix on INT4) summarised.

Per cell (arm, C): boot seconds, the boot's sequence-memory line, golden identical count against the 1.0.0 INT4
reference, decode = median over passes of the aggregate tok/s (sum of completion tokens / the pass wall) and of the
per-stream median tok/s (prose, code) with the requests counted per pass (fewer than C means a failed request),
TTFT = median seconds per size and load from ttft.py's lines. Reply shas are not compared: tfm_decode rotates the
prompt per pass and adds a nonce. Prints one Markdown table per metric."""
import glob
import json
import os
import re
import statistics
import sys
from collections import defaultdict

RUNS = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/work/lanes/par114/runs")
TT = re.compile(r"^TTFT sample (\S+) (\S+) ttft ([\d.]+) ")
BOOT = re.compile(r"^BOOT seconds (\d+)")
GOLD = re.compile(r"^GOLD .*: (\d+)/(\d+) identical")
MEM = re.compile(r"sequence memory: ([\d.]+ GiB) \(([\d.]+ GiB free)")
TEMP = re.compile(r"probe dec temp (\d+)")


def med(v):
    return statistics.median(v) if v else None


def f(v, d=1):
    return "-" if v is None else f"{v:.{d}f}"


cells = {}
for d in sorted(glob.glob(os.path.join(RUNS, "*-c*"))):
    name = os.path.basename(d)
    arm, c = name.rsplit("-c", 1)
    cell = {"arm": arm, "C": int(c), "boot": None, "mem": "-", "gold": "-", "temp": "-", "dec": {}, "ttft": {}}
    try:
        log = open(os.path.join(d, "arm.log"), errors="replace").read().splitlines()
    except FileNotFoundError:
        continue
    ttft = defaultdict(list)
    for line in log:
        if m := BOOT.match(line):
            cell["boot"] = int(m.group(1))
        elif m := GOLD.match(line):
            cell["gold"] = f"{m.group(1)}/{m.group(2)}"
        elif m := MEM.search(line):
            cell["mem"] = f"{m.group(1)} ({m.group(2)})"
        elif m := TEMP.search(line):
            cell["temp"] = m.group(1)
        elif m := TT.match(line):
            ttft[(m.group(1), m.group(2))].append(float(m.group(3)))
    cell["ttft"] = {k: med(v) for k, v in ttft.items()}
    rows = []
    try:
        rows = [json.loads(x) for x in open(os.path.join(d, "dec.jsonl")) if x.strip()]
    except FileNotFoundError:
        pass
    for kind in ("prose", "code"):
        passes = defaultdict(list)
        for r in rows:
            if r["kind"] == kind:
                passes[r["pass"]].append(r)
        aggs, meds, counts = [], [], []
        for p, rs in sorted(passes.items()):
            toks = sum(r["completion_tokens"] for r in rs)
            wall = max(r["wall"] for r in rs)
            aggs.append(toks / wall if wall else 0.0)
            meds.append(med([r["rate"] for r in rs]))
            counts.append(len(rs))
        cell["dec"][kind] = (med(aggs), med(meds), len(passes), min(counts) if counts else 0)
    cells[(arm, int(c))] = cell

levels = sorted({c for _, c in cells})
arms = ["stock", "ours", "up124"]
print("| streams | arm | boot s | sequence memory | golden vs 1.0.0 INT4 | GPU C at decode |")
print("|---|---|---:|---|---|---:|")
for c in levels:
    for a in arms:
        if (a, c) in cells:
            x = cells[(a, c)]
            print(f"| {c} | {a} | {f(x['boot'], 0)} | {x['mem']} | {x['gold']} | {x['temp']} |")
print()
print("| streams | prose agg stock / ours | prose per-stream stock / ours | code agg stock / ours | code per-stream stock / ours | requests a pass stock / ours |")
print("|---|---|---|---|---|---|")
for c in levels:
    s, o = cells.get(("stock", c)), cells.get(("ours", c))

    def pair(kind, i):
        a = s["dec"].get(kind, (None, None, 0, 0))[i] if s else None
        b = o["dec"].get(kind, (None, None, 0, 0))[i] if o else None
        gain = f" ({(b / a - 1) * 100:+.1f}%)" if a and b else ""
        return f"{f(a)} / {f(b)}{gain}"
    def reqs(x):
        return "-" if not x else "/".join(str(x["dec"].get(k, (0, 0, 0, 0))[3]) for k in ("prose", "code"))

    print(f"| {c} | {pair('prose', 0)} | {pair('prose', 1)} | {pair('code', 0)} | {pair('code', 1)} | {reqs(s)} / {reqs(o)} |")
print()
print("| streams | arm | prose agg | prose per-stream | code agg | code per-stream | requests a pass |")
print("|---|---|---:|---:|---:|---:|---|")
for c in levels:
    for a in arms:
        if (a, c) in cells and cells[(a, c)]["dec"]:
            x = cells[(a, c)]["dec"]
            pr, co = x.get("prose", (None, None, 0, 0)), x.get("code", (None, None, 0, 0))
            print(f"| {c} | {a} | {f(pr[0])} | {f(pr[1])} | {f(co[0])} | {f(co[1])} | {pr[3]}/{co[3]} |")
print()
sizes = ["cold1k-off", "cold8k-off", "cold32k-off", "cold120k-off"]
print("| streams | arm | load | " + " | ".join(f"TTFT {s} s" for s in sizes) + " |")
print("|---|---|---|" + "---:|" * len(sizes))
for c in levels:
    for a in arms:
        if (a, c) not in cells:
            continue
        x = cells[(a, c)]
        loads = sorted({k[1] for k in x["ttft"]})
        for ld in loads:
            print(f"| {c} | {a} | {ld} | " + " | ".join(f(x['ttft'].get((sz, ld)), 2) for sz in sizes) + " |")
