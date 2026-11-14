"""fp4stack.py LOG OUT - the FP4 stack window (fp4stack.sh) by stream count: aggregate tok/s prose / code of the
defaults (d, d2), the stack (s, s2) and production (p, p2), the /metrics counters, every decode reply's sha and the
golden token hashes against the first defaults cell, the boot self-check and the boot line's model, streams, pool
pages and budget; then the Markdown tables and the stack's two runs against the defaults' two (repeat spread).
With the stack without HC_Q12 (n, n2; fp4conf.sh): the noise rule over d, n and s (an arm is slower in a cell only when
both its runs are under both runs of the other and the mean gap is over 1%), the confirmation tables and OUT/rerun.txt,
the stream counts and arms holding a slower cell; runs 3 and 4 (d3 d4, n3 n4, s3 s4) are the rerun, and a cell
slower again there is a loss."""
import json
import os
import re
import sys

log, out = sys.argv[1], sys.argv[2]
HEAD = re.compile(r"^=== (\S+) C=(\d+) ")
AGG = re.compile(r"^DEC \S+ C=\d+ (prose|code) pass0: .* agg ([\d.]+)")
CNT = re.compile(r"tokens (\d+) rounds (\d+) drafted (\d+) accepted (\d+)")
A, B, P, N = ("d", "d2"), ("s", "s2"), ("p", "p2"), ("n", "n2")
RE = ("d3", "d4", "n3", "n4", "s3", "s4")
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
        if cc != c or name in A + B + P + N + RE or not p or not q:
            continue
        vs = f"{pct(p[0], mean(sp))} / {pct(q[0], mean(sc))}" if sp and sc else "-"
        vd = f"{pct(p[0], mean(dp))} / {pct(q[0], mean(dc))}" if dp and dc else "-"
        rows.append(f"| {c} | {name} | {p[0]:.1f} / {q[0]:.1f} | {vs} | {vd} | {ctr(name, c)} |")
if rows:
    print("\n| streams | arm | tok/s | against the stack | against the defaults"
          " | rounds, drafted a round, accepted a round |")
    print("|---:|---|---|---|---|---|")
    print("\n".join(rows))

PAIRS = {"d": (A, RE[0:2]), "n": (N, RE[2:4]), "s": (B, RE[4:6])}
NAMES = {"d": "defaults", "n": "without HC_Q12", "s": "stack"}


def rule(x, y):
    """The noise rule: x is slower than y only when both x runs are under both y runs and the mean gap is over 1%."""
    if len(x) < 2 or len(y) < 2:
        return None
    gap = (mean(x) / mean(y) - 1) * 100
    return gap, "SLOWER" if max(x) < min(y) and gap < -1 else "faster" if min(x) > max(y) and gap > 1 else "level"


conf = [c for c in cs if (N[0], c) in cells]
if conf:
    rerun, lines, gaps, table = {}, [], {}, []
    for c in conf:
        row = [str(c)] + [pair(PAIRS[a][0], c)[0] for a in "dns"]
        for x, y in (("n", "d"), ("n", "s"), ("s", "d"), ("s", "n")):
            words = []
            for kind in ("prose", "code"):
                v = rule(runs(PAIRS[x][0], c, kind), runs(PAIRS[y][0], c, kind))
                words.append(v)
                if v is None:
                    continue
                gaps.setdefault((x, y), []).append(v[0])
                if v[1] == "SLOWER":
                    rerun.setdefault(c, set()).update((x, y))
                again = rule(runs(PAIRS[x][1], c, kind), runs(PAIRS[y][1], c, kind))
                tail = "" if again is None else f"; rerun {again[0]:+.1f}% {again[1]}" + (
                    " LOSS" if v[1] == again[1] == "SLOWER" else "")
                lines.append(f"rule {c} {kind}: {NAMES[x]} against {NAMES[y]} {v[0]:+.1f}% {v[1]}{tail}")
            if (x, y) != ("s", "n"):
                row.append("-" if None in words else
                           f"{words[0][0]:+.1f}% / {words[1][0]:+.1f}% ({words[0][1]}, {words[1][1]})")
        table.append("| " + " | ".join(row) + " |")
    print("\n| streams | defaults (repeat) | without `HC_Q12=1` (repeat) | stack (repeat) | without against defaults"
          " | without against the stack | stack against defaults |")
    print("|---:|---|---|---|---|---|---|")
    print("\n".join(table))
    print()
    for (x, y), v in gaps.items():
        print(f"mean {NAMES[x]} against {NAMES[y]}: {mean(v):+.1f}% over {len(v)} cells ({min(v):+.1f}% to {max(v):+.1f}%)")
    print("\n".join(lines))
    print("\n| streams | rounds, drafted a round, accepted a round: defaults | without `HC_Q12=1` | stack | second runs |")
    print("|---:|---|---|---|---|")
    for c in conf:
        rep = "same" if all(ctr(PAIRS[a][0][1], c) == ctr(PAIRS[a][0][0], c) for a in "dns") else "; ".join(
            ctr(PAIRS[a][0][1], c) for a in "dns")
        print(f"| {c} | {ctr('d', c)} | {ctr('n', c)} | {ctr('s', c)} | {rep} |")
    print("\n| streams | model GiB, pool pages, GiB left: defaults (repeat) | without `HC_Q12=1` (repeat) | stack (repeat) |")
    print("|---:|---|---|---|")
    for c in conf:
        mem = ["; ".join(f"{b['model']}, {b['pages']}, {b['left']}" for b in (boot(n, c) for n in PAIRS[a][0]))
               for a in "dns"]
        print(f"| {c} | {' | '.join(mem)} |")
    with open(os.path.join(out, "rerun.txt"), "w") as f:
        f.write("".join(f"{c} {' '.join(a for a in 'dns' if a in arms)}\n" for c, arms in sorted(rerun.items())))
    if any((r, c) in cells for r in RE for c in conf):
        print("\n| streams | rerun: defaults (d3, d4) | without `HC_Q12=1` (n3, n4) | stack (s3, s4) |")
        print("|---:|---|---|---|")
        for c in conf:
            print(f"| {c} | {' | '.join(pair(PAIRS[a][1], c)[0] for a in 'dns')} |")
