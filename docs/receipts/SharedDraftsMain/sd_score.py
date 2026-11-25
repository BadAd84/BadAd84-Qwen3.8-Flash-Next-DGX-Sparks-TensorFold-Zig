#!/usr/bin/env python3
"""Score the clean-main SHARED_DRAFTS window from the stored per-cell evidence.

Reads <root>/arm<A>/<cell>/cell.json (cell = c1..c8, c<N>-run2, cached) and writes <root>/score.json.
Prints SCORE-SUMMARY and one RERUN line per level whose decode passes span more than 5 percent (before a
rerun) or RERUN-OPEN when still over after it. A level's final numbers come from c<N>-run2 when it exists.
"""
import argparse
import glob
import json
import os
import statistics
import sys

LEVELS = (1, 2, 4, 8)
NOISE = 0.05


def median(vals):
    vals = [v for v in vals if v is not None]
    return statistics.median(vals) if vals else None


def load(root):
    cells = {}
    for path in glob.glob(os.path.join(root, "arm*", "*", "cell.json")):
        arm_dir = os.path.basename(os.path.dirname(os.path.dirname(path)))
        label = os.path.basename(os.path.dirname(path))
        if not arm_dir.startswith("arm"):
            continue
        arm = arm_dir[3:]
        with open(path, encoding="utf-8") as f:
            cells[(arm, label)] = json.load(f)
    return cells


def metrics_sum(passes, name):
    total = None
    for p in passes:
        v = (p.get("counters_delta") or {}).get(name)
        if v is None:
            continue
        total = (total or 0) + v
    return total


def arm_level(cell):
    passes = cell.get("passes") or []
    aggs = [p["aggregate"] for p in passes]
    per_stream = [v for a in aggs for v in (a.get("per_stream_tps") or [])]

    def per_round(key_num, key_den):
        vals = []
        for a in aggs:
            if a.get(key_den):
                vals.append(a[key_num] / a[key_den])
        return median(vals)

    return {
        "passes": len(passes),
        "aggregate_tps": [a.get("aggregate_tps") for a in aggs],
        "aggregate_median": median([a.get("aggregate_tps") for a in aggs]),
        "aggregate_spread": (max([a["aggregate_tps"] for a in aggs]) / min([a["aggregate_tps"] for a in aggs]) - 1)
        if len(aggs) >= 2 and all(a.get("aggregate_tps") for a in aggs) and min(a["aggregate_tps"] for a in aggs) > 0 else None,
        "per_stream_median": median(per_stream),
        "per_stream_min": min(per_stream) if per_stream else None,
        "per_stream_max": max(per_stream) if per_stream else None,
        "ttft_median": median([a.get("ttft_median_s") for a in aggs]),
        "ttft_max": max([a.get("ttft_max_s") for a in aggs if a.get("ttft_max_s") is not None], default=None),
        "server_ttft_median": median([a.get("server_ttft_median_s") for a in aggs]),
        "prefill_median": median([a.get("prefill_median_s") for a in aggs]),
        "failed": sum(a.get("failed") or 0 for a in aggs),
        "incomplete": sum((a.get("streams") or 0) - (a.get("complete") or 0) for a in aggs),
        "speculative": {
            "rounds": sum((a.get("rounds") or 0) for a in aggs),
            "drafted": sum((a.get("drafted") or 0) for a in aggs),
            "accepted": sum((a.get("accepted") or 0) for a in aggs),
            "acceptance_rate": None,
            "replies": sum((a.get("speculative_replies") or 0) for a in aggs),
        },
        "metrics_delta": {k: metrics_sum(passes, k) for k in (
            "tensorfold:mtp_drafted_total", "tensorfold:mtp_accepted_total", "tensorfold:decode_rounds_total",
            "tensorfold:generation_tokens_total", "tensorfold:prompt_tokens_total",
            "tensorfold:prompt_tokens_cached_total")},
        "counter_inconsistent": any(
            a.get("accepted") is not None and a.get("drafted") is not None and a.get("accepted") > a.get("drafted")
            for a in aggs),
        "gpu_before": [p.get("gpu_before") for p in passes],
        "gpu_after": [p.get("gpu_after") for p in passes],
        "tokens_per_round": per_round("completion_tokens_total", "rounds"),
        "drafted_per_round": per_round("drafted", "rounds"),
        "accepted_per_round": per_round("accepted", "rounds"),
        "finish_reasons": sorted({fr for a in aggs for fr in (a.get("finish_reasons") or [])}),
        "completion_classes": sorted({c for a in aggs for c in (a.get("completion_classes") or [])}),
        "idle": idle_summary(cell),
    }


