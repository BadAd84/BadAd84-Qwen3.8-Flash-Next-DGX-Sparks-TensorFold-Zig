#!/usr/bin/env python3
"""resolve_cum.py TREE: resolve the calibrated-rule patch's one conflict on zmerge4's tree (W6Opus's w6_steps
accounting + the cum rule's calibration-probe bookkeeping in the same loop)."""
import re, sys
p = f"{sys.argv[1]}/zig/src/families/flashnext/cuda_lanes.zig"
s = open(p, encoding="utf-8").read()
new = """            var w6_most: usize = 0;
            for (reqs[0..requests.len], ls[0..requests.len]) |q, l| {
                l.held_n = q.drafted;
                l.probs_n = if (q.probs != null) q.drafted else 0; // the calibration probe
                w6_most = @max(w6_most, q.drafted);
            }
            self.w6_steps = w6_most + 1;
"""
s2, n = re.subn(r"<<<<<<< ours\n.*?=======\n.*?>>>>>>> theirs\n", lambda m: new, s, flags=re.S)
assert n == 1 and "<<<<<<<" not in s2
open(p, "w", encoding="utf-8", newline="\n").write(s2)
print("resolved")
