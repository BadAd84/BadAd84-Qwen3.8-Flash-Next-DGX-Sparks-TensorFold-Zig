#!/usr/bin/env python3
"""sumW.py RECEIPT_DIR - the widths receipt as tables: per-arm decode tok/s with the #3162 noise rule per cell (slower
= both branch runs under both main runs and the mean gap over 1%), the alone/serial counts, accepted per round, and
each boot's resident memory."""
import json
import sys
from pathlib import Path

R = Path(sys.argv[1])
ARMS = ["M1", "B1", "B2", "M2"]


def cells(arm):
    d = json.loads((R / arm / "conc_t0.json").read_text())
    return {(c["prompt"], c["streams"]): c for c in d["cells"]}


def openai(arm):
    d = json.loads((R / arm / "openai_t0.json").read_text())
    return {r["prompt"]: r["decode_tps_median"] for r in d}


def metrics(arm):
    acc = {}
    for line in (R / arm / "metrics.txt").read_text().splitlines():
        name, when, *rest = line.split()
        acc.setdefault(name, {})[when] = dict(zip(rest[0::2], map(float, rest[1::2])))
    out = {}
    for name, w in acc.items():
        b, a = w.get("before", {}), w.get("after", {})
        d = {k.split(":")[-1]: a.get(k, 0) - b.get(k, 0) for k in a}
        out[name] = (d.get("mtp_accepted_total", 0), d.get("mtp_drafted_total", 0), d.get("decode_rounds_total", 0))
    return out


def mem(arm):
    for line in (R / "run.log").read_text().splitlines():
        parts = line.split()
        if len(parts) > 2 and parts[0] == "MEM" and parts[1].endswith("/" + arm):
            return parts[2]
    return "?"


def verdict(m, b):
    gap = (sum(b) / len(b)) / (sum(m) / len(m)) - 1
    return gap, "SLOWER" if max(b) < min(m) and gap < -0.01 else "no slower"


C = {a: cells(a) for a in ARMS}
print("## bench_concurrent --alone --serial, greedy, 256 tokens, 3 reps: per-stream decode tok/s")
print("| prompt | streams | M1 | B1 | B2 | M2 | branch/main | verdict | alone equal (M1 B1 B2 M2) |")
print("|---|---|---|---|---|---|---|---|---|")
for key in C["M1"]:
    v = [C[a][key]["per_stream_tps"] for a in ARMS]
    gap, ver = verdict([v[0], v[3]], [v[1], v[2]])
    al = " ".join(f"{C[a][key]['alone'].get('equal', 0)}/{sum(C[a][key]['alone'].values())}" for a in ARMS)
    print(f"| {key[0]} | {key[1]} | {v[0]} | {v[1]} | {v[2]} | {v[3]} | {gap * 100:+.2f}% | {ver} | {al} |")
print()
O = {a: openai(a) for a in ARMS}
print("## bench_openai, greedy, 256 tokens: median decode tok/s of 3")
print("| prompt | M1 | B1 | B2 | M2 | branch/main | verdict |")
print("|---|---|---|---|---|---|---|")
for p in O["M1"]:
    v = [O[a][p] for a in ARMS]
    gap, ver = verdict([v[0], v[3]], [v[1], v[2]])
    print(f"| {p} | {v[0]:.2f} | {v[1]:.2f} | {v[2]:.2f} | {v[3]:.2f} | {gap * 100:+.2f}% | {ver} |")
print()
print("## Accepted per round over each bench (mtp_accepted_total / decode_rounds_total)")
for a in ARMS:
    parts = [f"{n} {acc / r:.3f} ({int(acc)} of {int(dr)} drafted, {int(r)} rounds)" for n, (acc, dr, r) in metrics(a).items() if r]
    print(f"- {a}: " + "; ".join(parts))
print()
print("## Resident memory after boot (docker stats)")
print(" ".join(f"{a} {mem(a)}" for a in ARMS))
print()
sys.path.insert(0, str(Path.home() / "work" / "target"))
from exact0014_sum import bench  # noqa: E402

m1 = bench(f"{R}/M1/conc_t0.json")
print("## Token hashes against M1's (bench_concurrent alone and serial, widest cell, first rep)")
for arm in ARMS:
    b = bench(f"{R}/{arm}/conc_t0.json")
    keys = sorted(set(b["hashes"]) & set(m1["hashes"]), key=str)
    same = sum(1 for k in keys if b["hashes"][k] == m1["hashes"][k] and b["hashes"][k][0])
    al, se = b["alone"][0.0], b["serial"][0.0]
    print(f"- {arm}: {same}/{len(keys)} equal to M1; alone {al[0]}/{sum(al)} equal, serial {se[0]}/{sum(se)} equal, "
          f"{b['failed']} failed, {b['tokens']} tokens")
