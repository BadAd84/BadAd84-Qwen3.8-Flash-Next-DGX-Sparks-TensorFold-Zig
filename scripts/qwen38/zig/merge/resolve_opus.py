#!/usr/bin/env python3
"""resolve_opus.py TREE: resolve w6d.patch's four conflicts on the merged tree: keep the merged code (W4's rows_out,
W1's n-gram touch, W2's window/depth split) and add W6Opus's draft-ids reader, stop lines, env and depth cap."""
import re, sys
t = sys.argv[1]
B = re.compile(r"<<<<<<< ours\n(.*?)=======\n(.*?)>>>>>>> theirs\n", re.S)

def fix(path, fns):
    p = f"{t}/{path}"
    s = open(p, encoding="utf-8").read()
    it = iter(fns)
    s2 = B.sub(lambda m: next(it)(m.group(1), m.group(2)), s)
    assert "<<<<<<<" not in s2 and s2 != s, path
    open(p, "w", encoding="utf-8", newline="\n").write(s2)

def e1(ours, theirs):  # draft ids from theirs, rows_out from ours
    t0, _ = theirs.split("\n", 1)
    o1 = ours.split("\n")[1]
    return t0 + "\n" + o1 + "\n"

def e2(ours, theirs):  # theirs' stop loop, then ours' n-gram touch lines
    touch = "\n".join(ours.split("\n")[1:])
    return theirs + touch

def l1(ours, theirs):  # theirs' constructor with ours' window/depth fields
    w = ours.split("\n")[0]
    theirs = theirs.replace(".window = @max(1, @min(window, max_rows)), .late_keep = late };",
                            ".window = w, .depth = w - 1, .late_keep = late };", 1)
    assert ".depth = w - 1" in theirs
    return w + "\n" + theirs

def l2(ours, theirs):  # theirs' adapt + cap, with ours' depth bound
    theirs = theirs.replace("var depth = @min(r.depth, self.window - 1);",
                            "var depth = @min(r.depth, @min(self.depth, self.window - 1));", 1)
    assert "self.depth, self.window - 1" in theirs
    return theirs

fix("zig/src/families/flashnext/cuda_engine.zig", [e1, e2])
fix("zig/src/families/flashnext/cuda_lanes.zig", [l1, l2])
print("resolved")