def ratio(a, b):
    if a is None or b in (None, 0):
        return None
    return a / b


def hashes(cells, arm, level, label):
    cell = cells.get((arm, label))
    if not cell:
        return None
    out = {}
    for p in cell.get("passes", []):
        for i, r in enumerate(p.get("replies") or []):
            out[(p["pass"], i)] = r
    return out


def compare_hashes(cells, arms, level, label=None):
    label = label or "c%d" % level
    a = hashes(cells, arms[0], level, label)
    b = hashes(cells, arms[1], level, label)
    if a is None or b is None:
        return {"status": "missing"}
    keys = sorted(set(a) & set(b))
    equal = unequal = missing = 0
    prompt_equal = prompt_unequal = 0
    prompt_mismatch = None
    first_div = None
    for k in keys:
        ra, rb = a[k], b[k]
        pa, pb = ra.get("prompt_tokens"), rb.get("prompt_tokens")
        if pa is not None and pa == pb:
            prompt_equal += 1
        elif pa is not None and pb is not None:
            prompt_unequal += 1
            if prompt_mismatch is None:
                prompt_mismatch = {"pass": k[0], "stream": k[1], "arm%s" % arms[0]: pa, "arm%s" % arms[1]: pb}
        ha, hb = ra.get("token_sha256"), rb.get("token_sha256")
        if not ha or not hb:
            missing += 1
            continue
        if ha == hb:
            equal += 1
            continue
        unequal += 1
        if first_div is None:
            ids_a, ids_b = ra.get("token_ids"), rb.get("token_ids")
            pos = None
            if isinstance(ids_a, list) and isinstance(ids_b, list):
                for j in range(min(len(ids_a), len(ids_b))):
                    if ids_a[j] != ids_b[j]:
                        pos = j
                        break
                if pos is None and len(ids_a) != len(ids_b):
                    pos = min(len(ids_a), len(ids_b))
            first_div = {"pass": k[0], "stream": k[1], "position": pos,
                         "arm%s" % arms[0]: ha, "arm%s" % arms[1]: hb,
                         "ids_arm%s" % arms[0]: (ids_a[:pos + 2] if pos is not None and isinstance(ids_a, list) else None),
                         "ids_arm%s" % arms[1]: (ids_b[:pos + 2] if pos is not None and isinstance(ids_b, list) else None)}
    return {"status": "compared", "equal": equal, "unequal": unequal, "missing": missing,
            "prompt_tokens_equal": prompt_equal, "prompt_tokens_unequal": prompt_unequal,
            "prompt_tokens_mismatch": prompt_mismatch,
            "first_divergence": first_div, "pairs": len(keys)}


def prompt_identity(cells, arms, level, label=None):
    label = label or "c%d" % level
    a = cells.get((arms[0], label))
    b = cells.get((arms[1], label))
    if not a or not b:
        return {"status": "missing"}
    pa = [[q.get("sha256") for q in p.get("prompts") or []] for p in a.get("passes") or []]
    pb = [[q.get("sha256") for q in p.get("prompts") or []] for p in b.get("passes") or []]
    return {"status": "identical" if pa == pb else "different", "passes": len(pa)}


def env_identity(root, arms, cell):
    out = {}
    for arm in arms:
        p = os.path.join(root, "arm%s" % arm, cell, "env-boot.txt")
        out[arm] = open(p, encoding="utf-8").read().splitlines() if os.path.exists(p) else None
    if out[arms[0]] is None or out[arms[1]] is None:
        return {"status": "missing"}
    sa, sb = set(out[arms[0]]), set(out[arms[1]])
    return {"status": "same" if sa == sb else "differs", "only_arm%s" % arms[0]: sorted(sa - sb),
            "only_arm%s" % arms[1]: sorted(sb - sa)}


