#!/usr/bin/env python3
"""Fail when any setting the served engine reads has no verdict in our env.

The engine's own table is the authoritative list of settings: every rule whose scope this serve
reads. A setting may be:

  carried        set in the launcher env, which the citation checker already requires a measurement for;
  default-ok     a `# default-ok NAME:` line in the register, with evidence;
  debt           a `# debt NAME:` line: explicit, counted, and to be measured;
  unreachable    a `# unreachable NAME:` line, with the reason and evidence.

A name with none of those is SILENT, which is the failure this gate exists for: an upstream default
inherited without anyone looking at it. A verdict line naming a setting the table no longer has is
STALE and also fails, so the register cannot rot into a list of things that no longer exist.

Portable across the serve repos: the table path, the launcher env, the register, the scopes and the
launcher's carried-line shape are all arguments.
"""
import argparse
import re
import sys
from pathlib import Path

ROW = re.compile(r'\.\{ \.name = "([A-Z0-9_]+)"')  # a row starts here; fields are read independently
SCOPE = re.compile(r'\.scope = \.(\w+)')
KIND = re.compile(r'\.kind = \.(\w+)')
FORMS = re.compile(r'\.forms = "([^"]*)"')
VERDICT = re.compile(r"^#\s*(default-ok|debt|unreachable)\s+([A-Z0-9_]+)\s*:\s*(.*)$")
CITE = re.compile(r"(work/[A-Za-z0-9_./-]+|docs/[A-Za-z0-9_./-]+|int-docs/[A-Za-z0-9_./-]+|scripts/[A-Za-z0-9_./-]+)")
SERVE_NAMES = re.compile(r"^(TF_|TENSORFOLD_)")


def table(path: Path, scopes: set[str]) -> dict[str, tuple[str, str]]:
    """Read a row per line, field by field: optional fields (trim, no_word, ...) must not hide a setting."""
    rows = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        m = ROW.search(line)
        if not m:
            continue
        scope = SCOPE.search(line)
        if not scope or scope.group(1) not in scopes:
            continue
        forms = FORMS.search(line)
        kind = KIND.search(line)
        rows[m.group(1)] = (scope.group(1), (forms.group(1) if forms else (kind.group(1) if kind else "?")) or "?")
    return rows


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--table", required=True, help="the served tree's zig/src/platform/environment.zig")
    ap.add_argument("--dev", required=True, help="the launcher env that carries our settings")
    ap.add_argument("--register", required=True, help="the register env holding verdict lines")
    ap.add_argument("--scopes", required=True, help="comma list of the table scopes this serve reads")
    ap.add_argument("--carried-pattern", default=r"^export ([A-Z0-9_]+)=",
                    help="regex with one group naming a setting the launcher env sets")
    ap.add_argument("--strict-carried", action="store_true",
                    help="also fail when the launcher env sets a serve setting this table does not have")
    args = ap.parse_args()

    scopes = {s.strip() for s in args.scopes.split(",") if s.strip()}
    rows = table(Path(args.table), scopes)
    if not rows:
        print(f"coverage: no settings parsed from {args.table} for scopes {sorted(scopes)}: the table format or scopes moved")
        return 2

    carried_re = re.compile(args.carried_pattern)
    carried = {}
    for line in Path(args.dev).read_text(encoding="utf-8").splitlines():
        m = carried_re.search(line)
        if m:
            carried[m.group(1)] = line.strip()

    verdicts = {}
    problems = []
    reg = Path(args.register)
    if reg.exists():
        for line in reg.read_text(encoding="utf-8").splitlines():
            m = VERDICT.match(line)
            if not m:
                continue
            kind, name, rest = m.groups()
            if name in verdicts:
                problems.append(f"{reg.name}: {name} has two verdicts")
            if not CITE.search(rest):
                problems.append(f"{reg.name}: {name} ({kind}) cites no evidence path")
            verdicts[name] = kind
    else:
        problems.append(f"{args.register} does not exist")

    silent = sorted(n for n in rows if n not in carried and n not in verdicts)
    stale = sorted(n for n in verdicts if n not in rows)
    for name in silent:
        scope, forms = rows[name]
        problems.append(f"SILENT {name} ({scope}, forms {forms}): neither set nor given a verdict")
    for name in stale:
        problems.append(f"STALE {name}: register names a setting the table does not have")

    counts = {"carried": 0, "default-ok": 0, "debt": 0, "unreachable": 0}
    for name in rows:
        if name in carried:
            counts["carried"] += 1
        elif name in verdicts:
            counts[verdicts[name]] += 1
    served_unknown = sorted(n for n in carried if SERVE_NAMES.match(n) and n not in rows)
    if served_unknown and args.strict_carried:
        for name in served_unknown:
            problems.append(f"UNREAD {name}: the launcher sets it and this tree's table does not have it")
    elif served_unknown:
        print("carried but not in this table (series-added or other-engine settings; confirm each has a reader "
              "in the tree you serve): " + ", ".join(served_unknown))

    print("coverage: %d settings in scope, carried %d, default-ok %d, debt %d, unreachable %d, silent %d"
          % (len(rows), counts["carried"], counts["default-ok"], counts["debt"], counts["unreachable"], len(silent)))
    for p in problems:
        print(p)
    return 1 if problems or silent else 0


if __name__ == "__main__":
    sys.exit(main())
