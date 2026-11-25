#!/usr/bin/env python3
"""Render <root>/score.json as <root>/tables.md - the concurrency table, the hash check, the idle TTFT case,
the cached two-stream cell, and the arm-environment identity."""
import argparse
import json
import os


def fmt(v, nd=2):
    if v is None:
        return "-"
    if isinstance(v, bool):
        return "yes" if v else "no"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        return f"{v:.{nd}f}"
    return str(v)


def pct(v):
    return (v - 1.0) * 100.0 if isinstance(v, (int, float)) else None


def table(headers, rows):
    out = ["| " + " | ".join(headers) + " |", "| " + " | ".join("---" for _ in headers) + " |"]
    for r in rows:
        out.append("| " + " | ".join(fmt(c) for c in r) + " |")
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    args = ap.parse_args()
    with open(os.path.join(args.root, "score.json"), encoding="utf-8") as f:
        s = json.load(f)
    lines = ["# Clean-main TF_FLASHNEXT_SHARED_DRAFTS window: TF_FLASHNEXT_SHARED_DRAFTS=1 against =0", "",
             "Arm 0: `TF_FLASHNEXT_SHARED_DRAFTS=0`; arm 1: `TF_FLASHNEXT_SHARED_DRAFTS=1` (engine default).",
             "Same image, checkpoint, launcher, serve flags, client and prompts; fresh server per cell.", ""]

    lines.append("## Decode by client concurrency (3 cold passes a cell, medians)")
    headers = ["C", "arm", "aggregate tok/s", "spread", "per-stream tok/s (median, min-max)", "TTFT s median",
               "TTFT s max", "server TTFT s", "prefill s", "idle 1k TTFT s", "idle 8k TTFT s", "tokens/round",
               "drafted/round", "accepted/round", "drafted", "accepted", "accept rate", "rounds",
               "metrics drafted", "metrics accepted", "failed"]
    rows = []
    for level in ("1", "2", "4", "8"):
        e = s["levels"].get(level) or {}
        for arm in ("0", "1"):
            a = (e.get("arms") or {}).get(arm)
            if not a:
                rows.append([level, arm] + ["-"] * (len(headers) - 2))
                continue
            sp = a.get("speculative") or {}
            md = a.get("metrics_delta") or {}
            idle = a.get("idle") or {}
            rows.append([level, arm, a.get("aggregate_median"), a.get("aggregate_spread"),
                         f'{fmt(a.get("per_stream_median"))} ({fmt(a.get("per_stream_min"))}-{fmt(a.get("per_stream_max"))})',
                         a.get("ttft_median"), a.get("ttft_max"), a.get("server_ttft_median"), a.get("prefill_median"),
                         ((idle.get("1k") or {}).get("ttft_median")), ((idle.get("8k") or {}).get("ttft_median")),
                         a.get("tokens_per_round"), a.get("drafted_per_round"), a.get("accepted_per_round"),
                         sp.get("drafted"), sp.get("accepted"),
                         (sp.get("accepted") / sp.get("drafted")) if (sp.get("drafted") or 0) else None,
                         sp.get("rounds"), md.get("tensorfold:mtp_drafted_total"),
                         md.get("tensorfold:mtp_accepted_total"), a.get("failed")])
    lines.append(table(headers, rows))
    lines.append("")

    lines.append("## Ratio arm 1 / arm 0, and the token-hash check")
    headers = ["C", "aggregate", "aggregate %", "per-stream", "per-stream %", "TTFT", "TTFT %", "server TTFT",
               "drafted", "accepted", "rounds", "hash equal", "hash unequal", "hash missing", "first divergence"]
    rows = []
    for level in ("1", "2", "4", "8"):
        e = s["levels"].get(level) or {}
        r = e.get("ratio") or {}
        h = e.get("hash") or {}
        fd = h.get("first_divergence")
        rows.append([level, r.get("aggregate"), pct(r.get("aggregate")), r.get("per_stream"),
                     pct(r.get("per_stream")), r.get("ttft"), pct(r.get("ttft")), r.get("server_ttft"),
                     r.get("drafted"), r.get("accepted"), r.get("rounds"), h.get("equal"), h.get("unequal"),
                     h.get("missing"),
                     (f"pass {fd['pass']} stream {fd['stream']} position {fd['position']}" if fd else "-")])
    lines.append(table(headers, rows))
    lines.append("")

    lines.append("## Idle TTFT (one stream, server idle, cold prompt, 2 reps a boot, every boot pooled)")
    headers = ["arm", "reps", "1k TTFT s median", "1k prompt tokens", "1k cached max", "8k TTFT s median",
               "8k prompt tokens", "8k cached max", "errors"]
    rows = []
    cached_cell = s.get("cached") or {}
    idle_all = cached_cell.get("idle_all") or {}
    for arm in ("0", "1"):
        idle = idle_all.get(arm) or {}
        i1 = idle.get("1k") or {}
        i8 = idle.get("8k") or {}
        rows.append([arm, i1.get("reps"), i1.get("ttft_median"), i1.get("prompt_tokens"),
                     max([c for c in (i1.get("cached_tokens") or []) if c is not None], default=None),
                     i8.get("ttft_median"), i8.get("prompt_tokens"),
                     max([c for c in (i8.get("cached_tokens") or []) if c is not None], default=None),
                     (i1.get("errors") or []) + (i8.get("errors") or [])])
    lines.append(table(headers, rows))
    lines.append("")

    lines.append("## Cached two-stream control (prime each prompt alone, then both streams together)")
    headers = ["arm", "two-stream cached tokens", "two-stream prompt tokens", "cache state", "TTFT s",
               "server TTFT s", "decode tok/s", "drafted", "accepted", "metrics cached delta"]
    rows = []
    for arm in ("0", "1"):
        c = cached_cell.get(arm)
        if not c:
            rows.append([arm] + ["-"] * (len(headers) - 1))
            continue
        st = c.get("streams") or []
        rows.append([arm, [x.get("cached_tokens") for x in st], [x.get("prompt_tokens") for x in st],
                     [x.get("cache_state") for x in st], [x.get("ttft") for x in st],
                     [x.get("server_ttft") for x in st], [x.get("decode_tps") for x in st],
                     c.get("metrics_drafted_delta"), c.get("metrics_accepted_delta"),
                     c.get("metrics_cached_delta")])
    lines.append(table(headers, rows))
    ch = (cached_cell.get("hashes") or {})
    lines.append("")
    lines.append(f"Cached-control token hashes across arms: {ch.get('status')} "
                 f"(equal {ch.get('equal')}, unequal {ch.get('unequal')}, missing {ch.get('missing')}; "
                 f"prompts equal {ch.get('prompts_equal')} of {ch.get('pairs')}).")
    fd = ch.get("first_divergence")
    if fd:
        lines.append(f"First cached-control divergence: stream {fd.get('stream')} position {fd.get('position')}.")
    lines.append("")

    lines.append("## Arm environment identity (the container's TF_/TENSORFOLD_ names, per cell)")
    for level in ("1", "2", "4", "8"):
        e = (s["levels"].get(level) or {}).get("env") or {}
        if e.get("status") and e.get("status") != "missing":
            only0 = e.get("only_arm0") or []
            only1 = e.get("only_arm1") or []
            lines.append(f"- c{level}: {e.get('status')}; only arm0 {only0}; only arm1 {only1}")
    ce = (cached_cell.get("env") or {})
    if ce:
        lines.append(f"- cached: {ce.get('status')}; only arm0 {ce.get('only_arm0')}; only arm1 {ce.get('only_arm1')}")
    for level in ("1", "2", "4", "8"):
        c = (s["levels"].get(level) or {}).get("cmd") or {}
        if c.get("status"):
            lines.append(f"- c{level} command: {c.get('status')} {c.get('cmd') or ''}")
    ids = s.get("image_ids") or {}
    lines.append(f"- image ids across the {len(ids)} captured cells: {s.get('image_unique')}")
    bad = [f"c{level} arm{arm}" for level in ("1", "2", "4", "8") for arm in ("0", "1")
           if (((s["levels"].get(level) or {}).get("arms") or {}).get(arm) or {}).get("counter_inconsistent")]
    lines.append(f"- speculative counters with accepted > drafted: {bad if bad else 'none'}")
    lines.append("")
    lines.append(f"Noise rule: a level whose three passes span more than 5 percent is re-booted once for both "
                 f"arms. Final rerun levels: {s.get('rerun')}")
    lines.append("")
    pt = []
    for level in ("1", "2", "4", "8"):
        h = (s["levels"].get(level) or {}).get("hash") or {}
        pt.append(f"c{level}: {h.get('prompt_tokens_equal')} equal / {h.get('prompt_tokens_unequal')} unequal")
    lines.append("Rendered prompt tokens (same prompt strings must render to the same count on both arms): "
                 + "; ".join(pt))
    sig = []
    for level in ("2", "4", "8"):
        ls = (s["levels"].get(level) or {}).get("lever_signature") or {}
        if ls:
            sig.append(f"c{level}: drafted/round arm1/arm0 {fmt(ls.get('drafted_per_round_ratio'), 3)}, "
                       f"lever reached the path: {fmt(ls.get('effect'))}")
    lines.append("Lever signature (a shared round must draft fewer tokens a round on arm 1; c1 has no shared "
                 "round, so it is the null control): " + ("; ".join(sig) if sig else "not measured"))
    print("\n".join(lines))


if __name__ == "__main__":
    main()
