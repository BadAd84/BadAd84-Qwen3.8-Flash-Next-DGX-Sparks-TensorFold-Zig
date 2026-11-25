#!/usr/bin/env python3
"""dist_probe.py SPEC.json ARM OUT.jsonl [SEEDS=160]

The candidate distribution at a forced prefix, on an engine that serves no logprobs (both arms of this window:
production refuses them in the server's field parser, the dev engine's Flash Next backend registers no first_row).

The instrument is the API's own sampler at temperature 1: the prompt is the chat prompt's token ids (/tokenize,
the chat route's renderer) followed by the reply's own token ids up to the first divergent token, sent as a
token-id prompt on /v1/completions; max_tokens 1. Each request with a distinct `seed` draws one sample from the
engine's temperature-1 distribution at that position; the reply's engine token hash (tensorfold.token_sha)
identifies the drawn token exactly, and the streamed delta carries its text.

  - top_k 20, top_p 1.0, min_p 0: both arms' keyed samplers take their candidate path, and the draw is the
    full-row softmax restricted to the top 20 (the two candidates of a tie are both inside it);
  - a temperature ladder (1.0, 0.2, 0.05): the pair's ratio at temperature T is exp(gap / T), so a low T turns a
    fraction of a logit into a large split. Applied to the engine's bf16 logits, the ladder measures the very
    margin that decides a greedy argmax: a pair whose bf16 logits are equal splits 50/50 at every T, one bf16 step
    apart (0.0625 near a logit of 10) reads about 78/22 at T = 0.05, and a gap of a logit or more reads 1/0.
  - the T=0 control first: max_tokens 1 at temperature 0 must reproduce the arm's own next token from the greedy
    chat cell. If it does not, the forced prefix is not faithful and the sweep's numbers are void (recorded).

Counts per token -> p(top1)/p(top2) = (n1 + 0.5)/(n2 + 0.5), gap in nats = ln of that ratio.
"""
from __future__ import annotations

import json
import os
import sys
import time
import urllib.error
import urllib.request

API = os.environ.get("API_URL", "http://127.0.0.1:8888").rstrip("/")


def ask(prefix_ids: list[int], seed: int, temperature: float, top_k: int, stream: bool = True) -> dict:
    body = {"model": os.environ.get("MODEL_NAME", "Qwen3.8-Flash-Next"), "prompt": prefix_ids,
            "max_tokens": 1, "temperature": temperature, "seed": seed, "stream": stream,
            "stream_options": {"include_usage": True}}
    if temperature > 0:
        body.update({"top_k": top_k, "top_p": 1.0, "min_p": 0.0})
    req = urllib.request.Request(API + "/v1/completions", json.dumps(body).encode(),
                                 {"Content-Type": "application/json"})
    t0 = time.perf_counter()
    try:
        return _read(req, stream, t0)
    except urllib.error.HTTPError as e:
        return {"error": f"HTTP {e.code}: {e.read().decode(errors='replace')[:300]}", "text": "", "deltas": [""],
                "token_sha": None, "usage": {}, "elapsed": time.perf_counter() - t0}
    except Exception as e:  # noqa: BLE001 - a transport failure is a recorded result
        return {"error": repr(e), "text": "", "deltas": [""], "token_sha": None, "usage": {},
                "elapsed": time.perf_counter() - t0}


def _read(req, stream: bool, t0: float) -> dict:
    with urllib.request.urlopen(req, timeout=600.0) as fp:
        if not stream:
            data = json.loads(fp.read().decode())
            choice = (data.get("choices") or [{}])[0]
            return {"text": choice.get("text") or "", "deltas": [choice.get("text") or ""],
                    "token_sha": (data.get("tensorfold") or {}).get("token_sha"),
                    "usage": data.get("usage"), "elapsed": time.perf_counter() - t0}
        deltas: list[str] = []
        stats: dict = {}
        usage: dict = {}
        for raw in fp:
            line = raw.decode().strip()
            if not line.startswith("data:") or line.endswith("[DONE]"):
                continue
            try:
                chunk = json.loads(line[5:])
            except json.JSONDecodeError:
                continue
            piece = ((chunk.get("choices") or [{}])[0].get("text")) or ""
            if piece:
                deltas.append(piece)
            if "tensorfold" in chunk:
                stats = chunk["tensorfold"]
            if chunk.get("usage"):
                usage = chunk["usage"]
    return {"text": "".join(deltas), "deltas": deltas, "token_sha": stats.get("token_sha"),
            "usage": usage, "elapsed": time.perf_counter() - t0}


def main() -> None:
    spec_path, arm, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
    seeds = int(sys.argv[4]) if len(sys.argv) > 4 else 160
    spec = json.load(open(spec_path, encoding="utf-8"))
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        for cell in spec["cells"]:
            prefix = cell["prefix_ids"]
            want = cell.get("arms", {}).get(arm, {})
            ctrl = ask(prefix, 1234, 0.0, 20)
            row = {"kind": "control", "arm": arm, "cell": cell["name"], "prompt": cell["prompt"], "k": cell["k"],
                   "expect_text": want.get("text"), "expect_sha": want.get("token_sha"),
                   "cands": cell.get("arms", {}), **ctrl}
            row["control_ok"] = (ctrl.get("text") == want.get("text")) if want.get("text") is not None else None
            f.write(json.dumps(row) + "\n")
            f.flush()
            print(f"DIST {arm} {cell['name']} control tok {ctrl.get('text')!r} "
                  f"sha {str(ctrl.get('token_sha'))[:16]} expect {want.get('text')!r} "
                  f"sha {str(want.get('token_sha'))[:16]} ok {row['control_ok']}", flush=True)
            n = int(cell.get("seeds") or seeds)
            temps = cell.get("temperatures") or [1.0]
            for t in temps:
                done = 0
                for s in range(1, n + 1):
                    r = ask(prefix, s, float(t), 20)
                    f.write(json.dumps({"kind": "sample", "arm": arm, "cell": cell["name"],
                                        "prompt": cell["prompt"], "temperature": float(t), "seed": s, **r}) + "\n")
                    f.flush()
                    done += 1
                    if s == 1 and r.get("error"):
                        print(f"DIST {arm} {cell['name']} T={t} aborted at the first sample: {r['error']}", flush=True)
                        break
                print(f"DIST {arm} {cell['name']} T={t} {done} samples done", flush=True)


if __name__ == "__main__":
    main()
