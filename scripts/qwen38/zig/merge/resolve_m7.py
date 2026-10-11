#!/usr/bin/env python3
"""resolve_m7.py TREE: zmerge7's one conflict (r3t-b's early first draw vs r3pc-whole's whole-prompt keep, both at
the end of prefillWith). Keep r3t-b's draw (it declares `first` and `drawn` earlier and may already have drawn), then
r3pc's whole-prompt snapshot, which must follow the last chunk's absorb + commit (it does: this is after the loop)."""
import re, sys
p = f"{sys.argv[1]}/zig/src/families/flashnext/cuda_engine.zig"
s = open(p, encoding="utf-8").read()
ours = """        if (!drawn) {
            try e.draw(e.last_logits, e.last_cand, 1, prompt.len, &first);
            if (e.pass_times) pw[3] = try e.passLap(&t_pw);
        }
"""
keep = """        // OTS: a whole-prompt state after the draw (its copies run behind the first token), with the logits row
        if (o.keep_at) |k| if (k == prompt.len) {
            const snap = try e.snapshot(seq, seq.st.mtp_len, seq.last_streams.?.ptr, true);
            kept = snap;
            snap.tokens = try e.gpa.dupe(u32, prompt);
        };
"""
s2, n = re.subn(r"<<<<<<< ours\n.*?>>>>>>> theirs\n", lambda m: ours + keep, s, flags=re.S)
assert n == 1 and "<<<<<<<" not in s2 and s2.count("var first: [1]u32") >= 1
open(p, "w", encoding="utf-8", newline="\n").write(s2)
print("resolved", n)
