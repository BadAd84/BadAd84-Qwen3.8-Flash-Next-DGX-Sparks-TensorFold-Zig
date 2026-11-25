#!/usr/bin/env python3
"""Assemble RESULT.md for the clean-main SHARED_DRAFTS window from the stored evidence.

Reads <root>/score.json, <root>/tables.md, <root>/run.log and <root>/restored/envcheck.txt, and the build
receipt passed with --build-receipt, then writes --out. Numbers come from score.json; nothing here measures.
"""
import argparse
import json
import os
import re

LEVELS = ("1", "2", "4", "8")


def fmt(v, nd=2, pct=False):
    if v is None:
        return "-"
    if isinstance(v, bool):
        return "yes" if v else "no"
    if isinstance(v, (int, float)):
        s = f"{v:.{nd}f}"
        return (s + " %") if pct else s
    return str(v)


def read(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


def marker(text, name, n=3):
    hits = [ln for ln in text.splitlines() if name in ln]
    return hits[-n:] if hits else []


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--build-receipt", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    root = args.root
    score = json.load(open(os.path.join(root, "score.json"), encoding="utf-8"))
    log = read(os.path.join(root, "run.log"))
    envcheck = read(os.path.join(root, "restored", "envcheck.txt"))
    tables = read(os.path.join(root, "tables.md"))
    image = read(os.path.join(root, "restored", "image.txt")).strip()
    health = read(os.path.join(root, "restored", "health.json")).strip()
    build = read(args.build_receipt)

    m = re.search(r"IMAGE_ID (\S+).*?SIZE (\d+)", build)
    image_id = m.group(1) if m else "-"
    m = re.search(r"BUILD OK (\w+)", build)
    binary_sha = m.group(1) if m else "-"
    m = re.search(r"SOURCE_SHA (\w+)", build)
    source_sha = m.group(1) if m else "-"

    lv = score["levels"]
    rows = []
    for level in LEVELS:
        e = lv.get(level) or {}
        r = e.get("ratio") or {}
        h = e.get("hash") or {}
        rows.append(f"| {level} | {fmt((e.get('arms') or {}).get('0', {}).get('aggregate_median'))} | "
                    f"{fmt((e.get('arms') or {}).get('1', {}).get('aggregate_median'))} | "
                    f"{fmt(r.get('aggregate'))} ({fmt((r.get('aggregate') or 0) * 100 - 100 if r.get('aggregate') else None)}%) | "
                    f"{fmt((e.get('arms') or {}).get('0', {}).get('ttft_median'), 3)} | "
                    f"{fmt((e.get('arms') or {}).get('1', {}).get('ttft_median'), 3)} | "
                    f"{h.get('equal')}/{h.get('unequal')}/{h.get('missing')} |")
    cached = score.get("cached") or {}
    ch = cached.get("hashes") or {}
    eq = sum((lv.get(l) or {}).get("hash", {}).get("equal") or 0 for l in LEVELS)
    neq = sum((lv.get(l) or {}).get("hash", {}).get("unequal") or 0 for l in LEVELS)
    miss = sum((lv.get(l) or {}).get("hash", {}).get("missing") or 0 for l in LEVELS)
    first = next(((lv.get(l) or {}).get("hash", {}).get("first_divergence") for l in LEVELS
                  if (lv.get(l) or {}).get("hash", {}).get("first_divergence")), None)

    lines = []
    lines.append("# RESULT: TF_FLASHNEXT_SHARED_DRAFTS=1 against =0 on a clean upstream main (issue #4803)")
    lines.append("")
    lines.append(f"Image `tensorfold-qwen38:main-9a38b1f7b` ({image_id}), built from `ashhart/TensorFold` "
                 f"`{source_sha}` with no OTS patch stack (binary sha256 `{binary_sha}`). Checkpoint "
                 "`nvidia/Qwen3.8-Flash-Next-FP4-Local` at `b9ce18a6887e18c089fdea8509a33e63429a3300`, main's "
                 "own ModelOpt checkpoint for one GB10. Arm 0 `TF_FLASHNEXT_SHARED_DRAFTS=0`, arm 1 `=1`; "
                 "everything else equal and captured per boot.")
    lines.append("")
    lines.append("## Headline")
    lines.append("")
    if neq == 0 and miss == 0 and eq:
        lines.append(f"Token hashes are equal across the arms in all {eq} measured replies"
                     f"{' and in the cached control' if (ch.get('equal') or 0) else ''}: the lever changed no "
                     "reply. The speed and counter differences are in the tables below.")
    elif neq:
        pos = "position unknown (no token ids in the reply)" if not first or first.get("position") is None \
            else f"first divergent token at position {first.get('position')} of pass {first.get('pass')}, " \
                 f"stream {first.get('stream')}"
        lines.append(f"Token hashes DIFFER in {neq} of {neq + eq} replies; {pos}.")
    else:
        lines.append(f"Token hashes could not be compared for {miss} replies (no 64-hex hash reported).")
    lines.append("")
    lines.append("| C | arm0 aggregate tok/s | arm1 aggregate tok/s | arm1/arm0 | TTFT arm0 s | TTFT arm1 s | "
                 "hash equal/unequal/missing |")
    lines.append("| --- | --- | --- | --- | --- | --- | --- |")
    lines.extend(rows)
    lines.append("")
    lines.append("## Draft and acceptance counters (per decode round, medians of the three passes)")
    lines.append("")
    lines.append("| C | drafted/round a0 | drafted/round a1 | accepted/round a0 | accepted/round a1 | "
                 "accept rate a0 | accept rate a1 | tokens/round a0 | tokens/round a1 |")
    lines.append("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    for level in LEVELS:
        e = lv.get(level) or {}
        a0 = (e.get("arms") or {}).get("0") or {}
        a1 = (e.get("arms") or {}).get("1") or {}

        def rate(a):
            s = a.get("speculative") or {}
            return (s.get("accepted") / s.get("drafted")) if (s.get("drafted") or 0) else None

        lines.append(f"| {level} | {fmt(a0.get('drafted_per_round'))} | {fmt(a1.get('drafted_per_round'))} | "
                     f"{fmt(a0.get('accepted_per_round'))} | {fmt(a1.get('accepted_per_round'))} | "
                     f"{fmt(rate(a0), 3)} | {fmt(rate(a1), 3)} | {fmt(a0.get('tokens_per_round'))} | "
                     f"{fmt(a1.get('tokens_per_round'))} |")
    lines.append("")
    lines.append("## Cached two-stream control")
    lines.append("")
    lines.append("| arm | prompt tokens (stream 1 / stream 2) | cached tokens (stream 1 / stream 2) | TTFT s | "
                 "decode tok/s (stream 1 / stream 2) | drafted | accepted |")
    lines.append("| --- | --- | --- | --- | --- | --- | --- |")
    for arm in ("0", "1"):
        c = cached.get(arm) or {}
        st = c.get("streams") or []
        lines.append(f"| {arm} | {[x.get('prompt_tokens') for x in st]} | {[x.get('cached_tokens') for x in st]} | "
                     f"{[x.get('ttft') for x in st]} | {[x.get('decode_tps') for x in st]} | "
                     f"{c.get('metrics_drafted_delta')} | {c.get('metrics_accepted_delta')} |")
    lines.append("")
    lines.append(f"Cached-control token hashes across the arms: {ch.get('status')} (equal {ch.get('equal')}, "
                 f"unequal {ch.get('unequal')}, missing {ch.get('missing')}; prompts equal "
                 f"{ch.get('prompts_equal')} of {ch.get('pairs')}).")
    lines.append("")
    lines.append("## Restore proof")
    lines.append("")
    for ln in marker(log, "RESTORED", 1):
        lines.append(f"- `{ln.strip()}`")
    lines.append(f"- restored image: `{image or '-'}`")
    lines.append(f"- `/health` body: `{health[:120] or '-'}`")
    for ln in (envcheck.strip().splitlines()[-2:] if envcheck.strip() else []):
        lines.append(f"- `{ln.strip()}`")
    lines.append("")
    lines.append("## Evidence bundle")
    lines.append("")
    lines.append("Per cell: `out/arm<A>/<cell>/cell.json` (every reply's `token_sha256`, token ids, TTFT, "
                 "decode rate, `speculative` counters, usage), `metrics-*.txt` (the `/metrics` scrapes the "
                 "counter deltas come from), `inspect-boot.json`, `cmd-boot.json`, `env-boot.txt`, "
                 "`server-log-boot.txt` and `server-log-end.txt` (the engine's own `done ... rounds= accepted=/drafted=` "
                 "lines), `gpu.txt` (thermals). The whole `out/` tree is in `out-bundle.tgz`.")
    lines.append("")
    lines.append("## Tables (verbatim from tables.md)")
    lines.append("")
    lines.append(tables.strip())
    lines.append("")
    with open(args.out, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    print(f"WROTE {args.out} ({len(lines)} lines)")


if __name__ == "__main__":
    main()
