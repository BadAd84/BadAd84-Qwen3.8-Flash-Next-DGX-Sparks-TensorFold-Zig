#!/usr/bin/env python3
"""short.py LABEL OUT.jsonl: agent-like short replies, one client: 12 distinct prompts (qf_harness code and prose
prompts with a fresh suffix each), 100 tokens each, sequentially. Prints the median end-to-end seconds per request and
the median client-side decode tok/s; every request is a new sequence (the per-request graph re-capture W3 removes)."""
import json, statistics, sys, random
import qf_harness as H

label, out = sys.argv[1], sys.argv[2]
prompts = (H.CODE_PROMPTS + H.PROSE_PROMPTS) * 2
tag = random.randrange(1 << 30)
el, rates = [], []
with open(out, "a", encoding="utf-8") as f:
    for i, p in enumerate(prompts[:12]):
        r = H.complete(f"{p}\n\n(short {tag}-{i})", 100)
        el.append(r["elapsed"])
        if r.get("completion_tokens", 0) > 1 and r["elapsed"] > r["ttft"]:
            rates.append((r["completion_tokens"] - 1) / (r["elapsed"] - r["ttft"]))
        f.write(json.dumps({"label": label, "i": i, "elapsed": r["elapsed"], "ttft": r["ttft"],
                            "completion_tokens": r["completion_tokens"], "sha": r.get("sha")}) + "\n")
print(f"{label} short: median {statistics.median(el):.3f} s a request, decode {statistics.median(rates):.1f} tok/s "
      f"[{min(el):.3f}-{max(el):.3f} s]")
