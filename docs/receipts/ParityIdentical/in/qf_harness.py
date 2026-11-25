#!/usr/bin/env python3
"""Qwen3.8 Flash Next speed campaign harness (spark4, port 8888).

Subcommands:
  gen      write fixed bench.py manifests (decode prose/code, prefill cold sizes)
  golden   run fixed greedy golden prompts, save full texts + shas (byte-identity oracle)
  diff     compare two golden files byte for byte
  sum      post-process bench.py --jsonl output -> median tables

All requests: temperature 0 (greedy), chat_template_kwargs enable_thinking false.
Only stdlib.
"""
from __future__ import annotations
import hashlib
import json
import os
import random
import statistics
import sys
import threading
import time
import urllib.request

API = os.environ.get("API_URL", "http://127.0.0.1:8888").rstrip("/")
MODEL = os.environ.get("MODEL_NAME", "Qwen3.8-Flash-Next")
RUNS = int(os.environ.get("RUNS", "3"))

WORDLIST = ("time year people way day man thing woman life child world school state family student "
            "group country problem hand part place case week company system program question work "
            "government number night point home water room mother area money story fact month lot "
            "right study book eye job word business issue side kind head house service friend father "
            "power hour game line end member law car city community name president team minute idea "
            "kid body information back parent face others level office door health person art war "
            "history party result change morning reason research girl guy moment air teacher force "
            "education river mountain signal engine garden theory market winter method bridge letter "
            "window voice paper field").split()

CODE_PROMPTS = [
    "Write a Python quicksort implementation with a docstring and unit tests.",
    "Write a Python function that merges two sorted linked lists, with type hints and tests.",
    "Write a Rust struct for a bounded ring buffer with push and pop methods and tests.",
    "Write a Python context manager that retries a block on transient IO errors, with tests.",
]
PROSE_PROMPTS = [
    "Explain how a lock-free ring buffer can pass messages between one writer and one reader without a mutex.",
    "A librarian has to shelve a cart of books that are already in call-number order. Describe a practical "
    "way to merge them into the stacks and what goes wrong if two carts arrive at once.",
    "Write a few paragraphs on why weather forecasts get worse further into the future, using the idea of "
    "sensitive dependence rather than a list of model names.",
    "Explain the difference between TCP and UDP congestion control to a new graduate engineer.",
]
GOLDEN = [
    "What is the capital of France? Answer with one word.",
    "Write a Python function that returns the n-th Fibonacci number.",
    "Summarize: photosynthesis converts light energy into chemical energy stored in sugars.",
    "Translate to French: the weather is nice today.",
    "List three prime numbers between 20 and 40.",
    "What is 17 * 23? Answer with the number only.",
]


def prose(tokens: int, seed: int) -> str:
    """Random-word prose sized to land near `tokens` after tokenization (measured: words * ~1.14 tokens,
    and the first sizing pass came out at 0.786x the target, so words = tokens * 0.92)."""
    rng = random.Random(seed)
    out = []
    while len(out) < tokens * 0.92:
        sentence = [rng.choice(WORDLIST) for _ in range(rng.randint(6, 16))]
        out += sentence[:-1] + [sentence[-1] + "."]
    return " ".join(out)


def body_of(prompt: str, max_tokens: int) -> dict:
    return {"model": MODEL, "stream": True, "max_tokens": max_tokens,
            "stream_options": {"include_usage": True},
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0, "seed": 1234,
            "chat_template_kwargs": {"enable_thinking": False}}


def complete(prompt: str, max_tokens: int, timeout: float = 7200.0) -> dict:
    """One streamed greedy request; returns content, timings and the engine stats block."""
    req = urllib.request.Request(API + "/v1/chat/completions", json.dumps(body_of(prompt, max_tokens)).encode(),
                                 {"Content-Type": "application/json"})
    t0 = time.perf_counter()
    fp = urllib.request.urlopen(req, timeout=timeout)
    chunks, stats, usage, first = [], {}, {}, None
    for raw in fp:
        line = raw.decode().strip()
        if not line.startswith("data:") or line.endswith("[DONE]"):
            continue
        try:
            chunk = json.loads(line[5:])
        except json.JSONDecodeError:
            continue
        delta = (chunk.get("choices") or [{}])[0].get("delta") or {}
        cdelta = delta.get("content") or ""
        if cdelta:
            if first is None:
                first = time.perf_counter()
            chunks.append(cdelta)
        if "tensorfold" in chunk:
            stats = chunk["tensorfold"]
        if chunk.get("usage"):
            usage = chunk["usage"]
    elapsed = time.perf_counter() - t0
    text = "".join(chunks)
    out = {"prompt": prompt, "content": text, "sha": hashlib.sha256(text.encode()).hexdigest(),
           "ttft": None if first is None else first - t0, "elapsed": elapsed,
           "prompt_tokens": usage.get("prompt_tokens"), "completion_tokens": usage.get("completion_tokens")}
    out.update(stats)
    return out


