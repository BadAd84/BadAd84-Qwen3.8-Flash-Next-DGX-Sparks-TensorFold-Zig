#!/usr/bin/env python3
"""trace_decode.py PORT [--model NAME] [--steps N] [--prompt-file F] [--out JSONL]

Drive ONE stream of a decode on a live OpenAI-compatible serve, greedily, for a fixed token count, and
record per-step arrivals. The point of the fixed count is that the run can be STOPPED mid-decode (the
container killed) while the CUPTI capture of the decode window is still whole - an HTTP client cannot
cancel a decoding stream half way and leave the GPU idle cleanly, but a bounded stream ("max_tokens" N
with "stream": false) finishes on its own after N tokens.

The prompt is read from a file (one prompt, held identical between arms), sent with temperature 0 so the
draws are greedy, and the same N for both arms. The reply's own token count is recorded so the profile's
window length is known.

Output (JSONL, one object):
  {"kind":"meta","model":...,"steps":N,"prompt_bytes":...,"t_send":...}
  {"kind":"done","completion_tokens":...,"t_first":...,"t_last":...,"wall_s":...}
"""
import argparse
import json
import sys
import time
import urllib.request

sys.stdout.reconfigure(line_buffering=True)
def _drain(url, body, timeout):
    """Stream one chat/completions request; return (data, wall_s). data has usage, stats, ttft."""
    req = urllib.request.Request(url, data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    t0 = time.time()
    fp = urllib.request.urlopen(req, timeout=timeout)
    chunks, stats, usage, first = [], {}, {}, None
    for raw in fp:
        line = raw.decode().strip()
        if not line.startswith("data:"):
            continue
        try:
            chunk = json.loads(line[5:])
        except Exception:
            continue
        delta = (chunk.get("choices") or [{}])[0].get("delta") or {}
        if delta.get("content"):
            if first is None:
                first = time.time()
            chunks.append(delta["content"])
        if "tensorfold" in chunk:
            stats = chunk["tensorfold"]
        if chunk.get("usage"):
            usage = chunk["usage"]
    data = {"usage": usage, "stats": stats, "ttft": first, "chunks": len(chunks)}
    return data, time.time() - t0




def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("port", type=int)
    ap.add_argument("--model", default="Qwen3.8-Flash-Next")
    ap.add_argument("--steps", type=int, default=64)
    ap.add_argument("--prompt-file", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--base", default=None, help="base URL host (default 127.0.0.1)")
    ap.add_argument("--probe-steps", type=int, default=0, help="a warm-up request of this many tokens first (cold prompt cache)")
    a = ap.parse_args()
    host = a.base or "127.0.0.1"
    base = "http://%s:%d" % (host, a.port)
    prompt = open(a.prompt_file, "r", encoding="utf-8").read()

    # tokenize the prompt first so the profile states its prompt length
    try:
        treq = urllib.request.Request(base + "/tokenize", data=json.dumps({"text": prompt}).encode(),
                                      headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(treq, timeout=60) as r:
            tok = json.loads(r.read().decode())
        ntok = tok.get("count") or len(tok.get("tokens") or tok.get("ids") or [])
    except Exception as e:  # tokenize is optional; the profile does not depend on it
        ntok = -1
        print("tokenize failed: %s" % e)

    out = open(a.out, "w", encoding="utf-8")
    out.write(json.dumps({"kind": "meta", "caport": a.port, "model": a.model, "steps": a.steps,
                          "prompt_bytes": len(prompt), "prompt_tokens": ntok, "t_send": time.time()}) + "\n")
    out.flush()

    # The request shape is the parity harness's own (tfm_decode_ids.py / qf_harness.body_of):
    # /v1/chat/completions, streamed, temperature 0, seed 1234, thinking off, one stream, a fixed max_tokens.
    body = {"model": a.model, "stream": True, "max_tokens": a.steps,
            "stream_options": {"include_usage": True},
            "messages": [{"role": "user", "content": prompt}],
            "temperature": 0, "seed": 1234,
            "chat_template_kwargs": {"enable_thinking": False}}
    if a.probe_steps:
        pb = dict(body)
        pb["max_tokens"] = a.probe_steps
        pb["messages"] = [{"role": "user", "content": prompt + "\n\n(probe)"}]
        try:
            _drain(base + "/v1/chat/completions", pb, timeout=1800)
            out.write(json.dumps({"kind": "probe", "probe_tokens": a.probe_steps}) + "\n")
            out.flush()
        except Exception as e:
            print("warm-up probe failed: %s" % e)
    data, dt = _drain(base + "/v1/chat/completions", body, timeout=1800)
    usage = data.get("usage", {}) or {}
    out.write(json.dumps({"kind": "done", "path": "/v1/chat/completions",
                          "completion_tokens": usage.get("completion_tokens"),
                          "prompt_tokens": usage.get("prompt_tokens"), "wall_s": dt,
                          "total_tokens": usage.get("total_tokens"),
                          "ttft_s": data.get("ttft")}) + "\n")
    out.close()
    print("done chat/completions completion_tokens %s wall %.2fs" % (usage.get("completion_tokens"), dt))
    return 0


if __name__ == "__main__":
    sys.exit(main())
