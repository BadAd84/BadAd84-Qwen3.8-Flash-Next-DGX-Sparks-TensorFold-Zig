#!/usr/bin/env python3
"""stageb.py SERIES OUT - the series without 0004 and 0012, cut patch by patch.

For every stage N of SERIES (a stage.py/fixlog.py output) the stage tree without 0004's and 0012's work is the
stage tree with those two patches reversed (`git apply -R --3way`, 0012 first once it is applied), the conflicts
resolved by dropping exactly the lines 0004 brought: its environment rules, its `cuda_ple_cache.zig` import, its
changelog bullets, and its eight knobs in `cuda_knobs.zig` (the file 0004 created; later patches add to it). Every
other patch of SERIES becomes the difference between consecutive such trees, under its own name.
"""
# Scratch it works in: work/fix0004 (seq = a worktree of work/upmain at the base; trees.json, the series dirs).
import json
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parents[4] / "work" / "fix0004"
SEQ = HERE / "seq"
GONE_RULES = ("TF_FLASHNEXT_GATHER_READ\"", "TF_FLASHNEXT_GATHER_THREADS\"", "TF_FLASHNEXT_GATHER_CACHE_MIB\"",
              "TF_FLASHNEXT_DRAFT_AHEAD\"", "TF_FLASHNEXT_PREFILL_TAIL\"", "TF_FLASHNEXT_GATHER_EARLY\"",
              "TF_FLASHNEXT_GATHER_LOG\"", "TF_FLASHNEXT_GATHER_LOCK_SCALES\"")
GONE_KNOBS = ("gatherRead", "gatherThreads", "gatherCacheMib", "draftAhead", "prefillTail", "gatherEarly",
              "gatherLog", "gatherLockScales")
KNOBS = "zig/src/families/flashnext/cuda_knobs.zig"


def git(*args, check=True):
    r = subprocess.run(["git", *args], cwd=str(SEQ), capture_output=True)
    if check and r.returncode != 0:
        raise SystemExit(f"git {' '.join(args)}: {r.stderr.decode(errors='replace')}")
    return r


def text(r):
    return r.stdout.decode(errors="replace")


def keep_line(path, line):
    if path.endswith("environment.zig"):
        return not any(g in line for g in GONE_RULES)
    if path.endswith("cuda_lanes.zig"):
        return "cuda_ple_cache.zig" not in line
    if path == "CHANGELOG.md":
        return "direct-mapped row cache" not in line and "gathers every stream's n-gram rows" not in line
    raise SystemExit(f"no rule to resolve a conflict in {path}")


def resolve(path):
    p = SEQ / path
    s = p.read_text(encoding="utf-8")
    pat = re.compile(r"<<<<<<< ours\n(.*?)=======\n(.*?)>>>>>>> theirs\n", re.S)
    s = pat.sub(lambda m: "".join(x for x in m.group(1).splitlines(keepends=True) if keep_line(path, x)), s)
    if "<<<<<<<" in s:
        raise SystemExit(f"{path}: a conflict block was left")
    p.write_text(s, encoding="utf-8", newline="\n")


def fix_knobs():
    p = SEQ / KNOBS
    if not p.exists():
        return
    s = p.read_text(encoding="utf-8")
    blocks = s.split("\n\n")
    kept = [b for b in blocks if not any(re.search(r"pub fn " + k + r"\(", b) for k in GONE_KNOBS)]
    s = "\n\n".join(kept)
    s = s.replace("//! Flash Next's n-gram, row-cache, prompt-path and prompt-shape switches (platform-validated "
                  "environment, read\n//! once per process); the defaults keep the plain paths.",
                  "//! Flash Next's prompt-path and prompt-shape switches (platform-validated environment, read once "
                  "per process);\n//! the defaults keep the plain paths.")
    p.write_text(s, encoding="utf-8", newline="\n")


def snap():
    paths = set(text(git("diff", "--name-only")).split()) | set(text(git("ls-files", "--others", "--exclude-standard")).split())
    for p in sorted(paths):
        git("add", "--", p)
    return text(git("write-tree")).strip()


def main(argv):
    series, out = Path(argv[1]).resolve(), Path(argv[2]).resolve()
    out.mkdir(parents=True, exist_ok=True)
    prog = json.loads((series / "progress.json").read_text(encoding="utf-8"))
    names = [n for n, _, _ in prog["series"]]
    trees = dict((n, t) for n, t, _ in prog["series"])
    p4, p12 = series / "0004-ngram-row-cache.patch", series / "0012-gather-direct.patch"
    new = [("", prog["base"])]
    for i, name in enumerate(names):
        if name[:4] in ("0004", "0012"):
            continue
        git("read-tree", "--reset", "-u", trees[name])
        git("clean", "-fdq")
        if i >= 3:
            reverse = ([p12] if i >= 11 else []) + [p4]
            for p in reverse:
                excl = ["--exclude=" + KNOBS] if p == p4 else []
                r = git("apply", "-R", "--index", "--3way", "--whitespace=nowarn", *excl, str(p), check=False)
                conflicted = [ln[3:] for ln in text(git("status", "--porcelain")).splitlines() if ln.startswith("UU ")]
                for path in conflicted:
                    resolve(path)
                if r.returncode != 0 and not conflicted:
                    raise SystemExit(f"{name}: reversing {p.name} failed: {r.stderr.decode(errors='replace')}")
            fix_knobs()
        new.append((name, snap()))
        print(f"{name}: stage without 0004/0012 {new[-1][1][:10]}")
    for (_, prev), (name, tree) in zip(new, new[1:]):
        d = git("diff", "--no-color", prev, tree).stdout
        (out / name).write_bytes(d)
        print(f"{name}: {len(d.splitlines())} lines")
    (out / "progress.json").write_text(json.dumps({"base": prog["base"], "todo": [], "series": [[n, t, "stageb"] for n, t in new[1:]]}, indent=1) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
