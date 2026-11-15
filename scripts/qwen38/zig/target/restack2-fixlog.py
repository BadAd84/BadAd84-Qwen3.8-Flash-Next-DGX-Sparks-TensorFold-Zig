#!/usr/bin/env python3
"""fixlog.py SERIES OUT - the series' CHANGELOG.md hunks rebuilt so that each patch adds exactly its own bullets.

SERIES is a stage.py output (progress.json: the base tree and each patch's stage tree). At stage N the changelog is
the base's, with the bullets of patches 1..N appended to the end of `## Unreleased` in patch order, a blank line
before each, and 0015's edit of 0003's bullet (fp8 KV now reaches the KV pages) applied from stage 15 on. Every
other path of every stage tree is kept as it is: OUT's patches differ from SERIES's only in CHANGELOG.md hunks, which
the script proves before it writes them.
"""
# Scratch it works in: work/fix0004 (seq = a worktree of work/upmain at the base; trees.json, the series dirs).
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parents[4] / "work" / "fix0004"
SEQ = HERE / "seq"
REPO = HERE.parents[1]
OLD = REPO / "patches" / "1.2.7"


def git(*args, env=None, inp=None):
    r = subprocess.run(["git", *args], cwd=str(SEQ), capture_output=True, env=env, input=inp)
    if r.returncode != 0:
        raise SystemExit(f"git {' '.join(args)}: {r.stderr.decode(errors='replace')}")
    return r.stdout


def added(patch: Path, path="CHANGELOG.md"):
    """The lines a patch adds to `path`, in order."""
    out, on = [], False
    for line in patch.read_text(encoding="utf-8").splitlines():
        if line.startswith("diff --git "):
            on = line == f"diff --git a/{path} b/{path}"
            continue
        if on and line.startswith("+") and not line.startswith("+++"):
            out.append(line[1:])
    return out


def bullets(lines):
    """Bullets (a '- ' line and its indented continuation lines, up to a blank line) out of added lines."""
    out, open_ = [], False
    for line in lines:
        if line.startswith("- "):
            out.append([line])
            open_ = True
        elif line.startswith("  ") and open_:
            out[-1].append(line)
        else:
            open_ = False
    return out


def main(argv):
    series, out = Path(argv[1]).resolve(), Path(argv[2]).resolve()
    out.mkdir(parents=True, exist_ok=True)
    prog = json.loads((series / "progress.json").read_text(encoding="utf-8"))
    names = [n for n, _, _ in prog["series"]]
    trees = [prog["base"]] + [t for _, t, _ in prog["series"]]
    by = {n[:4]: bullets(added(series / n)) for n in names}
    hc2 = [b for b in by["0010"] if "native hyper-connection read-out" in b[0]]
    upstream_note = "Internal: a CUDA family's disk module"
    own = {
        "0001": by["0001"],
        "0003": by["0003"],
        "0004": by["0004"],
        "0005": by["0005"],
        "0006": [b for b in by["0006"] if upstream_note not in b[0]],
        "0007": [b for b in by["0007"] if "direct-mapped row cache" not in b[0]],
        "0008": hc2,
        "0010": [b for b in by["0010"] if b not in hc2],
        "0011": by["0011"],
        "0014": [b for b in by["0014"] if "direct-mapped row cache" not in b[0]],
        "0015": [b for b in bullets(added(OLD / "0015-kv8-pages.patch")) if "reaches every served stream" in b[0]],
    }
    kv_from = "a captured set, the KV pages or `--learn-conversations`"
    kv_to = "a captured set or `--learn-conversations`"
    for k, v in own.items():
        if len(v) != (2 if k == "0004" else 1):
            raise SystemExit(f"{k}: {len(v)} bullets found")
    base_log = git("show", f"{trees[0]}:CHANGELOG.md").decode("utf-8")
    head, sep, tail = base_log.partition("\n## 1.2.9\n")
    if not sep:
        raise SystemExit("no ## 1.2.9 heading in the base changelog")
    head = head.rstrip("\n") + "\n"
    new_trees = [trees[0]]
    for i, name in enumerate(names, 1):
        body = []
        for n in names[:i]:
            for b in own.get(n[:4], []):
                body.append("\n" + "\n".join(b) + "\n")
        text = head + "".join(body)
        if i >= names.index("0015-kv8-pages.patch") + 1:
            if kv_from not in text:
                raise SystemExit("0003's bullet has no KV pages clause to edit")
            text = text.replace(kv_from, kv_to)
        text += "\n" + sep.lstrip("\n") + tail
        blob = git("hash-object", "-w", "--stdin", inp=text.encode("utf-8")).decode().strip()
        with tempfile.TemporaryDirectory() as d:
            env = dict(os.environ, GIT_INDEX_FILE=str(Path(d) / "index"))
            git("read-tree", trees[i], env=env)
            git("update-index", "--cacheinfo", f"100644,{blob},CHANGELOG.md", env=env)
            new_trees.append(git("write-tree", env=env).decode().strip())
    for i, name in enumerate(names, 1):
        rest_old = git("diff", "--no-color", trees[i - 1], trees[i], "--", ".", ":(exclude)CHANGELOG.md")
        rest_new = git("diff", "--no-color", new_trees[i - 1], new_trees[i], "--", ".", ":(exclude)CHANGELOG.md")
        if rest_old != rest_new:
            raise SystemExit(f"{name}: a path other than CHANGELOG.md changed")
        d = git("diff", "--no-color", new_trees[i - 1], new_trees[i])
        (out / name).write_bytes(d)
        print(f"{name}: {len(d.splitlines())} lines; CHANGELOG bullets {len(own.get(name[:4], []))}")
    (out / "progress.json").write_text(json.dumps({"base": trees[0], "todo": [], "series": [[n, t, "fixlog"] for n, t in zip(names, new_trees[1:])]}, indent=1) + "\n", encoding="utf-8")
    final = git("show", f"{new_trees[-1]}:CHANGELOG.md").decode("utf-8")
    (out / "CHANGELOG-unreleased.txt").write_text(final.partition("\n## 1.2.9\n")[0], encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
