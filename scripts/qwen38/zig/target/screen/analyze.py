#!/usr/bin/env python3
"""analyze.py --out DIR [--plan FILE] [--only ARM] [--print-verdict]: score a screen window by RULE.md.

Reads, per arm, the boots c1, a, c2 (and a2 when a KILL had to be confirmed), each a directory with
meta.json (the driver's record), conc.json (the report bench_concurrent.py wrote) and ttft.txt (the lines
ttft.py printed). Every field is read from the writer's own output; a missing field is an instrument
finding, never a zero. A directory that is not an arm of the plan (the discarded warm-up boot) is never
read.

The margin is pooled. Every arm contributes one control pair per cell, so a window of eleven arms gives
eleven estimates of the run-to-run spread at that cell; the margin is the median of those estimates, floored
at 1 percent (the resolvability floor). One noisy pair cannot widen every verdict, and one lucky pair cannot
narrow them: a pair whose own spread exceeds 25 percent makes its own arm INCONCLUSIVE.

KILL is asymmetric to PROMOTE on purpose, and the asymmetry is decided here, before any row. A KILL costs a
setting its alternative on the worklist, so it needs a treatment cell worse than both controls beyond the
margin AND corroboration: either a second judged cell lost in the same boot, or the same treatment cell lost
again on a second candidate boot (a2). A single-cell loss with neither is KILL-PENDING: not a verdict, and
the driver boots the candidate once more before the window reports it.

Verdicts: INCONCLUSIVE-FINDING, INCONCLUSIVE (unstable controls, or inside the pooled margin), KILL,
KILL-PENDING, PROMOTE, in that precedence. The rule is quoted beside each test in the code.
"""
import argparse
import json
import sys
from pathlib import Path

# name, prompt, streams, temperature, direction
CELLS = [("d1-prose", "chat", 1, 0.0, "high"), ("d1-code", "code", 1, 0.0, "high"),
         ("d4-prose", "chat", 4, 0.0, "high"), ("d4-code", "code", 4, 0.0, "high"),
         ("d4-sampled", "chat", 4, 1.0, "high"),
         ("c2k", None, None, None, "low"), ("c32k", None, None, None, "low")]
DEFAULT_TREATMENT = ("d4-prose", "d4-code")
SPECIAL_TREATMENT = {"TF_FLASHNEXT_SAMPLED_HEADS": ("d4-sampled",)}
UNSTABLE = 0.25
FLOOR = 0.01   # resolvability floor: a difference inside it is level, never KILL or PROMOTE


class Instrument(Exception):
    """A missing or malformed writer output: the boot cannot be scored, and the verdict says so."""


def fail(msg):
    raise Instrument(msg)


def ttft_medians(path):
    out = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        parts = line.split()
        if len(parts) < 8 or parts[0] != "summary":
            continue
        case, load = parts[1], parts[2]
        try:
            med = float(parts[parts.index("med") + 1])
        except (IndexError, ValueError):
            fail(f"{path}: no med in [{line}]")
        if load == "idle":
            out[case] = med
    return out


def load_boot(d, role):
    meta_p, conc_p, ttft_p = d / "meta.json", d / "conc.json", d / "ttft.txt"
    for p in (meta_p, conc_p, ttft_p):
        if not p.is_file():
            fail(f"{d}: missing {p.name}")
    meta = json.loads(meta_p.read_text(encoding="utf-8"))
    report = json.loads(conc_p.read_text(encoding="utf-8"))
    cells = report.get("cells")
    if not isinstance(cells, list) or not cells:
        fail(f"{conc_p}: no cells[]")
    values, tokens, flags = {}, {}, {}
    for name, prompt, streams, temp, _ in CELLS:
        if prompt is None:
            continue
        got = [c for c in cells if c.get("prompt") == prompt and c.get("streams") == streams
               and abs(float(c.get("temperature", -1)) - temp) < 1e-9]
        if len(got) != 1:
            fail(f"{conc_p}: {len(got)} cells for prompt {prompt} streams {streams} temperature {temp}")
        c = got[0]
        for key in ("aggregate_tps", "failed", "unmeasured", "alone", "serial", "reps"):
            if key not in c:
                fail(f"{conc_p}: cell {name} has no {key}")
        if c["aggregate_tps"] is None:
            fail(f"{conc_p}: cell {name} aggregate_tps null")
        values[name] = float(c["aggregate_tps"])
        seen = {q.get("prompt_tokens") for rep in c["reps"] for q in rep.get("requests", [])}
        seen.discard(None)
        if not seen:
            fail(f"{conc_p}: cell {name} carries no prompt_tokens")
        tokens[name] = seen
        flags[name] = (int(c["failed"]), int(c["unmeasured"]),
                       int((c.get("alone") or {}).get("unequal") or 0),
                       int((c.get("serial") or {}).get("unequal") or 0))
    med = ttft_medians(ttft_p)
    for name, case in (("c2k", "cold2k-off"), ("c32k", "cold32k-off")):
        if case not in med:
            fail(f"{ttft_p}: no idle summary for {case}")
        values[name] = med[case]
        tokens[name] = {None}
        flags[name] = (0, 0, 0, 0)
    return {"role": role, "meta": meta, "values": values, "tokens": tokens, "flags": flags}


