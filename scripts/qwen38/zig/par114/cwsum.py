#!/usr/bin/env python3
"""cwsum.py [RUNS_DIR]: the copy and edit probes of the up124 vs cw124 matrix.

Per cell (arm, streams): the median client-side decode rate of the verbatim copy and the one-word rewrite
(zcopy.jsonl, one stream), and of two concurrent file edits and an edit beside a prose reply (w2copy.jsonl, the
first stream of each pair, which is the edit). Reply shas are compared across arms at the same stream level: a
greedy reply must not depend on the copy policy."""
import glob
import json
import os
import statistics
import sys
from collections import defaultdict

RUNS = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser("~/work/lanes/par114/runs2")
ARMS = ["up124", "cw124"]
KINDS = [("copy", "zcopy"), ("rewrite", "zcopy"), ("edit2.0", "w2copy"), ("edit2.1", "w2copy"),
         ("editprose.0", "w2copy"), ("editprose.1", "w2copy")]

rates = defaultdict(list)
shas = defaultdict(set)
for d in sorted(glob.glob(os.path.join(RUNS, "*-c*"))):
    arm, c = os.path.basename(d).rsplit("-c", 1)
    for _, src in {(k, s) for k, s in KINDS}:
        path = os.path.join(d, f"{src}.jsonl")
        if not os.path.exists(path):
            continue
        for line in open(path, encoding="utf-8"):
            if not line.strip():
                continue
            r = json.loads(line)
            rates[(arm, int(c), r["kind"])].append(r["rate"])
            if r.get("sha"):
                shas[(int(c), r["kind"])].add((arm, r["sha"]))

levels = sorted({c for _, c, _ in rates})
print("| streams | kind | up124 tok/s | cw124 tok/s | change |")
print("|---|---|---:|---:|---:|")
for c in levels:
    for kind, _ in KINDS:
        a = rates.get(("up124", c, kind))
        b = rates.get(("cw124", c, kind))
        if not a and not b:
            continue
        ma = statistics.median(a) if a else None
        mb = statistics.median(b) if b else None
        ch = f"{(mb / ma - 1) * 100:+.1f}%" if ma and mb else "-"
        print(f"| {c} | {kind} | {'-' if ma is None else f'{ma:.1f}'} | {'-' if mb is None else f'{mb:.1f}'} | {ch} |")
print()
bad = 0
for (c, kind), pairs in sorted(shas.items()):
    by_arm = defaultdict(set)
    for arm, sha in pairs:
        by_arm[arm].add(sha)
    both = [a for a in ARMS if a in by_arm]
    if len(both) == 2:
        same = by_arm[both[0]] == by_arm[both[1]]
        bad += 0 if same else 1
        print(f"shas c{c} {kind}: {'equal' if same else 'DIFFER'} {sorted(by_arm[both[0]])} vs {sorted(by_arm[both[1]])}")
print(f"\n{bad} kind(s) whose replies differ between the arms")
