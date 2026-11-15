#!/usr/bin/env python3
"""sumP.py RECEIPT_DIR - receiptP.sh's cold-prompt table: ttft.py's median cold TTFT per size and bench_cache.py's
first (cold) request, per arm, with the #3162 noise rule for a time (slower = both branch runs above both main runs and
the mean gap over 1%)."""
import json
import re
import sys
from pathlib import Path

R = Path(sys.argv[1])
ARMS = ["M1", "B1", "B2", "M2"]


def ttft(arm):
    text = (R / arm / "ttft.out").read_text(errors="replace")
    return {m.group(1): float(m.group(3)) for m in re.finditer(r"^summary cold(\d+k)-off idle n (\d+) ttft med ([0-9.]+)", text, re.M)}


def cache(arm):
    d = json.loads((R / arm / "cache.json").read_text())
    first = [r for r in d.get("rows", []) if r.get("phase") == "first"]
    return (first[0].get("ttft_s"), first[0].get("prompt_tokens"), first[0].get("cached_tokens")) if first else (None, None, None)


def verdict(m, b):
    gap = (sum(b) / len(b)) / (sum(m) / len(m)) - 1
    return gap, "SLOWER" if min(b) > max(m) and gap > 0.01 else "no slower"


T = {a: ttft(a) for a in ARMS}
print("| prompt | M1 | B1 | B2 | M2 | branch against main | slower? |")
print("|---|---|---|---|---|---|---|")
for size in sorted(T["M1"], key=lambda s: int(s[:-1])):
    v = [T[a][size] for a in ARMS]
    gap, ver = verdict([v[0], v[3]], [v[1], v[2]])
    print(f"| cold {size}, ttft.py median of 3 (s) | {v[0]:.3f} | {v[1]:.3f} | {v[2]:.3f} | {v[3]:.3f} | {gap * 100:+.2f}% | {ver} |")
C = {a: cache(a) for a in ARMS}
v = [C[a][0] for a in ARMS]
if all(x is not None for x in v):
    gap, ver = verdict([v[0], v[3]], [v[1], v[2]])
    print(f"| bench_cache --require-cold, {C['M1'][1]} tokens, first ttft_s | {v[0]:.3f} | {v[1]:.3f} | {v[2]:.3f} | {v[3]:.3f} | {gap * 100:+.2f}% | {ver} |")
print()
print("cached tokens on each cold first request: " + " ".join(f"{a} {C[a][2]}" for a in ARMS))
