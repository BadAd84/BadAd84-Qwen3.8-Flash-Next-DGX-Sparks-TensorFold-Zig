#!/usr/bin/env python3
"""hash_cmp.py --root OUT - reply-hash equality between arms at the same level.

Reads each cell's dec.jsonl (rows: label, C, kind, pass, j, sha, token_sha) and prints, for every arm and
level, how many rows are equal to P's and to D's at the same (kind, pass, j). A lever that claims the same
bits (PROMPT_MM=0, GRAPH_FAIL=1) must read all-equal; a copy-policy or tier change that alters served rows
reads unequal and is a behaviour change, whatever its speed.
"""
import argparse
import glob
import json
import os
import re
import sys

ARMS = ("P", "D", "A1", "A2", "A3", "A4")


def last_run(root, arm, c):
    runs = []
    for path in glob.glob(os.path.join(root, arm, f"c{c}", "run*")):
        m = re.search(r"run(\d+)$", path)
        if m:
            runs.append((int(m[1]), path))
    return sorted(runs)[-1][1] if runs else None


def rows(run):
    out = {}
    try:
        text = open(os.path.join(run, "dec.jsonl"), encoding="utf-8", errors="replace").read()
    except OSError:
        return out
    for line in text.splitlines():
        try:
            r = json.loads(line)
        except json.JSONDecodeError:
            continue
        out[(r.get("kind"), r.get("pass"), r.get("j"))] = (r.get("sha"), r.get("token_sha"))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    a = ap.parse_args()
    levels = sorted({int(re.search(r"/c(\d+)/", p.replace(chr(92), "/"))[1])
                     for p in glob.glob(os.path.join(a.root, "P", "c*", "run*"))})
    print("# reply-hash equality per arm and level (rows equal / rows compared)\n")
    print("| level | arm | vs P text | vs P tokens | vs D text | vs D tokens |")
    print("|---:|---|---:|---:|---:|---:|")
    for c in levels:
        base = {}
        for k in ("P", "D"):
            run = last_run(a.root, k, c)
            base[k] = rows(run) if run else {}
        for arm in ARMS:
            run = last_run(a.root, arm, c)
            if not run:
                continue
            mine = rows(run)
            cells = []
            for ref in ("P", "D"):
                b = base[ref]
                if not b:
                    cells.append("-")
                    cells.append("-")
                    continue
                keys = [k for k in mine if k in b]
                text = sum(1 for k in keys if mine[k][0] == b[k][0])
                tok = sum(1 for k in keys if mine[k][1] == b[k][1])
                cells.append(f"{text}/{len(keys)}")
                cells.append(f"{tok}/{len(keys)}")
            print(f"| {c} | {arm} | {cells[0]} | {cells[1]} | {cells[2]} | {cells[3]} |")
    return 0


if __name__ == "__main__":
    sys.exit(main())
