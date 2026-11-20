"""analyze_knobs.py OUT --base M1,M2 [--write] [--window NAME]

Cells, the noise rule, exactness tallies and boot evidence for one knob window. Arms are the directories under
OUT/<pass>/<arm>/; an arm whose name ends in 'b' is the second run of the treatment named without it (C1536 and
C1536b are the two runs of TF_FLASHNEXT_CHUNK=1536), and --base names the two main runs that bracket the window.

A cell is SLOWER when both treatment runs are under both main runs (for a latency: over) and the mean gap is over
1%, FASTER when both are over both and the gap is over 1%, LEVEL otherwise; a cell with fewer than two runs on
either side is reported with its gap and 'unmeasured'.

--write writes cells.csv, decode.md, ttft.md, exactness.md, golden.md, boot.md and summary.json into OUT/analysis.
"""
import argparse
import csv
import glob
import json
import os
import statistics
import sys

REPS = ("reps",)


def fmean(vals):
    vals = [v for v in vals if isinstance(v, (int, float))]
    return statistics.fmean(vals) if vals else None


def verdict(values, base, after, higher_is_worse=False):
    m = [values[a] for a in base if a in values]
    b = [values[a] for a in after if a in values]
    if len(m) < 2 or len(b) < 2:
        gap = None
        if m and b:
            gap = (fmean(b) - fmean(m)) / fmean(m) * 100
        return gap, "unmeasured"
    gap = (fmean(b) - fmean(m)) / fmean(m) * 100
    if higher_is_worse:
        if min(b) > max(m) and gap > 1.0:
            return gap, "slower"
        if max(b) < min(m) and gap < -1.0:
            return gap, "faster"
        return gap, "level"
    if max(b) < min(m) and gap < -1.0:
        return gap, "slower"
    if min(b) > max(m) and gap > 1.0:
        return gap, "faster"
    return gap, "level"


def treatment(arm):
    return arm[:-1] if len(arm) > 1 and arm.endswith("b") else arm


def arm_dirs(out):
    """OUT/<arm>/<pass>/ (the driver's layout): one entry an arm, its pass directories its runs."""
    arms = {}
    for p in sorted(glob.glob(os.path.join(out, "*"))):
        if not os.path.isdir(p):
            continue
        arm = os.path.basename(p)
        if ".rejected" in arm:
            continue
        passes = [q for q in sorted(glob.glob(os.path.join(p, "*"))) if os.path.isdir(q)]
        if passes:
            arms[arm] = passes
    return arms


def read_json(path):
    try:
        return json.load(open(path, encoding="utf-8"))
    except (OSError, ValueError):
        return None


def decode_cells(out, arms):
    """(treatment, arm, key) -> {metric: value} for the greedy decode cells."""
    cells = {}
    for arm, dirs in arms.items():
        for d in dirs:
            pass_name = os.path.basename(d)
            p = os.path.join(d, "conc_t0.json")
            data = read_json(p)
            if data:
                for c in data.get("cells") or []:
                    if c.get("temperature") not in (0, 0.0):
                        continue
                    key = (pass_name + "/conc_t0", c.get("prompt") or "", float(c.get("temperature") or 0.0), int(c.get("streams") or 1))
                    cells.setdefault(key, {})[arm] = {
                        "tps": c.get("aggregate_tps"),
                        "failed": c.get("failed"),
                        "unmeasured": c.get("unmeasured"),
                        "tpr": (c.get("pooled") or {}).get("tokens_per_chunk"),
                        "reps": len(c.get("reps") or []),
                    }
            data = read_json(os.path.join(d, "openai_t0.json"))
            if data:
                for e in data:
                    key = (pass_name + "/openai_t0", e.get("prompt") or "", float(e.get("temperature") or 0.0), 1)
                    cells.setdefault(key, {})[arm] = {
                        "tps": e.get("decode_tps_median"),
                        "failed": 0, "unmeasured": 0,
                        "tpr": e.get("tokens_per_chunk_median"),
                        "reps": len(e.get("decode_tps_all") or []),
                        "ttft": e.get("ttft_s_median"),
                    }
    return cells


def ttft_cells(out, arms):
    """(treatment, arm, case, load) -> median ttft from the summary lines."""
    cells = {}
    for arm, dirs in arms.items():
        for d in dirs:
            for name in ("ttft", "ttft64"):
                path = os.path.join(d, name + ".out")
                if not os.path.exists(path):
                    continue
                for line in open(path, encoding="utf-8", errors="replace"):
                    f = line.split()
                    if not f or f[0] != "summary":
                        continue
                    # summary <case> <load> n <n> ttft med <s> p90 <s> ...
                    try:
                        case, load = f[1], f[2]
                        med = float(f[f.index("med") + 1])
                    except (IndexError, ValueError):
                        continue
                    cells.setdefault((os.path.basename(d) + "/" + case, load), {})[arm] = med
    return cells


