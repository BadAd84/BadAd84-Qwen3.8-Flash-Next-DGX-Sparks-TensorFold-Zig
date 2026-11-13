"""Summary of exact0014.sh: the three exactness equalities per arm, and each arm's replies against main's."""

import json
import sys

ARMS = ("main", "pr-default", "pr-mxfp8")


def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def bench(path):
    """bench_concurrent output: serial counts once per (prompt, temperature), alone counts per temperature, and the
    alone and serial token hashes of the widest cell's first rep keyed by (prompt, temperature, stream index)."""
    r = load(path)
    if r is None:
        return None
    serial, alone, failed, widest, hashes = {}, {}, 0, {}, {}
    for c in r["cells"]:
        key = (c["prompt"], c["temperature"])
        if c.get("serial") and key not in serial:
            serial[key] = c["serial"]
        a = alone.setdefault(c["temperature"], [0, 0, 0])
        for i, k in enumerate(("equal", "unequal", "failed")):
            a[i] += (c.get("alone") or {}).get(k, 0)
        failed += c.get("failed", 0)
        if c["streams"] >= widest.get(key, (0, None))[0]:
            widest[key] = (c["streams"], c)
    tokens = set()
    for key, (_, c) in widest.items():
        for i, cmp in enumerate(c["reps"][0].get("comparisons", [])):
            hashes[(key[0], key[1], i)] = (cmp["alone"].get("token_sha256"), cmp["serial"].get("token_sha256"))
            tokens.add(cmp["alone"].get("tokens"))
    s = {}
    for (prompt, temp), v in serial.items():
        t = s.setdefault(temp, [0, 0, 0])
        for i, k in enumerate(("equal", "unequal", "failed")):
            t[i] += v.get(k, 0)
    return {"serial": s, "alone": alone, "failed": failed, "hashes": hashes, "tokens": sorted(tokens, key=str)}


def drafts(path):
    r = load(path)
    if r is None:
        return None
    rows = r["rows"]
    return {"n": len(rows), "equal": sum(1 for x in rows if x["equal"]), "basis": sorted({x["basis"] for x in rows}),
            "tokens": sorted({t for x in rows for t in x["tokens"]}, key=str),
            "accepted": [x["drafted"]["accepted"] for x in rows], "drafted": [x["drafted"]["drafted"] for x in rows],
            "plain_drafted": [x["plain"]["drafted"] for x in rows],
            "ids": {x["name"]: x["plain"]["token_ids"] or x["plain"]["token_sha256"] for x in rows}}


def resumes(fresh_path, turns_path):
    r, t = load(fresh_path), load(turns_path)
    if r is None:
        return None
    rows = r["rows"]
    return {"n": len(rows), "ok": sum(1 for x in rows if not x["problems"]),
            "problems": [p for x in rows for p in x["problems"]], "cached": [x["resumed_cached"] for x in rows],
            "prompt": [x["fresh_plain"]["prompt_tokens"] for x in rows],
            "fresh_cached": sorted({c for x in rows for c in (x["fresh_plain"]["cached_tokens"],
                                                              x["fresh_drafted"]["cached_tokens"])}, key=str),
            "tokens": [x["fresh_plain"]["completion_tokens"] for x in rows],
            "basis": sorted({x["plain"]["basis"] for x in rows}),
            "first": {y["name"]: y["first"]["token_ids"] for y in (t or {}).get("rows", [])},
            "resumed": {y["name"]: y["resumed"]["token_ids"] for y in (t or {}).get("rows", [])}}


def serve_check(path):
    try:
        lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        return None
    return {"ok": [x[5:] for x in lines if x.startswith("ok   ")], "fail": [x[5:] for x in lines if x.startswith("FAIL ")]}


def scan(node, found):
    if isinstance(node, dict):
        if "equal_first_tokens" in node:
            found.append(node)
        for v in node.values():
            scan(v, found)
    elif isinstance(node, list):
        for v in node:
            scan(v, found)


