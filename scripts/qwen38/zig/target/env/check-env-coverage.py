#!/usr/bin/env python3
"""Fail when any setting the served engine reads has no verdict in our env.

The engine's own table (`zig/src/platform/environment.zig`) is the authoritative list of settings:
every rule with a scope the Flash Next serve reads (flashnext, cuda, common). A setting may be:

  carried        an `export NAME=` line in dev.env, which check-dev-env.py requires a measurement for;
  default-ok     a `# default-ok NAME:` line in register.env, with evidence;
  debt           a `# debt NAME:` line in register.env: explicit, counted, and to be measured;
  unreachable    a `# unreachable NAME:` line in register.env, with the reason and evidence.

A name with none of those is SILENT, which is the failure this gate exists for: an upstream default
inherited without anyone looking at it. A verdict line naming a setting the table no longer has is
STALE and also fails, so the register cannot rot into a list of things that no longer exist.
"""
import argparse
import re
import sys
from pathlib import Path

SCOPES = ("flashnext", "cuda", "common")
ROW = re.compile(r'\.\{ \.name = "([A-Z0-9_]+)", \.scope = \.(\w+), \.kind = \.(\w+), \.forms = "([^"]*)"')
EXPORT = re.compile(r"^export ([A-Z0-9_]+)=")
VERDICT = re.compile(r"^#\s*(default-ok|debt|unreachable)\s+([A-Z0-9_]+)\s*:\s*(.*)$")
CITE = re.compile(r"(work/[A-Za-z0-9_./-]+|docs/[A-Za-z0-9_./-]+|scripts/[A-Za-z0-9_./-]+)")


def table(path: Path) -> dict[str, tuple[str, str]]:
    text = path.read_text(encoding="utf-8")
    rows = {}
    for name, scope, kind, forms in ROW.findall(text):
        if scope in SCOPES:
            rows[name] = (scope, forms or kind)
    return rows


def outcomes(dev: Path, reg: Path) -> tuple[dict[str, str], dict[str, str], list[str]]:
    carried = {}
    for line in dev.read_text(encoding="utf-8").splitlines():
        m = EXPORT.match(line)
        if m:
            carried[m.group(1)] = line
    verdicts = {}
    problems = []
    if reg.exists():
        for line in reg.read_text(encoding="utf-8").splitlines():
            m = VERDICT.match(line)
            if not m:
                continue
            kind, name, rest = m.groups()
            if name in verdicts:
                problems.append(f"{reg.name}: {name} has two verdicts")
            if not CITE.search(rest):
                problems.append(f"{reg.name}: {name} ({kind}) cites no work/ or docs/ evidence")
            verdicts[name] = kind
    return carried, verdicts, problems


def main() -> int:
    here = Path(__file__).resolve().parent
    ap = argparse.ArgumentParser()
    ap.add_argument("--table", required=True, help="the engine's zig/src/platform/environment.zig to judge against")
    ap.add_argument("--dev", default=str(here / "dev.env"))
    ap.add_argument("--register", default=str(here / "register.env"))
    ap.add_argument("--strict-carried", action="store_true",
                    help="also fail when dev.env exports a setting this table does not have (run against the served tree)")
    args = ap.parse_args()

    rows = table(Path(args.table))
    if not rows:
        print(f"coverage: no settings parsed from {args.table}: the table format moved")
        return 2
    carried, verdicts, problems = outcomes(Path(args.dev), Path(args.register))

    silent = sorted(n for n in rows if n not in carried and n not in verdicts)
    stale = sorted(n for n in verdicts if n not in rows)
    if not verdicts:
        # An empty register is the state this gate is meant to forbid, not a pass.
        problems.append(f"{args.register} is missing or holds no verdict line")

    counts = {"carried": 0, "default-ok": 0, "debt": 0, "unreachable": 0, "silent": len(silent)}
    for name in rows:
        if name in carried:
            counts["carried"] += 1
        elif name in verdicts:
            counts[verdicts[name]] += 1

    for name in silent:
        scope, forms = rows[name]
        problems.append(f"SILENT {name} ({scope}, forms {forms}): neither exported nor given a verdict")
    for name in stale:
        problems.append(f"STALE {name}: register names a setting the table does not have")
    unknown_carried = sorted(n for n in carried if n not in rows)
    if unknown_carried and args.strict_carried:
        for name in unknown_carried:
            problems.append(f"UNREAD {name}: dev.env sets it and this tree's table does not have it")
    elif unknown_carried:
        print("carried but not in this table (series-added or production-engine-only; check each has a reader in the tree you serve): "
              + ", ".join(unknown_carried))

    print(
        "coverage: %d settings in scope, carried %d, default-ok %d, debt %d, unreachable %d, silent %d"
        % (len(rows), counts["carried"], counts["default-ok"], counts["debt"], counts["unreachable"], counts["silent"])
    )
    for p in problems:
        print(p)
    return 1 if problems or silent else 0


if __name__ == "__main__":
    sys.exit(main())
