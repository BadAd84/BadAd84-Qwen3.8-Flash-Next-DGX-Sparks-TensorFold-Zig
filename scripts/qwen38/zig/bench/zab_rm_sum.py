#!/usr/bin/env python3
"""zab_rm_sum.py LOG: zab_rm.sh's arms side by side, ours against base.

Golden: each arm's zgold_cmp.py verdict (every golden reply byte-identical to the reference file: N/N, exit 0);
boot: zab_rm.sh's BOOT ... FAILED lines; effort: effort_check.py's verdict (the server honoured RigMark's extra body);
TTFT: ttft.py's section (cold 1k-120k thinking off / on, the warm turn, idle and with 3 streams decoding; ours
against base); RigMark: rigmark_sum.py's section from the RIGMARK lines. An arm that ran (any of its lines is in the
log) must have a golden verdict. Exit 1 on any golden DIFF or missing verdict, boot failure, effort failure, TTFT
probe error or RigMark error."""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ttft  # noqa: E402  (beside this script, in the repo and in ~/work/bench on spark6)
import rigmark_sum  # noqa: E402  (beside this script too)

ARMS = ("base", "ours")
TAGS = ("BOOT", "GOLD", "SHAPE", "TTFT", "EFFORT", "RIGMARK")


def golden(lines):
    """({arm: (same, total, exit code or None)}, set of arms that ran, [errors]) from the log."""
    gold: dict = {}
    ran: set = set()
    errors: list = []
    for line in lines:
        p = line.rstrip("\n").split(None, 2)
        if len(p) >= 2 and p[0] in TAGS:
            ran.add(p[1])
        if len(p) < 3:
            continue
        tag, arm, rest = p
        if tag == "BOOT" and rest.startswith("FAILED"):
            errors.append(f"boot {arm}: {rest}")
        elif tag == "GOLD":
            m = re.search(r": (\d+)/(\d+) identical to ", rest)
            same, total, rc = gold.get(arm, (None, None, None))
            if m:
                same, total = int(m[1]), int(m[2])
            e = re.fullmatch(r"exit (\d+)", rest.strip())
            if e:
                rc = int(e[1])
            gold[arm] = (same, total, rc)
        elif tag == "EFFORT":
            if rest.startswith("effort FAILED"):
                errors.append(f"effort {arm}: {rest}")
            e = re.fullmatch(r"exit (\d+)", rest.strip())
            if e and e[1] != "0":
                errors.append(f"effort {arm}: effort_check.py exit {e[1]}")
    return gold, ran, errors


def order_of(groups):
    return sorted(groups, key=lambda g: (g not in ARMS, ARMS.index(g) if g in ARMS else 0, g))


def main() -> int:
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    with open(sys.argv[1], errors="replace") as f:
        lines = f.readlines()
    start = next((ln.strip() for ln in lines if " ZABRM " in ln and " START: " in ln), None)
    if start:
        print(start)
    gold, ran, errors = golden(lines)
    bad = len(errors)
    for arm in order_of(ran):
        same, total, rc = gold.get(arm, (None, None, None))
        if same is None or rc is None:
            print(f"golden {arm}: NO VERDICT")
            bad += 1
        elif same == total and total > 0 and rc == 0:
            print(f"golden {arm}: {same}/{total} MATCH")
        else:
            print(f"golden {arm}: {same}/{total} DIFF (zgold_cmp.py exit {rc})")
            bad += 1
    for e in errors:
        print(f"ERROR {e}")
    samples, t_errors, excluded, order = ttft.collect(lines)
    groups = order_of(order)
    ref = "base" if "base" in groups else (groups[0] if groups else None)
    print("\n".join(ttft.section(samples, t_errors, excluded, groups, ref=ref)))
    found, r_errors, r_order = rigmark_sum.collect(lines)
    r_groups = order_of(r_order)
    rm_lines, rm_bad = rigmark_sum.section(found, r_errors, r_groups,
                                           ref="base" if "base" in r_groups else None)
    print("\n".join(rm_lines))
    return 1 if bad or t_errors or rm_bad else 0


if __name__ == "__main__":
    sys.exit(main())