def cache(path):
    r = load(path)
    if r is None:
        return None
    rows = []
    scan(r, rows)
    eq = [x["equal_first_tokens"] for x in rows]
    states = {}
    for x in rows:
        states[x.get("cache_state")] = states.get(x.get("cache_state"), 0) + 1
    qualified = {k: v for k, v in r.items() if "qualif" in k} if isinstance(r, dict) else {}
    return {"equal": eq.count(True), "unequal": eq.count(False), "unverified": eq.count(None), "states": states,
            "qualified": qualified, "cached": [x.get("cached_tokens") for x in rows]}


def counts(c):
    return f"{c[0]}/{c[0] + c[1] + c[2]} equal" + (f", {c[1]} unequal" if c[1] else "") + (f", {c[2]} unverified" if c[2] else "")


def main():
    out = sys.argv[1]
    data = {}
    for arm in ARMS:
        d = f"{out}/{arm}"
        data[arm] = {"conc": bench(f"{d}/on/concurrent.json"), "gold": bench(f"{d}/on/golden.json"),
                     "d_on": drafts(f"{d}/on/drafts.json"), "d_off": drafts(f"{d}/off/drafts.json"),
                     "res": resumes(f"{d}/off/fresh.json", f"{d}/on/turns.json"),
                     "sc": serve_check(f"{d}/off/serve_check.out"), "cache": cache(f"{d}/on/cache.json")}
    rows, verdict = [], {arm: {1: True, 2: True, 3: True} for arm in ARMS}

    def row(check, measure, cell):
        line = [check, measure]
        for arm in ARMS:
            text, good = cell(data[arm])
            verdict[arm][check] &= good
            line.append(text)
        rows.append(line)

    def bench_serial(key, temp):
        def cell(a):
            b = a[key]
            if b is None or temp not in b["serial"]:
                return "missing", False
            c = b["serial"][temp]
            return f"{counts(c)} (token_sha256, {b['tokens']} tok)", c[1] == 0 and c[2] == 0 and c[0] > 0
        return cell

    def bench_alone(key, temp):
        def cell(a):
            b = a[key]
            if b is None or temp not in b["alone"]:
                return "missing", False
            c = b["alone"][temp]
            return f"{counts(c)}, {b['failed']} failed requests", c[1] == 0 and c[2] == 0 and c[0] > 0 and b["failed"] == 0
        return cell

    def drafted(key):
        def cell(a):
            d = a[key]
            if d is None:
                return "missing", False
            acc = [x for x in d["accepted"] if x is not None]
            good = d["equal"] == d["n"] and d["n"] > 0 and bool(acc) and min(acc) > 0
            return (f"{d['equal']}/{d['n']} equal ({','.join(d['basis'])}, {d['tokens']} tok); accepted "
                    f"{min(acc) if acc else None}-{max(acc) if acc else None} a reply, plain drafted "
                    f"{sorted(set(map(str, d['plain_drafted'])))}"), good
        return cell

    def sc_lines(words):
        def cell(a):
            s = a["sc"]
            if s is None:
                return "missing", False
            ok = [x for x in s["ok"] if any(w in x for w in words)]
            bad = [x for x in s["fail"] if any(w in x for w in words)]
            return f"{len(ok)}/{len(ok) + len(bad)} ok" + (f" FAIL: {bad}" if bad else ""), not bad and bool(ok)
        return cell

    def resumed(a):
        r = a["res"]
        if r is None:
            return "missing", False
        return (f"{r['ok']}/{r['n']} equal ({','.join(r['basis'])}, {r['tokens']} tok); resumed from {r['cached']} "
                f"of {r['prompt']} prompt tokens; fresh cached {r['fresh_cached']}"
                + (f"; {r['problems']}" if r["problems"] else "")), r["ok"] == r["n"] and r["n"] > 0

    def cache_cell(a):
        c = a["cache"]
        if c is None:
            return "missing", False
        return (f"{c['equal']} equal, {c['unequal']} unequal, {c['unverified']} unverified; states {c['states']}; "
                f"cached {c['cached']}; {c['qualified']}"), c["unequal"] == 0 and c["equal"] > 0

    row(1, "bench_concurrent --serial, code+chat, greedy", bench_serial("conc", 0.0))
    row(1, "bench_concurrent --serial, code+chat, temperature 1.0", bench_serial("conc", 1.0))
    row(1, "bench_concurrent --serial, six golden, greedy", bench_serial("gold", 0.0))
    row(1, "served_exactness drafts, 8 prompts, cache on", drafted("d_on"))
    row(1, "served_exactness drafts, 8 prompts, cache off", drafted("d_off"))
    row(1, "serve_check drafted == serial (greedy, t0.8), cache off", sc_lines(("drafted == serial",)))
    row(2, "served_exactness turns (on) against fresh (off), 5 chats", resumed)
    row(2, "bench_cache repeated/concurrent == first, cache on", cache_cell)
    row(3, "bench_concurrent --alone, identical code+chat, 1/2/4, greedy", bench_alone("conc", 0.0))
    row(3, "bench_concurrent --alone, code+chat, 1/2/4, temperature 1.0", bench_alone("conc", 1.0))
    row(3, "bench_concurrent --alone, six golden distinct, 1/2/4/6, greedy", bench_alone("gold", 0.0))
    row(3, "serve_check together/among-decoders/twice, cache off",
        sc_lines(("together", "unchanged", "among decoders", "twice")))
    print("| check | measure | main | PR, unset | PR, mxfp8 |")
    print("|---|---|---|---|---|")
    for line in rows:
        print("| " + " | ".join(str(x) for x in line) + " |")
    print()
    print("| check | main | PR, unset | PR, mxfp8 |")
    print("|---|---|---|---|")
    names = {1: "drafted == draft:false", 2: "resumed == fresh", 3: "concurrent == solo"}
    for check in (1, 2, 3):
        print(f"| {names[check]} | " + " | ".join("PASS" if verdict[arm][check] else "FAIL" for arm in ARMS) + " |")
    print()
    print("Replies against main's (same request, same boot kind):")
    ref = data["main"]
    for arm in ARMS[1:]:
        a = data[arm]
        parts = []
        for key in ("conc", "gold"):
            if a[key] and ref[key]:
                keys = sorted(set(a[key]["hashes"]) & set(ref[key]["hashes"]), key=str)
                same = sum(1 for k in keys if a[key]["hashes"][k] == ref[key]["hashes"][k] and a[key]["hashes"][k][0])
                parts.append(f"{key} alone+serial hashes {same}/{len(keys)}")
        for key in ("d_on", "d_off"):
            if a[key] and ref[key]:
                keys = sorted(set(a[key]["ids"]) & set(ref[key]["ids"]))
                same = sum(1 for k in keys if a[key]["ids"][k] == ref[key]["ids"][k] and a[key]["ids"][k])
                parts.append(f"{key} plain token ids {same}/{len(keys)}")
        if a["res"] and ref["res"]:
            for part in ("first", "resumed"):
                keys = sorted(set(a["res"][part]) & set(ref["res"][part]))
                same = sum(1 for k in keys if a["res"][part][k] == ref["res"][part][k] and a["res"][part][k])
                parts.append(f"turn {part} token ids {same}/{len(keys)}")
        print(f"- {arm}: " + "; ".join(parts))
    print()
    print("serve_check lines (cache off; its resumed == fresh line compares two cold requests on that server):")
    for arm in ARMS:
        s = data[arm]["sc"]
        print(f"- {arm}: " + ("missing" if s is None else f"{len(s['ok'])} ok, {len(s['fail'])} FAIL {s['fail']}"))


if __name__ == "__main__":
    main()
