#!/usr/bin/env python3
"""zdiverge.py A.jsonl B.jsonl: greedy replies of two arms to the same prompts (zarm.sh rows), each pair's identical
or where it first differs (characters of A's reply, and the share of the reply before it). For a lossy arm against
an exact one: how far its greedy replies follow the exact model's."""
import json, statistics, sys

def load(p):
    out = {}
    for line in open(p, encoding="utf-8"):
        r = json.loads(line)
        if r.get("content") is not None:
            out.setdefault(r["prompt"], r["content"])
    return out

a, b = load(sys.argv[1]), load(sys.argv[2])
same, shares = 0, []
for p in sorted(set(a) & set(b)):
    x, y = a[p], b[p]
    if x == y:
        same += 1
        shares.append(1.0)
        continue
    n = next((i for i, (c, d) in enumerate(zip(x, y)) if c != d), min(len(x), len(y)))
    shares.append(n / max(1, len(x)))
    print(f"differs at char {n:5d} of {len(x):5d} ({n / max(1, len(x)):.0%}): ...{x[max(0, n - 40):n]!r} | {x[n:n + 30]!r} vs {y[n:n + 30]!r}")
k = len(shares)
print(f"{same}/{k} replies identical; median share before the first difference {statistics.median(shares):.0%}")
