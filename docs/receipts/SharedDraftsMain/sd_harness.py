#!/usr/bin/env python3
"""Task #4803: clean-main TF_FLASHNEXT_SHARED_DRAFTS A/B client.

Imports upstream's own stream reader and evidence helpers from the built tree's tools/ directory, so SSE
parsing, piece timing, token_sha256 and the speculative block are the repository's own instrument.

Modes:
  decode --level N   idle TTFT cases, then 3 barrier-started passes of N streams on distinct cold prompts
  cached             idle TTFT cases, then the cached two-stream control (prime A and B alone, then A+B together)

Every request is greedy (temperature 0), thinking off, max_tokens per mode, ignore_eos, streamed, with
usage and return_token_ids, drafts on. Writes <out>/cell.json and <out>/replies.jsonl, and metrics
snapshots as text files.
"""
import argparse
import hashlib
import json
import os
import statistics
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = os.environ.get("SD_TOOLS", os.path.join(HERE, "tools"))
sys.path.insert(0, TOOLS)
import bench_stream  # noqa: E402  (the tree's own reader)
from bench_evidence import Evidence  # noqa: E402

PROSE = [
    "Write two paragraphs about how a harbour town changes between summer and winter. Describe the light, "
    "the work on the water, and the people who stay through both seasons.",
    "Explain in two paragraphs why a small public library matters to a town, using the reading room, the "
    "staff and one ordinary afternoon as your examples.",
    "Describe a long train journey through hills and farmland in two paragraphs, following one passenger "
    "and what they notice from the window as the day passes.",
    "Write two paragraphs about repairing an old wooden boat. Cover the tools, the materials and the "
    "patience the work asks for, in plain practical language.",
]
CODE = [
    "Write a Python module that implements a thread-safe LRU cache with per-entry TTL expiry. Include the "
    "class, docstrings, and a short usage example in a comment.",
    "Write a Python function that merges overlapping intervals from a list of tuples and returns the merged "
    "list sorted by start, with a docstring and three example calls.",
    "Write a Python script that walks a directory tree, finds files larger than a threshold, and prints a "
    "sorted report of the largest ones with sizes in human units.",
    "Write a Python module that parses a simple INI-style configuration file into nested dictionaries, "
    "raising a clear error on malformed lines, with docstrings.",
]
COUNTERS = [
    "tensorfold:mtp_drafted_total",
    "tensorfold:mtp_accepted_total",
    "tensorfold:decode_rounds_total",
    "tensorfold:generation_tokens_total",
    "tensorfold:prompt_tokens_total",
    "tensorfold:prompt_tokens_cached_total",
    "tensorfold:prefix_cache_queries_total",
    "tensorfold:prefix_cache_hits_total",
    "tensorfold:requests_running",
]


def log(msg):
    print(f"[{time.strftime('%Y-%m-%dT%H:%M:%S')}] {msg}", flush=True)


def gpu_line():
    try:
        r = subprocess.run(
            ["nvidia-smi", "--query-gpu=temperature.gpu,clocks.sm,power.draw,memory.used",
             "--format=csv,noheader"], capture_output=True, text=True, timeout=20)
        return r.stdout.strip().replace("\n", ";")
    except Exception:  # noqa: BLE001
        return "nvidia-smi unavailable"


def scrape(base, tag, outdir):
    try:
        with urllib.request.urlopen(base + "/metrics", timeout=30) as resp:
            text = resp.read().decode()
    except Exception as exc:  # noqa: BLE001 - a missing scrape is reported, not fatal to the cell
        text = f"SCRAPE-FAILED {type(exc).__name__}: {exc}\n"
    path = os.path.join(outdir, f"metrics-{tag}.txt")
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)
    vals = {}
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        if len(parts) < 2:
            continue
        try:
            vals[parts[0]] = float(parts[1])
        except ValueError:
            continue
    return {k: vals.get(k) for k in COUNTERS}


