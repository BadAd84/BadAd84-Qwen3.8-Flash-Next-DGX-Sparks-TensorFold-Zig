#!/usr/bin/env python3
"""draft_accounting.py PORT N --rounds 3 --max-tokens 400 --tag X --out rows.jsonl

The spec-decoding record Mia's harness keeps and ours did not: per round, the draft counters' deltas and the
ratios built from them. TensorFold's server exposes them on /metrics as counters over finished requests
(mtp_drafted_total, mtp_accepted_total, decode_rounds_total), so a before/after pair around a round is that
round's own numbers.

Each round sends N greedy streams at once (thinking off, temperature 0, include_usage) and records:
tokens, draft_rounds, drafted, accepted, acceptance (accepted/drafted), ms_per_round, tok_per_round, plus the
usual per-stream decode tok/s, TTFT and reply sha. A serve without the counters yields nulls, never zeros.

Usage: draft_accounting.py 8300 4 --rounds 3 --kind prose --tag zig-P4 --out ~/bench/draft-P4.jsonl
This file is self-contained on purpose: nconftest, no dependencies, runnable on any Spark.
"""
import hashlib, json, sys, threading, time, urllib.request

TAIL = ("Output only Python source. No comments, no docstrings, no markdown fences. "
        "Then add tests and the helpers this needs. Keep writing code.")
PROMPTS = [
    "Write a detailed step-by-step explanation of how a hash map works, including collision handling, resizing, "
    "and time complexity. Be thorough.",
    "Write a short story about a lighthouse keeper who finds a message in a bottle.",
    "Explain how a refrigerator moves heat out of its cabinet, step by step.",
    "Explain in depth how TCP congestion control works: slow start, congestion avoidance, fast retransmit and "
    "fast recovery, with examples. Be thorough.",
]
CODE = [
    "binary_search\ndef binary_search(nums, target) -> int: index of target in a sorted list, or -1.\n" + TAIL,
    "lru_cache\nclass LRUCache: get(key) and put(key, value) in O(1) with a capacity limit.\n" + TAIL,
    "trie\nclass Trie: insert(word), search(word), starts_with(prefix).\n" + TAIL,
    "dijkstra\ndef dijkstra(graph, src) -> dict: shortest distances in a weighted adjacency dict.\n" + TAIL,
]
COUNTERS = ("mtp_drafted_total", "mtp_accepted_total", "decode_rounds_total")


def parse_metrics(text):
    got = dict.fromkeys(COUNTERS, None)
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "{" in line:
            name, _, rest = line.partition("{")
            _, _, rest = rest.partition("}")
            parts = rest.split()
        else:
            parts = line.split()
            name = parts[0] if parts else ""
        if name in got and parts:
            try:
                got[name] = float(parts[-1])
            except ValueError:
                pass
    return got


def fetch_metrics(base, timeout=10):
    try:
        with urllib.request.urlopen(base + "/metrics", timeout=timeout) as r:
            return parse_metrics(r.read().decode("utf-8", "replace"))
    except Exception:
        return dict.fromkeys(COUNTERS, None)


def account(before, after, tokens, span_s):
    def delta(name):
        b, a = before.get(name), after.get(name)
        if b is None or a is None or a < b:
            return None
        return int(a - b)
    rounds = delta(COUNTERS[2]); drafted = delta(COUNTERS[0]); accepted = delta(COUNTERS[1])
    return {"rounds": rounds, "drafted": drafted, "accepted": accepted,
            "acceptance": (accepted / drafted) if (drafted and accepted is not None) else None,
            "tok_per_round": (tokens / rounds) if (rounds and rounds > 0) else None,
            "ms_per_round": (span_s * 1e3 / rounds) if (rounds and rounds > 0 and span_s is not None) else None}


def opt(name, default, argv):
    if name in argv:
        i = argv.index(name); v = argv[i + 1]; del argv[i:i + 2]; return v
    return default


