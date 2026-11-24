#!/usr/bin/env python3
"""zgold_cmp.py A.json B.json ...: compare qf_harness golden files; every reply must match the first file's."""
import json, sys
ref = json.load(open(sys.argv[1]))
def items(g):
    if isinstance(g, dict) and "replies" in g: g = g["replies"]
    if isinstance(g, list): return {r.get("id", i): r.get("sha") or r.get("content") for i, r in enumerate(g)}
    return {k: (v.get("sha") or v.get("content")) if isinstance(v, dict) else v for k, v in g.items()}
R = items(ref); bad = 0
for p in sys.argv[2:]:
    X = items(json.load(open(p)))
    same = sum(1 for k in R if X.get(k) == R[k])
    print(f"{p}: {same}/{len(R)} identical to {sys.argv[1]}")
    bad += same != len(R)
sys.exit(1 if bad else 0)
