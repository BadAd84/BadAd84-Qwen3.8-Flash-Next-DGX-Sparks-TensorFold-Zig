#!/usr/bin/env python3
"""score_pks.py --root OUT [--final] - the 0041 prompt-tile window's per-arm tables.

Reads the same cell artefacts the ParityGap scorer does (each cell's dec.log decode lines, ttft.out
summary/sample lines) and prints, per level, every arm's decode aggregate, its ratio against F0 (the
control), tokens a round, acceptance, rounds a second, ms a round, and its cold 8k/32k TTFT ratio against
F0. Ratios are arm / F0: above 1 decode is faster, below 1 TTFT is faster. --final also prints the
geometric-mean summary over the levels measured.

Arms: F0 (the engine's 128-column prompt tile), F1 (TF_FLASHNEXT_PROMPT_KS_N=64 GROUP=8), F2 (KS_N=64
GROUP=0). See docs/receipts/PrefillKernelPort/AB-PLAN.md.
"""
import argparse
import math
import re
import statistics
import sys
from pathlib import Path

DEC = re.compile(r"^DEC \S+ C=(\d+) (\w+) pass(\d+): per-stream med ([\d.]+) min ([\d.]+) agg ([\d.]+) "
                 r"tok/wall ([\d.]+) tokens (\d+) rounds (\d+) drafted (\d+) accepted (\d+)")
SUMMARY = re.compile(r"^summary (\S+) (\S+) n (\d+)(?: ttft med ([\d.]+))?(?:.*excluded (\d+))?")
SAMPLE = re.compile(r"^sample (\S+) (\S+) ttft ([\d.]+) .*?prompt (\d+) cached (\d+)")
TTFT_KEYS = ("cold1k-off", "cold8k-off", "cold8k-on", "cold32k-off", "cold32k-on", "warm2k")
CONTROL = "F0"
ARMS = ("F0", "F1", "F2")


def read(path):
    try:
        return Path(path).read_text(errors="replace")
    except OSError:
        return ""


def last_run(root, arm, c):
    runs = []
    for run in sorted(Path(root).glob(f"{arm}/c{c}/run*")):
        if (run / "meta.txt").exists() or (run / "dec.log").exists():
            runs.append((run.name, run))
    return sorted(runs)[-1][1] if runs else None


def dec(run):
    out = {}
    for line in read(run / "dec.log").splitlines():
        m = DEC.match(line)
        if not m:
            continue
        c, kind, _pass, _pmed, _pmin, agg, wall, tokens, rounds, drafted, accepted = m.groups()
        d = out.setdefault(kind, {"agg": [], "wall_s": [], "tokens": 0, "rounds": 0, "drafted": 0, "accepted": 0})
        d["agg"].append(float(agg))
        d["wall_s"].append(float(wall))
        d["tokens"] += int(tokens)
        d["rounds"] += int(rounds)
        d["drafted"] += int(drafted)
        d["accepted"] += int(accepted)
    return out


def ttft(run):
    out = {}
    for line in read(run / "ttft.out").splitlines():
        m = SUMMARY.match(line)
        if m and m.group(4):
            case, _load, _n, med_s, _excl = m.groups()
            out[case] = {"med": float(med_s)}
            continue
        m = SAMPLE.match(line)
        if m:
            _a, case, secs, _p, _c = m.groups()
            out.setdefault(case, {"vals": []}).setdefault("vals", []).append(float(secs))
    res = {}
    for k, v in out.items():
        if "med" in v:
            res[k] = {"med": v["med"]}
        elif v.get("vals"):
            res[k] = {"med": statistics.median(v["vals"])}
    return res


def collect(root):
    levels, data = set(), {}
    for arm in ARMS:
        for c in (1, 2, 4, 6, 8):
            run = last_run(root, arm, c)
            if run is None:
                continue
            levels.add(c)
            data[(arm, c)] = {**dec(run), "_ttft": ttft(run)}
    return sorted(levels), data


def med(xs):
    return statistics.median(xs) if xs else None


def r(a, b):
    return None if a is None or not b else a / b


