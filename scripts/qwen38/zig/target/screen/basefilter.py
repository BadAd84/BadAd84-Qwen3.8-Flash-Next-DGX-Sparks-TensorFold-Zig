#!/usr/bin/env python3
"""basefilter.py SRC DST --passes REGEX [--report FILE]: the base the launcher can actually carry.

The recipe launcher builds its `-e` arguments from `env | grep -E '^(TENSORFOLD|TF_FLASHNEXT)_[A-Z0-9_]+='`
(start.sh), so a setting whose name the filter does not match never reaches the container, whatever the env
file says. The screen's base is therefore the committed env file as that filter carries it:

  carried      `export NAME=value` with NAME matching the filter: kept verbatim.
  not carried  `export NAME=value` with NAME failing the filter: written commented as
               `# NOT-CARRIED export NAME=value` (the citation above it stays in place, and an arm builder
               that looks for `^export NAME=` cannot find it, so no arm can be planned on it), and listed
               in the report with its value and line number.
  absence      `unset NAME` and `export NAME` with no value: kept. The container's absence satisfies them
               however the filter behaves, and check_env.py proves that absence on every boot.

DST starts with a comment naming SRC and its sha256, so the base in a boot record can be traced to the file
it came from. Prints `BASE-CARRIED n NOT-CARRIED m PASSES <regex>`. Exit 2 when SRC is missing, no line is
carried, or DST equals SRC.
"""
import argparse
import hashlib
import re
import sys
from pathlib import Path


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--passes", required=True, help="the launcher's own name filter")
    ap.add_argument("--report", default="", help="write `NAME<TAB>value<TAB>line` per not-carried line")
    args = ap.parse_args()
    src, dst = Path(args.src), Path(args.dst)
    if not src.is_file():
        print(f"BASE-SRC-MISSING {src}")
        return 2
    if src.resolve() == dst.resolve():
        print("BASE-DST-IS-SRC: refusing to rewrite the source in place")
        return 2
    text = src.read_text(encoding="utf-8")
    sha = hashlib.sha256(text.encode("utf-8")).hexdigest()
    keep = re.compile(args.passes)
    carried, dropped, out = 0, [], []
    for i, line in enumerate(text.splitlines(), start=1):
        m = re.match(r"^export ([A-Z0-9_]+)=", line)
        if m and not keep.search(m.group(1)):
            name = m.group(1)
            value = line.partition("=")[2]
            dropped.append((name, value, i))
            out.append(f"# NOT-CARRIED (the launcher's filter {args.passes} does not carry it): {line}")
            continue
        if m:
            carried += 1
        out.append(line)
    if carried == 0:
        print(f"BASE-NO-CARRIED: not one export line in {src} matches {args.passes}")
        return 2
    header = [f"# SCREEN BASE: {dst.name}, derived from {src} sha256 {sha}",
              f"# {carried} value lines the launcher filter {args.passes} carries are live; {len(dropped)} lines "
              f"it cannot carry are commented below and listed in the report.",
              "# The committed file remains the env of record; this file is what the screen can boot."]
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text("\n".join(header + out) + "\n", encoding="utf-8", newline="\n")
    if args.report:
        rep = Path(args.report)
        rep.parent.mkdir(parents=True, exist_ok=True)
        rep.write_text("".join(f"{n}\t{v}\tline {i}\n" for n, v, i in dropped), encoding="utf-8", newline="\n")
    print(f"BASE-CARRIED {carried} NOT-CARRIED {len(dropped)} PASSES {args.passes} SRC-SHA256 {sha}")
    for n, v, i in dropped:
        print(f"NOT-CARRIED {n}={v} line {i}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