def try_load(d, role):
    """None when the boot's three files are absent: a partial window is a state, not an exception."""
    for p in (d / "meta.json", d / "conc.json", d / "ttft.txt"):
        if not p.is_file():
            return None
    return load_boot(d, role)


def findings(boots, roles):
    c1 = boots["c1"]
    out = []
    for role in roles:
        m = boots[role]["meta"]
        if int(m.get("boot_rc", 0)) != 0:
            out.append(f"{role}: boot_rc {m.get('boot_rc')}")
        if int(m.get("health", 0)) != 200:
            out.append(f"{role}: health {m.get('health')}")
        if int(m.get("foreign", 0)) != 0:
            out.append(f"{role}: foreign requests {m.get('foreign')}")
        if str(m.get("digest")) != str(c1["meta"].get("digest")):
            out.append(f"{role}: digest {m.get('digest')} != control {c1['meta'].get('digest')}")
        if int(m.get("settings_ok", 1)) != 1:
            out.append(f"{role}: the arm's settings did not reach the container")
        for name, _, _, temp, kind in CELLS:
            failed, unmeasured, alone, serial = boots[role]["flags"][name]
            if failed or unmeasured:
                out.append(f"{role}: {name} failed {failed} unmeasured {unmeasured}")
            if boots[role]["tokens"][name] != c1["tokens"][name]:
                out.append(f"{role}: {name} prompt_tokens {sorted(map(str, boots[role]['tokens'][name]))} "
                           f"!= control {sorted(map(str, c1['tokens'][name]))}")
            if kind == "high" and temp == 0.0 and (alone or serial):
                out.append(f"{role}: {name} greedy text changed (alone unequal {alone}, serial unequal {serial})")
    return out


