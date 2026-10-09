#!/usr/bin/env python3
"""resolve_w5b.py TREE: resolve w5-hc-decode-glue.patch on zmerge4's tree: take the final W5 version of both hunks
(its comment, and the reduce+act / down / up-mix branches). The ours side only adds pf5's L2-prefetch hook there,
which is off by default and was measured as a wash (DROP), so it is left out."""
import re, sys
p = f"{sys.argv[1]}/zig/src/families/flashnext/cuda_forward.zig"
s = open(p, encoding="utf-8").read()
s2, n = re.subn(r"<<<<<<< ours\n.*?=======\n(.*?)>>>>>>> theirs\n", lambda m: m.group(1), s, flags=re.S)
assert n == 2 and "<<<<<<<" not in s2
open(p, "w", encoding="utf-8", newline="\n").write(s2)
print("resolved", n)
