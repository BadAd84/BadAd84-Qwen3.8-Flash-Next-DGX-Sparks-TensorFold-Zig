#!/usr/bin/env python3
"""checkb.py - is tree B = stage 3 plus exactly the later patches' lines (0005-0011, 0013-0019), file by file?

For every file, the multiset of lines the later patches of series A add and remove is compared with the lines
diff(stage 3, B) adds and removes. Prints each file where the two differ, with the lines that differ.
"""
# Scratch it works in: work/fix0004 (seq = a worktree of work/upmain at the base; trees.json, the series dirs).
import collections
import json
import re
import subprocess
from pathlib import Path

HERE = Path(__file__).resolve().parents[4] / "work" / "fix0004"
SEQ = HERE / "seq"
trees = json.loads((HERE / "trees.json").read_text(encoding="utf-8"))
s3 = trees[3]
b = (HERE / "bfinal.txt").read_text().strip()
later = sorted(p for p in (HERE / "A").glob("0*.patch") if p.name[:4] not in ("0001", "0002", "0003", "0004", "0012"))


def per_file(text):
    out = collections.defaultdict(lambda: [collections.Counter(), collections.Counter()])
    cur = None
    for line in text.splitlines():
        m = re.match(r"^diff --git a/(\S+) b/(\S+)", line)
        if m:
            cur = m.group(2)
            continue
        if line.startswith("+++") or line.startswith("---"):
            continue
        if cur and line.startswith("+"):
            out[cur][0][line[1:]] += 1
        elif cur and line.startswith("-"):
            out[cur][1][line[1:]] += 1
    return out


want = collections.defaultdict(lambda: [collections.Counter(), collections.Counter()])
for p in later:
    for f, (add, rem) in per_file(p.read_text(encoding="utf-8")).items():
        # a line one patch adds and a later one removes cancels
        want[f][0].update(add)
        want[f][1].update(rem)
got = per_file(subprocess.run(["git", "diff", "--no-color", s3, b], cwd=str(SEQ), capture_output=True,
                              text=True, encoding="utf-8").stdout)
bad = 0
for f in sorted(set(want) | set(got)):
    wa, wr = want[f]
    net_a, net_r = wa - wr, wr - wa
    ga, gr = got[f]
    if net_a == ga and net_r == gr:
        continue
    bad += 1
    print(f"== {f}")
    for line in sorted((net_a - ga).elements()):
        print("   later patches add, B lacks:", line[:150])
    for line in sorted((ga - net_a).elements()):
        print("   B adds, later patches do not:", line[:150])
    for line in sorted((net_r - gr).elements()):
        print("   later patches remove, B keeps:", line[:150])
    for line in sorted((gr - net_r).elements()):
        print("   B removes, later patches do not:", line[:150])
print(f"{len(set(want) | set(got))} files, {bad} differ")
