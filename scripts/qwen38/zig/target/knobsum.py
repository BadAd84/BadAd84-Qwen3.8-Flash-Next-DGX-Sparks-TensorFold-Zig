#!/usr/bin/env python3
"""knobsum.py [LOG] - the knob sweep as a delta table against the base arm.

Reads the DEC lines patcheval.sh prints (DEC pe-<arm>-c<C> C=<C> <kind> pass0: ... agg <x>), takes the base arm as the
reference, and prints per arm the four cells with their deltas. Verdicts are left to the reader: any cell below -2%
is a regression, which per the fleet rule is not a keep.
"""
from __future__ import annotations

import re
import sys

PAT = re.compile(r"DEC pe-([a-z0-9]+)-c([14]) C=[14] (\w+) pass0: per-stream med ([\d.]+) min [\d.]+ agg ([\d.]+)")


def main() -> None:
    path = sys.argv[1] if len(sys.argv) > 1 else "/home/adam/work/target/knob.log"
    rows: dict[str, dict] = {}
    for line in open(path, encoding="utf-8", errors="replace"):
        m = PAT.match(line)
        if not m:
            continue
        rows.setdefault(m[1], {}).setdefault(int(m[2]), {})[m[3]] = float(m[5])
    base = rows.get("base", {})
    print("| arm | C1 prose | C1 code | C4 prose | C4 code | dC1 code | dC4 code | dC1 prose | dC4 prose |")
    print("|---|---|---|---|---|---|---|---|---|")

    def delta(a, b):
        if not a or not b:
            return "-"
        return f"{(a / b - 1) * 100:+.1f}%"

    for arm in sorted(rows):
        c1, c4 = rows[arm].get(1, {}), rows[arm].get(4, {})
        b1, b4 = base.get(1, {}), base.get(4, {})
        print(
            f"| {arm} | {c1.get('prose', 0):.1f} | {c1.get('code', 0):.1f} | {c4.get('prose', 0):.1f} | "
            f"{c4.get('code', 0):.1f} | {delta(c1.get('code'), b1.get('code'))} | {delta(c4.get('code'), b4.get('code'))} | "
            f"{delta(c1.get('prose'), b1.get('prose'))} | {delta(c4.get('prose'), b4.get('prose'))} |"
        )


if __name__ == "__main__":
    main()