def one(base, model, prompt, maxt, res, idx, t_send):
    body = {"model": model, "messages": [{"role": "user", "content": prompt}], "max_tokens": maxt, "temperature": 0,
            "top_p": 1, "stream": True, "stream_options": {"include_usage": True},
            "chat_template_kwargs": {"enable_thinking": False}}
    req = urllib.request.Request(base + "/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    first = last = None; text = []; usage = None
    with urllib.request.urlopen(req, timeout=1800) as r:
        for raw in r:
            line = raw.decode().strip()
            if not line.startswith("data:"):
                continue
            data = line[5:].strip()
            if data == "[DONE]":
                break
            ev = json.loads(data)
            if ev.get("usage"):
                usage = ev["usage"]
            for ch in ev.get("choices") or []:
                c = (ch.get("delta") or {}).get("content") or (ch.get("delta") or {}).get("reasoning_content")
                if c:
                    now = time.perf_counter()
                    first = first or now
                    last = now
                    text.append(c)
    end = time.perf_counter()
    ct = (usage or {}).get("completion_tokens", 0)
    res[idx] = {"ttft_s": (first - t_send) if first else None, "first": first, "last": last, "end": end,
                "completion_tokens": ct,
                "decode_tok_s": (ct - 1) / (last - first) if first and last and last > first else None,
                "sha": hashlib.sha256("".join(text).encode()).hexdigest()[:12]}


def wave(base, model, prompts, n, maxt):
    res = [None] * n; before = fetch_metrics(base); t0 = time.perf_counter(); th = []
    for i in range(n):
        t = threading.Thread(target=one, args=(base, model, prompts[i % len(prompts)], maxt, res, i, time.perf_counter()))
        t.start(); th.append(t)
    for t in th:
        t.join()
    after = fetch_metrics(base)
    toks = sum(r["completion_tokens"] for r in res)
    end = max(r["end"] for r in res)
    lasts = [r["last"] for r in res if r["last"]]
    firsts = [r["first"] for r in res if r["first"]]
    span = (max(lasts) - min(firsts)) if len(lasts) == len(res) and len(firsts) == len(res) else None
    d = account(before, after, sum(max(0, r["completion_tokens"] - 1) for r in res), span)
    return {"streams": res, "wall_s": end - t0, "agg_tok_s": toks / (end - t0), "drafts": d}


def main(argv):
    rounds = int(opt("--rounds", "3", argv)); maxt = int(opt("--max-tokens", "400", argv))
    tag = opt("--tag", "", argv); out = opt("--out", "", argv)
    prompts = CODE if opt("--kind", "prose", argv) == "code" else PROMPTS
    port, n = argv[1], int(argv[2]); base = f"http://127.0.0.1:{port}"
    model = json.load(urllib.request.urlopen(base + "/v1/models", timeout=10))["data"][0]["id"]
    wave(base, model, prompts, n, 32)          # warm-up, not recorded
    rows = []
    for k in range(rounds):
        w = wave(base, model, prompts, n, maxt); d = w["drafts"]
        row = {"tag": tag, "n": n, "round": k, "agg_tok_s": round(w["agg_tok_s"], 2),
               "wall_s": round(w["wall_s"], 2),
               "per_stream": [round(s["decode_tok_s"] or 0, 2) for s in w["streams"]],
               "ttft_ms": [round((s["ttft_s"] or 0) * 1e3) for s in w["streams"]],
               "tokens": [s["completion_tokens"] for s in w["streams"]],
               "sha": [s["sha"] for s in w["streams"]],
               "draft_rounds": d["rounds"], "drafted": d["drafted"], "accepted": d["accepted"],
               "acceptance": round(d["acceptance"], 3) if d["acceptance"] is not None else None,
               "ms_per_round": round(d["ms_per_round"], 1) if d["ms_per_round"] is not None else None,
               "tok_per_round": round(d["tok_per_round"], 2) if d["tok_per_round"] is not None else None}
        rows.append(row)
        print(json.dumps(row), flush=True)
    if out:
        with open(out, "a") as f:
            for r in rows:
                f.write(json.dumps(r) + "\n")


if __name__ == "__main__":
    main(sys.argv)
