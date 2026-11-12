#!/usr/bin/env python3
"""arm_sum.py LOG ARM [ARM ...] - the decode cells of patcheval.sh arms as one table.

LOG is the run's log (widetile.log): its `DEC pe-<arm>-c<C> ...` lines carry the aggregate tok/s and the rounds a
512-token reply took. The reply hashes come from ~/work/target/bench/pe-<arm>/c<C>/dec.jsonl, so two arms can be
compared reply by reply, and the window self-check from that cell's boot log. ROOT= and LEVELS= pick another
target directory and another stream list.
"""
from __future__ import annotations

import json
import os
import re
import sys

ROOT = os.environ.get("ROOT", os.path.expanduser("~/work/target"))
LEVELS = [int(c) for c in os.environ.get("LEVELS", "1 2 4 6 8").split()]
DEC = re.compile(r"^DEC pe-(\S+?)-c(\d+) C=(\d+) (prose|code) pass\d+: .*?agg ([\d.]+) .*?rounds (\d+)")


def decode_lines(log: str) -> dict:
    out: dict = {}
    for line in open(log, encoding="utf-8", errors="replace"):
        m = DEC.match(line.strip())
        if m:
            arm, c, _, kind, agg, rounds = m.groups()
            out.setdefault((arm, int(c)), {})[kind] = (float(agg), int(rounds))
    return out


def shas(arm: str, c: int) -> dict:
    d = os.path.join(ROOT, "bench", f"pe-{arm}", f"c{c}", "dec.jsonl")
    out: dict = {}
    if os.path.exists(d):
        for line in open(d, encoding="utf-8", errors="replace"):
            try:
                r = json.loads(line)
            except json.JSONDecodeError:
                continue
            out[(r.get("kind"), r.get("pass"), r.get("j"))] = r.get("sha")
    return out


def check(arm: str, c: int) -> str:
    logs = os.path.join(ROOT, "bench", f"pe-{arm}", f"c{c}", "logs.txt")
    if os.path.exists(logs):
        m = re.search(r"window self-check: (\d+ of \d+)", open(logs, encoding="utf-8", errors="replace").read())
        if m:
            return m.group(1)
    return "-"


def main() -> None:
    if len(sys.argv) < 3:
        print("usage: arm_sum.py LOG ARM [ARM ...]")
        return
    dec = decode_lines(sys.argv[1])
    arms = sys.argv[2:]
    print("| arm | " + " | ".join(f"C={c}" for c in LEVELS) + " | rounds prose/code | self-check |")
    print("|---" * (len(LEVELS) + 3) + "|")
    for arm in arms:
        row, rounds = [], "-"
        for c in LEVELS:
            cell = dec.get((arm, c))
            if not cell:
                row.append("-")
                continue
            row.append(" / ".join(f"{cell[k][0]:.1f}" if k in cell else "-" for k in ("prose", "code")))
            if rounds == "-":
                rounds = " / ".join(str(cell[k][1]) if k in cell else "-" for k in ("prose", "code"))
        first = next((c for c in LEVELS if (arm, c) in dec), LEVELS[0])
        print(f"| {arm} | {' | '.join(row)} | {rounds} | {check(arm, first)} |")
    ref = arms[0]
    for arm in arms[1:]:
        same = diff = 0
        for c in LEVELS:
            a, b = shas(ref, c), shas(arm, c)
            for key, sha in a.items():
                if key in b:
                    same += b[key] == sha
                    diff += b[key] != sha
        print(f"replies {arm} against {ref}: {same} identical, {diff} different")


if __name__ == "__main__":
    main()
