#!/usr/bin/env python3
"""score_arms.py --root OUT [--select|--final] - the parity-gap window's per-arm tables.

Reads the harness's own output only: dec.log (DEC lines: per-stream median, aggregate, tok/wall, tokens,
rounds, drafted, accepted), ttft.out (sample and summary lines, idle), meta.txt, boot.log.
Ratios are arm / control: above 1 decode is faster, below 1 TTFT is faster.
"""
import argparse
import glob
import os
import re
import statistics
import sys

DEC = re.compile(r"^DEC \S+ C=(\d+) (\w+) pass(\d+): per-stream med ([\d.]+) min ([\d.]+) agg ([\d.]+) "
                 r"tok/wall ([\d.]+) tokens (\d+) rounds (\d+) drafted (\d+) accepted (\d+)")
SUMMARY = re.compile(r"^summary (\S+) (\S+) n (\d+)(?: ttft med ([\d.]+))?(?:.*excluded (\d+))?")
SAMPLE = re.compile(r"^sample (\S+) (\S+) ttft ([\d.]+) .*?prompt (\d+) cached (\d+)")
TTFT_KEYS = ("cold1k-off", "cold8k-off", "cold8k-on", "cold32k-off", "cold32k-on", "warm2k")
FAMILY = {"P": "P", "D": "D", "A1": "D", "A2": "P", "A3": "P", "A4": "D"}
ARMS = ("P", "D", "A1", "A2", "A3", "A4")


def read(path):
    try:
        return open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return ""


def last_run(root, arm, c):
    runs = []
    for path in glob.glob(os.path.join(root, arm, f"c{c}", "run*")):
        m = re.search(r"run(\d+)$", path)
        if m:
            runs.append((int(m[1]), path))
    return sorted(runs)[-1][1] if runs else None


def dec(run):
    out = {}
    for line in read(os.path.join(run, "dec.log")).splitlines():
        m = DEC.match(line)
        if not m:
            continue
        kind = m[2]
        cell = out.setdefault(kind, {"agg": [], "med": [], "wall": [], "tokens": 0, "rounds": 0,
                                     "drafted": 0, "accepted": 0, "wall_s": []})
        cell["agg"].append(float(m[6]))
        cell["med"].append(float(m[4]))
        cell["wall"].append(float(m[7]))
        cell["wall_s"].append(int(m[8]) / float(m[7]) if float(m[7]) else 0.0)
        cell["tokens"] += int(m[8])
        cell["rounds"] += int(m[9])
        cell["drafted"] += int(m[10])
        cell["accepted"] += int(m[11])
    return out


def ttft(run):
    out = {}
    for line in read(os.path.join(run, "ttft.out")).splitlines():
        m = SUMMARY.match(line)
        if m and m[2] == "idle":
            out[m[1]] = {"med": float(m[4]) if m[4] else None, "n": int(m[3])}
            continue
        m = SAMPLE.match(line)
        if m and m[2] == "idle":
            out.setdefault(m[1], {"med": None, "samples": []}).setdefault("samples", []).append(float(m[3]))
    return out


def med(xs):
    return statistics.median(xs) if xs else None


def r(a, b):
    return None if a is None or not b else a / b


def f(v, nd=3):
    return "-" if v is None else f"{v:.{nd}f}"


def spread(xs):
    xs = [x for x in xs if x is not None]
    if len(xs) < 2 or min(xs) == 0:
        return None
    return max(xs) / min(xs) - 1


def collect(root):
    data = {}
    levels = sorted({int(re.search(r"/c(\d+)/", p.replace(chr(92), "/"))[1])
                     for p in glob.glob(os.path.join(root, "*", "c*", "run*"))})
    for c in levels:
        for arm in ARMS:
            run = last_run(root, arm, c)
            if not run:
                continue
            d = dec(run)
            d["_ttft"] = ttft(run)
            d["_spread"] = {k: spread(v["agg"]) for k, v in dec(run).items()}
            data[(arm, c)] = d
    return levels, data


