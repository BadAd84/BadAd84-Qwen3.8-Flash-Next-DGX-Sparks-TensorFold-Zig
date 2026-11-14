"""fp4stack.py LOG OUT - the FP4 stack window (fp4stack.sh) by stream count: aggregate tok/s prose / code of the
defaults (d, d2), the stack (s, s2) and production (p, p2), the /metrics counters, every decode reply's sha and the
golden token hashes against the first defaults cell, the boot self-check and the boot line's model, streams, pool
pages and budget; then the Markdown tables and the stack's two runs against the defaults' two (repeat spread)."""
import json
import os
import re
import sys

log, out = sys.argv[1], sys.argv[2]
HEAD = re.compile(r"^=== (\S+) C=(\d+) ")
AGG = re.compile(r"^DEC \S+ C=\d+ (prose|code) pass0: .* agg ([\d.]+)")
CNT = re.compile(r"tokens (\d+) rounds (\d+) drafted (\d+) accepted (\d+)")
A, B, P = ("d", "d2"), ("s", "s2"), ("p", "p2")
cells, cur = {}, None
for line in open(log, encoding="utf-8", errors="replace"):
    m = HEAD.match(line)
    if m:
        cur = (m.group(1), int(m.group(2)))
        cells[cur] = {}
        continue
    m = AGG.match(line)
    if m and cur:
        n = CNT.search(line)
        cells[cur][m.group(1)] = (float(m.group(2)),) + (tuple(int(x) for x in n.groups()) if n else ())


def read(name, c, f):
    p = os.path.join(out, f"{name}-c{c}", f)
    return open(p, encoding="utf-8", errors="replace").read() if os.path.exists(p) else None


def shas(name, c):
    t = read(name, c, "dec.jsonl")
    return None if t is None else [(r["kind"], r["j"], r["sha"]) for r in map(json.loads, t.splitlines())]


def gold(name, c):
    t = read(name, c, "zgold.json")
    return None if t is None else [r.get("token_sha") for r in json.loads(t)]


def same(x, base):
    return "-" if x is None or base is None else f"{sum(a == b for a, b in zip(x, base))}/{len(base)}"


def field(pattern, line):
    m = re.search(pattern, line)
    return m.group(1) if m else "-"


def boot(name, c):
    t = read(name, c, "logs.txt") or ""
    line = next((s for s in t.splitlines() if re.search(r"\bmodel [\d.]+ GiB;", s)), "")
    check = re.search(r"window self-check: (\d+ of \d+)", t)
    return {"model": field(r"model ([\d.]+) GiB", line), "streams": field(r"(\d+) streams? at once", line),
            "pages": field(r"taking (\d+) pages", line), "left": field(r"of ([\d.]+) GiB left", line),
            "check": check.group(1) if check else "-"}


def runs(names, c, kind):
    return [cells[(n, c)][kind][0] for n in names if kind in cells.get((n, c), {})]


def mean(v):
    return sum(v) / len(v)


def pct(a, b):
    return f"{(a / b - 1) * 100:+.1f}%"


def ctr(name, c):
    v = cells.get((name, c), {})
    p, q = v.get("prose", ()), v.get("code", ())
    if len(p) < 5 or len(q) < 5:
        return "-"
    return f"{p[2]} / {q[2]}, {p[3] / p[2]:.2f} / {q[3] / q[2]:.2f}, {p[4] / p[2]:.2f} / {q[4] / q[2]:.2f}"


def pair(names, c):
    pr, co = runs(names, c, "prose"), runs(names, c, "code")
    if not pr or not co:
        return "-", None, None
    s = f"{pr[0]:.1f} / {co[0]:.1f}" + (f" ({pr[1]:.1f} / {co[1]:.1f})" if len(pr) > 1 and len(co) > 1 else "")
    return s, mean(pr), mean(co)