def resume_cells(out, arms):
    """(treatment, arm) -> the resume bench's A2/A3 cached tokens and A3 ttft, and bench_cache's rows."""
    cells = {}
    for arm, dirs in arms.items():
        for d in dirs:
            doc = read_json(os.path.join(d, "resume.json"))
            if doc:
                by = {r.get("label"): r for r in doc.get("rows") or []}
                a2, a3 = by.get("A2") or {}, by.get("A3") or {}
                cells.setdefault(("resume", "A3_cached_tokens"), {})[arm] = a3.get("cached_tokens")
                cells.setdefault(("resume", "A3_ttft_s"), {})[arm] = a3.get("ttft_s")
                cells.setdefault(("resume", "A2_cached_tokens"), {})[arm] = a2.get("cached_tokens")
            doc = read_json(os.path.join(d, "cache.json"))
            if doc:
                rows = doc.get("rows") or []
                first = next((r for r in rows if r.get("phase") == "first"), {})
                rep = next((r for r in rows if r.get("phase") == "repeated"), {})
                cells.setdefault(("cache", "first_ttft_s"), {})[arm] = first.get("ttft_s")
                cells.setdefault(("cache", "repeated_cached_tokens"), {})[arm] = rep.get("cached_tokens")
                cells.setdefault(("cache", "repeated_ttft_s"), {})[arm] = rep.get("ttft_s")
    return cells


def exactness(out, arms):
    rows = []
    for arm, dirs in arms.items():
        for d in dirs:
            doc = read_json(os.path.join(d, "drafts.json"))
            if doc:
                ok = sum(1 for r in doc.get("rows") or [] if r.get("equal"))
                rows.append({"arm": arm, "cell": "drafts", "equal": ok,
                             "total": len(doc.get("rows") or []),
                             "basis": ",".join(sorted({str(r.get("basis")) for r in doc.get("rows") or []}))})
            doc = read_json(os.path.join(d, "fresh.json"))
            if doc:
                ok = sum(1 for r in doc.get("rows") or [] if not r.get("problems"))
                rows.append({"arm": arm, "cell": "fresh", "equal": ok,
                             "total": len(doc.get("rows") or []),
                             "basis": ",".join(sorted({str(r.get("plain", {}).get("basis")) for r in doc.get("rows") or []}))})
            doc = read_json(os.path.join(d, "turns.json"))
            if doc:
                resumed = sum(1 for r in doc.get("rows") or [] if (r.get("resumed", {}).get("cached_tokens") or 0) > 0)
                rows.append({"arm": arm, "cell": "turns", "equal": resumed,
                             "total": len(doc.get("rows") or []), "basis": "resumed_from_cache"})
    return rows


def solo_vs_concurrent(out, arms):
    """Compare each concurrent temperature-1 cell's replies with the solo cell's, by token_sha256."""
    rows = []
    for arm, dirs in arms.items():
        for d in dirs:
            data = read_json(os.path.join(d, "conc_t1.json"))
            if not data:
                continue
            per = {}
            for c in data.get("cells") or []:
                key = (c.get("prompt") or "", float(c.get("temperature") or 0.0))
                shas = []
                for rep in c.get("reps") or []:
                    for ev in rep.get("evidence") or []:
                        shas.append(ev.get("token_sha256"))
                per.setdefault(key, {})[int(c.get("streams") or 1)] = shas
            for key, by_stream in per.items():
                solo = by_stream.get(1)
                if not solo:
                    continue
                for streams, shas in by_stream.items():
                    if streams == 1:
                        continue
                    same = sum(1 for a, b in zip(solo, shas) if a and a == b)
                    rows.append({"arm": arm, "prompt": os.path.basename(d) + "/" + key[0], "temperature": key[1], "streams": streams,
                                 "equal": same, "total": min(len(solo), len(shas))})
    return rows


