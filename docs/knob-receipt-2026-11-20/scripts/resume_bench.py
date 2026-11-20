"""resume_bench.py URL MODEL [--tokens 8192] [--fillers 14] [--salt-prefix NAME] [--output FILE]

The TF_CACHE_EVICT cell: does a RAM snapshot that has been resumed once survive later eviction pressure?

Sequence, one stream, greedy, thinking off:
  A          conversation A: a fresh-salted filler, ~--tokens tokens, 16 reply tokens
  F1..Fk     k fresh-salted fillers of the same size, each distinct, to fill the snapshot store
  A2         A again: the resume that earns the credit (report its cached_tokens)
  G1..Gm     more distinct fillers, the pressure that would evict A under main order
  A3         A again: the measurement. Under main, if A was evicted, cached_tokens falls and the prefills
             again; under decayed_resume, A is kept and cached_tokens stays high.

Every request records prompt_tokens, cached_tokens, ttft_s (send to first content token), the reply's
token_sha256 and whether the reply is complete. Nothing is cached across runs: each run's salts are fresh.
"""
import argparse
import json
import sys
import time
import urllib.request
import uuid
from random import Random

WORDS = ("lattice probe ferrule datum spindle gauge trellis offset stylus kinematic fixture wafer cosine baseline "
         "granite bearing encoder servo axis spline tolerance flatness runout").split()


def filler(tokens, rnd):
    lines = max(1, int(tokens / 21.8))
    out = [f"Record {uuid.uuid4().hex[:8]} of the number set."]
    for i in range(lines):
        out.append(f"{i + 1}. " + " ".join(rnd.choice(WORDS) for _ in range(12)))
    return "\n".join(out)


def stream(base, model, prompt, tokens):
    body = {
        "model": model,
        "max_tokens": tokens,
        "temperature": 0,
        "stream": True,
        "stream_options": {"include_usage": True},
        "chat_template_kwargs": {"enable_thinking": False},
        "messages": [{"role": "user", "content": prompt}],
    }
    req = urllib.request.Request(base + "/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    t0 = time.perf_counter()
    first = None
    texts = []
    runtime = {}
    usage = {}
    with urllib.request.urlopen(req, timeout=1800) as resp:
        for raw in resp:
            line = raw.decode("utf-8", "replace").strip()
            if not line.startswith("data:"):
                continue
            data = line[5:].strip()
            if data == "[DONE]":
                break
            try:
                obj = json.loads(data)
            except ValueError:
                continue
            if obj.get("usage"):
                usage = obj["usage"]
            tf = obj.get("tensorfold")
            if isinstance(tf, dict):
                runtime.update(tf)
            for choice in obj.get("choices") or []:
                delta = choice.get("delta") or {}
                text = delta.get("content") or delta.get("reasoning_content") or ""
                if choice.get("delta", {}).get("tool_calls"):
                    text = text or "\u0000"
                if text:
                    if first is None:
                        first = time.perf_counter()
                    texts.append(text)
    end = time.perf_counter()
    return {
        "prompt_tokens": (usage.get("prompt_tokens")),
        "cached_tokens": ((usage.get("prompt_tokens_details") or {}).get("cached_tokens")),
        "completion_tokens": usage.get("completion_tokens"),
        "ttft_s": (first - t0) if first is not None else None,
        "elapsed_s": end - t0,
        "token_sha256": runtime.get("token_sha256") or runtime.get("token_sha"),
        "complete": first is not None,
    }


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("base")
    p.add_argument("model")
    p.add_argument("--tokens", type=int, default=9000)
    p.add_argument("--against", type=int, default=14, help="fillers before the first resume")
    p.add_argument("--after", type=int, default=10, help="fillers between the two resumes")
    p.add_argument("--reply", type=int, default=16)
    p.add_argument("--seed", type=int, default=20261120)
    p.add_argument("--output")
    a = p.parse_args(argv)
    rnd = Random(a.seed)
    base = a.base.rstrip("/")
    conv = filler(a.tokens, rnd)
    rows = []

    def send(label, prompt):
        r = stream(base, a.model, prompt, a.reply)
        r["label"] = label
        rows.append(r)
        print(f"{label} prompt {r['prompt_tokens']} cached {r['cached_tokens']} ttft {r['ttft_s']:.3f} "
              f"sha {str(r['token_sha256'])[:12]}", flush=True)
        return r

    send("A1", conv)
    for i in range(a.against):
        send(f"F1_{i}", filler(a.tokens, rnd))
    send("A2", conv)
    for i in range(a.after):
        send(f"F2_{i}", filler(a.tokens, rnd))
    send("A3", conv)
    out = {"tokens": a.tokens, "against": a.against, "after": a.after, "rows": rows}
    if a.output:
        open(a.output, "w", encoding="utf-8").write(json.dumps(out, indent=2) + "\n")
    ok = all(r["complete"] for r in rows)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
