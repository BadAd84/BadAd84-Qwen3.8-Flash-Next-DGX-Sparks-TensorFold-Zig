#!/usr/bin/env python3
"""zab_rm_combine.py NAME=LOG:ARM ... [NAME=RECEIPT.json ...]: one table across sweeps, e.g. the Python stock and
production arms beside the Zig stock and OTS arms and RigMark's published card:

  zab_rm_combine.py py-stock=zabrm-py-stock.log:base py-ours=zabrm-py-ours.log:ours \\
      zig-stock=zabrm-m5-stock-1010.log:base zmerge5=zabrm-m5-stock-1010.log:ours \\
      vllm-card=~/rigmark/results/reference/qwen38-flash-next-nvidia-nvfp4-tp2-low.json

Each NAME=LOG:ARM takes that zab_rm.sh log's "TTFT <ARM> ..." and "RIGMARK <ARM> ..." lines as group NAME; each
NAME=RECEIPT.json is a RigMark receipt read with rigmark_sum.headline (RigMark only). The sections are ttft.section
and rigmark_sum.section (the same code as zab_rm_sum.py), the first NAME the reference. rigmark_sum's sweep check
reports receipts that are not one matched sweep (another comparison ID, protocol or RigMark revision: a published
card's receipt is) as RigMark ERROR lines: read them as labels of what differs. Exit 0 / 1 as those sections' errors."""
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rigmark_sum  # noqa: E402  (beside this script)
import ttft  # noqa: E402  (beside this script)


def lines_of(spec: str) -> tuple[str, list[str]]:
    name, _, src = spec.partition("=")
    if not name or not src:
        raise SystemExit(f"zab_rm_combine: {spec!r} is not NAME=LOG:ARM or NAME=RECEIPT.json")
    if src.endswith(".json"):
        with open(Path(src).expanduser()) as f:
            h = rigmark_sum.headline(json.load(f))
        return name, [f"RIGMARK {name} summary {json.dumps(h, sort_keys=True, separators=(',', ':'))}\n",
                      f"RIGMARK {name} exit 0\n"]
    log, _, arm = src.rpartition(":")
    out = []
    with open(Path(log).expanduser(), errors="replace") as f:
        for line in f:
            p = line.split(" ", 2)
            if len(p) == 3 and p[0] in ("TTFT", "RIGMARK") and p[1] == arm:
                out.append(f"{p[0]} {name} {p[2]}")
    if not out:
        raise SystemExit(f"zab_rm_combine: {log} has no TTFT / RIGMARK lines for arm {arm!r}")
    return name, out


def main() -> int:
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    names, lines = [], []
    for spec in sys.argv[1:]:
        name, got = lines_of(spec)
        names.append(name)
        lines += got
    samples, t_errors, excluded, order = ttft.collect(lines)
    groups = [n for n in names if n in order]
    print("\n".join(ttft.section(samples, t_errors, excluded, groups, ref=groups[0] if groups else None)))
    found, r_errors, r_order = rigmark_sum.collect(lines)
    r_groups = [n for n in names if n in r_order]
    rm_lines, rm_bad = rigmark_sum.section(found, r_errors, r_groups, ref=r_groups[0] if r_groups else None)
    print("\n".join(rm_lines))
    return 1 if t_errors or rm_bad else 0


if __name__ == "__main__":
    sys.exit(main())