def greedy_hashes(out, arms, base):
    """token_sha256 of every greedy reply, per cell, per arm (for the cross-arm equality tally)."""
    first = {}
    for arm, dirs in arms.items():
        for d in dirs:
            for name in ("conc_t0", "openai_t0", "golden"):
                data = read_json(os.path.join(d, name + ".json"))
                if not data:
                    continue
                cells = data if isinstance(data, list) else (data.get("cells") or [])
                for c in cells:
                    key = (os.path.basename(d) + "/" + name, c.get("prompt") or "", int(c.get("streams") or 1))
                    shas = []
                    if isinstance(c, dict) and "cells" not in c and "evidence" in c:
                        shas = [ev.get("token_sha256") for ev in c["evidence"]]
                    else:
                        for rep in c.get("reps") or []:
                            shas = [ev.get("token_sha256") for ev in rep.get("evidence") or []]
                    first.setdefault(key, {})[arm] = shas
    tally = []
    for key, per_arm in sorted(first.items()):
        ref_arm = next((a for a in base if a in per_arm and per_arm[a]), None)
        if not ref_arm:
            continue
        ref = per_arm[ref_arm]
        for arm, shas in per_arm.items():
            if arm == ref_arm or not shas:
                continue
            same = sum(1 for a, b in zip(ref, shas) if a and a == b)
            tally.append({"cell": "/".join(str(x) for x in key), "arm": arm, "ref": ref_arm,
                          "equal": same, "total": min(len(ref), len(shas))})
    return tally


def probe_health(out, arms):
    rows = []
    for arm, dirs in arms.items():
        for d in dirs:
            g = os.path.join(d, "gets.txt")
            if os.path.exists(g):
                nonlocal_ = 0
                for line in open(g, encoding="utf-8", errors="replace"):
                    if "nonlocal=" in line:
                        try:
                            nonlocal_ += int(line.split("nonlocal=")[1].split()[0])
                        except (IndexError, ValueError):
                            pass
                rows.append({"arm": arm, "pass": os.path.basename(d), "foreign": nonlocal_})
    return rows


