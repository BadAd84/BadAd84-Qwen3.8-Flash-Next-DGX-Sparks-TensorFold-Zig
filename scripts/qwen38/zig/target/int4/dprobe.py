"""dprobe.py NAME OUT.jsonl - per-prompt draft counters of the serve on :8888, one request at a time: the six golden
prompts (256 tokens) and the first prose and code prompts of the decode harness (512 tokens), greedy, thinking off.
Each line: rounds, drafted and accepted from /metrics around the request, the reply's tokens and sha."""
import json
import os
import sys
import urllib.request

sys.path.insert(0, os.path.expanduser("~/work"))
import qf_harness as H  # noqa: E402

KEYS = ("decode_rounds_total", "mtp_drafted_total", "mtp_accepted_total")


def metric(name: str) -> float:
    text = urllib.request.urlopen(H.API + "/metrics", timeout=5).read().decode()
    for line in text.splitlines():
        parts = line.split()
        if len(parts) == 2 and parts[0] == f"tensorfold:{name}":
            return float(parts[1])
    return float("nan")


def main() -> None:
    name, out = sys.argv[1], sys.argv[2]
    cases = [(f"golden-{i}", p, 256) for i, p in enumerate(H.GOLDEN)]
    cases += [("prose", H.PROSE_PROMPTS[0], 512), ("code", H.CODE_PROMPTS[0], 512)]
    tot = {"tokens": 0, "rounds": 0, "drafted": 0, "accepted": 0}
    with open(out, "w", encoding="utf-8") as f:
        for case, prompt, mt in cases:
            m0 = {k: metric(k) for k in KEYS}
            r = H.complete(prompt, mt)
            m1 = {k: metric(k) for k in KEYS}
            d = {k: m1[k] - m0[k] for k in KEYS}
            row = {"arm": name, "case": case, "tokens": r.get("completion_tokens"), "rounds": d[KEYS[0]],
                   "drafted": d[KEYS[1]], "accepted": d[KEYS[2]], "sha": r.get("sha", "")[:16], "token_sha": r.get("token_sha"),
                   "content": r.get("content")}
            f.write(json.dumps(row) + "\n")
            for k in tot:
                tot[k] += row[k] or 0
            rd = max(row["rounds"], 1)
            print(f"PROBE {name} {case} tokens {row['tokens']} rounds {row['rounds']:.0f} drafted {row['drafted']:.0f} "
                  f"accepted {row['accepted']:.0f} tok/round {row['tokens'] / rd:.2f} acc/round {row['accepted'] / rd:.2f} "
                  f"sha {row['sha']}", flush=True)
    rd = max(tot["rounds"], 1)
    print(f"PROBE {name} all tokens {tot['tokens']} rounds {tot['rounds']:.0f} drafted {tot['drafted']:.0f} accepted "
          f"{tot['accepted']:.0f} tok/round {tot['tokens'] / rd:.2f} drafted/round {tot['drafted'] / rd:.2f} "
          f"acc/round {tot['accepted'] / rd:.2f}", flush=True)


if __name__ == "__main__":
    main()