def ask(base, model, prompt, max_tokens):
    body = {
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "temperature": 0,
        "max_tokens": max_tokens,
        "ignore_eos": True,
        "stream": True,
        "stream_options": {"include_usage": True},
        "chat_template_kwargs": {"enable_thinking": False},
        "return_token_ids": True,
        "draft": True,
    }
    req = urllib.request.Request(base + "/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    sent = time.perf_counter()
    col = bench_stream.Collector(sent)
    try:
        with urllib.request.urlopen(req, timeout=1800) as resp:
            col.read(resp)
    except urllib.error.HTTPError as exc:  # noqa: BLE001 - record the server's own words
        try:
            body = exc.read().decode()[:400]
        except Exception:  # noqa: BLE001
            body = ""
        return {"error": f"HTTP {exc.code}: {body}", "prompt": prompt[:48], "complete": False,
                "speculative": None}
    except Exception as exc:  # noqa: BLE001 - a failed request is recorded, not fatal
        return {"error": type(exc).__name__ + ": " + str(exc)[:200], "prompt": prompt[:48],
                "complete": False, "speculative": None}
    wall = time.perf_counter() - sent
    ev = col.evidence.finish(col.usage, col.runtime, col.end == "done")
    runtime = col.runtime if isinstance(col.runtime, dict) else {}
    pieces = col.pieces
    ttft = (pieces[0][0] - sent) if pieces else None
    last = pieces[-1][0] if pieces else None
    n = ev.get("tokens")
    decode_tps = ((n - 1) / (last - pieces[0][0])) if (n and n > 1 and pieces and last > pieces[0][0]) else None
    return {
        "error": None if col.end == "done" else (col.end or "incomplete"),
        "complete": col.end == "done",
        "prompt_head": prompt[:64],
        "prompt_sha256": hashlib.sha256(prompt.encode()).hexdigest(),
        "prompt_chars": len(prompt),
        "prompt_tokens": ev.get("prompt_tokens"),
        "cached_tokens": ev.get("cached_tokens"),
        "cache_state": ev.get("cache_state"),
        "completion_tokens": n,
        "token_sha": ev.get("token_sha"),
        "token_sha256": ev.get("token_sha256"),
        "token_ids": runtime.get("token_ids"),
        "ttft_s": ttft,
        "last_token_s": (last - sent) if last is not None else None,
        "decode_tps": decode_tps,
        "wall_s": wall,
        "server_ttft_s": runtime.get("time_to_first_token"),
        "server_tps": runtime.get("tokens_per_second"),
        "server_decode_s": runtime.get("seconds"),
        "prefill_s": runtime.get("prefill_seconds"),
        "drafts_flag": runtime.get("drafts"),
        "thinking": runtime.get("enable_thinking"),
        "reasoning_effort": runtime.get("reasoning_effort"),
        "speculative": col.speculative or None,
        "usage": col.usage if isinstance(col.usage, dict) else None,
        "finish_reasons": [col.finish[i] for i in sorted(col.finish)],
        "pieces": len(pieces),
        "completion_class": col.completion(),
    }


def together(base, model, prompts, max_tokens):
    gate = threading.Barrier(len(prompts))
    out = [None] * len(prompts)

    def run(i):
        try:
            gate.wait(timeout=60)
        except Exception as exc:  # noqa: BLE001
            out[i] = {"error": "barrier: " + type(exc).__name__, "complete": False}
            return
        out[i] = ask(base, model, prompts[i], max_tokens)

    threads = [threading.Thread(target=run, args=(i,)) for i in range(len(prompts))]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    return out


def aggregate(runs):
    done = [r for r in runs if r.get("decode_tps") is not None and r.get("complete")]
    out = {"streams": len(runs), "complete": len(done), "failed": len(runs) - len(done)}
    if not done:
        return out
    first = min(r["ttft_s"] for r in done) if all(r.get("ttft_s") is not None for r in done) else None
    last = max(r["last_token_s"] for r in done) if all(r.get("last_token_s") is not None for r in done) else None
    tokens_after_first = sum(r["completion_tokens"] - 1 for r in done)
    span = (last - first) if (first is not None and last is not None and last > first) else None
    out["aggregate_tps"] = (tokens_after_first / span) if span else None
    out["makespan_s"] = span
    out["per_stream_tps"] = [r["decode_tps"] for r in done]
    out["per_stream_median_tps"] = statistics.median(out["per_stream_tps"]) if out["per_stream_tps"] else None
    out["ttft_s"] = [r["ttft_s"] for r in done]
    out["ttft_median_s"] = statistics.median([t for t in out["ttft_s"] if t is not None]) if out["ttft_s"] else None
    out["ttft_max_s"] = max([t for t in out["ttft_s"] if t is not None], default=None)
    out["server_ttft_median_s"] = statistics.median(
        [r["server_ttft_s"] for r in done if r.get("server_ttft_s") is not None]) if any(
        r.get("server_ttft_s") is not None for r in done) else None
    out["prefill_median_s"] = statistics.median(
        [r["prefill_s"] for r in done if r.get("prefill_s") is not None]) if any(
        r.get("prefill_s") is not None for r in done) else None
    spec = [r.get("speculative") for r in done if isinstance(r.get("speculative"), dict)]
    out["speculative_replies"] = len(spec)
    out["rounds"] = sum(int(s.get("rounds") or 0) for s in spec) if spec else None
    out["drafted"] = sum(int(s.get("drafted") or 0) for s in spec) if spec else None
    out["accepted"] = sum(int(s.get("accepted") or 0) for s in spec) if spec else None
    out["acceptance_rate"] = (out["accepted"] / out["drafted"]) if (out.get("drafted") or 0) > 0 else None
    out["cached_tokens"] = sum(int(r["cached_tokens"] or 0) for r in done)
    out["completion_tokens_total"] = sum(r["completion_tokens"] for r in done)
    out["prompt_tokens"] = [r.get("prompt_tokens") for r in done]
    out["token_sha256"] = [r.get("token_sha256") for r in done]
    out["completion_classes"] = sorted({r.get("completion_class") for r in done})
    out["finish_reasons"] = sorted({fr for r in done for fr in (r.get("finish_reasons") or [])})
    return out


def prompt_for(level, pass_no, idx):
    """A fixed prompt whose first token is unique per (level, pass, index), identical across arms, so every
    pass is cold on the prompt cache and both arms see byte-identical strings."""
    tag = hashlib.sha1(f"{level}-{pass_no}-{idx}".encode()).hexdigest()[:10]
    kind = "prose" if idx % 2 == 0 else "code"
    base = PROSE[(idx // 2) % len(PROSE)] if kind == "prose" else CODE[(idx // 2) % len(CODE)]
    return f"Sd{tag}4803 {base}"


def idle_prompt(rep, size):
    tag = hashlib.sha1(f"idle-{rep}-{size}".encode()).hexdigest()[:10]
    filler = (
        "The workshop opened early and the kettle was already warm. Outside, the yard filled with the sound "
        "of carts and the smell of cut timber. Inside, the benches were clear, the tools were hung in order, "
        "and the day's list waited on the board. ")
    target_chars = 4200 if size == "1k" else 34000
    text = (filler * ((target_chars // len(filler)) + 1))[:target_chars]
    return f"Sd{tag}4803 Read the following notes and then summarise them in two short paragraphs.\n\n{text}"


def cell_decode(base, model, level, outdir):
    cell = {"mode": "decode", "level": level, "gpu_start": gpu_line(), "started": time.strftime("%Y-%m-%dT%H:%M:%S")}
    idle = []
    for size in ("1k", "8k"):
        for rep in (1, 2):
            p = idle_prompt(rep, size)
            r = ask(base, model, p, 64)
            r["size"] = size
            r["rep"] = rep
            idle.append(r)
            log(f"idle {size} rep{rep} tokens={r.get('prompt_tokens')} cached={r.get('cached_tokens')} "
                f"ttft={r.get('ttft_s')} err={r.get('error')}")
    cell["idle"] = idle
    passes = []
    for pass_no in (1, 2, 3):
        prompts = [prompt_for(level, pass_no, i) for i in range(level)]
        before = scrape(base, f"c{level}-p{pass_no}-before", outdir)
        gpu_before = gpu_line()
        runs = together(base, model, prompts, 512)
        gpu_after = gpu_line()
        after = scrape(base, f"c{level}-p{pass_no}-after", outdir)
        delta = {k: (None if before.get(k) is None or after.get(k) is None else after[k] - before[k])
                 for k in COUNTERS}
        agg = aggregate(runs)
        rec = {"pass": pass_no,
               "prompts": [{"sha256": hashlib.sha256(p.encode()).hexdigest(), "chars": len(p)} for p in prompts],
               "gpu_before": gpu_before, "gpu_after": gpu_after,
               "counters_before": before, "counters_after": after, "counters_delta": delta,
               "aggregate": agg, "replies": runs}
        passes.append(rec)
        log(f"c{level} pass{pass_no} agg={agg.get('aggregate_tps')} per_stream_med={agg.get('per_stream_median_tps')} "
            f"ttft_med={agg.get('ttft_median_s')} drafted={agg.get('drafted')} accepted={agg.get('accepted')} "
            f"rounds={agg.get('rounds')} metrics_drafted={delta.get('tensorfold:mtp_drafted_total')} "
            f"failed={agg.get('failed')}")
        for r in runs:
            if r.get("error"):
                log(f"  stream error {r.get('error')}")
    cell["passes"] = passes
    cell["gpu_end"] = gpu_line()
    agg_med = statistics.median([p["aggregate"]["aggregate_tps"] for p in passes if p["aggregate"].get("aggregate_tps")]) if any(p["aggregate"].get("aggregate_tps") for p in passes) else None
    vals = [p["aggregate"]["aggregate_tps"] for p in passes if p["aggregate"].get("aggregate_tps")]
    cell["aggregate_tps_median"] = agg_med
    cell["aggregate_tps_spread"] = (max(vals) / min(vals) - 1) if len(vals) >= 2 and min(vals) > 0 else None
    return cell


def cell_cached(base, model, outdir):
    cell = {"mode": "cached", "level": 2, "gpu_start": gpu_line(), "started": time.strftime("%Y-%m-%dT%H:%M:%S")}
    idle = []
    for size in ("1k", "8k"):
        for rep in (1, 2):
            p = idle_prompt(rep, size)
            r = ask(base, model, p, 64)
            r["size"] = size
            r["rep"] = rep
            idle.append(r)
    cell["idle"] = idle
    a = "Benchmark session sd4803-cached-A. " + PROSE[0]
    b = "Benchmark session sd4803-cached-B. " + CODE[1]
    before = scrape(base, "cached-before", outdir)
    prime_a = ask(base, model, a, 512)
    prime_b = ask(base, model, b, 512)
    gpu_before = gpu_line()
    cached = together(base, model, [a, b], 512)
    gpu_after = gpu_line()
    after = scrape(base, "cached-after", outdir)
    delta = {k: (None if before.get(k) is None or after.get(k) is None else after[k] - before[k]) for k in COUNTERS}
    cell.update({"prime_a": prime_a, "prime_b": prime_b, "streams": cached,
                 "aggregate": aggregate(cached), "gpu_before": gpu_before, "gpu_after": gpu_after,
                 "counters_before": before, "counters_after": after, "counters_delta": delta,
                 "gpu_end": gpu_line()})
    log(f"cached prime cached_a={prime_a.get('cached_tokens')}/{prime_a.get('prompt_tokens')} "
        f"cached_b={prime_b.get('cached_tokens')}/{prime_b.get('prompt_tokens')}; two-stream "
        f"cached={[r.get('cached_tokens') for r in cached]} prompts={[r.get('prompt_tokens') for r in cached]} "
        f"agg={cell['aggregate'].get('aggregate_tps')} drafted={cell['aggregate'].get('drafted')} "
        f"accepted={cell['aggregate'].get('accepted')}")
    return cell


def cell_smoke(base, model, outdir):
    cell = {"mode": "smoke", "gpu_start": gpu_line(), "started": time.strftime("%Y-%m-%dT%H:%M:%S")}
    before = scrape(base, "smoke-before", outdir)
    r = ask(base, model, "Smoke check 4803: say hello in five words.", 16)
    after = scrape(base, "smoke-after", outdir)
    cell.update({"reply": r, "counters_before": before, "counters_after": after,
                 "gpu_end": gpu_line()})
    log(f"smoke complete={r.get('complete')} tokens={r.get('completion_tokens')} "
        f"sha={r.get('token_sha256')} drafts={r.get('speculative')} err={r.get('error')}")
    return cell


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8888")
    ap.add_argument("--model", default="Qwen3.8-Flash-Next")
    ap.add_argument("--out", required=True)
    ap.add_argument("--mode", choices=("decode", "cached", "smoke"), required=True)
    ap.add_argument("--level", type=int, default=1)
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)
    if args.mode == "decode":
        cell = cell_decode(args.base, args.model, args.level, args.out)
    elif args.mode == "cached":
        cell = cell_cached(args.base, args.model, args.out)
    else:
        cell = cell_smoke(args.base, args.model, args.out)
    cell["finished"] = time.strftime("%Y-%m-%dT%H:%M:%S")
    with open(os.path.join(args.out, "cell.json"), "w", encoding="utf-8") as f:
        json.dump(cell, f, indent=1)
    log(f"WROTE {os.path.join(args.out, 'cell.json')}")


if __name__ == "__main__":
    main()
