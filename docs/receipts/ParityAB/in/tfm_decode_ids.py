#!/usr/bin/env python3
"""tfm_decode_ids.py LABEL C OUT.jsonl [PASSES=3] [KINDS=prose,code]  (spark6, parity window)

The SPEED-TARGET's decode harness (`~/work/lanes/tfmain/tfm_decode.py`, sha256 3e535944...) with three additions,
none of which touches a cell's arithmetic: every reply's engine-reported token hash (`token_sha`, and
`token_sha256` where the engine sends one) and its server-side prefill / first-token timings are written into the
JSONL beside the client text sha; a pass whose requests all failed prints a DEC line marked UNMEASURED instead of
crashing on an empty median; and the metric lookup accepts the name with and without the `tensorfold:` prefix and
both rounds spellings, so an arm whose web server exposes `mtp_rounds_total` still gets its counters. The DEC line
text is byte-compatible with the original, so target_sum.py still parses a log written by this file.

Original docstring: Decode with every slot busy: C barrier-started greedy requests (thinking off, 512 tokens,
distinct prompts, a per-pass nonce so every prompt is cold), prose then code, PASSES passes each. Per request
(client side, as zig_sum.py): decode tok/s = (completion tokens - 1) / (elapsed - ttft). Per pass: per-stream
median / min, aggregate = the sum of the C per-request decode rates, and tokens/wall = all completion tokens / the
batch's wall time. /metrics' rounds, drafted, accepted around each pass. Every reply's sha is kept (cross-arm
exactness at C streams).

This file also prints one `TOK` line a pass: the engine's token hash for each request j, in j order, which is what
"token hashes every cell" is checked against in the receipt.
"""
from __future__ import annotations
import json
import os
import statistics
import sys
import urllib.request
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qf_harness as H  # noqa: E402

ROUNDS = ("decode_rounds_total", "mtp_rounds_total")
DRAFTED = ("mtp_drafted_total", "decode_drafted_total")
ACCEPTED = ("mtp_accepted_total", "decode_accepted_total")


def _series(name: str) -> float:
    text = urllib.request.urlopen(H.API + "/metrics", timeout=5).read().decode()
    for line in text.splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[0] in (f"tensorfold:{name}", name):
            try:
                return float(parts[1])
            except ValueError:
                return float("nan")
    return float("nan")


def metric(names) -> float:
    """The first of `names` the server exposes (with or without the tensorfold: prefix); nan when none does."""
    try:
        for name in names:
            value = _series(name)
            if value == value:          # not nan
                return value
        return float("nan")
    except OSError:
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
                m0 = {k: metric(v) for k, v in (("rounds", ROUNDS), ("drafted", DRAFTED), ("accepted", ACCEPTED))}
                rows = H.bench_arm(batch, 512, c, 1)
                m1 = {k: metric(v) for k, v in (("rounds", ROUNDS), ("drafted", DRAFTED), ("accepted", ACCEPTED))}
                rates = []
                for j, r in enumerate(rows):
                    n, el, ft = r.get("completion_tokens"), r.get("elapsed"), r.get("ttft")
                    rate = (n - 1) / (el - ft) if n and n > 1 and ft is not None and el > ft else None
                    if rate is not None:
                        rates.append(rate)
                    f.write(json.dumps({"label": label, "C": c, "kind": kind, "pass": p, "j": j,
                                        "sha": r["sha"], "completion_tokens": n, "ttft": ft, "elapsed": el,
                                        "wall": r.get("wall"), "rate": rate,
                                        "token_sha": r.get("token_sha"),
                                        "token_sha256": r.get("token_sha256"),
                                        "prefill_seconds": r.get("prefill_seconds"),
                                        "time_to_first_token": r.get("time_to_first_token"),
                                        "server_seconds": r.get("seconds"),
                                        "prompt_tokens": r.get("prompt_tokens")}) + "\n")
                toks = sum(r.get("completion_tokens") or 0 for r in rows)
                wall = rows[0]["wall"]
                d = {k: m1[k] - m0[k] for k in m0}
                if rates:
                    print(f"DEC {label} C={c} {kind} pass{p}: per-stream med {statistics.median(rates):.2f} "
                          f"min {min(rates):.2f} agg {sum(rates):.1f} tok/wall {toks / wall:.1f} tokens {toks} "
                          f"rounds {d['rounds']:.0f} drafted {d['drafted']:.0f} accepted {d['accepted']:.0f}",
                          flush=True)
                else:
                    print(f"DEC {label} C={c} {kind} pass{p}: UNMEASURED tokens {toks} wall {wall:.1f} "
                          f"errors {sum(1 for r in rows if not r.get('completion_tokens'))}", flush=True)
                print(f"TOK {label} C={c} {kind} pass{p}: " + " ".join(
                    (r.get("token_sha") or (r.get("token_sha256") or "")[:12] or r["sha"][:12]) for r in rows),
                    flush=True)


if __name__ == "__main__":
    main()