def f(v, nd=3):
    return "-" if v is None else f"{v:.{nd}f}"


def agg(d, kind):
    return med(d.get(kind, {}).get("agg")) if d else None


def ttf(d, case):
    return d.get("_ttft", {}).get(case, {}).get("med") if d else None


def rs(d, kind):
    cell = d.get(kind, {})
    if not cell.get("rounds") or not cell.get("wall_s"):
        return None
    return cell["rounds"] / sum(cell["wall_s"])


def geomean(vals):
    vals = [v for v in vals if v]
    return None if not vals else math.exp(sum(math.log(v) for v in vals) / len(vals))


def row_table(levels, data):
    out = ["## Decode and TTFT per arm and level\n"]
    out.append("| level | arm | prose agg | vs F0 | code agg | vs F0 | tok/round p | c | accept p | c | rounds/s p | c | ms/round p | c | cold8k | cold32k |")
    out.append("|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
    for c in levels:
        ctrl = data.get((CONTROL, c))
        for arm in ARMS:
            d = data.get((arm, c))
            if not d:
                continue
            pr, co = agg(d, "prose"), agg(d, "code")
            tp = (d.get("prose", {}).get("tokens", 0) / d["prose"]["rounds"]) if d.get("prose", {}).get("rounds") else None
            tc = (d.get("code", {}).get("tokens", 0) / d["code"]["rounds"]) if d.get("code", {}).get("rounds") else None
            ap = (d["prose"]["accepted"] / d["prose"]["drafted"]) if d.get("prose", {}).get("drafted") else None
            ac = (d["code"]["accepted"] / d["code"]["drafted"]) if d.get("code", {}).get("drafted") else None
            rp, rc_ = rs(d, "prose"), rs(d, "code")
            out.append(f"| {c} | {arm} | {f(pr,1)} | {f(r(pr, agg(ctrl,'prose')))} | {f(co,1)} | {f(r(co, agg(ctrl,'code')))} | "
                       f"{f(tp,2)} | {f(tc,2)} | {f(ap,3)} | {f(ac,3)} | {f(rp,2)} | {f(rc_,2)} | "
                       f"{f(1000/rp,2) if rp else None} | {f(1000/rc_,2) if rc_ else None} | "
                       f"{f(r(ttf(d,'cold8k-off'), ttf(ctrl,'cold8k-off')))} | {f(r(ttf(d,'cold32k-off'), ttf(ctrl,'cold32k-off')))} |")
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
            out.append(f"| {c} | {arm} | " + " | ".join(f(ttf(d, k)) for k in TTFT_KEYS) + " |")
    return "\n".join(out)


def summary(levels, data):
    out = ["\n## Arm against F0 over the levels measured (geometric mean)\n"]
    out.append("| arm | levels | decode vs F0 | cold8k vs F0 | cold32k vs F0 |")
    out.append("|---|---|---:|---:|---:|")
    for arm in ARMS:
        if arm == CONTROL:
            continue
        got = [c for c in levels if (arm, c) in data and (CONTROL, c) in data]
        if not got:
            continue
        dd, e8, e3 = [], [], []
        for c in got:
            a, ctrl = data[(arm, c)], data[(CONTROL, c)]
            for kind in ("prose", "code"):
                dd.append(r(agg(a, kind), agg(ctrl, kind)))
            e8.append(r(ttf(a, "cold8k-off"), ttf(ctrl, "cold8k-off")))
            e3.append(r(ttf(a, "cold32k-off"), ttf(ctrl, "cold32k-off")))
        out.append(f"| {arm} | {','.join(map(str, got))} | {f(geomean(dd))} | {f(geomean(e8))} | {f(geomean(e3))} |")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--final", action="store_true")
    args = ap.parse_args()
    levels, data = collect(args.root)
    if not levels:
        print("no cells found under", args.root)
        return 1
    print(f"levels {levels}; arms {ARMS}; control {CONTROL}")
    print(row_table(levels, data))
    if args.final:
        print(ttft_table(levels, data))
        print(summary(levels, data))
    return 0


if __name__ == "__main__":
    sys.exit(main())
