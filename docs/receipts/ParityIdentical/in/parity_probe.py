#!/usr/bin/env python3
"""parity_probe.py greedy LABEL ARM MODE C OUT.jsonl  (spark6, the parity-identical window)

One boot's cells on the serving port (API_URL): every fixed prompt in prompts/ at concurrency C, greedy,
512 tokens, thinking off, through the target's own harness (qf_harness.complete, the SHA-256 of the reply text
as the ParityAB window computed it), plus the identities an exact comparison needs:

  - the prompt's rendered token ids from /tokenize (the chat route's own renderer, same template), so the two
    arms' model inputs can be compared, not just their lengths;
  - each reply's reconstructed token ids (/tokenize of the reply text, add_special_tokens=false) and the
    per-chunk deltas the stream carried, so the first divergent token index and its token text are known even
    though neither engine serves logprobs;
  - the engine's own token hash (`tensorfold.token_sha`) beside the client text sha.

Rows are JSONL, one a request, plus one a prompt (its ids). Writes each row as it completes.
"""
from __future__ import annotations

import hashlib
import json
import os
import sys
import time
import urllib.request
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
os.environ.setdefault("API_URL", os.environ.get("API_URL", "http://127.0.0.1:8888"))
import qf_harness as H  # noqa: E402

PROMPTS = ["prose-rec0", "code-rec0", "prose-1k", "code-1k", "prose-8k"]


def post(path: str, body: dict, timeout: float = 120.0) -> dict:
    req = urllib.request.Request(H.API + path, json.dumps(body).encode(), {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as fp:
        return json.loads(fp.read().decode())


def delta_stream(prompt: str, max_tokens: int, c: int, extra: dict | None = None) -> list[dict]:
    """`c` barrier-started streamed requests; one row a request with its deltas, text, shas and stats."""
    body = H.body_of(prompt, max_tokens)
    if extra:
        body.update(extra)
    out: list[dict | None] = [None] * c
    barrier = threading.Barrier(c)

    def worker(i: int) -> None:
        barrier.wait()
        req = urllib.request.Request(H.API + "/v1/chat/completions", json.dumps(body).encode(),
                                     {"Content-Type": "application/json"})
        t0 = time.perf_counter()
        try:
            out[i] = _one(req, t0)
        except Exception as e:  # noqa: BLE001 - a failed request is a recorded row
            out[i] = {"content": "", "deltas": [], "sha": hashlib.sha256(b"").hexdigest(), "error": repr(e),
                      "ttft": None, "elapsed": time.perf_counter() - t0, "prompt_tokens": None,
                      "completion_tokens": 0, "deltas_len": 0}

    def _one(req, t0: float) -> dict:
        deltas: list[str] = []
        stats: dict = {}
        usage: dict = {}
        first = None
        with urllib.request.urlopen(req, timeout=7200.0) as fp:
            for raw in fp:
                line = raw.decode().strip()
                if not line.startswith("data:") or line.endswith("[DONE]"):
                    continue
                try:
                    chunk = json.loads(line[5:])
                except json.JSONDecodeError:
                    continue
                d = (chunk.get("choices") or [{}])[0].get("delta") or {}
                piece = d.get("content") or ""
                if piece:
                    if first is None:
                        first = time.perf_counter()
                    deltas.append(piece)
                if "tensorfold" in chunk:
                    stats = chunk["tensorfold"]
                if chunk.get("usage"):
                    usage = chunk["usage"]
        text = "".join(deltas)
        return {"content": text, "deltas": deltas, "sha": hashlib.sha256(text.encode()).hexdigest(),
                "ttft": None if first is None else first - t0, "elapsed": time.perf_counter() - t0,
                "prompt_tokens": usage.get("prompt_tokens"), "completion_tokens": usage.get("completion_tokens"),
                "deltas_len": len(deltas), **stats}

    threads = [threading.Thread(target=worker, args=(i,)) for i in range(c)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    return [r for r in out if r is not None]


def main() -> None:
    label, arm, mode, c, out_path = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5]
    prompts_dir = os.path.join(HERE, "prompts")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        for name in PROMPTS:
            text = open(os.path.join(prompts_dir, name + ".txt"), encoding="utf-8").read()
            try:
                rendered = post("/tokenize", {"messages": [{"role": "user", "content": text}],
                                              "chat_template_kwargs": {"enable_thinking": False},
                                              "add_generation_prompt": True})
                ids = rendered.get("tokens") or []
            except Exception as e:  # noqa: BLE001 - a missing /tokenize is a recorded result, not a crash
                ids = []
                f.write(json.dumps({"kind": "prompt", "label": label, "prompt": name, "ids": [],
                                    "ids_error": repr(e)}) + "\n")
                f.flush()
            if ids:
                f.write(json.dumps({"kind": "prompt", "label": label, "prompt": name, "ids": ids,
                                    "ids_count": len(ids),
                                    "ids_sha": hashlib.sha256(",".join(map(str, ids)).encode()).hexdigest()}) + "\n")
                f.flush()
            rows = delta_stream(text, 512, c)
            for j, r in enumerate(rows):
                try:
                    enc = post("/tokenize", {"prompt": r["content"], "add_special_tokens": False})
                    reply_ids = enc.get("tokens") or []
                except Exception as e:  # noqa: BLE001
                    reply_ids = []
                    r["reply_ids_error"] = repr(e)
                r.update({"kind": "req", "label": label, "arm": arm, "mode": mode, "C": c, "prompt": name,
                          "j": j, "reply_ids": reply_ids})
                f.write(json.dumps(r) + "\n")
                f.flush()
                print(f"REQ {label} {name} C={c} j={j} tok {r.get('completion_tokens')} "
                      f"delta_n {r.get('deltas_len')} sha {r['sha'][:16]} tok_sha {str(r.get('token_sha'))[:16]}",
                      flush=True)


if __name__ == "__main__":
    main()