def rs(d, kind):
    """rounds a second, from the cell's own totals (tokens / tok-per-wall-second summed over passes)."""
    cell = d.get(kind) if d else None
    if not cell or not cell.get("rounds") or not sum(cell.get("wall_s", [0])):
        return None
    return cell["rounds"] / sum(cell["wall_s"])


def agg(d, kind):
    return med(d.get(kind, {}).get("agg")) if d else None


def ttf(d, case):
    return d.get("_ttft", {}).get(case, {}).get("med") if d else None


def row_table(root, levels, data):
    out = []
    out.append("## Decode and TTFT per arm and level\n")
    out.append("| level | arm | prose agg | vs P | vs D | code agg | vs P | vs D | tok/round prose | code | accept prose | code | rounds/s prose | code | ms/round prose | code | cold8k vs P | cold32k vs P |")
    out.append("|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
    for c in levels:
        base = {a: data.get((a, c)) for a in ("P", "D")}
        for arm in ARMS:
            d = data.get((arm, c))
            if not d:
                continue
            P, D = base["P"], base["D"]
            pr, co = agg(d, "prose"), agg(d, "code")
            tp = (d.get("prose", {}).get("tokens", 0) / d["prose"]["rounds"]) if d.get("prose", {}).get("rounds") else None
            tc = (d.get("code", {}).get("tokens", 0) / d["code"]["rounds"]) if d.get("code", {}).get("rounds") else None
            ap = (d["prose"]["accepted"] / d["prose"]["drafted"]) if d.get("prose", {}).get("drafted") else None
            ac = (d["code"]["accepted"] / d["code"]["drafted"]) if d.get("code", {}).get("drafted") else None
            rp = rs(d, "prose")
            rc_ = rs(d, "code")
            out.append(f"| {c} | {arm} | {f(pr,1)} | {f(r(pr, agg(P,'prose')))} | {f(r(pr, agg(D,'prose')))} | "
                       f"{f(co,1)} | {f(r(co, agg(P,'code')))} | {f(r(co, agg(D,'code')))} | "
                       f"{f(tp,2)} | {f(tc,2)} | {f(ap,3)} | {f(ac,3)} | "
                       f"{f(rp,2)} | {f(rc_,2)} | "
                       f"{f(1000/rp,2) if rp else None} | {f(1000/rc_,2) if rc_ else None} | "
                       f"{f(r(ttf(d,'cold8k-off'), ttf(P,'cold8k-off')))} | "
                       f"{f(r(ttf(d,'cold32k-off'), ttf(P,'cold32k-off')))} |")
    return "\n".join(out)


def ttft_table(levels, data):
    out = ["\n## Cold TTFT (median of 2, idle) and warm turn, seconds\n"]
    out.append("| level | arm | " + " | ".join(TTFT_KEYS) + " |")
    out.append("|---:|---|" + "---:|" * len(TTFT_KEYS))
    for c in levels:
        for arm in ARMS:
            d = data.get((arm, c))
            if not d:
                continue
            out.append(f"| {c} | {arm} | " + " | ".join(f(ttf(d, k), 3) for k in TTFT_KEYS) + " |")
    return "\n".join(out)


def spreads(levels, data):
    out = ["\n## Repeat spreads (decode 3 passes max/min-1, per kind)\n"]
    out.append("| level | arm | prose | code |")
    out.append("|---:|---|---:|---:|")
    for c in levels:
        for arm in ARMS:
            d = data.get((arm, c))
            if not d:
                continue
            sp = d.get("_spread", {})
            out.append(f"| {c} | {arm} | {f(sp.get('prose'),3)} | {f(sp.get('code'),3)} |")
    return "\n".join(out)


def geomean(vals):
    vals = [v for v in vals if v]
    if not vals:
        return None
    import math
    return math.exp(sum(math.log(v) for v in vals) / len(vals))


def summary(levels, data):
    out = ["\n## Arm against control over the levels measured (geometric mean)\n"]
    out.append("| arm | levels | decode vs P | decode vs D | cold8k vs P | cold8k vs D | cold32k vs P | cold32k vs D |")
    out.append("|---|---|---:|---:|---:|---:|---:|---:|")
    for arm in ARMS:
        if arm in ("P", "D"):
            continue
        got = [c for c in levels if (arm, c) in data and ("P", c) in data and ("D", c) in data]
        if not got:
            continue
        dp, dd, e8p, e8d, e3p, e3d = [], [], [], [], [], []
        for c in got:
            a, P, D = data[(arm, c)], data[("P", c)], data[("D", c)]
            for kind in ("prose", "code"):
                dp.append(r(agg(a, kind), agg(P, kind)))
                dd.append(r(agg(a, kind), agg(D, kind)))
            e8p.append(r(ttf(a, "cold8k-off"), ttf(P, "cold8k-off")))
            e8d.append(r(ttf(a, "cold8k-off"), ttf(D, "cold8k-off")))
            e3p.append(r(ttf(a, "cold32k-off"), ttf(P, "cold32k-off")))
            e3d.append(r(ttf(a, "cold32k-off"), ttf(D, "cold32k-off")))
        out.append(f"| {arm} | {','.join(map(str, got))} | {f(geomean(dp))} | {f(geomean(dd))} | "
                   f"{f(geomean(e8p))} | {f(geomean(e8d))} | {f(geomean(e3p))} | {f(geomean(e3d))} |")
    return "\n".join(out)


def select(levels, data):
    """Promote an arm when its ratio against its own family's control leaves 0.98-1.02 in either decode
    kind or the cold 8k/32k TTFT at a screen level. Rank by the largest deviation; at most two promote."""
    found = []
    for arm in ("A1", "A2", "A3", "A4"):
        ctrl = FAMILY[arm]
        dev, why = 0.0, []
        for c in levels:
            a, b = data.get((arm, c)), data.get((ctrl, c))
            if not a or not b:
                continue
            for kind in ("prose", "code"):
                x = r(agg(a, kind), agg(b, kind))
                if x is None:
                    continue
                if abs(x - 1) > abs(dev):
                    dev = x - 1
                if abs(x - 1) > 0.02:
                    why.append(f"c{c}-{kind} {x:.3f}")
            for case in ("cold8k-off", "cold32k-off"):
                x = r(ttf(a, case), ttf(b, case))
                if x is None:
                    continue
                if abs(x - 1) > abs(dev):
                    dev = x - 1
                if abs(x - 1) > 0.02:
                    why.append(f"c{c}-{case} {x:.3f}")
        if why:
            found.append((abs(dev), arm, why))
    found.sort(reverse=True)
    print("SELECT screen ratios outside 0.98-1.02 against the family control")
    for dev, arm, why in found:
        print(f"CANDIDATE {arm} maxdev {dev:.3f} :: {'; '.join(why)}")
    for dev, arm, why in found[:2]:
        print(f"PROMOTE {arm} {dev:.3f} :: {'; '.join(why)}")
    if not found:
        print("PROMOTE-NONE every arm within 2 percent of its control at the screen levels")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--select", action="store_true")
    ap.add_argument("--final", action="store_true")
    a = ap.parse_args()
    levels, data = collect(a.root)
    if not levels:
        print("no cells under", a.root)
        return 2
    if a.select:
        select(levels, data)
        return 0
    print(f"# Parity-gap window tables ({os.path.abspath(a.root)})\n")
    print(f"levels measured: {', '.join(map(str, levels))}\n")
    print(row_table(a.root, levels, data))
    print(ttft_table(levels, data))
    print(spreads(levels, data))
    if a.final:
        print(summary(levels, data))
    return 0


if __name__ == "__main__":
    sys.exit(main())
