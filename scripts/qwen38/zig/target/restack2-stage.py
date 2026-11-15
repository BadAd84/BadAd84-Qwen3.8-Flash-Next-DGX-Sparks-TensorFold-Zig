#!/usr/bin/env python3
"""stage.py - the package's patches as stage trees in work/fix0004/seq (a worktree of work/upmain at the base).

  stage.py check               apply 0001-0019 in order, record each stage's tree in trees.json, and prove that
                               `git diff` between consecutive trees reproduces every package file byte for byte
  stage.py at N                leave the worktree and index at stage N (0 = the base)
  stage.py build N OUT [-S P]  take the worktree as it stands as stage N (its changed paths staged by name), then
                               apply the package's later patches in order, skipping every P given with -S, each plain
                               first and with --3way if that fails; stops at a conflict and records progress in
                               OUT/progress.json
  stage.py resume OUT          after a conflict is resolved by hand: stage the resolved paths, record the tree, go on
  stage.py cut OUT             write OUT's series: each patch the diff between consecutive recorded trees

No commit is made: stage trees are `git write-tree` objects, so the base tree is never edited in place.
"""
# Scratch it works in: work/fix0004 (seq = a worktree of work/upmain at the base; trees.json, the series dirs).
import json
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]
PKG = REPO / "patches" / "main-964174ea05"
SEQ = REPO / "work" / "fix0004" / "seq"
TREES = REPO / "work" / "fix0004" / "trees.json"
BASE = "964174ea05879e6dde1de1198a3aae3ef8b46a3b"


def git(*args, check=True):
    r = subprocess.run(["git", *args], cwd=str(SEQ), capture_output=True)
    if check and r.returncode != 0:
        raise SystemExit(f"git {' '.join(args)}: {r.stderr.decode(errors='replace')}")
    return r


def out_of(r):
    return r.stdout.decode(errors="replace")


def names():
    return sorted(p.name for p in PKG.glob("[0-9][0-9][0-9][0-9]-*.patch"))


def reset_to(tree):
    git("read-tree", "--reset", "-u", tree)
    git("clean", "-fdq")


def snap():
    """The worktree as a tree: every changed, removed or new path staged by name."""
    paths = set(out_of(git("diff", "--name-only")).split())
    paths |= set(out_of(git("ls-files", "--others", "--exclude-standard")).split())
    for p in sorted(paths):
        git("add", "--", p)
    return out_of(git("write-tree")).strip()


def diff(a, b):
    return git("diff", "--no-color", a, b).stdout


def check():
    base_tree = out_of(git("rev-parse", BASE + "^{tree}")).strip()
    reset_to(base_tree)
    trees = [base_tree]
    for n in names():
        git("apply", "--index", "--whitespace=nowarn", str(PKG / n))
        trees.append(out_of(git("write-tree")).strip())
    bad = 0
    for i, n in enumerate(names(), 1):
        if diff(trees[i - 1], trees[i]) != (PKG / n).read_bytes():
            print(f"{n}: the stage diff differs from the package file")
            bad += 1
    TREES.write_text(json.dumps(trees, indent=1) + "\n", encoding="utf-8")
    print(f"{len(names())} stages, {bad} differ; trees in {TREES.name}")
    return 1 if bad else 0


def at(n):
    trees = json.loads(TREES.read_text(encoding="utf-8"))
    reset_to(trees[n])
    print(f"worktree at stage {n}: {trees[n]}")
    return 0


def run(out, prog):
    """Apply prog['todo'] in order onto the worktree, recording a tree after each."""
    while prog["todo"]:
        name = prog["todo"][0]
        r = git("apply", "--index", "--whitespace=nowarn", str(PKG / name), check=False)
        how = "plain"
        if r.returncode != 0:
            r = git("apply", "--index", "--3way", "--whitespace=nowarn", str(PKG / name), check=False)
            how = "3way"
            if r.returncode != 0:
                (out / "progress.json").write_text(json.dumps(prog, indent=1) + "\n", encoding="utf-8")
                print(f"{name}: conflict ({how}); resolve in {SEQ} and run `stage.py resume {out}`")
                print(r.stderr.decode(errors="replace"))
                return 1
        prog["series"].append([name, snap(), how])
        prog["todo"].pop(0)
        print(f"{name}: applied ({how})")
    (out / "progress.json").write_text(json.dumps(prog, indent=1) + "\n", encoding="utf-8")
    print("all applied")
    return 0


def build(n, out, skip):
    trees = json.loads(TREES.read_text(encoding="utf-8"))
    out = Path(out).resolve()
    out.mkdir(parents=True, exist_ok=True)
    prog = {"base": trees[0], "series": [[name, trees[i], "package"] for i, name in enumerate(names()[: n - 1], 1)],
            "todo": [x for x in names()[n:] if x not in skip]}
    prog["series"].append([names()[n - 1], snap(), "worktree"])
    return run(out, prog)


def resume(out):
    out = Path(out).resolve()
    prog = json.loads((out / "progress.json").read_text(encoding="utf-8"))
    name = prog["todo"].pop(0)
    prog["series"].append([name, snap(), "resolved"])
    print(f"{name}: recorded as resolved by hand")
    return run(out, prog)


def cut(out):
    out = Path(out).resolve()
    prog = json.loads((out / "progress.json").read_text(encoding="utf-8"))
    if prog["todo"]:
        raise SystemExit(f"{len(prog['todo'])} patches still to apply")
    prev = prog["base"]
    for name, tree, how in prog["series"]:
        d = diff(prev, tree)
        (out / name).write_bytes(d)
        pkg = PKG / name
        same = pkg.exists() and d == pkg.read_bytes()
        print(f"{name}: {len(d.splitlines())} lines ({how}), {'identical to' if same else 'differs from'} the package")
        prev = tree
    return 0


def main(argv):
    if len(argv) == 2 and argv[1] == "check":
        return check()
    if len(argv) == 3 and argv[1] == "at":
        return at(int(argv[2]))
    if len(argv) >= 4 and argv[1] == "build":
        skip = [argv[i + 1] for i in range(4, len(argv) - 1) if argv[i] == "-S"]
        return build(int(argv[2]), argv[3], skip)
    if len(argv) == 3 and argv[1] == "resume":
        return resume(argv[2])
    if len(argv) == 3 and argv[1] == "cut":
        return cut(argv[2])
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