cs = sorted({c for _, c in cells})
for c in cs:
    base, gbase = shas("d", c), gold("d", c)
    print(f"--- {c} stream(s)")
    for (name, cc), v in cells.items():
        if cc != c:
            continue
        b = boot(name, c)
        mem = f"model {b['model']} streams {b['streams']} pages {b['pages']} left {b['left']} check {b['check']}"
        p, q = v.get("prose"), v.get("code")
        if not p or not q:
            print(f"{name:3s} no decode  {mem}")
            continue
        cnt = f"  rounds, drafted a round, accepted a round {ctr(name, c)}" if ctr(name, c) != "-" else ""
        print(f"{name:3s} {p[0]:6.1f} / {q[0]:6.1f}{cnt}  shas {same(shas(name, c), base)}"
              f"  golden {same(gold(name, c), gbase)}  {mem}")

print("\n| streams | defaults (repeat) | stack (repeat) | production (end of window) | stack against production"
      " | stack against defaults |")
print("|---:|---|---|---|---|---|")
for c in cs:
    (sa, ap, ac), (sb, bp, bc), (sp, pp, pc) = pair(A, c), pair(B, c), pair(P, c)
    vp = f"{pct(bp, pp)} / {pct(bc, pc)}" if bp and pp else "-"
    va = f"{pct(bp, ap)} / {pct(bc, ac)}" if bp and ap else "-"
    print(f"| {c} | {sa} | {sb} | {sp} | {vp} | {va} |")

print("\n| streams | defaults: rounds, drafted a round, accepted a round | stack: the same | repeats |"
      " stack and repeat replies against the defaults' |")
print("|---:|---|---|---|---|")
for c in cs:
    rep = "same" if ctr("d2", c) == ctr("d", c) and ctr("s2", c) == ctr("s", c) else f"{ctr('d2', c)}; {ctr('s2', c)}"
    base, gbase = shas("d", c), gold("d", c)
    eq = ", ".join(f"{n} {same(shas(n, c), base)}" for n in ("s", "s2", "d2"))
    if c == 1:
        eq += "; golden " + ", ".join(f"{n} {same(gold(n, c), gbase)}" for n in ("s", "s2", "d2"))
    print(f"| {c} | {ctr('d', c)} | {ctr('s', c)} | {rep} | {eq} |")

print("\n| streams | defaults: model GiB, pool pages, GiB left (repeat) | stack: the same (repeat) |")
print("|---:|---|---|")
for c in cs:
    mem = ["; ".join(f"{b['model']}, {b['pages']}, {b['left']}" for b in (boot(n, c) for n in names)) for names in (A, B)]
    print(f"| {c} | {mem[0]} | {mem[1]} |")

print()
for c in cs:
    for kind in ("prose", "code"):
        a, b = runs(A, c, kind), runs(B, c, kind)
        if a and b:
            v = "SLOWER" if max(b) < min(a) else "faster" if min(b) > max(a) else "overlap"
            print(f"spread {c} {kind}: defaults {a} stack {b} -> {v}, stack against defaults {pct(mean(b), mean(a))}")
for n in ("d", "s", "p"):
    for c in cs:
        t = read(n, c, "env.txt")
        if t:
            print(f"env {n}-c{c}: {' '.join(sorted(t.split()))}")

rows = []
for c in cs:
    sp, sc, dp, dc = runs(B, c, "prose"), runs(B, c, "code"), runs(A, c, "prose"), runs(A, c, "code")
    for (name, cc), v in cells.items():
        p, q = v.get("prose"), v.get("code")
        if cc != c or name in A + B + P or not p or not q:
            continue
        vs = f"{pct(p[0], mean(sp))} / {pct(q[0], mean(sc))}" if sp and sc else "-"
        vd = f"{pct(p[0], mean(dp))} / {pct(q[0], mean(dc))}" if dp and dc else "-"
        rows.append(f"| {c} | {name} | {p[0]:.1f} / {q[0]:.1f} | {vs} | {vd} | {ctr(name, c)} |")
if rows:
    print("\n| streams | arm | tok/s | against the stack | against the defaults"
          " | rounds, drafted a round, accepted a round |")
    print("|---:|---|---|---|---|---|")
    print("\n".join(rows))
