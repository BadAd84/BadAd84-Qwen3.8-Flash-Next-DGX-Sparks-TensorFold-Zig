#!/usr/bin/env python3
"""zcopy.py LABEL OUT.jsonl [runs=3]: qf_arms.py's copy and rewrite replies (a ~1,800-token text repeated verbatim,
then rewritten with one word changed; PR #319's metrics) with client-side decode rates, for servers without
TensorFold's per-request stats (the Zig release): (completion tokens - 1) / (elapsed - time to the first token)."""
import json, statistics, sys
import qf_harness as H

label, out = sys.argv[1], sys.argv[2]
runs = int(sys.argv[3]) if len(sys.argv) > 3 else 3
cases = {
    "copy": "Repeat the following text verbatim, with no additions:\n\n" + H.prose(1800, 424242),
    "rewrite": ("Rewrite the text below exactly, changing only the word 'time' to 'hour'. Keep everything else "
                "identical:\n\n" + H.prose(1800, 777)),
}
with open(out, "a", encoding="utf-8") as f:
    for kind, prompt in cases.items():
        rates = []
        for run in range(runs):
            r = H.complete(prompt, 2048)
            rate = (r["completion_tokens"] - 1) / (r["elapsed"] - r["ttft"])
            rates.append(rate)
            f.write(json.dumps({"label": label, "kind": kind, "run": run, "completion_tokens": r["completion_tokens"],
                                "ttft": r["ttft"], "elapsed": r["elapsed"], "rate": rate, "sha": r.get("sha")}) + "\n")
        print(f"{label} {kind}: median {statistics.median(rates):.1f} tok/s {[round(x, 1) for x in rates]}", flush=True)
