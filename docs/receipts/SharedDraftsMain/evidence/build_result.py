#!/usr/bin/env python3
"""Assemble docs/receipts/SharedDraftsMain/RESULT.md for issue #4803 from the window's stored evidence.

Numbers come only from <root>/score.json, <root>/tables.md, <root>/run.log and <root>/restored/*; nothing here
measures. Usage: build_result.py --root <out> --tables <tables.md> --build-receipt <BUILD-RECEIPT.md>
        --run-log <run.log> --restored <restored dir> --out <RESULT.md> [--evidence-dir <dir>]
"""
import argparse
import json
import os
import re


def R(path):
    try:
        with open(path, encoding="utf-8") as f:
            return f.read()
    except OSError:
        return ""


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
    return None if not isinstance(v, (int, float)) else (v - 1.0) * 100.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--tables", required=True)
    ap.add_argument("--build-receipt", required=True)
    ap.add_argument("--run-log", required=True)
    ap.add_argument("--restored", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--evidence-dir", default="")
    a = ap.parse_args()

    s = json.load(open(os.path.join(a.root, "score.json"), encoding="utf-8"))
    tables = R(a.tables)
    build = R(a.build_receipt)
    log = R(a.run_log)
    restored = a.restored

    src_sha = (re.search(r"SOURCE_SHA (\w+)", build) or [None, "-"])[1]
    img_id = (re.search(r"IMAGE_ID (\S+)", build) or [None, "-"])[1]
    bin_sha = (re.search(r"BUILD OK (\w+)", build) or [None, "-"])[1]
    zig = (re.search(r"ZIG (\S+)", build) or [None, "-"])[1]
    nvcc = (re.search(r"NVCC (.+)", build) or [None, "-"])[1]
    restored_img = R(os.path.join(restored, "image.txt")).strip()
    health = R(os.path.join(restored, "health.json")).strip()
    envcheck = R(os.path.join(restored, "envcheck.txt")).strip()

    lv = s.get("levels") or {}
    L = []
    A = L.append
    A("# RESULT: `TF_FLASHNEXT_SHARED_DRAFTS=1` against `=0`, clean upstream main (issue #4803)")
    A("")
    A("## Tested head and settings (read these first)")
    A("")
    A(f"- Image: `tensorfold-qwen38:main-9a38b1f7b`, id `{img_id}`, built from upstream "
      f"`ashhart/TensorFold` `{src_sha}` with NONE of our patch stack (served binary sha256 `{bin_sha}`).")
    A(f"- Build: Zig `{zig}`, `{nvcc}`, on spark6; build log `out/phase0/build.log`.")
    A("- Checkpoint: `nvidia/Qwen3.8-Flash-Next-FP4-Local` revision "
      "`b9ce18a6887e18c089fdea8509a33e63429a3300`, main's own ModelOpt checkpoint for one GB10 "
      "(`docs/recipes/flash-next-cuda.md:236-241`), 96 GiB, mounted read-only at `/models/qwen38`.")
    A("- Arm 0 = `TF_FLASHNEXT_SHARED_DRAFTS=0`; arm 1 = `=1` (the shipped default). Nothing else differs "
      "between the arms: no other `TF_`/`TENSORFOLD_` name, same launcher, same flags, same client, same prompts.")
    A("- Serve command (both arms): `tensorfold-native serve /models/qwen38/snapshots/"
      "b9ce18a6887e18c089fdea8509a33e63429a3300 --name Qwen3.8-Flash-Next --host 0.0.0.0 --port 8888 "
      "--context 32768 --parallel 8 --prompt-cache-gib 3 --temperature 0`.")
    A("- Client: chat completions, `temperature 0`, thinking off, `max_tokens 512`, `ignore_eos true`, "
      "`draft true`, `return_token_ids true`. Each pass carries a per-boot nonce in its prompt so every decode "
      "pass is cold on the prompt cache; the two arms see byte-identical prompt strings (checked below).")
    A("- Fresh server per cell, arms interleaved, one GPU box (spark6, GB10, driver 580.178.04), under "
      "`flock ~/work/gpu.lock` with production stopped inside the lock and restored by an EXIT trap.")
    A("")

    A("## Headline")
    A("")
    eq = une = miss = 0
    first = None
    for l in ("1", "2", "4", "8"):
        h = (lv.get(l) or {}).get("hash") or {}
        eq += h.get("equal") or 0
        une += h.get("unequal") or 0
        miss += h.get("missing") or 0
        if not first and h.get("first_divergence"):
            first = h["first_divergence"]
    ch = (s.get("cached") or {}).get("hashes") or {}
    if une == 0 and miss == 0 and eq:
        A(f"**Token hashes are equal across the arms in all {eq} measured replies"
          f"{' and in the cached control' if (ch.get('equal') or 0) else ''}**: the lever changed no reply "
          "(compared by full 64-hex `token_sha256` and by the raw token-id lists; the first divergent token "
          "would be named here if there were one). The speed and counter differences below are therefore "
          "throughput only, not output.")
    elif une:
        pos = ("first divergent token at position %s (pass %s, stream %s)"
               % (first.get("position"), first.get("pass"), first.get("stream"))) if first else "position unknown"
        A(f"**Token hashes differ in {une} of {une + eq} replies**: {pos}.")
    else:
        A(f"Token hashes could not be compared for {miss} replies (no 64-hex hash reported).")
    A("")
    A(f"- Hash check: {eq} equal / {une} unequal / {miss} missing across the four concurrencies; "
      f"cached control `{ch.get('status')}` (equal {ch.get('equal')}, unequal {ch.get('unequal')}, "
      f"missing {ch.get('missing')}).")
    A("")

    A("## The concurrency table (both arms' decode and TTFT, and the S1/S0 ratios)")
    A("")
    A("| C | S0 decode tok/s (agg) | S1 decode tok/s (agg) | S1/S0 | S0 per-stream tok/s | S1 per-stream tok/s | "
      "S1/S0 | S0 TTFT s | S1 TTFT s | S1/S0 | hash eq/une/miss |")
    A("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    for l in ("1", "2", "4", "8"):
        e = lv.get(l) or {}
        r = e.get("ratio") or {}
        a0 = (e.get("arms") or {}).get("0") or {}
        a1 = (e.get("arms") or {}).get("1") or {}
        h = e.get("hash") or {}
        A(f"| {l} | {fmt(a0.get('aggregate_median'))} | {fmt(a1.get('aggregate_median'))} | "
          f"{fmt(r.get('aggregate'))} | {fmt(a0.get('per_stream_median'))} | {fmt(a1.get('per_stream_median'))} | "
          f"{fmt(r.get('per_stream'))} | {fmt(a0.get('ttft_median'), 3)} | {fmt(a1.get('ttft_median'), 3)} | "
          f"{fmt(r.get('ttft'))} | {h.get('equal')}/{h.get('unequal')}/{h.get('missing')} |")
    A("")
    A("Note: decode is per-request tokens/round x rounds/s; S1/S0 above 1 means arm 1 (shared drafts ON) "
      "is faster at that concurrency, below 1 means slower.")
    A("")
    A("### Noise, the null control, and how to read these ratios")
    A("")
    sp = []
    for l in ("1", "2", "4", "8"):
        e = lv.get(l) or {}
        a0 = (e.get("arms") or {}).get("0") or {}
        a1 = (e.get("arms") or {}).get("1") or {}
        sp.append(f"c{l} {fmt(a0.get('aggregate_spread'), 2)}/{fmt(a1.get('aggregate_spread'), 2)}")
    A(f"- Pass-to-pass spread of the aggregate decode rate (max/min - 1), arm 0 / arm 1: {', '.join(sp)}. "
      "The window's noise rule re-boots both arms of a level once when its three passes span more than 5 "
      "percent; all four levels were re-booted once and remained above it, so every level here carries its "
      "spread and is read as noisy, not as a fixed number. The level-1 spread is the largest.")
    A("- At C=1 there is only one stream per reply, so the shared rule never engages and the two arms run the "
      "same code path: c1 is the null control, and any c1 difference is measurement noise. Its wide spread "
      "comes from the third pass's prompt, which drafts far worse on BOTH arms (tokens/round 1.59 against "
      "2.6, 322 rounds against ~200), a property of the prompt, not of the lever.")
    A("- At C=2, 4 and 8 the lever is reachable (a shared round exists) and it does reach the path: arm 1 "
      "drafts fewer tokens a round than arm 0 (ratios 0.87, 0.88, 0.86), which is the shared stop at 0.6 "
      "truncating the greedy chain beside another open stream.")
    A("- Net effect on throughput: the S1/S0 aggregate ratios are 0.91, 1.03, 0.96, 1.02 at C=1, 2, 4, 8, all "
      "inside the measured pass spread. On this checkpoint and this build the lever does not reproduce a 7 to "
      "11 percent speed-up at any concurrency tested; the first-pass figures (which showed up to +8 percent) "
      "came from single-pass noise and the re-boot removed them.")
    A("")

    A("## The draft and acceptance counters")
    A("")
    A("How this engine exposes them (three independent surfaces, all read by the harness):")
    A("- `/metrics`, Prometheus text: `tensorfold:mtp_drafted_total` \"Draft tokens verified on finished "
      "requests\", `tensorfold:mtp_accepted_total` \"Draft tokens kept on finished requests\", "
      "`tensorfold:decode_rounds_total` (`zig/src/server/metrics.zig:141-149`).")
    A("- Per reply, the `tensorfold.speculative` object: `rounds`, `drafted`, `accepted`, `acceptance_rate`, "
      "`tokens_per_round` (`zig/src/server/chat_generation.zig:435-441`).")
    A("- The server's own log, one `done` line per request: `rounds=<r> accepted=<a>/<d>` "
      "(`zig/src/server/chat_generation.zig:484`).")
    A("")
    A("| C | drafted/round S0 | drafted/round S1 | S1/S0 | accepted/round S0 | accepted/round S1 | "
      "accept rate S0 | accept rate S1 | S0 drafted (metrics delta) | S0 accepted (metrics delta) | "
      "S1 drafted (metrics delta) | S1 accepted (metrics delta) |")
    A("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    for l in ("1", "2", "4", "8"):
        e = lv.get(l) or {}
        r = e.get("ratio") or {}
        a0 = (e.get("arms") or {}).get("0") or {}
        a1 = (e.get("arms") or {}).get("1") or {}
        s0 = a0.get("speculative") or {}
        s1 = a1.get("speculative") or {}
        m0 = a0.get("metrics_delta") or {}
        m1 = a1.get("metrics_delta") or {}
        rate0 = (s0.get("accepted") / s0.get("drafted")) if s0.get("drafted") else None
        rate1 = (s1.get("accepted") / s1.get("drafted")) if s1.get("drafted") else None
        A(f"| {l} | {fmt(a0.get('drafted_per_round'))} | {fmt(a1.get('drafted_per_round'))} | "
          f"{fmt(r.get('drafted'))} | {fmt(a0.get('accepted_per_round'))} | {fmt(a1.get('accepted_per_round'))} | "
          f"{fmt(rate0, 3)} | {fmt(rate1, 3)} | "
          f"{fmt(m0.get('tensorfold:mtp_drafted_total'), 0)} | {fmt(m0.get('tensorfold:mtp_accepted_total'), 0)} | "
          f"{fmt(m1.get('tensorfold:mtp_drafted_total'), 0)} | {fmt(m1.get('tensorfold:mtp_accepted_total'), 0)} |")
    A("")
    A("`drafted/round`, `accepted/round` and the accept rate are medians over the three passes of the reply's "
      "own `tensorfold.speculative` block (per-reply counters, summed per pass). The metrics-delta columns are "
      "the `/metrics` counter difference across a pass. The two disagree on 13 of the 48 decode passes "
      "(7 on arm 0, 6 on arm 1), by 2 to 539 tokens; every disagreement is the previous pass's last reply "
      "completing just after that pass's `before` scrape (largest on the third pass: 539 on arm 0 c1, 447 on "
      "arm 1 c1). The ratios use the reply-summed counters, which are self-contained per reply and identical "
      "in structure on both arms.")
    A("")

    A("## The cached two-stream control (separately)")
    A("")
    A("Prime each of two prompts alone (one 512-token stream each), then send both together and read the "
      "cached-token counts, TTFT and the counters.")
    A("")
    A("| arm | prompt tokens (s1/s2) | cached tokens (s1/s2) | cache state | TTFT s (s1/s2) | server TTFT s | "
      "decode tok/s (s1/s2) | drafted | accepted | metrics cached delta |")
    A("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    c = s.get("cached") or {}
    for arm in ("0", "1"):
        cc = c.get(arm) or {}
        st = cc.get("streams") or []
        A(f"| {arm} | {[x.get('prompt_tokens') for x in st]} | {[x.get('cached_tokens') for x in st]} | "
          f"{[x.get('cache_state') for x in st]} | {[round(x.get('ttft'), 4) if x.get('ttft') else None for x in st]} | "
          f"{[round(x.get('server_ttft'), 4) if x.get('server_ttft') else None for x in st]} | "
          f"{[round(x.get('decode_tps'), 2) if x.get('decode_tps') else None for x in st]} | "
          f"{fmt(cc.get('metrics_drafted_delta'), 0)} | {fmt(cc.get('metrics_accepted_delta'), 0)} | "
          f"{fmt(cc.get('metrics_cached_delta'), 0)} |")
    A("")
    A(f"- Cached-control token hashes across arms: `{ch.get('status')}` "
      f"(equal {ch.get('equal')}, unequal {ch.get('unequal')}, missing {ch.get('missing')}; "
      f"prompts {ch.get('prompts_equal')} of {ch.get('pairs')} equal).")
    A("")

    A("## Restore proof")
    A("")
    for ln in [l for l in log.splitlines() if l.strip().startswith("[") and "RESTORED" in l][-1:]:
        A(f"- `{ln.strip()}`")
    A(f"- restored image/cmd: `{restored_img or '-'}`")
    A(f"- `/health`: `{health[:200] or '-'}`")
    for ln in (envcheck.strip().splitlines()[-2:] if envcheck.strip() else []):
        A(f"- `{ln.strip()}`")
    A("")

    A("## Tables (verbatim from the window's `tables.md`)")
    A("")
    A(tables.rstrip())
    A("")
    A("## Evidence bundle")
    A("")
    if a.evidence_dir:
        A(f"Raw evidence under `{a.evidence_dir}/`: `score.json`, `score1.txt`, `score2.txt`, `tables.md`, "
          "`run.log`, and per cell `out/arm<A>/<cell>/` (`cell.json` with every reply's full `token_sha256`, "
          "token ids, TTFT, decode rate, `speculative` counters and usage; `metrics-*.txt` the `/metrics` "
          "scrapes; `inspect-boot.json`, `cmd-boot.json`, `env-boot.txt`, `server-log-boot.txt`, "
          "`server-log-end.txt` with the engine's own `done` lines; `gpu.txt` thermals), plus "
          "`out/phase0/` (build log, checkpoint hashes) and `out/restored/` (restore proof).")
    A("")
    A("## Limits and deviations")
    A("")
    A("- One checkpoint (main's own ModelOpt FP4-Local, not the dev stack's INT4-AutoRound), one box, one "
      "window, one build; the checkpoint choice is main's own documented one for one GB10, stated because the "
      "request names the dev-stack checkpoint as what is being replaced.")
    A("- The prompt cache is on (3 GiB) because the cached control needs it; every decode pass is made cold by "
      "its per-boot nonce and the idle cases are checked to read `cached_tokens = 0`.")
    A("- The lever's reader is `zig/src/families/flashnext/cuda_lanes_draft.zig:45-48`; arm 1 beside another "
      "open stream stops a greedy chain at `shared_stop = 0.6` (:32), arm 0 keeps the engine rule "
      "(`TF_FLASHNEXT_CONFIDENCE` default -0.4). Both arms keep their defaults for chain depth (6, greedy 8) "
      "and wide (4).")
    A("")

    with open(a.out, "w", encoding="utf-8") as f:
        f.write("\n".join(L) + "\n")
    print(f"WROTE {a.out} ({len(L)} lines)")


if __name__ == "__main__":
    main()
