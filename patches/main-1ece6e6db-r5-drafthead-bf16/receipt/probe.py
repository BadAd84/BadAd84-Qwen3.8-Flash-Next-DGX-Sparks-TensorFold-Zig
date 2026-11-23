"""probe.py BASE MODEL --label LABEL --output FILE [--container NAME]

One boot's greedy replies to a fixed prompt set, each prompt sent twice: drafted (the request carries no `draft`
field) and plain (`"draft": false`). Greedy (temperature 0), thinking off, streamed, 64 tokens, and the reply's own
token ids requested (`return_token_ids`), so two replies compare on token_sha256 and, when they differ, on the first
index that differs.

The prompt set is fixed here, byte for byte, so every arm sends the identical strings; the script prints each
prompt's sha256 and the record carries them. Prompts are new to the server on every boot (no prompt is repeated
between the arms' boots except by design), so a comparison is a plain reply against a drafted reply on the same
bytes rather than a cache-state comparison.

The engine's own counters are read around every request: `mtp_drafted_total` growing proves the drafter ran, so an
equality that held because drafts had silently stopped cannot pass for a serving fix.

Exit 0 when every request completed; the equality verdict is read from --output by compare.py, never from this code.
"""
import argparse
import hashlib
import json
import sys
import time
import urllib.request
import uuid

WORDS = ("lattice probe ferrule datum spindle gauge trellis offset stylus kinematic fixture wafer cosine baseline "
         "granite bearing encoder servo axis spline tolerance flatness runout").split()

# The fixed prompt set: three short asks and one record-shaped medium prompt. Written once, hashed into the record.
SHORT = [
    ("sum", "Reply with one sentence: what is the sum of the first ten odd numbers?"),
    ("code", "Write one line of Zig that declares an immutable slice of four u32 values named ticks."),
    ("plan", "Reply with three short bullet points on checking a kinematic fixture's runout on a granite surface plate."),
]


def medium(seed: int, tokens: int) -> str:
    """coldcache.py's filler generator: the same prompt for the same seed on every arm."""
    import random

    rnd = random.Random(seed)
    lines = max(1, int(tokens / 21.8))
    out = [f"Record {uuid.UUID(int=seed).hex[:8]} of the number set."]
    for i in range(lines):
        out.append(f"{i + 1}. " + " ".join(rnd.choice(WORDS) for _ in range(12)))
    return "\n".join(out)


PROMPTS = SHORT + [("medium", medium(20261123, 1200))]


def _blocks(block):
    """The engine's per-reply block is one object; accept a list too, so either shape reads."""
    if isinstance(block, dict):
        return [block]
    if isinstance(block, list):
        return [b for b in block if isinstance(b, dict)]
    return []


def metrics(base):
    try:
        with urllib.request.urlopen(base + "/metrics", timeout=10) as r:
            text = r.read().decode("utf-8", "replace")
    except Exception:
        return {}
    out = {}
    for line in text.splitlines():
        if not line.startswith("tensorfold:"):
            continue
        body = line[len("tensorfold:"):].strip()
        parts = body.split()
        for key in ("decode_rounds_total", "mtp_drafted_total", "mtp_accepted_total", "prompt_tokens_total", "generated_tokens_total"):
            for i, p in enumerate(parts):
                if p == key and i + 1 < len(parts):
                    try:
                        out[key] = float(parts[i + 1])
                    except ValueError:
                        pass
    return out


