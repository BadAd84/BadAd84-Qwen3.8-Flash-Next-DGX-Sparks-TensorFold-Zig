#!/usr/bin/env python3
"""Fail when any setting the served engine reads is not SET in our env.

The rule (owner, 2026-11-23): no setting may be unset. The engine's own table is the authoritative list
of settings: every rule whose scope this serve reads. Each one must be set in the launcher env, at the
value we chose; choosing the engine default means writing that default out with its citation, never
leaving the variable absent.

  carried   an `export NAME=value` line in the launcher env, or an `export NAME` line with no value
            where the reader tests the variable's PRESENCE, so only an unset variable states the
            default (TF_ROCE_GID_INDEX and TENSORFOLD_CUDA_KERNELS today, whose read sites are quoted
            on the line). The citation checker requires an evidence path above every one of them.
  absent    nothing at all: SILENT, the failure this gate exists for, because an upstream default then
            takes effect with nobody having looked at it.

A `# default-ok|debt|unreachable NAME:` line in the register is an ANNOTATION on a value that is set,
never a substitute for setting it (VERDICT-ONLY fails). A `# missing NAME=` worklist line is temporary:
each is moved into the launcher env with its citation and deleted here, and the gate fails while one
remains (WORKLIST). A verdict line naming a setting the table no longer has is STALE and also fails, so
the register cannot rot into a list of things that no longer exist.

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
MISSING = re.compile(r"^#\s*missing\s+([A-Z0-9_]+)=(.*)$")
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
    ap.add_argument("--carried-pattern", default=r"^export ([A-Z0-9_]+)(?:=|$)",
                    help="regex with one group naming a setting the launcher env sets, with a value or as a "
                         "no-value statement where only absence states the engine default")
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

    silent = sorted(n for n in rows if n not in carried)
    markers = []
    if Path(args.register).exists():
        for line in Path(args.register).read_text(encoding="utf-8").splitlines():
            m = MISSING.match(line)
            if m:
                markers.append(m.group(1))
    stale = sorted(n for n in verdicts if n not in rows)
    for name in silent:
        scope, forms = rows[name]
        problems.append(f"MISSING {name} ({scope}, forms {forms}): not set in the env")
    for name in stale:
        problems.append(f"STALE {name}: register names a setting the table does not have")

    counts = {"set": 0, "annotated": 0}
    for name in rows:
        if name in carried:
            counts["set"] += 1
            if name in verdicts:
                counts["annotated"] += 1
    verdict_only = sorted(n for n in verdicts if n in rows and n not in carried)
    for name in verdict_only:
        problems.append(f"VERDICT-ONLY {name}: a note in the register is not a setting; write the value in the env")
    for name in markers:
        problems.append(f"WORKLIST {name}: the register still lists it as missing; move it into the env")
    served_unknown = sorted(n for n in carried if SERVE_NAMES.match(n) and n not in rows)
    if served_unknown and args.strict_carried:
        for name in served_unknown:
            problems.append(f"UNREAD {name}: the launcher sets it and this tree's table does not have it")
    elif served_unknown:
        print("carried but not in this table (series-added or other-engine settings; confirm each has a reader "
              "in the tree you serve): " + ", ".join(served_unknown))

    print("coverage: %d settings in scope, set %d, missing %d, annotations %d, worklist markers %d"
          % (len(rows), counts["set"], len(silent), counts["annotated"], len(markers)))
    for p in problems:
        print(p)
    return 1 if problems or silent else 0


if __name__ == "__main__":
    sys.exit(main())
