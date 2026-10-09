#!/usr/bin/env python3
"""resolve_fable.py TREE: resolve the two conflicts of ots0105-propose-floor.patch on the merged tree: keep the merged
code (ngram touch, window/depth fields) and add the propose fields and envFloat."""
import re, sys
t = sys.argv[1]

def fix(path, fn):
    p = f"{t}/{path}"
    s = open(p, encoding="utf-8").read()
    s2 = re.sub(r"<<<<<<< ours\n(.*?)=======\n(.*?)>>>>>>> theirs\n", fn, s, flags=re.S)
    assert "<<<<<<<" not in s2 and s2 != s, path
    open(p, "w", encoding="utf-8", newline="\n").write(s2)

def engine(m):
    ours = m.group(1)
    return ours.replace("stops[i] = .{ .c = r.confidence };", "stops[i] = .{ .c = r.confidence, .propose = r.propose };", 1)

def lanes(m):
    ours, theirs = m.group(1), m.group(2)
    ours = ours.replace(".late_keep = late };",
                        '.late_keep = late, .propose = envFloat("TF_FLASHNEXT_PROPOSE", 0), .propose_tpr = envFloat("TF_FLASHNEXT_PROPOSE_TPR", 0) };', 1)
    extra = theirs.split("\n", 1)[1]  # everything after theirs' return line: "        }\n\n        fn envFloat ..."
    return ours + extra

fix("zig/src/families/flashnext/cuda_engine.zig", engine)
fix("zig/src/families/flashnext/cuda_lanes.zig", lanes)
print("resolved")
