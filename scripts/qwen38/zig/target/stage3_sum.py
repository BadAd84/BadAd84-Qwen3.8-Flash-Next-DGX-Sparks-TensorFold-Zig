#!/usr/bin/env python3
"""stage3_sum.py - the rung ladder as one table: each rung against stock and against the rung before it.

Reads ~/work/target/stage3.log (the DEC lines patcheval.sh prints) and each arm's bench/pe-<arm>/c1 files for the
golden comparison against stock's golden and the boot self-check line.
"""
from __future__ import annotations

import json
import os
import re

ROOT = os.path.expanduser("~/work/target")
PAT = re.compile(r"DEC pe-([a-z0-9]+)-c([14]) C=[14] (\w+) pass0: per-stream med ([\d.]+) min [\d.]+ agg ([\d.]+)")
ORDER = ["s3stock", "s3r05rows", "s3r12kv8", "s3r15ngram", "s3r17chunk", "s3r19gemm2", "s3r21head", "s3r25hc",
         "s3r26q12", "s3r27cost", "s3r29vision", "s3r32all", "s3stock2"]


def shas(arm: str) -> list[str]:
    p = os.path.join(ROOT, "bench", f"pe-{arm}", "c1", "zgold.json")
    try:
        d = json.load(open(p))
    except (OSError, ValueError):
        return []
    items = d if isinstance(d, list) else d.get("replies") or d.get("items") or list(d.values())
    out = []
    for it in items:
        out.append(it.get("sha") if isinstance(it, dict) else str(it))
    return out


def check(arm: str) -> str:
    p = os.path.join(ROOT, "bench", f"pe-{arm}", "c1", "logs.txt")
    try:
        t = open(p, errors="replace").read()
    except OSError:
        return "-"
    m = re.search(r"window self-check: (\d+ of \d+)", t)
    w = re.search(r"serving (\d+)-row copy windows", t)
    return (m.group(1) if m else "none") + (f", {w.group(1)} rows" if w else "")


def main() -> None:
    rows: dict[str, dict] = {}
    for line in open(os.path.join(ROOT, "stage3.log"), errors="replace"):
        m = PAT.match(line)
        if m:
            rows.setdefault(m[1], {}).setdefault(int(m[2]), {})[m[3]] = float(m[5])
    ref = shas("s3stock")
    base = rows.get("s3stock", {})
    print("| rung | C1 prose | C1 code | C4 prose | C4 code | vs stock C1 p/c | vs stock C4 p/c | vs previous C1 c / C4 c | golden vs stock | self-check |")
    print("|---|---|---|---|---|---|---|---|---|---|")
    prev = None

    def d(a, b):
        return "-" if not a or not b else f"{(a / b - 1) * 100:+.1f}%"

    for arm in ORDER:
        if arm not in rows:
            print(f"| {arm} | not run | | | | | | | | |")
            continue
        c1, c4 = rows[arm].get(1, {}), rows[arm].get(4, {})
        b1, b4 = base.get(1, {}), base.get(4, {})
        got = shas(arm)
        gold = f"{sum(1 for a, b in zip(got, ref) if a == b)}/{len(ref)}" if got and ref else "-"
        pv = "-"
        if prev:
            p1, p4 = rows[prev].get(1, {}), rows[prev].get(4, {})
            pv = f"{d(c1.get('code'), p1.get('code'))} / {d(c4.get('code'), p4.get('code'))}"
        print(f"| {arm} | {c1.get('prose', 0):.1f} | {c1.get('code', 0):.1f} | {c4.get('prose', 0):.1f} | {c4.get('code', 0):.1f} | "
              f"{d(c1.get('prose'), b1.get('prose'))} / {d(c1.get('code'), b1.get('code'))} | "
              f"{d(c4.get('prose'), b4.get('prose'))} / {d(c4.get('code'), b4.get('code'))} | {pv} | {gold} | {check(arm)} |")
        if arm != "s3stock2":
            prev = arm


if __name__ == "__main__":
    main()
