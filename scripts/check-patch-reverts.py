#!/usr/bin/env python3
"""check-patch-reverts.py SERIES_DIR [--allow FILE] - a patch that silently takes back what the base or an earlier
patch of the series put there.

A ported patch cut against an older tree applies cleanly and compiles while deleting base lines it never meant to
touch (old 0022 dropped `self.pos0 = pos0` from Pass.chunk and the `prompt_last` store, and switched 0017's default
back). Three shapes are reported, per patch in filename order:

  undo      a line an EARLIER patch of the series added is removed and not put back by this patch
  restore   a line an EARLIER patch of the series removed is added again (a default flipped back)
  delete    a code line of the BASE is removed outright: no added line of the same change resembles it

Every finding must be listed in the allow file (default SERIES_DIR/REVERTS.allow) as
`NNNN|path|the stripped line|why it is right`; anything else fails. Blank lines, comment-only lines and files that
are not Zig, CUDA, C or Python source are not examined.
"""
from __future__ import annotations

import difflib
import glob
import os
import re
import sys

SOURCE = (".zig", ".cu", ".cuh", ".c", ".h", ".py", ".sh")
COMMENT = re.compile(r"^\s*(//|#|\*|/\*)")
RESEMBLES = 0.6


def blocks(patch_text: str):
    """(path, removed lines, added lines) for every run of changed lines of every file of a patch."""
    path = None
    rem: list[str] = []
    add: list[str] = []
    in_hunk = False
    for line in patch_text.split("\n"):
        if line.startswith("diff --git "):
            if rem or add:
                yield path, rem, add
                rem, add = [], []
            m = re.match(r"diff --git a/(.*) b/(.*)$", line)
            path = m.group(2) if m else None
            in_hunk = False
            continue
        if line.startswith("@@"):
            if rem or add:
                yield path, rem, add
                rem, add = [], []
            in_hunk = True
            continue
        if not in_hunk:
            continue
        if line.startswith("-") and not line.startswith("---"):
            if add and not rem:  # a new run starts after an added-only run
                yield path, rem, add
                rem, add = [], []
            rem.append(line[1:])
        elif line.startswith("+") and not line.startswith("+++"):
            add.append(line[1:])
        else:
            if rem or add:
                yield path, rem, add
                rem, add = [], []
    if rem or add:
        yield path, rem, add


def code(line: str) -> bool:
    s = line.strip()
    return bool(s) and not COMMENT.match(s) and s not in ("{", "}", "};", "},", ");", "} else {", "else {")


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    series = args[0]
    allow_path = os.path.join(series, "REVERTS.allow")
    if "--allow" in sys.argv:
        allow_path = sys.argv[sys.argv.index("--allow") + 1]
    allowed: set[tuple[str, str, str]] = set()
    if os.path.exists(allow_path):
        for raw in open(allow_path, encoding="utf-8"):
            parts = raw.rstrip("\n").split("|")
            if len(parts) >= 4 and not raw.startswith("#"):
                allowed.add((parts[0], parts[1], parts[2]))
    added_by: dict[tuple[str, str], str] = {}
    removed_by: dict[tuple[str, str], str] = {}
    findings: list[tuple[str, str, str, str, str]] = []
    patches = sorted(glob.glob(os.path.join(series, "*.patch")))
    for p in patches:
        num = os.path.basename(p).split("-", 1)[0]
        text = open(p, encoding="utf-8", errors="replace").read()
        per_file_added: dict[str, set[str]] = {}
        per_file_removed: dict[str, set[str]] = {}
        todo = []
        for path, rem, add in blocks(text):
            if path is None or not path.endswith(SOURCE):
                continue
            per_file_added.setdefault(path, set()).update(a.strip() for a in add)
            per_file_removed.setdefault(path, set()).update(r.strip() for r in rem)
            todo.append((path, rem, add))
        # a line the patch adds anywhere (the same file, or the file it moved to) is a move, not a removal
        moved: set[str] = set().union(*per_file_added.values()) if per_file_added else set()
        for path, rem, add in todo:
            for r in rem:
                s = r.strip()
                if not code(r) or s in moved:
                    continue
                if (path, s) in added_by:
                    findings.append((num, path, s, "undo", f"added by {added_by[(path, s)]}"))
                    continue
                best = max((difflib.SequenceMatcher(None, s, a.strip()).ratio() for a in add if code(a)), default=0.0)
                if best < RESEMBLES:
                    findings.append((num, path, s, "delete", "a base line, nothing added resembles it"))
            for a in add:
                s = a.strip()
                if code(a) and (path, s) in removed_by and s not in per_file_removed.get(path, set()):
                    findings.append((num, path, s, "restore", f"removed by {removed_by[(path, s)]}"))
        for path, lines in per_file_added.items():
            for s in lines:
                added_by.setdefault((path, s), num)
                removed_by.pop((path, s), None)
        for path, lines in per_file_removed.items():
            for s in lines:
                if s not in per_file_added.get(path, set()):
                    removed_by[(path, s)] = num
                    added_by.pop((path, s), None)
    open_ = [f for f in findings if (f[0], f[1], f[2]) not in allowed]
    for num, path, s, kind, why in open_:
        print(f"{num} {kind:8s} {path}: {s[:150]}   [{why}]")
    print(f"check-patch-reverts: {len(patches)} patches, {len(findings)} findings, {len(findings) - len(open_)} allowed, {len(open_)} open")
    return 1 if open_ else 0


if __name__ == "__main__":
    sys.exit(main())
