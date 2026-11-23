#!/usr/bin/env python3
"""mkenv.py SRC NAME VALUE DST [--passes REGEX]: a copy of SRC with exactly one setting changed.

The old `export NAME=value` line must occur exactly once; its text is quoted as a comment above the new line
so no citation in the file is left describing a value the arm no longer holds. Exits 2 when the line is not
unique or absent, so a screen arm can never silently boot an unchanged environment. When --passes is given,
a NAME the launcher's filter cannot carry is refused here (exit 3) before anything is written: an arm on such
a name would boot a container without it and measure the control twice.
"""
import argparse
import hashlib
import re
import sys
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("name")
    ap.add_argument("value")
    ap.add_argument("dst")
    ap.add_argument("--passes", default="", help="the launcher's own name filter")
    args = ap.parse_args()
    src, name, value, dst = Path(args.src), args.name, args.value, Path(args.dst)
    if args.passes and not re.search(args.passes, name):
        print(f"MKENV-PASSAGE-REFUSED {name}: the launcher filter {args.passes} cannot carry it, so an arm on "
              f"it would measure the control twice")
        return 3
    text = src.read_text(encoding="utf-8").replace("\r\n", "\n")
    lines = text.splitlines()
    hits = [i for i, line in enumerate(lines) if line.startswith(f"export {name}=") or line == f"export {name}"]
    if len(hits) != 1:
        print(f"MKENV-REFUSED {name}: {len(hits)} export lines in {src}")
        return 2
    i = hits[0]
    old = lines[i]
    lines[i:i + 1] = [f"# SCREEN arm: was `{old}`; the citation above describes the committed value, not this arm.",
                      f"export {name}={value}"]
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    check = [line for line in dst.read_text(encoding="utf-8").splitlines() if line.startswith(f"export {name}=")]
    if check != [f"export {name}={value}"]:
        print(f"MKENV-VERIFY-FAILED {name}: {check}")
        return 4
    print(f"mkenv {dst}: {old} -> export {name}={value} src-sha256 "
          f"{hashlib.sha256(text.encode('utf-8')).hexdigest()}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