def bench_arm(prompt, max_tokens: int, clients: int, runs: int) -> list[dict]:
    """`clients` barrier-started requests (one prompt each, cycling `prompt` if it is one string),
    `runs` rounds; returns one record per request."""
    prompts = [prompt] * clients if isinstance(prompt, str) else list(prompt)
    rows = []
    for run in range(runs):
        barrier = threading.Barrier(clients)
        out = [None] * clients
        wall0 = 0.0

        def worker(i: int):
            nonlocal wall0
            barrier.wait()
            if i == 0:
                wall0 = time.perf_counter()
            out[i] = complete(prompts[i % len(prompts)], max_tokens)
        threads = [threading.Thread(target=worker, args=(i,)) for i in range(clients)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        wall = time.perf_counter() - wall0
        for r in out:
            r["run"], r["clients"], r["wall"] = run, clients, wall
            rows.append(r)
    return rows


def cmd_gen(outdir: str) -> None:
    """Fixed manifests for the recipe's bench.py: decode (prose/code, 512 tokens) and prefill (cold sizes)."""
    os.makedirs(outdir, exist_ok=True)
    for kind, prompts in (("prose", PROSE_PROMPTS), ("code", CODE_PROMPTS)):
        reqs = [{"id": f"{kind}-{i}", "prompt": p, "max_tokens": 512, "temperature": 0, "seed": 1234,
                 "thinking": False} for i, p in enumerate(prompts)]
        path = os.path.join(outdir, f"decode-{kind}.json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump({"requests": reqs}, f, indent=2)
        print("wrote", path)
    for tokens in (8000, 32000, 128000):
        reqs = []
        for run in range(3):                       # unique random content every run: always cold
            reqs.append({"id": f"prefill-{tokens}-r{run}", "prompt": prose(tokens, 900000 + tokens + run * 7919),
                         "max_tokens": 16, "temperature": 0, "seed": 1234, "thinking": False})
        path = os.path.join(outdir, f"prefill-{tokens}.json")
        with open(path, "w", encoding="utf-8") as f:
            json.dump({"requests": reqs}, f, indent=2)
        print("wrote", path)


def cmd_golden(path: str) -> None:
    """Fixed greedy prompts; full texts saved for byte-identity comparisons across configs."""
    rows = []
    for i, p in enumerate(GOLDEN):
        r = complete(p, 256)
        r["id"] = f"golden-{i}"
        rows.append(r)
        print(f"golden-{i}: {r.get('completion_tokens')} tok  sha={r['sha'][:16]}  {r['elapsed']:.1f}s")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(rows, f, indent=2, ensure_ascii=False)
    print("wrote", path)


def cmd_diff(a: str, b: str) -> None:
    ra = {r["id"]: r for r in json.load(open(a, encoding="utf-8"))}
    rb = {r["id"]: r for r in json.load(open(b, encoding="utf-8"))}
    same = 0
    for key in sorted(ra):
        if key not in rb:
            print(f"{key}: MISSING in {b}")
            continue
        if ra[key]["content"] == rb[key]["content"]:
            same += 1
            print(f"{key}: IDENTICAL ({len(ra[key]['content'])} chars)")
        else:
            ca, cb = ra[key]["content"], rb[key]["content"]
            k = next((j for j in range(min(len(ca), len(cb))) if ca[j] != cb[j]), min(len(ca), len(cb)))
            print(f"{key}: DIFFER at char {k} of {len(ca)}/{len(cb)}: {ca[k:k+30]!r} vs {cb[k:k+30]!r}")
    print(f"{same}/{len(ra)} identical")


def _med(xs):
    return round(statistics.median(xs), 2) if xs else float("nan")


def cmd_sum(path: str) -> None:
    """One row per (label, clients): median per-request decode tok/s, aggregate tok/s, TTFT, yield, accept."""
    rows = [json.loads(line) for line in open(path, encoding="utf-8") if line.strip()]
    groups = {}
    for r in rows:
        groups.setdefault((r.get("label", "run"), r.get("clients")), []).append(r)
    print(f"{'label':<22} {'C':>2} {'n':>3} {'decode tok/s':>13} {'agg tok/s':>10} {'TTFT ms':>9} "
          f"{'yield':>6} {'accept':>7} {'prefill t/s':>12}")
    for (label, clients), rs in sorted(groups.items()):
        ok = [r for r in rs if r.get("completion_tokens") and r.get("decode_s")]
        if not ok:
            continue
        per = [r["completion_tokens"] / r["decode_s"] for r in ok]
        runs = sorted({r["run"] for r in ok})
        aggs = []
        for run in runs:
            rr = [r for r in ok if r["run"] == run]
            gen = sum(r["completion_tokens"] for r in rr)
            dec = max(r["decode_s"] for r in rr)
            if dec > 0:
                aggs.append(gen / dec)
        ttfts = [r["ttft"] * 1e3 for r in ok if r.get("ttft")]
        yld = [1 + r["accepted"] / r["rounds"] for r in ok if r.get("rounds")]
        acc = [r["accepted"] / r["drafted"] for r in ok if r.get("drafted")]
        pref = [r["prompt_tokens"] / r["prefill_s"] for r in ok if r.get("prefill_s") and r["prompt_tokens"]]
        print(f"{label:<22} {clients:>2} {len(ok):>3} {_med(per):>13} {_med(aggs):>10} {_med(ttfts):>9.0f} "
              f"{_med(yld):>6} {_med(acc):>7} {_med(pref):>12}")


def main() -> None:
    cmd = sys.argv[1] if len(sys.argv) > 1 else "sum"
    if cmd == "gen":
        cmd_gen(sys.argv[2])
    elif cmd == "golden":
        cmd_golden(sys.argv[2])
    elif cmd == "diff":
        cmd_diff(sys.argv[2], sys.argv[3])
    elif cmd == "sum":
        cmd_sum(sys.argv[2])
    else:
        sys.exit("unknown command: " + cmd)


if __name__ == "__main__":
    main()
