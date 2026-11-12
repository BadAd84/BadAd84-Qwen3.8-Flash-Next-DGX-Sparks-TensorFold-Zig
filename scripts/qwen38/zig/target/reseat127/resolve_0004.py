#!/usr/bin/env python3
"""resolve_0004.py TREE - patch 0004 (n-gram row cache, draft-ahead) on v1.2.7: cuda_mtp_ops.zig.

v1.2.7 moved Ops.draftMany's body to a module-level draftMany (one shared head loop, picks through draw.pick) and
left a one-line wrapper. Our patch adds the draft-ahead argument to draftMany and three calls in its loop. The
resolution keeps upstream's structure and puts the argument and the three calls into the module-level function.
"""
import io
import re
import sys

p = sys.argv[1].rstrip("/\\") + "/zig/src/families/flashnext/cuda_mtp_ops.zig"
s = io.open(p, encoding="utf-8", newline="").read()
eol = "\r\n" if "\r\n" in s else "\n"
s = s.replace("\r\n", "\n")


def one(old: str, new: str, what: str) -> None:
    global s
    assert s.count(old) == 1, f"{what}: found {s.count(old)} times"
    s = s.replace(old, new, 1)


# the two imports both stay
one('<<<<<<< ours\nconst module = @This();\n=======\nconst ple_cache = @import("cuda_ple_cache.zig");\n>>>>>>> theirs\n',
    'const module = @This();\nconst ple_cache = @import("cuda_ple_cache.zig");\n', "imports")
# the wrapper stays upstream's, with the argument passed on
m = re.search(r"<<<<<<< ours\n(        /// Draft several lanes through the shared operator loop\.\n)(        pub fn draftMany\(o: Self, .*?outs: \[\]const \*Chain)\) !void \{\n            return module\.draftMany\(o, ds, nexts, rows, counts, positions, sms, confidences, outs\);\n=======\n.*?>>>>>>> theirs\n", s, re.S)
assert m, "the draftMany conflict is not the one this resolves"
s = s[: m.start()] + m.group(1) + m.group(2) + ", ahead: ?*ple_cache.Ahead) !void {\n            return module.draftMany(o, ds, nexts, rows, counts, positions, sms, confidences, outs, ahead);\n" + s[m.end():]
assert "<<<<<<<" not in s and ">>>>>>>" not in s
# the module-level loop takes the argument and the three calls
sig = re.search(r"\npub fn draftMany\(o: anytype, .*?outs: \[\]const \*Chain\) !void \{\n", s, re.S)
assert sig, "module-level draftMany not found"
head = sig.group(0)
s = s.replace(head, head.replace("outs: []const *Chain) !void {", "outs: []const *Chain, ahead: ?*ple_cache.Ahead) !void {"), 1)
at = s.index("\npub fn draftMany(o: anytype, ")
body = s[at:]
end = body.index("\n}\n") + 3
fn = body[:end]


def infn(old: str, new: str, what: str) -> None:
    global fn
    assert fn.count(old) == 1, f"{what}: found {fn.count(old)} times in draftMany"
    fn = fn.replace(old, new, 1)


infn("    try o.forwardHeadMany(ds, nexts, rows, true);\n    var act:", "    try o.forwardHeadMany(ds, nexts, rows, true);\n    if (ahead) |a| a.flush();\n    var act:", "flush after the kept rows")
infn("            out.n += 1;\n            if (!t.more) continue;\n", "            out.n += 1;\n            if (ahead) |a| a.push(i, got.token);\n            if (!t.more) continue;\n", "push a drafted token")
infn("            for (step_ds[0..n_step]) |d| d.drafted += 1;\n        }\n        n_act = next_act;\n",
     "            for (step_ds[0..n_step]) |d| d.drafted += 1;\n        }\n        // asked once the step is on the stream: the reads run while it does\n        if (ahead) |a| a.flush();\n        n_act = next_act;\n", "flush after a step")
s = s[:at] + fn + body[end:]
io.open(p, "w", encoding="utf-8", newline="").write(s.replace("\n", eol))
# v1.2.7's own test calls the module-level function: it passes no read-ahead
t = sys.argv[1].rstrip("/\\") + "/zig/src/families/flashnext/cuda_mtp_nonfinite_more_test.zig"
ts = io.open(t, encoding="utf-8", newline="").read()
call = "&.{ null, null }, &.{ 0, 0 }, &.{ &first, &second })"
assert ts.count(call) == 2, f"the two draftMany calls of the non-finite test: found {ts.count(call)}"
io.open(t, "w", encoding="utf-8", newline="").write(ts.replace(call, "&.{ null, null }, &.{ 0, 0 }, &.{ &first, &second }, null)"))
print("resolve_0004: cuda_mtp_ops.zig resolved (upstream's module-level draftMany with the draft-ahead argument)")