def boot_rows(out, arms, image):
    rows = []
    for arm, dirs in arms.items():
        for d in dirs:
            bt = os.path.join(d, "boot_time.txt")
            if not os.path.exists(bt):
                continue
            info = {}
            for line in open(bt, encoding="utf-8", errors="replace"):
                k, _, v = line.strip().partition(" ")
                info[k] = v
            env = []
            envp = os.path.join(d, "env.txt")
            if os.path.exists(envp):
                env = [l.strip() for l in open(envp, encoding="utf-8", errors="replace") if l.strip().startswith(("TF_", "TENSORFOLD_"))]
            rows.append({"arm": arm, "pass": os.path.basename(d), "rc": info.get("boot_rc"),
                         "wall_s": info.get("wall_s"), "par": info.get("par"), "ctx": info.get("ctx"),
                         "overrides": info.get("overrides"), "env": env, "image": image})
    return rows


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("out")
    p.add_argument("--base", default="M1,M2")
    p.add_argument("--image", default="tensorfold-qwen38:knob-m-1ece6e6d")
    p.add_argument("--window", default="")
    p.add_argument("--write", action="store_true")
    a = p.parse_args(argv)
    out = a.out
    arms = arm_dirs(out)
    if not arms:
        print("no arm directories under", out, file=sys.stderr)
        return 1
    base = [x for x in a.base.split(",") if x]
    for b in base:
        if b not in arms:
            print(f"base arm {b} missing: have {sorted(arms)}", file=sys.stderr)
            return 1
    treat = {}
    for arm in arms:
        treat.setdefault(treatment(arm), []).append(arm)

    cells = decode_cells(out, arms)
    tt = ttft_cells(out, arms)
    ex = exactness(out, arms)
    rc = resume_cells(out, arms)
    solo = solo_vs_concurrent(out, arms)
    hashes = greedy_hashes(out, arms, base)
    health = probe_health(out, arms)
    boots = boot_rows(out, arms, a.image)

    # decode cell verdicts
    rows = []
    for key, per_arm in sorted(cells.items()):
        for tname, mem in sorted(treat.items()):
            if tname in ("M1", "M2"):
                continue
            values = {arm: per_arm[arm]["tps"] for arm in mem if arm in per_arm and per_arm[arm]["tps"]}
            everything = {arm: per_arm[arm]["tps"] for arm in per_arm if per_arm[arm].get("tps")}
            gap, v = verdict(everything, [b for b in base if b in everything], list(values))
            tpr = fmean([per_arm[arm].get("tpr") for arm in mem if arm in per_arm])
            rows.append({"cell": "/".join(str(x) for x in key), "treatment": tname,
                         "runs": len(values), "tps": fmean(values.values()) if values else None,
                         "base_tps": fmean([per_arm[b]["tps"] for b in base if b in per_arm and per_arm[b]["tps"]]),
                         "gap_pct": round(gap, 2) if gap is not None else None, "verdict": v,
                         "tokens_per_round": round(tpr, 3) if tpr else None})

    # resume and cache cells: tokens a resume keeps (higher is better) and its TTFT (higher is worse)
    rrows = []
    for key, per_arm in sorted(rc.items()):
        for tname, mem in sorted(treat.items()):
            if tname in ("M1", "M2"):
                continue
            values = {arm: per_arm[arm] for arm in mem if arm in per_arm and isinstance(per_arm[arm], (int, float))}
            if not values:
                continue
            everything = {arm: v for arm, v in per_arm.items() if isinstance(v, (int, float))}
            worse = key[1].endswith("ttft_s")
            gap, v = verdict(everything, [b for b in base if b in everything], list(values), higher_is_worse=worse)
            rrows.append({"cell": "/".join(key), "treatment": tname, "runs": len(values),
                          "value": round(fmean(values.values()), 3),
                          "base_value": round(fmean([per_arm[b] for b in base if b in per_arm]), 3),
                          "gap_pct": round(gap, 2) if gap is not None else None, "verdict": v})

    # ttft verdicts (latency: higher is worse)
    trows = []
    for key, per_arm in sorted(tt.items()):
        for tname, mem in sorted(treat.items()):
            if tname in ("M1", "M2"):
                continue
            values = {arm: per_arm[arm] for arm in mem if arm in per_arm and per_arm[arm]}
            everything = {arm: v for arm, v in per_arm.items() if v}
            gap, v = verdict(everything, [b for b in base if b in everything], list(values), higher_is_worse=True)
            trows.append({"case": key[0], "load": key[1], "treatment": tname, "runs": len(values),
                          "ttft_s": round(fmean(values.values()), 3) if values else None,
                          "base_ttft_s": round(fmean([per_arm[b] for b in base if b in per_arm]), 3),
                          "gap_pct": round(gap, 2) if gap is not None else None, "verdict": v})

    # counts per treatment: how many cells answered faster, slower, level, unmeasured
    counts = {}
    for r in rows:
        c = counts.setdefault(r["treatment"], {"faster": 0, "slower": 0, "level": 0, "unmeasured": 0, "cells": 0})
        c["cells"] += 1
        if r["verdict"] in c:
            c[r["verdict"]] += 1
    for r in trows:
        c = counts.setdefault(r["treatment"], {"faster": 0, "slower": 0, "level": 0, "unmeasured": 0, "cells": 0})
        c["cells"] += 1
        if r["verdict"] in c:
            c[r["verdict"]] += 1

    # the environment each arm printed, and how it differs from the first base boot
    base_env = next((b["env"] for b in boots if b["arm"] == base[0]), [])
    for b in boots:
        b["differs_by"] = sorted(set(b["env"]) ^ set(base_env))

    summary = {
        "counts": counts,
        "window": a.window or os.path.basename(out.rstrip("/")),
        "image": a.image,
        "base_arms": base,
        "arms": sorted(arms),
        "treatments": {k: sorted(v) for k, v in sorted(treat.items())},
        "decode_cells": rows,
        "ttft_cells": trows,
        "resume_cells": rrows,
        "exactness": ex,
        "solo_vs_concurrent": solo,
        "cross_arm_hashes": hashes,
        "foreign": health,
        "boots": boots,
    }
    print(json.dumps({k: summary[k] for k in ("window", "arms", "treatments")}, indent=1))
    for r in rows:
        print(f"{r['cell']:28s} {r['treatment']:10s} runs {r['runs']} {str(r['tps'])[:7]:>7s} vs "
              f"{str(r['base_tps'])[:7]:>7s} {str(r['gap_pct']):>7s}% {r['verdict']}")
    for r in rrows:
        print(f"RESUME {r['cell']:26s} {r['treatment']:10s} {str(r['value']):>9s} vs {str(r['base_value']):>9s} "
              f"{str(r['gap_pct']):>7s}% {r['verdict']}")
    for r in trows:
        print(f"TTFT {r['case']:12s} {r['load']:5s} {r['treatment']:10s} {str(r['ttft_s']):>8s} vs "
              f"{str(r['base_ttft_s']):>8s} {str(r['gap_pct']):>7s}% {r['verdict']}")
    if a.write:
        d = os.path.join(out, "analysis")
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "cells.csv"), "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0].keys()) if rows else ["cell"])
            w.writeheader()
            w.writerows(rows)
        with open(os.path.join(d, "ttft.csv"), "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=list(trows[0].keys()) if trows else ["case"])
            w.writeheader()
            w.writerows(trows)
        json.dump(summary, open(os.path.join(d, "summary.json"), "w", encoding="utf-8"), indent=1)
        with open(os.path.join(d, "decode.md"), "w", encoding="utf-8") as f:
            f.write(f"# Decode cells, window {summary['window']}, image {a.image}\n\n")
            f.write("Counts per treatment over the decode and TTFT cells (faster / slower / level / unmeasured):\n\n")
            for t, c in sorted(counts.items()):
                f.write(f"- {t}: {c['faster']} faster, {c['slower']} slower, {c['level']} level, "
                        f"{c['unmeasured']} unmeasured, of {c['cells']}\n")
            f.write("\n")
            f.write("Cell, treatment, runs, treatment tok/s, main tok/s, gap %, verdict.\n\n")
            f.write("| cell | treatment | runs | tok/s | main | gap | verdict | tpr |\n| --- | --- | --- | --- | --- | --- | --- | --- |\n")
            for r in rows:
                f.write(f"| {r['cell']} | {r['treatment']} | {r['runs']} | {r['tps']} | {r['base_tps']} | "
                        f"{r['gap_pct']} | {r['verdict']} | {r['tokens_per_round']} |\n")
        with open(os.path.join(d, "ttft.md"), "w", encoding="utf-8") as f:
            f.write(f"# TTFT cells, window {summary['window']}\n\n")
            f.write("| case | load | treatment | runs | ttft s | main s | gap | verdict |\n| --- | --- | --- | --- | --- | --- | --- | --- |\n")
            for r in trows:
                f.write(f"| {r['case']} | {r['load']} | {r['treatment']} | {r['runs']} | {r['ttft_s']} | "
                        f"{r['base_ttft_s']} | {r['gap_pct']} | {r['verdict']} |\n")
        with open(os.path.join(d, "resume.md"), "w", encoding="utf-8") as f:
            f.write(f"# Resume and cache cells, window {summary['window']}\n\n")
            f.write("| cell | treatment | runs | value | main | gap | verdict |\n| --- | --- | --- | --- | --- | --- | --- |\n")
            for r in rrows:
                f.write(f"| {r['cell']} | {r['treatment']} | {r['runs']} | {r['value']} | {r['base_value']} | "
                        f"{r['gap_pct']} | {r['verdict']} |\n")
        with open(os.path.join(d, "exactness.md"), "w", encoding="utf-8") as f:
            f.write(f"# Exactness, window {summary['window']}\n\n")
            f.write("| arm | cell | equal | total | basis |\n| --- | --- | --- | --- | --- |\n")
            for r in ex:
                f.write(f"| {r['arm']} | {r['cell']} | {r['equal']} | {r['total']} | {r['basis']} |\n")
            f.write("\nConcurrent equals solo (temperature 1 and 0, streams against the solo stream):\n\n")
            f.write("| arm | prompt | temp | streams | equal | total |\n| --- | --- | --- | --- | --- | --- |\n")
            for r in solo:
                f.write(f"| {r['arm']} | {r['prompt']} | {r['temperature']} | {r['streams']} | {r['equal']} | {r['total']} |\n")
        with open(os.path.join(d, "golden.md"), "w", encoding="utf-8") as f:
            f.write(f"# Cross-arm greedy equality (token_sha256), window {summary['window']}\n\n")
            f.write("| cell | arm | against | equal | total |\n| --- | --- | --- | --- | --- |\n")
            for r in hashes:
                f.write(f"| {r['cell']} | {r['arm']} | {r['ref']} | {r['equal']} | {r['total']} |\n")
        with open(os.path.join(d, "boot.md"), "w", encoding="utf-8") as f:
            f.write(f"# Boots and environment, window {summary['window']}\n\n")
            f.write("| arm | pass | rc | wall s | par | ctx | overrides | env vars | differs from "
                    f"{base[0]} by |\n| --- | --- | --- | --- | --- | --- | --- | --- | --- |\n")
            for r in boots:
                f.write(f"| {r['arm']} | {r['pass']} | {r['rc']} | {r['wall_s']} | {r['par']} | {r['ctx']} | "
                        f"{r['overrides']} | {len(r['env'])} | {'; '.join(r['differs_by']) or 'nothing'} |\n")
            f.write("\nThe environment each boot printed (the container inspect), the base boot first:\n\n")
            for r in boots:
                if r["arm"] == base[0] and r["pass"] == "a":
                    f.write("```\n" + "\n".join(r["env"]) + "\n```\n\n")
                    break
            f.write("Every other arm's list is in its own `env.txt` under `out/<window>/<arm>/<pass>/`.\n")
            f.write("\nForeign requests per arm (requests the arm did not send):\n\n")
            for r in health:
                f.write(f"- {r['arm']} {r['pass']}: {r['foreign']}\n")
        print("wrote", d)
    return 0


if __name__ == "__main__":
    sys.exit(main())
