#!/usr/bin/env python3
"""fp8cmp.py A.jsonl B.jsonl: two arms' decode replies (tfm_decode.py's dec.jsonl), sha by kind, pass and stream."""
import json
import sys


def shas(path):
    out = {}
    with open(path) as f:
        for line in f:
            if line.strip():
                r = json.loads(line)
                out[(r["kind"], r["pass"], r["j"])] = r["sha"]
    return out


a, b = shas(sys.argv[1]), shas(sys.argv[2])
same = sum(1 for k in a if b.get(k) == a[k])
print(f"{same}/{len(a)} decode replies identical ({sys.argv[2]} against {sys.argv[1]})")
sys.exit(0 if a and same == len(a) else 1)