def pooled_spreads(out, plan):
    """Per cell, every arm's control-to-control spread; the median is the window's margin estimate."""
    pairs = {c[0]: [] for c in CELLS}
    for arm in plan:
        d = Path(out) / arm
        try:
            c1, c2 = try_load(d / "c1", "c1"), try_load(d / "c2", "c2")
        except Instrument:
            continue
        if c1 is None or c2 is None:
            continue
        for name, _, _, _, _ in CELLS:
            mid = (c1["values"][name] + c2["values"][name]) / 2
            pairs[name].append(abs(c1["values"][name] - c2["values"][name]) / mid)
    pooled, worst = {}, {}
    for name, ps in pairs.items():
        s = sorted(ps)
        n = len(s)
        if not n:
            continue
        pooled[name] = s[n // 2] if n % 2 else (s[n // 2 - 1] + s[n // 2]) / 2
        worst[name] = s[-1]
    return pooled, worst, {k: len(v) for k, v in pairs.items()}


def score(boots, treatment, pooled, a2=None):
    c1v, av, c2v = boots["c1"]["values"], boots["a"]["values"], boots["c2"]["values"]
    rows, unstable_cells = {}, []
    for name, _, _, _, kind in CELLS:
        mid = (c1v[name] + c2v[name]) / 2
        own = abs(c1v[name] - c2v[name]) / mid
        s = pooled.get(name, own)
        if own > UNSTABLE:
            unstable_cells.append((name, own))
        m = max(s, FLOOR)
        if kind == "high":
            better = av[name] > c1v[name] * (1 + m) and av[name] > c2v[name] * (1 + m)
            worse = av[name] < c1v[name] * (1 - m) and av[name] < c2v[name] * (1 - m)
        else:
            better = av[name] < c1v[name] * (1 - m) and av[name] < c2v[name] * (1 - m)
            worse = av[name] > c1v[name] * (1 + m) and av[name] > c2v[name] * (1 + m)
        rows[name] = {"c1": c1v[name], "c2": c2v[name], "a": av[name], "mid": mid, "pair": own, "pool": s,
                      "margin": m, "delta": (av[name] - mid) / mid, "better": better, "worse": worse}
    a2rows = None
    if a2 is not None:
        a2rows = {}
        for name, _, _, _, kind in CELLS:
            mid = (c1v[name] + c2v[name]) / 2
            m = max(pooled.get(name, abs(c1v[name] - c2v[name]) / mid), FLOOR)
            x = a2["values"][name]
            if kind == "high":
                worse = x < c1v[name] * (1 - m) and x < c2v[name] * (1 - m)
            else:
                worse = x > c1v[name] * (1 + m) and x > c2v[name] * (1 + m)
            a2rows[name] = {"a": x, "worse": worse}

    # Report-only cells: d4-sampled enters no verdict for an arm whose treatment is not the sampled cell.
    report_only = {c[0] for c in CELLS if c[0] == "d4-sampled" and c[0] not in treatment}
    judges = [c[0] for c in CELLS if c[0] not in report_only]
    guards = [c for c in judges if c not in treatment]
    lost = [c for c in judges if rows[c]["worse"]]
    tlost = [c for c in treatment if rows[c]["worse"]]
    pool_bad = [c for c in judges if pooled.get(c, 0) > UNSTABLE]
    found = findings(boots, ("a", "c2"))
    if a2 is not None:
        found += [f"a2: {x}" for x in findings({"c1": boots["c1"], "a2": a2}, ("a2",))]

    if found:
        return "INCONCLUSIVE-FINDING", "; ".join(found), rows
    if unstable_cells:
        name, s = max(unstable_cells, key=lambda t: t[1])
        return "INCONCLUSIVE", f"unstable controls: {name} spread {s * 100:.1f}% > 25%", rows
    if pool_bad:
        name = max(pool_bad, key=lambda c: pooled[c])
        return "INCONCLUSIVE", (f"the window cannot resolve a change: pooled spread at {name} is "
                                f"{pooled[name] * 100:.1f}% > 25%"), rows

    if tlost:
        if len(lost) >= 2:
            note = (f"worse than both controls beyond the pooled margin in {','.join(tlost)} "
                    f"(corroborated by {','.join(lost)})")
            return "KILL", marginal(note, lost, rows), rows
        if a2 is None:
            note = (f"one treatment cell lost ({','.join(tlost)}) in a single candidate boot; a KILL needs a "
                    f"second judged cell or a second candidate boot, so this is not a verdict")
            return "KILL-PENDING", note, rows
        if any(a2rows[c]["worse"] for c in tlost):
            note = f"worse than both controls beyond the pooled margin in {','.join(tlost)}, confirmed on a2"
            return "KILL", note, rows
        note = (f"the single-boot loss in {','.join(tlost)} was not confirmed by the second candidate boot; "
                f"it is inside run-to-run variation until a quiet cell or more reps says otherwise")
        return "INCONCLUSIVE", note, rows
    if lost:
        return "INCONCLUSIVE", (f"guard cell(s) {','.join(lost)} worse than both controls beyond the pooled "
                                f"margin; no treatment cell lost, so not a KILL, and a guard loss bars PROMOTE"), rows
    if all(rows[t]["better"] for t in treatment) and not any(rows[g]["worse"] for g in guards):
        note = "treatment " + ",".join(treatment) + " beyond the pooled margin, no guard worse"
        gov = min(abs(rows[t]["delta"]) for t in treatment)
        if gov < 0.02:
            note += f" (marginal: the smaller gain beyond the margin is {gov * 100:.1f} percent)"
        return "PROMOTE", note, rows
    inside = [c[0] for c in CELLS if c[0] in treatment and not rows[c[0]]["better"]]
    return "INCONCLUSIVE", "treatment inside the pooled margin in " + ",".join(inside), rows


def marginal(note, lost, rows):
    gov = min(abs(rows[c]["delta"]) for c in lost)
    if gov < 0.02:
        note += f" (marginal: the smallest loss beyond the margin is {gov * 100:.1f} percent)"
    return note


def read_plan(path):
    plan = {}
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        arm, name, value, tier, why = line.split("\t")
        plan[arm] = (name, value, tier, why)
    return plan


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    ap.add_argument("--plan", default=str(Path(__file__).with_name("plan.tsv")))
    ap.add_argument("--only", action="append", default=[], help="score only this arm (repeatable); pooling still "
                                                              "uses every measured control pair in the window")
    ap.add_argument("--print-verdict", action="store_true",
                    help="print `VERDICT <arm> <verdict>` lines only, for the driver's inline confirm step")
    args = ap.parse_args()
    out = Path(args.out)
    plan = read_plan(args.plan)
    pooled, worst, counts = pooled_spreads(out, plan)
    arms = [a for a in sorted(plan) if not args.only or a in args.only]

    results = []
    for arm in arms:
        d = out / arm
        if not d.is_dir():
            continue
        boots, bad = {}, ""
        for role in ("c1", "a", "c2"):
            try:
                b = try_load(d / role, role)
            except Instrument as e:
                bad = str(e)
                break
            if b is not None:
                boots[role] = b
        a2 = None
        try:
            a2 = try_load(d / "a2", "a2") if (d / "a2").is_dir() else None
        except Instrument as e:
            bad = bad or str(e)
        if bad:
            verdict, note, rows = "INCONCLUSIVE-FINDING", bad, {}
        elif len(boots) != 3:
            present = sorted(p.name for p in d.iterdir() if p.is_dir()) if d.is_dir() else []
            verdict, note, rows = "INCOMPLETE", f"boots with cells {sorted(boots)} of {present}", {}
        else:
            treatment = SPECIAL_TREATMENT.get(plan[arm][0], DEFAULT_TREATMENT)
            try:
                verdict, note, rows = score(boots, treatment, pooled, a2)
            except Instrument as e:
                verdict, note, rows = "INCONCLUSIVE-FINDING", str(e), {}
        results.append((arm, plan[arm][0], plan[arm][1], verdict, note, rows,
                        SPECIAL_TREATMENT.get(plan[arm][0], DEFAULT_TREATMENT)[0]))

    if args.print_verdict:
        for arm, name, value, verdict, note, rows, _ in results:
            print(f"VERDICT\t{arm}\t{verdict}")
        return 0

    print("| arm | setting | treatment c1 | c2 | arm | pair | pool | delta | verdict | note |")
    print("|---|---|---:|---:|---:|---:|---:|---:|---|---|")
    for arm, name, value, verdict, note, rows, cell in results:
        if cell not in rows:
            print(f"| {arm} | {name}={value} | | | | | | | **{verdict}** | {note} |")
            continue
        r = rows[cell]
        print(f"| {arm} | {name}={value} | {r['c1']:.1f} | {r['c2']:.1f} | {r['a']:.1f} | "
              f"{r['pair'] * 100:.1f}% | {r['pool'] * 100:.1f}% | {r['delta'] * 100:+.1f}% | "
              f"**{verdict}** | {note} |")
    for cname, _, _, _, _ in CELLS:
        if cname in pooled:
            print(f"POOL {cname} {pooled[cname] * 100:.1f}% max {worst[cname] * 100:.1f}% n {counts[cname]}")

    lines = ["arm\tsetting\tvalue\tverdict\tnote\t" + "\t".join(c[0] for c in CELLS)]
    for arm, name, value, verdict, note, rows, cell in results:
        cells = []
        for cname, _, _, _, _ in CELLS:
            r = rows.get(cname)
            cells.append(f"{r['a']:.3f}({r['delta'] * 100:+.1f}%,pair {r['pair'] * 100:.1f}%,"
                         f"pool {r['pool'] * 100:.1f}%)" if r else "")
        lines.append("\t".join([arm, name, value, verdict, note, *cells]))
    (out / "scores.tsv").write_text("\n".join(lines) + "\n", encoding="utf-8")
    tally = {}
    for v in results:
        tally[v[3]] = tally.get(v[3], 0) + 1
    print()
    print("counts " + " ".join(f"{k} {v}" for k, v in sorted(tally.items())))
    print(f"wrote {out / 'scores.tsv'} ({len(results)} arms)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
