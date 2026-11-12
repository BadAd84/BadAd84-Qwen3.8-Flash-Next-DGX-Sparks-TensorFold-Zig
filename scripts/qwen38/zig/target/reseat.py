#!/usr/bin/env python3
"""reseat.py TREE OUT [RESOLVERS_DIR] - re-seat patches/1.2.6 on the TensorFold commit checked out in TREE.

One patch at a time, in order:
  1. `git apply --3way` of the patch without CHANGELOG.md;
  2. RESOLVERS_DIR/resolve_NNNN.py TREE, when there is one (a hand-written resolution of that patch's conflicts on
     this base, each edit asserted);
  3. it stops, listing the files, if a conflict is left;
  4. the changelog: our bullets up to this patch (what the first N patches add to the OLD base's CHANGELOG.md) go
     under `## Unreleased` at the top of the NEW base's file, so no patch ever conflicts there again;
  5. the new patch N is the exact difference between the staged trees before and after.
OUT gets NNNN-<lever>.patch for the new base. TREE must be a clean worktree of a repository that also holds the old
base commit (its objects are needed for the three-way applies and the old changelog).
"""
from __future__ import annotations

import difflib
import glob
import os
import subprocess
import sys

OLD_BASE = "6e9af930261a88bb28ac0bfb157ce8e57e9eea07"
REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))))
SERIES = os.path.join(REPO, "patches", "1.2.6")


def git(tree: str, *args: str, env: dict | None = None, check: bool = True, data: bytes | None = None) -> str:
    r = subprocess.run(["git", *args], cwd=tree, capture_output=True, env={**os.environ, **(env or {})}, input=data)
    if check and r.returncode != 0:
        raise SystemExit(f"git {' '.join(args)}: {r.stderr.decode(errors='replace')[:2000]}")
    return r.stdout.decode(errors="replace")


def old_changelog(tree: str, patches: list[str], n: int) -> list[str]:
    """CHANGELOG.md of the old base with the first n patches applied (a scratch index; nothing is checked out)."""
    idx = os.path.join(git(tree, "rev-parse", "--absolute-git-dir").strip(), "reseat-old.index")
    env = {"GIT_INDEX_FILE": idx}
    if os.path.exists(idx):
        os.remove(idx)
    git(tree, "read-tree", OLD_BASE, env=env)
    for p in patches[:n]:
        git(tree, "apply", "--cached", "--whitespace=nowarn", p, env=env)
    text = git(tree, "show", ":CHANGELOG.md", env=env)
    os.remove(idx)
    return text.replace("\r\n", "\n").split("\n")


def our_bullets(base: list[str], now: list[str]) -> list[str]:
    out = []
    for line in difflib.ndiff(base, now):
        if line.startswith("+ ") and line[2:].strip() and not line[2:].startswith("## "):
            out.append(line[2:])
    return out


def write_changelog(tree: str, new_base_text: str, bullets: list[str]) -> None:
    eol = "\r\n" if "\r\n" in new_base_text else "\n"
    lines = new_base_text.replace("\r\n", "\n").split("\n")
    first = next(i for i, line in enumerate(lines) if line.startswith("## "))
    block: list[str] = []
    if lines[first].strip() != "## Unreleased":
        block += ["## Unreleased", ""]
        at = first
    else:
        at = first + 2
    for b in bullets:
        block += [b, ""]
    lines[at:at] = block
    with open(os.path.join(tree, "CHANGELOG.md"), "w", encoding="utf-8", newline="") as f:
        f.write(eol.join(lines))


def main() -> int:
    tree, out = sys.argv[1], sys.argv[2]
    resolvers = sys.argv[3] if len(sys.argv) > 3 else ""
    patches = sorted(glob.glob(os.path.join(SERIES, "[0-9]*.patch")))
    os.makedirs(out, exist_ok=True)
    for old in glob.glob(os.path.join(out, "[0-9]*.patch")):
        os.remove(old)
    if git(tree, "status", "--porcelain").strip():
        raise SystemExit(f"{tree} is not clean")
    head = git(tree, "rev-parse", "HEAD").strip()
    new_base_changelog = git(tree, "show", "HEAD:CHANGELOG.md")
    old_base_changelog = old_changelog(tree, patches, 0)
    prev = git(tree, "rev-parse", "HEAD^{tree}").strip()
    for n, p in enumerate(patches, 1):
        name = os.path.basename(p)
        r = subprocess.run(["git", "apply", "--3way", "--exclude=CHANGELOG.md", "--whitespace=nowarn", p], cwd=tree, capture_output=True)
        log = r.stderr.decode(errors="replace")
        three = log.count("Falling back to 3-way merge") + log.count("Performing three-way merge")
        res = os.path.join(resolvers, f"resolve_{name[:4]}.py") if resolvers else ""
        resolved = ""
        if res and os.path.exists(res):
            rr = subprocess.run([sys.executable, res, tree], capture_output=True, text=True)
            if rr.returncode != 0:
                raise SystemExit(f"{name}: resolver failed: {rr.stdout[-800:]}{rr.stderr[-1500:]}")
            resolved = "; " + rr.stdout.strip().split("\n")[-1]
            for f in git(tree, "diff", "--name-only", "--diff-filter=U").split():
                text = open(os.path.join(tree, f), encoding="utf-8", errors="replace").read()
                if "<<<<<<< " not in text and ">>>>>>> " not in text:
                    git(tree, "add", "--", f)
        left = git(tree, "diff", "--name-only", "--diff-filter=U").split()
        if left:
            print(f"{name}: STOPS on {head[:9]}: conflicts left in {' '.join(left)}")
            return 3
        if r.returncode != 0 and not resolved:
            print(f"{name}: STOPS on {head[:9]}: {log.strip()[:600]}")
            return 3
        write_changelog(tree, new_base_changelog, our_bullets(old_base_changelog, old_changelog(tree, patches, n)))
        others = [f for f in git(tree, "ls-files", "--others", "--exclude-standard", "-z").split("\0") if f]
        if others:
            git(tree, "add", "--", *others)
        git(tree, "add", "-u")
        now = git(tree, "write-tree").strip()
        diff = subprocess.run(["git", "diff", "--binary", prev, now], cwd=tree, capture_output=True).stdout
        with open(os.path.join(out, name), "wb") as f:
            f.write(diff)
        print(f"{name}: seated ({three} files by three-way{resolved})")
        prev = now
    print(f"reseat: {len(patches)} patches seated on {head[:9]}, tree {prev}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
