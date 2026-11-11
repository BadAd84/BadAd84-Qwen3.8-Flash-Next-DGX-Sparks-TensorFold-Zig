#!/usr/bin/env python3
"""patcheval_sum.py [ROOT] - the per-lever evaluation as a verdict table.

Reads ~/work/target/bench/pe-<arm>/c<C>/dec.jsonl and arm logs written by patcheval.sh. The baseline is `pe-base`.
A lever is KEEP only when it is faster at both C=1 and C=4 on the code prompt and not slower on prose at either level;
`tie` when every delta is inside 2%; otherwise DROP. Print the numbers so the verdict can be checked by hand.
"""
from __future__ import annotations

import glob
import json
import os
import re
import statistics as st
import sys


def cell(root: str, arm: str, c: int) -> dict:
    out = {"prose": None, "code": None, "gold": "-", "check": ""}
    d = os.path.join(root, "bench", f"pe-{arm}", f"c{c}")
    dec = os.path.join(d, "dec.jsonl")
    if os.path.exists(dec):
        agg: dict[str, list[float]] = {"prose": [], "code": []}
        for line in open(dec, encoding="utf-8", errors="replace"):
            try:
                r = json.loads(line)
            except json.JSONDecodeError:
                continue
            kind = r.get("kind")
            if kind in agg and r.get("agg"):
                agg[kind].append(float(r["agg"]))
        out["prose"] = st.median(agg["prose"]) if agg["prose"] else None
        out["code"] = st.median(agg["code"]) if agg["code"] else None
    logs = os.path.join(d, "logs.txt")
    if os.path.exists(logs):
        text = open(logs, encoding="utf-8", errors="replace").read()
        m = re.search(r"window self-check: (\d+ of \d+)", text)
        if m:
            out["check"] = m.group(1)
    return out


def main() -> None:
    root = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/work/target")
    arms = sorted({os.path.basename(p)[3:] for p in glob.glob(os.path.join(root, "bench", "pe-*"))})
    if "base" not in arms:
        print("no pe-base arm yet")
        return
    base = {c: cell(root, "base", c) for c in (1, 4)}
    print("| lever | C=1 prose | C=4 prose | C=1 code | C=4 code | delta code C1/C4 | self-check | verdict |")
    print("|---|---|---|---|---|---|---|---|")
    for arm in arms:
        row = [arm]
        verdict = "keep"
        dcode = []
        for c in (1, 4):
            got = cell(root, arm, c)
            ref = base[c]
            row.append((got["prose"], ref["prose"]))
            dcode.append((got["code"], ref["code"]))
        c1p, c4p = row[1], row[2]
        pc = []
        for got, ref in [c1p, c4p, dcode[0], dcode[1]]:
            pc.append(None if not got or not ref else (got / ref - 1) * 100)
        for p in (pc[0], pc[1], pc[2], pc[3]):
            if p is not None and p < -2:
                verdict = "drop"
        if verdict == "keep":
            if all(p is not None and abs(p) <= 2 for p in pc):
                verdict = "tie"
            elif not (pc[2] and pc[3] and pc[2] > 2 and pc[3] > 2):
                verdict = "modify"
        fmt = lambda p: "-" if p is None else f"{p:+.1f}%"
        print(
            f"| {arm} | {c1p[0] or 0:.1f} | {c4p[0] or 0:.1f} | {dcode[0][0] or 0:.1f} | {dcode[1][0] or 0:.1f} | "
            f"{fmt(pc[2])} / {fmt(pc[3])} | {cell(root, arm, 1)['check'] or '-'} | {verdict} |"
        )


if __name__ == "__main__":
    main()
