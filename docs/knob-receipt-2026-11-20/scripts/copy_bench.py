"""copy_bench.py URL MODEL --text FILE [--tokens 256] [--reps 3] [--label] [--output]

The copy cells of a copy-window receipt: the same text sent twice per rep, once with the instruction to repeat it
verbatim and once with the instruction to repeat it with exactly one word changed, one stream, greedy, drafts on.

Per rep it records the reply's speed (client-measured decode tok/s, (tokens - 1) / span), its token ids from the
server's runtime block and their SHA-256, the first character at which the reply leaves the text, the server's own
MTP counters for that request (rounds, drafted, accepted, tokens a round) and the /metrics deltas around the case,
so "the copy was actually copied" and "the window was actually wider" are both checkable from the file rather than
assumed. A case that fails to stream to [DONE] is recorded with its error and excluded from the medians.
"""

import argparse
import hashlib
import json
import re
import statistics
import sys
import time
import urllib.request

from bench_stream import Collector

CASES = {
    "verbatim": "Repeat the text below exactly as it is written, from its first character, and nothing else: no"
                " introduction, no commentary, no code fence.\n\n",
    "changed": "Repeat the text below from its first character, changing exactly one word, and nothing else: no"
               " introduction, no commentary, no code fence.\n\n",
}
METRIC = ("mtp_drafted_total", "mtp_accepted_total")


def metrics(base):
    try:
        with urllib.request.urlopen(base + "/metrics", timeout=5) as resp:
            text = resp.read().decode("utf-8", "replace")
    except Exception:  # noqa: BLE001 - a metrics read that fails is reported as absent
        return {}
    out = {}
    for line in text.splitlines():
        if line.startswith("#"):
            continue
        name = line.split(" ", 1)[0].rsplit("{", 1)[0]
        if not re.fullmatch(r"[a-z_:]*mtp_(drafted|accepted)_total", name):
            continue
        key = "drafted" if "drafted" in name else "accepted"
        try:
            out[key] = out.get(key, 0) + int(float(line.rsplit(" ", 1)[1]))
        except (IndexError, ValueError):
            continue
    return out


def first_difference(reply, text):
    """The first character index at which the reply leaves the text, or None while it stays inside it."""
    for i, (a, b) in enumerate(zip(reply, text)):
        if a != b:
            return i
    return None if len(reply) <= len(text) else len(text)