def file_text(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read().strip()
    except OSError:
        return None


def cmd_identity(root, arms, cell):
    a = file_text(os.path.join(root, "arm%s" % arms[0], cell, "cmd-boot.json"))
    b = file_text(os.path.join(root, "arm%s" % arms[1], cell, "cmd-boot.json"))
    if a is None or b is None:
        return {"status": "missing"}
    return {"status": "same" if a == b else "differs", "cmd": a}


def compare_streams(cells, arms, label):
    a = cells.get((arms[0], label))
    b = cells.get((arms[1], label))
    if not a or not b:
        return {"status": "missing"}
    sa, sb = a.get("streams") or [], b.get("streams") or []
    equal = unequal = missing = prompts_equal = 0
    first = None
    for i in range(min(len(sa), len(sb))):
        ra, rb = sa[i], sb[i]
        if ra.get("prompt_sha256") and ra.get("prompt_sha256") == rb.get("prompt_sha256"):
            prompts_equal += 1
        ha, hb = ra.get("token_sha256"), rb.get("token_sha256")
        if not ha or not hb:
            missing += 1
            continue
        if ha == hb:
            equal += 1
            continue
        unequal += 1
        if first is None:
            ids_a, ids_b = ra.get("token_ids"), rb.get("token_ids")
            pos = None
            if isinstance(ids_a, list) and isinstance(ids_b, list):
                for j in range(min(len(ids_a), len(ids_b))):
                    if ids_a[j] != ids_b[j]:
                        pos = j
                        break
                if pos is None and len(ids_a) != len(ids_b):
                    pos = min(len(ids_a), len(ids_b))
            first = {"stream": i, "position": pos}
    return {"status": "compared", "equal": equal, "unequal": unequal, "missing": missing,
            "prompts_equal": prompts_equal, "pairs": min(len(sa), len(sb)), "first_divergence": first}


def idle_all(cells, arm):
    runs = {"1k": [], "8k": []}
    for (a, _label), cell in cells.items():
        if a != arm:
            continue
        for r in cell.get("idle") or []:
            if r.get("size") in runs:
                runs[r["size"]].append(r)
    out = {}
    for size, rs in runs.items():
        out[size] = {"ttft": [r.get("ttft_s") for r in rs],
                     "ttft_median": median([r.get("ttft_s") for r in rs]),
                     "server_ttft": [r.get("server_ttft_s") for r in rs],
                     "prompt_tokens": [r.get("prompt_tokens") for r in rs],
                     "cached_tokens": [r.get("cached_tokens") for r in rs],
                     "reps": len(rs),
                     "errors": [r.get("error") for r in rs if r.get("error")]}
    return out


def cached_cell(cell):
    if not cell:
        return None
    streams = cell.get("streams") or []
    agg = cell.get("aggregate") or {}
    return {
        "prime": [{"cached_tokens": cell.get("prime_a", {}).get("cached_tokens"),
                   "prompt_tokens": cell.get("prime_a", {}).get("prompt_tokens"),
                   "ttft": cell.get("prime_a", {}).get("ttft_s")},
                  {"cached_tokens": cell.get("prime_b", {}).get("cached_tokens"),
                   "prompt_tokens": cell.get("prime_b", {}).get("prompt_tokens"),
                   "ttft": cell.get("prime_b", {}).get("ttft_s")}],
        "streams": [{"prompt_tokens": r.get("prompt_tokens"), "cached_tokens": r.get("cached_tokens"),
                     "cache_state": r.get("cache_state"), "ttft": r.get("ttft_s"),
                     "server_ttft": r.get("server_ttft_s"), "decode_tps": r.get("decode_tps"),
                     "token_sha256": r.get("token_sha256"), "token_ids": r.get("token_ids"),
                     "speculative": r.get("speculative"), "complete": r.get("complete"),
                     "error": r.get("error")} for r in streams],
        "aggregate_tps": agg.get("aggregate_tps"),
        "metrics_cached_delta": (cell.get("counters_delta") or {}).get("tensorfold:prompt_tokens_cached_total"),
        "metrics_drafted_delta": (cell.get("counters_delta") or {}).get("tensorfold:mtp_drafted_total"),
        "metrics_accepted_delta": (cell.get("counters_delta") or {}).get("tensorfold:mtp_accepted_total"),
        "idle": idle_summary(cell),
    }


def idle_summary(cell):
    out = {}
    for size in ("1k", "8k"):
        runs = [r for r in (cell.get("idle") or []) if r.get("size") == size]
        out[size] = {"ttft": [r.get("ttft_s") for r in runs],
                     "ttft_median": median([r.get("ttft_s") for r in runs]),
                     "server_ttft": [r.get("server_ttft_s") for r in runs],
                     "prompt_tokens": [r.get("prompt_tokens") for r in runs],
                     "cached_tokens": [r.get("cached_tokens") for r in runs],
                     "errors": [r.get("error") for r in runs if r.get("error")]}
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--final", action="store_true")
    args = ap.parse_args()
    root = args.root
    arms = ("0", "1")
    cells = load(root)
    score = {"root": root, "final": args.final, "cells": sorted("%s/%s" % k for k in cells)}

    # label selection: a rerun replaces the level's first run when it exists
    def label_for(level):
        for arm in arms:
            if (arm, "c%d-run2" % level) in cells:
                return "c%d-run2" % level
        return "c%d" % level

    levels = {}
    rerun = []
    for level in LEVELS:
        label = label_for(level)
        entry = {"label": label, "arms": {}}
        for arm in arms:
            cell = cells.get((arm, label))
            entry["arms"][arm] = arm_level(cell) if cell else None
        entry["hash"] = compare_hashes(cells, arms, level, label)
        entry["prompts"] = prompt_identity(cells, arms, level, label)
        entry["env"] = env_identity(root, arms, label)
        entry["cmd"] = cmd_identity(root, arms, label)
        a0 = entry["arms"]["0"]
        a1 = entry["arms"]["1"]
        if a0 and a1:
            entry["ratio"] = {
                "aggregate": ratio(a1.get("aggregate_median"), a0.get("aggregate_median")),
                "per_stream": ratio(a1.get("per_stream_median"), a0.get("per_stream_median")),
                "ttft": ratio(a1.get("ttft_median"), a0.get("ttft_median")),
                "server_ttft": ratio(a1.get("server_ttft_median"), a0.get("server_ttft_median")),
                "drafted": ratio(a1["speculative"].get("drafted"), a0["speculative"].get("drafted")),
                "accepted": ratio(a1["speculative"].get("accepted"), a0["speculative"].get("accepted")),
                "rounds": ratio(a1["speculative"].get("rounds"), a0["speculative"].get("rounds")),
            }
            for k in ("drafted", "accepted"):
                d, r = a1["speculative"].get(k), a0["speculative"].get(k)
                if d:
                    entry["ratio"]["%s_share" % k] = r
            if level > 1 and a0.get("drafted_per_round") and a1.get("drafted_per_round"):
                lr = a1["drafted_per_round"] / a0["drafted_per_round"]
                entry["lever_signature"] = {"drafted_per_round_ratio": lr, "effect": abs(lr - 1.0) > 0.02}
        worst = max((e or 0) for e in ((a0 or {}).get("aggregate_spread"), (a1 or {}).get("aggregate_spread")))
        entry["spread_worst"] = worst
        if worst and worst > NOISE:
            if args.final:
                print("RERUN-OPEN both c%d %.3f" % (level, worst))
            else:
                rerun.append((level, worst))
                print("RERUN both c%d spread %.3f" % (level, worst))
        levels[str(level)] = entry

    cached = {}
    for arm in arms:
        cached[arm] = cached_cell(cells.get((arm, "cached")))
    cached["hashes"] = compare_streams(cells, arms, "cached")
    cached["env"] = env_identity(root, arms, "cached")
    for arm in arms:
        cached.setdefault("idle_all", {})[arm] = idle_all(cells, arm)

    score["levels"] = levels
    score["cached"] = cached
    ids = {}
    for path in glob.glob(os.path.join(root, "arm*", "*", "image-id-boot.txt")):
        ids[os.path.relpath(path, root)] = file_text(path)
    score["image_ids"] = ids
    score["image_unique"] = sorted({v for v in ids.values() if v})
    if args.final:
        score["rerun"] = [l for l, _ in rerun]
    with open(os.path.join(root, "score.json"), "w", encoding="utf-8") as f:
        json.dump(score, f, indent=1)

    eq = unequal = missing = 0
    for level, e in levels.items():
        h = e["hash"]
        if h.get("status") == "compared":
            eq += h["equal"]
            unequal += h["unequal"]
            missing += h["missing"]
    print("SCORE-SUMMARY levels %d hash_equal %d hash_unequal %d hash_missing %d cached_hash %s final %s"
          % (len(levels), eq, unequal, missing, (cached.get("hashes") or {}).get("status"), args.final))


if __name__ == "__main__":
    sys.exit(main())
