#!/usr/bin/env python3
"""Refresh env/register.env against the engine's own settings table.

Run at every re-seat, pointing --table at the new tree's `zig/src/platform/environment.zig`.
It keeps every existing verdict line as written, and appends a `debt` line for each setting the
table now has that dev.env does not export and the register does not name. That is what turns a
new upstream knob into a visible entry instead of a silently inherited default; the coverage gate
then fails if anyone skips the step.
"""
import argparse
import re
import subprocess
from pathlib import Path

SCOPES = ("flashnext", "cuda", "common")
ROW = re.compile(r'\.\{ \.name = "([A-Z0-9_]+)", \.scope = \.(\w+), \.kind = \.(\w+), \.forms = "([^"]*)"')
EXPORT = re.compile(r"^export ([A-Z0-9_]+)=")
VERDICT = re.compile(r"^#\s*(default-ok|debt|unreachable)\s+([A-Z0-9_]+)\s*:")


def main() -> int:
    here = Path(__file__).resolve().parent
    ap = argparse.ArgumentParser()
    ap.add_argument("--table", required=True)
    ap.add_argument("--dev", default=str(here / "dev.env"))
    ap.add_argument("--register", default=str(here / "register.env"))
    ap.add_argument("--evidence", default="docs/ENV-REGISTER.md")
    args = ap.parse_args()

    text = Path(args.table).read_text(encoding="utf-8")
    rows = [(n, s, f or k) for n, s, k, f in ROW.findall(text) if s in SCOPES]
    carried = {m.group(1) for m in (EXPORT.match(l) for l in Path(args.dev).read_text(encoding="utf-8").splitlines()) if m}

    reg = Path(args.register)
    old = reg.read_text(encoding="utf-8").splitlines() if reg.exists() else []
    known = {m.group(2) for m in (VERDICT.match(l) for l in old) if m}
    root = Path(args.table).resolve().parent
    while root != root.parent and not (root / ".git").exists():
        root = root.parent
    sha = subprocess.run(["git", "-C", str(root), "rev-parse", "HEAD"],
                         capture_output=True, text=True).stdout.strip() or "unknown"

    added = []
    for name, scope, forms in rows:
        if name in carried or name in known:
            continue
        added.append(f"# debt {name}: new in the table at {sha[:9]}, not measured on our stack; forms {forms};"
                     f" evidence {args.evidence}")
        known.add(name)

    header = (f"# ENV REGISTER: a verdict for every setting the Flash Next serve reads, from the engine's own table.\n"
              f"# One line per setting that dev.env does not export: default-ok (with its measurement),\n"
              f"# debt (explicit and counted, to be measured) or unreachable (with the reason).\n"
              f"# check-env-coverage.py fails on any setting with no line and on any line with no setting.\n")
    body = [l for l in old if not l.startswith("# ENV REGISTER")]
    out = "\n".join([header] + [l for l in body if l.startswith("#") is False or True]) + "\n"
    if added:
        out += "\n# Added by update-env-register.py against %s.\n" % sha[:9] + "\n".join(added) + "\n"
    reg.write_text(out, encoding="utf-8")
    print(f"register: {len(rows)} settings in scope, {len(carried)} carried in dev.env, {len(known)} verdicts, {len(added)} added as debt")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
