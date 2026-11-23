#!/usr/bin/env python3
"""Refresh the env register against the engine's own settings table.

Run at every re-seat, pointing --table at the new tree's `zig/src/platform/environment.zig`. It keeps
every existing annotation as written, and appends a temporary `# missing NAME=<default>` worklist line
for each setting the table now has that the launcher env does not set and the register does not
already name. The worklist is what turns a new upstream knob into a visible entry instead of a silently
inherited default; the coverage gate then fails until each line is moved into the launcher env, with its
citation, and deleted here. The verdict classes are annotations on values that are set, never a
substitute for setting one.
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
    ap.add_argument("--absent-pattern", default=r"^unset ([A-Z0-9_]+)$",
                    help="the absence form: a presence-tested setting whose default no value can state")
    ap.add_argument("--evidence", default="docs/ENV-REGISTER.md")
    ap.add_argument("--source", default="", help="the tree label to record (default: the table's git sha)")
    ap.add_argument("--defaults-from-tree", default="", help="a tree whose zig/src read sites supply each setting's literal default")
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
    absent_re = re.compile(args.absent_pattern)
    carried = set()
    for line in Path(args.dev).read_text(encoding="utf-8").splitlines():
        m = carried_re.search(line) or absent_re.search(line)
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

    defaults = {}
    if args.defaults_from_tree:
        import re as _re
        pat = _re.compile(r'environment\.read\(\s*[A-Za-z0-9_?.]+\s*,\s*"([A-Z0-9_]+)"\s*,\s*([^)]+)\)')
        for f in Path(args.defaults_from_tree, "zig", "src").rglob("*.zig"):
            txt = f.read_text(encoding="utf-8", errors="replace")
            for m in pat.finditer(txt):
                where = str(f).replace("\\", "/").split("zig/src/")[-1]
                defaults.setdefault(m.group(1), (m.group(2).strip(), where))

    added = []
    for name, scope, forms in rows:
        if name in carried or name in known:
            continue
        if name in defaults:
            value, where = defaults[name]
            if value == "null":
                added.append(f"# missing {name}=presence  # the reader tests the variable's presence: state `unset {name}`"
                             f" when nothing else supplies it, else the value that realises the default; read at"
                             f" {where}; forms {forms}")
            else:
                how = ("literal" if value in ("true", "false") or value.replace("-", "").isdigit()
                       else "expression: " + value)
                added.append(f"# missing {name}={value}  # {how}, read at {where}; forms {forms}")
        else:
            added.append(f"# missing {name}=???  # no literal default found in the tree; forms {forms}")
        known.add(name)

    header = (f"# {HEADER}: annotations on settings dev.env sets, never a substitute for setting one.\n"
              f"# The rule (owner, 2026-11-23): no setting may be unset. Every setting the served table has is set in\n"
              f"# dev.env at a stated value, and choosing the engine default means writing that default out with its\n"
              f"# read site. A rebase that adds a row fails check-env-coverage.py until its value is written in dev.env\n"
              f"# and the worklist line this script added is deleted. A `# missing NAME=` line is temporary work,\n"
              f"# never a resting state; a `# default-ok|debt|unreachable NAME:` line annotates a value that is already\n"
              f"# set and must cite its evidence. A `# image-baked NAME=value:` line records that the served image's own\n"
              f"# ENV carries the name, which forbids the `unset` form: the container always has a value.\n")
    # Drop the old header as one contiguous comment block: matching its first line alone left its own
    # continuation lines in the body, so they accumulated one re-seat at a time. An annotation line ends
    # the block even when someone writes it straight under the header.
    body = list(old)
    for i, line in enumerate(body):
        if line.startswith(f"# {HEADER}"):
            end = i
            while end < len(body) and body[end].startswith("#") and not VERDICT.match(body[end]):
                end += 1
            body = body[:i] + body[end:]
            break
    while body and body[0].strip() == "":
        body.pop(0)
    out = "\n".join([header] + body) + "\n"
    if added:
        out += "\n# Added by update-env-register.py against %s.\n" % sha[:9] + "\n".join(added) + "\n"
    reg.write_text(out, encoding="utf-8", newline="\n")  # LF on every OS: the boxes source this file
    print(f"register: {len(rows)} settings in scope, {len(carried)} carried in the launcher env, "
          f"{len(known)} verdicts, {len(added)} added to the worklist")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