def ask(base, model, prompt, tokens, warm=False):
    body = {"model": model, "max_tokens": tokens, "temperature": 0, "seed": 1234, "stream": True,
            "stream_options": {"include_usage": True}, "ignore_eos": True, "return_token_ids": True,
            "messages": [{"role": "user", "content": prompt}],
            "chat_template_kwargs": {"enable_thinking": False}}
    req = urllib.request.Request(base + "/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    sent = time.perf_counter()
    reply = Collector(sent)
    try:
        with urllib.request.urlopen(req, timeout=1800) as resp:
            reply.read(resp)
    except Exception as exc:  # noqa: BLE001 - a failed request is recorded, not fatal
        return {"error": f"{type(exc).__name__}: {exc}", "complete": False}
    if reply.end == "error":
        return {"error": "server_stream_error", "complete": False}
    complete = reply.end == "done"
    pieces = reply.pieces
    observed = reply.evidence.finish(reply.usage, reply.runtime, complete)
    n = observed["tokens"]
    out = {"complete": complete, **observed}
    if pieces:
        first, last = pieces[0][0], pieces[-1][0]
        out["ttft_s"] = round(first - sent, 3)
        out["decode_s"] = round(last - first, 3)
        out["decode_tps"] = round((n - 1) / (last - first), 1) if complete and n and n > 1 and last > first else None
    else:
        out["ttft_s"] = out["decode_s"] = out["decode_tps"] = None
        out["unmeasured"] = True
    ids = (reply.runtime or {}).get("token_ids")
    if isinstance(ids, list) and all(type(x) is int for x in ids):
        out["token_ids"] = ids
        out["token_ids_sha256"] = hashlib.sha256(json.dumps(ids).encode()).hexdigest()
        out["ids_checked"] = out["token_ids_sha256"] == (out.get("token_sha256") or "")
    spec = reply.speculative or {}
    out["rounds"] = spec.get("rounds")
    out["drafted"] = spec.get("drafted")
    out["accepted"] = spec.get("accepted")
    out["tokens_per_round"] = round(spec.get("tokens_per_round"), 3) if isinstance(spec.get("tokens_per_round"), (int, float)) else None
    out["text"] = "".join(reply.text)
    if warm:
        out["warm"] = True
    return out


def main():
    p = argparse.ArgumentParser()
    p.add_argument("base")
    p.add_argument("model")
    p.add_argument("--text", required=True)
    p.add_argument("--tokens", type=int, default=256)
    p.add_argument("--reps", type=int, default=3)
    p.add_argument("--label", default="")
    p.add_argument("--output")
    args = p.parse_args()
    base = args.base.rstrip("/")
    text = open(args.text, encoding="utf-8").read()
    report = {"label": args.label, "tokens": args.tokens, "text_chars": len(text),
              "text_sha256": hashlib.sha256(text.encode()).hexdigest(), "cases": []}
    for case, instruction in CASES.items():
        prompt = instruction + text
        before = metrics(base)
        ask(base, args.model, prompt, 16, warm=True)  # warm-up: the prompt's state is built once
        reps = []
        for _ in range(args.reps):
            rep = ask(base, args.model, prompt, args.tokens)
            if rep.get("complete"):
                rep["first_diff"] = first_difference(rep.get("text") or "", text)
                rep["prefix_chars"] = (rep["first_diff"] if rep["first_diff"] is not None
                                       else min(len(rep.get("text") or ""), len(text)))
                rep["reply_chars"] = len(rep.get("text") or "")
                rep["starts_with_text"] = bool(rep.get("text")) and text.startswith(rep["text"][:40])
            reps.append(rep)
            shown = {k: rep.get(k) for k in ("complete", "decode_tps", "tokens", "tokens_per_round", "rounds",
                                             "accepted", "drafted", "cached_tokens", "first_diff", "token_sha256",
                                             "ids_checked", "error")}
            print(json.dumps({case: shown}), flush=True)
        after = metrics(base)
        tps = [r["decode_tps"] for r in reps if isinstance(r.get("decode_tps"), (int, float))]
        rounds = [r["tokens_per_round"] for r in reps if isinstance(r.get("tokens_per_round"), (int, float))]
        report["cases"].append({
            "case": case, "instruction_chars": len(instruction), "reps": reps,
            "decode_tps_median": round(statistics.median(tps), 1) if tps else None,
            "tokens_per_round_median": round(statistics.median(rounds), 3) if rounds else None,
            "tokens_per_round_max": max(rounds) if rounds else None,
            "prompt_tokens": next((r.get("prompt_tokens") for r in reps if r.get("prompt_tokens")), None),
            "cached_tokens": [r.get("cached_tokens") for r in reps],
            "copied": sum(1 for r in reps if r.get("starts_with_text")),
            "first_diffs": [r.get("first_diff") for r in reps],
            "metrics_before": before, "metrics_after": after,
            "server_drafted": (after.get("drafted", 0) - before.get("drafted", 0)) if before and after else None,
            "server_accepted": (after.get("accepted", 0) - before.get("accepted", 0)) if before and after else None,
        })
    if args.output:
        with open(args.output, "w", encoding="utf-8") as f:
            json.dump(report, f, indent=1)
    # a reply that leaves the text is data, not a failed probe: only a case with no complete rep fails the invocation
    return 0 if all(any(r.get("complete") for r in c["reps"]) for c in report["cases"]) else 1


if __name__ == "__main__":
    sys.exit(main())