def stream(base, model, prompt, tokens, draft):
    """One streamed reply: ids, shas and text. `draft` False sends the engine's own non-speculative path."""
    body = {
        "model": model,
        "max_tokens": tokens,
        "temperature": 0,
        "stream": True,
        "stream_options": {"include_usage": True},
        "chat_template_kwargs": {"enable_thinking": False},
        "return_token_ids": True,
        "messages": [{"role": "user", "content": prompt}],
    }
    if not draft:
        body["draft"] = False
    req = urllib.request.Request(base + "/v1/chat/completions", data=json.dumps(body).encode(),
                                 headers={"Content-Type": "application/json"})
    t0 = time.perf_counter()
    ids, text, shas, usage, err = [], [], {}, {}, None
    try:
        with urllib.request.urlopen(req, timeout=600) as r:
            for raw in r:
                line = raw.decode("utf-8", "replace").strip()
                if not line.startswith("data:"):
                    continue
                data = line[len("data:"):].strip()
                if data == "[DONE]":
                    break
                try:
                    chunk = json.loads(data)
                except json.JSONDecodeError:
                    continue
                if chunk.get("error"):
                    err = chunk["error"]
                    continue
                for block in _blocks(chunk.get("tensorfold")):
                    if block.get("token_ids"):
                        ids.extend(block["token_ids"])
                    for k in ("token_sha", "token_sha256"):
                        if block.get(k):
                            shas[k] = block[k]
                for choice in chunk.get("choices") or []:
                    piece = (choice.get("delta") or {}).get("content")
                    if piece:
                        text.append(piece)
                if chunk.get("usage"):
                    usage = chunk["usage"]
    except Exception as exc:  # an HTTP 500 arrives here: the error body names the refusal
        err = {"transport": repr(exc)}
    joined = "".join(text)
    return {
        "ids": ids,
        "text": joined,
        "text_sha256": hashlib.sha256(joined.encode("utf-8")).hexdigest(),
        "shas": shas,
        "usage": usage,
        "error": err,
        "seconds": round(time.perf_counter() - t0, 3),
    }


def first_diff(a, b):
    for i, (x, y) in enumerate(zip(a, b)):
        if x != y:
            return i
    return None if len(a) == len(b) else min(len(a), len(b))


def main():
    p = argparse.ArgumentParser()
    p.add_argument("base")
    p.add_argument("model")
    p.add_argument("--label", required=True)
    p.add_argument("--output", required=True)
    p.add_argument("--container", default=None)
    p.add_argument("--tokens", type=int, default=64)
    args = p.parse_args()

    record = {"label": args.label, "base": args.base, "model": args.model, "tokens": args.tokens,
              "prompts": [], "runs": {}}
    ok = True
    for key, prompt in PROMPTS:
        entry = {"key": key, "sha256": hashlib.sha256(prompt.encode()).hexdigest(), "chars": len(prompt)}
        record["prompts"].append(entry)
        for arm, draft in (("drafted", True), ("plain", False)):
            before = metrics(args.base)
            got = stream(args.base, args.model, prompt, args.tokens, draft)
            after = metrics(args.base)
            counters = {k: after.get(k, 0) - before.get(k, 0) for k in ("decode_rounds_total", "mtp_drafted_total", "mtp_accepted_total")}
            got["counters"] = counters
            record["runs"][f"{key}/{arm}"] = got
            if got["error"] is not None:
                ok = False
            print(f"RUN {args.label} {key} {arm} ids {len(got['ids'])} sha {got['shas'].get('token_sha256', '-')[:16]} "
                  f"err {json.dumps(got['error'])[:160] if got['error'] else '-'} drafted {counters['mtp_drafted_total']:.0f} "
                  f"rounds {counters['decode_rounds_total']:.0f} {got['seconds']}s", flush=True)
        d, q = record["runs"][f"{key}/drafted"], record["runs"][f"{key}/plain"]
        equal = d["shas"].get("token_sha256") is not None and d["shas"].get("token_sha256") == q["shas"].get("token_sha256")
        print(f"WITHIN {args.label} {key} drafted-vs-plain {'EQ' if equal else 'DIFFER'} first_diff {first_diff(d['ids'], q['ids'])}",
              flush=True)
    record["complete"] = ok
    with open(args.output, "w") as f:
        json.dump(record, f, indent=1, sort_keys=True)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
