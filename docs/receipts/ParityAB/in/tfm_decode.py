#!/usr/bin/env python3
"""tfm_decode.py LABEL C OUT.jsonl [PASSES=3] [KINDS=prose,code]  (spark6, ~/work/lanes/tfmain; = conc68 c68_decode.py + KINDS)
Decode with every slot busy: C barrier-started greedy requests (thinking off, 512 tokens, distinct prompts, a
per-pass nonce so every prompt is cold), prose then code, PASSES passes each. Per request (client side, as zig_sum.py):
decode tok/s = (completion tokens - 1) / (elapsed - ttft). Per pass: per-stream median / min, aggregate = the sum of
the C per-request decode rates, and tokens/wall = all completion tokens / the batch's wall time. /metrics' rounds,
drafted, accepted around each pass. Every reply's sha is kept (cross-arm exactness at C streams)."""
from __future__ import annotations
import json
import statistics
import sys
import urllib.request
sys.path.insert(0, "/home/adam/work")
import qf_harness as H  # noqa: E402


def metric(name: str) -> float:
    try:
        text = urllib.request.urlopen(H.API + "/metrics", timeout=5).read().decode()
    except OSError:
        return float("nan")
    for line in text.splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[0] == f"tensorfold:{name}":
            return float(parts[1])
    return float("nan")


def main() -> None:
    label, c, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    passes = int(sys.argv[4]) if len(sys.argv) > 4 else 3
    kinds = sys.argv[5].split(",") if len(sys.argv) > 5 else ["prose", "code"]
    with open(out, "a", encoding="utf-8") as f:
        for kind, prompts in (("prose", H.PROSE_PROMPTS), ("code", H.CODE_PROMPTS)):
            if kind not in kinds:
                continue
            for p in range(passes):
                batch = [f"{prompts[(p + j) % len(prompts)]}\n\n(session {p}-{j})" for j in range(c)]
                m0 = {k: metric(k) for k in ("decode_rounds_total", "mtp_drafted_total", "mtp_accepted_total")}
                rows = H.bench_arm(batch, 512, c, 1)
                m1 = {k: metric(k) for k in m0}
                rates = []
                for j, r in enumerate(rows):
                    n, el, ft = r.get("completion_tokens"), r.get("elapsed"), r.get("ttft")
                    rate = (n - 1) / (el - ft) if n and n > 1 and ft is not None and el > ft else None
                    if rate is not None:
                        rates.append(rate)
                    f.write(json.dumps({"label": label, "C": c, "kind": kind, "pass": p, "j": j, "sha": r["sha"],
                                        "completion_tokens": n, "ttft": ft, "elapsed": el, "wall": r.get("wall"),
                                        "rate": rate}) + "\n")
                toks = sum(r.get("completion_tokens") or 0 for r in rows)
                wall = rows[0]["wall"]
                d = {k: m1[k] - m0[k] for k in m0}
                print(f"DEC {label} C={c} {kind} pass{p}: per-stream med {statistics.median(rates):.2f} "
                      f"min {min(rates):.2f} agg {sum(rates):.1f} tok/wall {toks / wall:.1f} tokens {toks} "
                      f"rounds {d['decode_rounds_total']:.0f} drafted {d['mtp_drafted_total']:.0f} "
                      f"accepted {d['mtp_accepted_total']:.0f}", flush=True)


if __name__ == "__main__":
    main()
