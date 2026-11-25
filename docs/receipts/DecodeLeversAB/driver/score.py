#!/usr/bin/env python3
"""score.py --root OUT [--final] - score B0 vs G1 (DECODE_GRAPH=1) and A1 (ATTN_LANES=1) across C=1..8."""
import argparse
import math
import re
import statistics
import sys
from pathlib import Path

DEC = re.compile(r"^DEC \S+ C=(\d+) (\w+) pass(\d+): per-stream med ([\d.]+) min ([\d.]+) agg ([\d.]+) "
                 r"tok/wall ([\d.]+) tokens (\d+) rounds (\d+) drafted (\d+) accepted (\d+)")
SUMMARY = re.compile(r"^summary (\S+) (\S+) n (\d+)(?: ttft med ([\d.]+))?(?:.*excluded (\d+))?")
TTFT_KEYS = ("cold1k-off", "cold8k-off", "cold8k-on", "cold32k-off", "cold32k-on", "warm2k")
ARMS = ("B0", "G1", "A1")
CONTROL = "B0"


def read(p):
    try:
        return Path(p).read_text(errors="replace")
    except OSError:
        return ""


def parse_cell(run: Path):
    out = {"prose": [], "code": [], "toks": [], "ttft": {}}
    for line in read(run / "dec.log").splitlines():
        if line.startswith("TOK "):
            out["toks"].append(line.split(": ", 1)[1].strip())
        m = DEC.match(line)
        if m:
            out[m.group(2)].append(float(m.group(6)))
    for line in read(run / "ttft.out").splitlines():
        m = SUMMARY.match(line)
        if m and m.group(4):
            out["ttft"][m.group(1)] = float(m.group(4))
    return out


def med(xs):
    return statistics.median(xs) if xs else None


def r(a, b):
    return None if (a is None or not b) else a / b


def f(v, nd=3):
    return "-" if v is None else f"{v:.{nd}f}"


def geomean(xs):
    xs = [x for x in xs if x]
    return None if not xs else math.exp(sum(math.log(x) for x in xs) / len(xs))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--final", action="store_true")
    args = ap.parse_args()
    root = Path(args.root)
    data = {}
    levels = []
    for c in (1, 2, 4, 6, 8):
        any_c = False
        for arm in ARMS:
            run = root / arm / f"c{c}" / "run1"
            if (run / "dec.log").exists():
                data[(arm, c)] = parse_cell(run)
                any_c = True
        if any_c:
            levels.append(c)
    if not levels:
        print("no cells found")
        return 1

    print("## Decode and TTFT per arm and level\n")
    print("| level | arm | prose agg | vs B0 | code agg | vs B0 | cold8k vs B0 | cold32k vs B0 | warm2k vs B0 | hashes vs B0 |")
    print("|---:|---|---:|---:|---:|---:|---:|---:|---:|---|")
    for c in levels:
        ctrl = data.get((CONTROL, c))
        for arm in ARMS:
            d = data.get((arm, c))
            if not d:
                continue
            pr, co = med(d["prose"]), med(d["code"])
            cpr, cco = (med(ctrl["prose"]), med(ctrl["code"])) if ctrl else (None, None)
            e8 = r(d["ttft"].get("cold8k-off"), ctrl["ttft"].get("cold8k-off") if ctrl else None)
            e3 = r(d["ttft"].get("cold32k-off"), ctrl["ttft"].get("cold32k-off") if ctrl else None)
            wm = r(d["ttft"].get("warm2k"), ctrl["ttft"].get("warm2k") if ctrl else None)
            if ctrl and len(ctrl["toks"]) == len(d["toks"]) and ctrl["toks"]:
                hs = f"{sum(a == b for a, b in zip(ctrl['toks'], d['toks']))}/{len(ctrl['toks'])}"
            else:
                hs = "-"
            print(f"| {c} | {arm} | {f(pr,1)} | {f(r(pr,cpr))} | {f(co,1)} | {f(r(co,cco))} | {f(e8)} | {f(e3)} | {f(wm)} | {hs} |")

    if args.final:
        print("\n## Geometric mean against B0 over measured levels\n")
        print("| arm | levels | prose vs B0 | code vs B0 | decode vs B0 | cold8k vs B0 | cold32k vs B0 | warm2k vs B0 |")
        print("|---|---|---:|---:|---:|---:|---:|---:|")
        for arm in ("G1", "A1"):
            got = [c for c in levels if (arm, c) in data and (CONTROL, c) in data]
            if not got:
                continue
            prs, cos, dds, e8s, e3s, wms = [], [], [], [], [], []
            for c in got:
                a, b = data[(arm, c)], data[(CONTROL, c)]
                rp, rc = r(med(a["prose"]), med(b["prose"])), r(med(a["code"]), med(b["code"]))
                prs.append(rp); cos.append(rc); dds.extend([rp, rc])
                e8s.append(r(a["ttft"].get("cold8k-off"), b["ttft"].get("cold8k-off")))
                e3s.append(r(a["ttft"].get("cold32k-off"), b["ttft"].get("cold32k-off")))
                wms.append(r(a["ttft"].get("warm2k"), b["ttft"].get("warm2k")))
            print(f"| {arm} | {','.join(map(str, got))} | {f(geomean(prs))} | {f(geomean(cos))} | {f(geomean(dds))} | {f(geomean(e8s))} | {f(geomean(e3s))} | {f(geomean(wms))} |")
    return 0


if __name__ == "__main__":
    sys.exit(main())
