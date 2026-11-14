"""fp4sum.py LOG OUT_DIR - a window's cells by stream count: tok/s, rounds, drafted, accepted (prose / code), the
decode replies' shas and the golden token hashes against the defaults cell `d` at the same stream count, and the boot
self-check."""
import json
import os
import re
import sys

log, out = sys.argv[1], sys.argv[2]
HEAD = re.compile(r"^=== (\S+) C=(\d+) ")
DEC = re.compile(r"^DEC \S+ C=\d+ (prose|code) pass0: .* agg ([\d.]+) .* tokens (\d+) rounds (\d+) drafted (\d+) accepted (\d+)")
cells, cur = {}, None
for line in open(log, encoding="utf-8", errors="replace"):
    m = HEAD.match(line)
    if m:
        cur = (m.group(1), int(m.group(2)))
        cells.setdefault(cur, {})
        continue
    m = DEC.match(line)
    if m and cur:
        cells[cur][m.group(1)] = tuple(float(x) for x in m.groups()[1:])


def shas(name, c):
    p = os.path.join(out, f"{name}-c{c}", "dec.jsonl")
    if not os.path.exists(p):
        return None
    return [(r["kind"], r["j"], r["sha"]) for r in map(json.loads, open(p))]


def gold(name, c):
    p = os.path.join(out, f"{name}-c{c}", "zgold.json")
    return [r.get("token_sha") for r in json.load(open(p))] if os.path.exists(p) else None


def check(name, c):
    p = os.path.join(out, f"{name}-c{c}", "logs.txt")
    if not os.path.exists(p):
        return "-"
    m = re.search(r"window self-check: (\d+) of (\d+)", open(p, encoding="utf-8", errors="replace").read())
    return f"{m.group(1)}/{m.group(2)}" if m else "-"


for c in sorted({k[1] for k in cells}):
    base = shas("d", c)
    gbase = gold("d", c)
    print(f"--- {c} stream(s)")
    for (name, cc), v in cells.items():
        if cc != c:
            continue
        p, q = v.get("prose"), v.get("code")
        if not p or not q:
            print(f"{name:12s} no decode")
            continue
        same = shas(name, c)
        eq = "-" if base is None or same is None else ("same" if same == base else "DIFF")
        g = gold(name, c)
        geq = "-" if g is None or gbase is None else ("6/6" if g == gbase else f"{sum(a == b for a, b in zip(g, gbase))}/6")
        print(f"{name:12s} {p[0]:6.1f} / {q[0]:6.1f}  rounds {p[2]:5.0f} / {q[2]:5.0f}  drafted {p[3]:5.0f} / {q[3]:5.0f}"
              f"  accepted {p[4]:5.0f} / {q[4]:5.0f}  tok/round {p[1] / p[2]:.2f} / {q[1] / q[2]:.2f}  shas {eq}  golden {geq}"
              f"  check {check(name, c)}")
