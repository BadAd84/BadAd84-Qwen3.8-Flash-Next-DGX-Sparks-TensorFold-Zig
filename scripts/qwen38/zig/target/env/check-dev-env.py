#!/usr/bin/env python3
"""Fail when a setting in dev.env has no citation behind it.

Every `export NAME=value` line states a setting, and so does either presence form: `unset NAME` states
a default that only absence gives, and must carry the read site that tests presence. Each one must be
preceded within eight lines by a comment citing a `work/` or `docs/` path. A comment naming the name
itself is not enough: the citation has to be a file that holds the measurement, or, in the explicit
defaults section, the read site whose default the line states. A valueless `export NAME` is not a
setting at all and is refused by check-env-coverage.py (NO-VALUE).
"""
import re
import sys
from pathlib import Path

PATH = Path(__file__).with_name("dev.env")
CITE = re.compile(r"(work/[A-Za-z0-9_./-]+|docs/[A-Za-z0-9_./-]+|scripts/[A-Za-z0-9_./-]+)")
EXPORT = re.compile(r"^(?:export ([A-Z0-9_]+)(?:=|$)|unset ([A-Z0-9_]+)$)")


def main() -> int:
    lines = PATH.read_text(encoding="utf-8").splitlines()
    bad = []
    for i, line in enumerate(lines):
        m = EXPORT.match(line)
        if not m:
            continue
        window = lines[max(0, i - 8):i]
        if not any(CITE.search(w) and not w.startswith("#!") for w in window):
            bad.append(f"{PATH.name}:{i + 1}: {m.group(1) or m.group(2)} has no cited measurement in the eight lines above it")
    for b in bad:
        print(b)
    print(f"dev-env: {len(bad)} setting(s) without a citation")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
