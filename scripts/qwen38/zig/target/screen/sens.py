#!/usr/bin/env python3
"""sens.py --out DIR: the rule against the ProseDraft receipt's own measured numbers, asserted.

Three synthetic boots in the writer's shape. The two treatment cells carry the receipt's values: prose 4
streams B0 207.8, C0 207.6, S0 229.0, G8 207.3, C20 207.9; code 4 streams S0 300.1 against B0 276.8 and
C0 277.2 (work/ProseDraft/RESULT.md:68-84). Every other cell is held equal, so it cannot judge. This tests
the rule's decision boundary against numbers the repo already promoted or called level, not the box: the arm
the repo promoted must come out PROMOTE and the two it recorded level must not be killed. Prints one line a
case and SENS-OK, or SENS-BAD and exit 1.
"""
import argparse
import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
CASES = {
    "shared-drafts-s0": ({"prose": (207.8, 229.0, 207.6), "code": (276.8, 300.1, 277.2)}, "PROMOTE"),
    "greedy-wide-g8": ({"prose": (207.8, 207.3, 207.6), "code": (276.8, 277.0, 277.2)}, "INCONCLUSIVE"),
    "confidence-c20": ({"prose": (207.8, 207.9, 207.6), "code": (276.8, 277.3, 277.2)}, "INCONCLUSIVE"),
}
ARM = "01-attn-lanes"


def boot(d, prose4, code4):
    Path(d).mkdir(parents=True, exist_ok=True)
    cells = []
    for prompt, streams, temp in (("chat", 1, 0.0), ("code", 1, 0.0), ("chat", 4, 0.0),
                                  ("code", 4, 0.0), ("chat", 4, 1.0)):
        val = prose4 if (prompt, streams, temp) == ("chat", 4, 0.0) else \
              code4 if (prompt, streams) == ("code", 4) else 100.0
        cells.append({"prompt": prompt, "temperature": temp, "streams": streams, "failed": 0,
                      "unmeasured": 0, "aggregate_tps": val, "per_stream_tps": val / streams,
                      "alone": {"equal": streams, "unequal": 0, "failed": 0},
                      "serial": {"equal": streams, "unequal": 0, "failed": 0},
                      "reps": [{"requests": [{"prompt_tokens": 3000} for _ in range(streams)]}]})
    (Path(d) / "conc.json").write_text(json.dumps({"label": str(d), "cells": cells}), encoding="utf-8")
    (Path(d) / "ttft.txt").write_text(
        "summary cold2k-off idle n 3 ttft med 0.500 p90 0.52 admit 0.01 queue - prefill - other 0.49 server - excluded 0\n"
        "summary cold32k-off idle n 3 ttft med 8.000 p90 8.2 admit 0.03 queue - prefill - other 7.97 server - excluded 0\n",
        encoding="utf-8")
    (Path(d) / "meta.json").write_text(json.dumps({"boot_rc": 0, "health": 200, "foreign": 0, "digest": "same",
                                                  "settings_ok": 1}), encoding="utf-8")


def verdict(root):
    p = subprocess.run([sys.executable, str(HERE / "analyze.py"), "--out", str(root / "out"),
                        "--plan", str(root / "plan.tsv"), "--print-verdict"],
                       capture_output=True, text=True)
    for line in p.stdout.splitlines():
        f = line.split("\t")
        if len(f) == 3 and f[0] == "VERDICT" and f[1] == ARM:
            return f[2]
    return f"NO-VERDICT({p.returncode}:{p.stderr.strip()[:80]})"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True, help="a scratch directory; nothing here is a receipt")
    args = ap.parse_args()
    bad = 0
    for label, (vals, expect) in CASES.items():
        root = Path(args.out) / label
        for i, role in enumerate(("c1", "a", "c2")):
            boot(root / "out" / ARM / role, vals["prose"][i], vals["code"][i])
        (root / "plan.tsv").write_text(f"{ARM}\tTF_FLASHNEXT_SHARED_DRAFTS\t0\tA1\treceipt\n", encoding="utf-8")
        got = verdict(root)
        ok = got == expect
        bad += 0 if ok else 1
        print(f"SENS {label:18s} {got:14s} expect {expect:14s} {'ok' if ok else 'FAILED'}")
    print("SENS-OK" if not bad else f"SENS-BAD {bad}")
    return 0 if not bad else 1


if __name__ == "__main__":
    sys.exit(main())
