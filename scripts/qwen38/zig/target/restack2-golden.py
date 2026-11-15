#!/usr/bin/env python3
"""restack2-golden.py REF CELL... - each cell's golden replies (qf_harness.py golden's zgold.json) against REF's.

A reply is equal when its text sha and its token sha256 are; prints `N/6 identical` a cell, and the differing ids.
"""
import json
import sys


def key(path):
    rows = json.load(open(path))
    return {(r.get("id"), r.get("prompt")): (r.get("sha"), r.get("token_sha256")) for r in rows}


def main(argv):
    ref = key(argv[1])
    bad = 0
    for cell in argv[2:]:
        got = key(cell)
        same = [k for k in ref if got.get(k) == ref[k]]
        diff = [str(k[0]) for k in ref if got.get(k) != ref[k]]
        if len(same) != len(ref) or len(got) != len(ref):
            bad += 1
        print(f"{cell}: {len(same)}/{len(ref)} identical{'' if not diff else ' (differ: ' + ', '.join(diff) + ')'}")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
