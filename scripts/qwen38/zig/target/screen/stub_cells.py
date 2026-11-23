#!/usr/bin/env python3
"""stub_cells.py OUTDIR ROLE MODE: the exact fields the real writers write, for the driver's dry run.

ROLE is c1, a, c2 or a2; MODE is promote, kill2, kill1, kill1c, guard, inside or unstable. bench_concurrent.py's
report JSON carries cells[] with prompt, streams, temperature, aggregate_tps, failed, unmeasured, alone, serial
and reps[].requests[].prompt_tokens; ttft.py prints `summary <case> <load> n .. ttft med <s> ..`. This stub
writes both shapes and nothing else, so a field the analyzer needs but the real writer does not emit shows up
before any GPU time is spent.

The control pair is 1 percent apart (26 percent for `unstable`). A candidate cell the mode does not name sits
at plus 0.2 percent, inside the 1 percent floor, so only the named cells judge:

  promote  d4-prose and d4-code plus 6 percent                -> PROMOTE
  kill2    d4-prose minus 8, d4-code minus 6                  -> KILL on two cells
  kill1    d4-prose minus 8 only                              -> KILL-PENDING without a2
  kill1c   kill1, and a2 with d4-prose minus 8                -> KILL confirmed
  guard    d1-code minus 10, no treatment cell                -> INCONCLUSIVE, not KILL
  inside   nothing moves                                      -> INCONCLUSIVE
"""
import json
import sys
from pathlib import Path

out = Path(sys.argv[1])
role, mode = sys.argv[2], sys.argv[3]
out.mkdir(parents=True, exist_ok=True)

BASE = {("chat", 1, 0.0): 180.0, ("code", 1, 0.0): 260.0, ("chat", 4, 0.0): 520.0, ("code", 4, 0.0): 780.0,
        ("chat", 4, 1.0): 480.0}
NAMES = {("chat", 1, 0.0): "d1-prose", ("code", 1, 0.0): "d1-code", ("chat", 4, 0.0): "d4-prose",
         ("code", 4, 0.0): "d4-code", ("chat", 4, 1.0): "d4-sampled"}
FACTORS = {"promote": {"d4-prose": 1.06, "d4-code": 1.06},
           "kill2": {"d4-prose": 0.92, "d4-code": 0.94},
           "kill1": {"d4-prose": 0.92},
           "kill1c": {"d4-prose": 0.92},
           "guard": {"d1-code": 0.90},
           "inside": {},
           "unstable": {}}
INSIDE = 1.002
s_ctl = 0.30 if mode == "unstable" else 0.01


def factor(key):
    if role == "c1":
        return 1.0
    if role == "c2":
        return 1 + s_ctl
    return FACTORS[mode].get(NAMES[key], INSIDE)


cells = []
for key, base in BASE.items():
    prompt, streams, temp = key
    v = round(base * factor(key), 3)
    alone = 4 if streams == 4 else 1
    cells.append({
        "prompt": prompt, "temperature": temp, "streams": streams, "failed": 0, "unmeasured": 0,
        "aggregate_tps": v, "per_stream_tps": round(v / streams, 2), "ttft_s_max": 0.4,
        "request": {"ttft_s": 0.3, "decode_tps": round(v / streams, 2)},
        "pooled": {"ttft_s": 0.3}, "completions": {"eos": streams}, "timing_valid": True,
        "alone": {"equal": alone, "unequal": 0, "failed": 0},
        "serial": {"equal": alone, "unequal": 0, "failed": 0},
        "reps": [{"requests": [{"prompt_tokens": 3000, "ttft_s": 0.3, "decode_tps": round(v / streams, 2)}
                               for _ in range(streams)]}],
    })

with open(out / "conc.json", "w", encoding="utf-8") as f:
    json.dump({"label": f"{role}-{mode}", "tokens": 256, "mixed": False, "cells": cells}, f, indent=1)
    f.write("\n")


def ttft(value):
    if role == "c1":
        return value
    if role == "c2":
        return round(value * (1 + s_ctl), 3)
    return round(value * INSIDE, 3)


lines = []
for case, value in (("cold2k-off", 0.55), ("cold32k-off", 8.40)):
    v = ttft(value)
    lines.append(f"summary {case} idle n 3 ttft med {v:.3f} p90 {v * 1.05:.3f} admit 0.010 queue - "
                 f"prefill - other {v - 0.01:.3f} server - excluded 0")
(out / "ttft.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")
print(f"stub {out} role {role} mode {mode}")
