#!/usr/bin/env python3
"""Refresh the env register against the engine's own settings table.

Run at every re-seat, pointing --table at the new tree's `zig/src/platform/environment.zig`. It
keeps every existing verdict line as written, and appends a `debt` line for each setting the table
now has that the launcher env does not set and the register does not name. That is what turns a new
upstream knob into a visible entry instead of a silently inherited default; the coverage gate then
fails if anyone skips the step.
"""
import argparse
import re
import subprocess
from pathlib import Path

ROW = re.compile(r'\.\{ \.name = "([A-Z0-9_]+)"')  # a row starts here; fields are read independently
SCOPE = re.compile(r'\.scope = \.(\w+)')
KIND = re.compile(r'\.kind = \.(\w+)')
FORMS = re.compile(r'\.forms = "([^"]*)"')
VERDICT = re.compile(r"^#\s*(default-ok|debt|unreachable)\s+([A-Z0-9_]+)\s*:")
HEADER = "ENV REGISTER"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--table", required=True)
    ap.add_argument("--dev", required=True)
    ap.add_argument("--register", required=True)
    ap.add_argument("--scopes", required=True, help="comma list of the table scopes this serve reads")
    ap.add_argument("--carried-pattern", default=r"^export ([A-Z0-9_]+)=")
    ap.add_argument("--evidence", default="docs/ENV-REGISTER.md")
    ap.add_argument("--source", default="", help="the tree label to record (default: the table's git sha)")
    args = ap.parse_args()

    scopes = {s.strip() for s in args.scopes.split(",") if s.strip()}
    text = Path(args.table).read_text(encoding="utf-8")
    rows = []
    for line in text.splitlines():
        m = ROW.search(line)
        scope = SCOPE.search(line)
        if not m or not scope or scope.group(1) not in scopes:
            continue
        forms = FORMS.search(line)
        kind = KIND.search(line)
        rows.append((m.group(1), scope.group(1), (forms.group(1) if forms else (kind.group(1) if kind else "?")) or "?"))
    carried_re = re.compile(args.carried_pattern)
    carried = set()
    for line in Path(args.dev).read_text(encoding="utf-8").splitlines():
        m = carried_re.search(line)
        if m:
            carried.add(m.group(1))

    reg = Path(args.register)
    old = reg.read_text(encoding="utf-8").splitlines() if reg.exists() else []
    known = {m.group(2) for m in (VERDICT.match(l) for l in old) if m}
    root = Path(args.table).resolve().parent
    while root != root.parent and not (root / ".git").exists():
        root = root.parent
    sha = args.source or (subprocess.run(["git", "-C", str(root), "rev-parse", "HEAD"],
                                        capture_output=True, text=True).stdout.strip() or "unknown")

    added = []
    for name, scope, forms in rows:
        if name in carried or name in known:
            continue
        added.append(f"# debt {name}: new in the table at {sha[:9]}, not measured on this stack; forms {forms};"
                     f" evidence {args.evidence}")
        known.add(name)

    header = (f"# {HEADER}: a verdict for every setting this serve reads, from the engine's own table.\n"
              f"# One line per setting the launcher does not set: default-ok (with its measurement),\n"
              f"# debt (explicit and counted, to be measured) or unreachable (with the reason).\n"
              f"# check-env-coverage.py fails on any setting with no line and on any line with no setting.\n")
    body = [l for l in old if not l.startswith(f"# {HEADER}")]
    out = "\n".join([header] + body) + "\n"
    if added:
        out += "\n# Added by update-env-register.py against %s.\n" % sha[:9] + "\n".join(added) + "\n"
    reg.write_text(out, encoding="utf-8")
    print(f"register: {len(rows)} settings in scope, {len(carried)} carried in the launcher env, "
          f"{len(known)} verdicts, {len(added)} added as debt")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
