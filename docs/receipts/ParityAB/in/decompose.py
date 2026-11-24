#!/usr/bin/env python3
"""decompose.py --root OUT - a decode cell split into tokens a round and milliseconds a round.

A cell's rate is (tokens a round) / (ms a round) x 1000. The engine counts the batch's decode rounds, drafted and
accepted drafts in `/metrics` around each pass (tfm_decode_ids.py writes the deltas into its DEC line), and the pass's
own decode window is the longest per-request (elapsed - ttft) in its JSONL. So this prints, per arm and level and
kind, the median pass's tokens, rounds, drafted, accepted, acceptance, tokens a round and ms a round, and the two arms
side by side with each difference named - which is how a decode gap is attributed to drafting volume or to round cost
instead of guessed.

Usage: decompose.py --root OUT [--levels 1,2,4,6,8]
"""
from __future__ import annotations
import argparse
import glob
import json
import os
import re
import statistics
import sys

DEC = re.compile(r"^DEC \S+ C=(\d+) (\w+) pass(\d+): per-stream med ([\d.]+) min ([\d.]+) agg ([\d.]+) "
                 r"tok/wall ([\d.]+) tokens (\d+) rounds ([\d.]+) drafted ([\d.]+) accepted ([\d.]+)")


def read(path: str) -> str:
    try:
        return open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return ""


def last_run(root: str, arm: str, c: int) -> str | None:
    runs = []
    for path in glob.glob(os.path.join(root, arm, f"c{c}", "run*")):
        m = re.search(r"run(\d+)$", path)
        if m:
            runs.append((int(m[1]), path))
    return sorted(runs)[-1][1] if runs else None


def cell(run: str, kind: str) -> dict | None:
    rows = [json.loads(line) for line in read(os.path.join(run, "dec.jsonl")).splitlines() if line.strip()]
    lines = [DEC.match(line) for line in read(os.path.join(run, "dec.log")).splitlines()]
    passes = [m for m in lines if m and m[2] == kind]
    if not passes:
        return None
    keep = []
    for m in passes:
        p = int(m[3])
        mine = [r for r in rows if r.get("kind") == kind and r.get("pass") == p]
        windows = [1000.0 * (r["elapsed"] - r["ttft"]) for r in mine
                   if r.get("elapsed") is not None and r.get("ttft") is not None and r["elapsed"] > r["ttft"]]
        rounds = float(m[9])
        tokens = int(m[8])
        keep.append({"tokens": tokens, "rounds": rounds, "drafted": float(m[10]), "accepted": float(m[11]),
                     "accept": (float(m[11]) / float(m[10])) if float(m[10]) else None,
                     "tokens_round": tokens / rounds if rounds else None,
                     "ms_round": (max(windows) / rounds) if rounds and windows else None})
    med = lambda key: statistics.median([k[key] for k in keep if k[key] is not None]) if any(
        k[key] is not None for k in keep) else None
    return {key: med(key) for key in ("tokens", "rounds", "drafted", "accepted", "accept", "tokens_round", "ms_round")}


def f(v, nd=2):
    return "-" if v is None else f"{v:.{nd}f}"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--levels", default="1,2,4,6,8")
    args = ap.parse_args()
    levels = [int(x) for x in args.levels.split(",")]
    print("| concurrency | kind | arm | tokens a round | ms a round | accept | tokens | rounds | the other arm |")
    print("|---:|---|---|---:|---:|---:|---:|---:|---|")
    for c in levels:
        for kind in ("prose", "code"):
            got = {}
            for arm in ("P", "D"):
                run = last_run(args.root, arm, c)
                got[arm] = cell(run, kind) if run else None
            for arm in ("P", "D"):
                mine, other = got[arm], got["D" if arm == "P" else "P"]
                if not mine:
                    print(f"| {c} | {kind} | {arm} | - | - | - | - | - | no cell |")
                    continue
                note = ""
                if other and mine.get("tokens_round") and mine.get("ms_round") and other.get("tokens_round") and other.get("ms_round"):
                    tr = mine["tokens_round"] / other["tokens_round"]
                    mr = mine["ms_round"] / other["ms_round"]
                    note = (f"{arm}/{'D' if arm == 'P' else 'P'} tr {tr:.3f} ms {mr:.3f} => its rate {tr / mr:.3f}")
                print(f"| {c} | {kind} | {arm} | {f(mine['tokens_round'])} | {f(mine['ms_round'])} | "
                      f"{f(mine['accept'], 3)} | {f(mine['tokens'], 0)} | {f(mine['rounds'], 0)} | {note} |")
    return 0


if __name__ == "__main__":
    sys.exit(main())
