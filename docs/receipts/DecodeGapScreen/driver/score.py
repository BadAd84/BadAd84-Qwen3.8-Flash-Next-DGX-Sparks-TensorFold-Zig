#!/usr/bin/env python3
"""score.py --root OUT - summarize DecodeGapScreen arms vs D0a/D0b controls and verify reply hashes."""
import argparse
import re
import statistics
import sys
from pathlib import Path

DEC = re.compile(r"^DEC \S+ C=(\d+) (\w+) pass(\d+): per-stream med ([\d.]+) min ([\d.]+) agg ([\d.]+) "
                 r"tok/wall ([\d.]+) tokens (\d+) rounds (\d+) drafted (\d+) accepted (\d+)")
ARMS = ("D0a", "D1", "D2", "D3", "D4", "D5", "D6", "D0b")
LABELS = {
    "D0a": "control-start",
    "D1": "ATTN_LANES=1",
    "D2": "DECODE_GRAPH=1",
    "D3": "READOUT_FUSE=1",
    "D4": "QMMF_HALF_BELOW=0",
    "D5": "SHARED_SIDE=0",
    "D6": "MTP_WEIGHTS=bf16",
    "D0b": "control-end",
}


def parse_dec(path: Path):
    if not path.exists():
        return None
    out = {"prose": [], "code": [], "toks": []}
    for line in path.read_text(errors="replace").splitlines():
        if line.startswith("TOK "):
            out["toks"].append(line.split(": ", 1)[1].strip())
        m = DEC.match(line)
        if m:
            kind = m.group(2)
            out.setdefault(kind, []).append(float(m.group(6)))
    return out


def med(xs):
    return statistics.median(xs) if xs else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    args = ap.parse_args()
    root = Path(args.root)
    for c in (8, 1):
        rows = {}
        for arm in ARMS:
            d = parse_dec(root / arm / f"c{c}" / "dec.log")
            if d:
                rows[arm] = d
        if not rows:
            continue
        c0 = rows.get("D0a")
        c0_p = med(c0["prose"]) if c0 else None
        c0_c = med(c0["code"]) if c0 else None
        print(f"## Level C={c}\n")
        print("| arm | lever | prose agg | vs D0a | code agg | vs D0a | hashes vs D0a |")
        print("|---|---|---:|---:|---:|---:|---|")
        for arm in ARMS:
            d = rows.get(arm)
            if not d:
                continue
            pr, co = med(d["prose"]), med(d["code"])
            prs = f"{pr:.1f}" if pr is not None else "-"
            cos = f"{co:.1f}" if co is not None else "-"
            rp = f"{pr / c0_p:.3f}" if (pr and c0_p) else "-"
            rc = f"{co / c0_c:.3f}" if (co and c0_c) else "-"
            if c0 and len(c0["toks"]) == len(d["toks"]) and c0["toks"]:
                eq = sum(a == b for a, b in zip(c0["toks"], d["toks"]))
                hs = f"{eq}/{len(c0['toks'])}"
            else:
                hs = "-"
            print(f"| {arm} | {LABELS[arm]} | {prs} | {rp} | {cos} | {rc} | {hs} |")
        print()


if __name__ == "__main__":
    sys.exit(main())
