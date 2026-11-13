#!/usr/bin/env python3
"""seat_experts_prod.py TREE - add the expert-count log to the production engine tree (the ai-engine layout).

The int4 experts have one launch funnel (`launch` in families/flashnext/cuda_int4.zig), so one hook reports what
the plan really made for every gate/up and down call. A no-op unless TF_FLASHNEXT_EXPERT_LOG=1. Idempotent.
"""
from __future__ import annotations

import io
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LAUNCH = ("    try cuda.launch.launch(k.fns[kind][j][q], .{ .grid = .{ .x = @intCast(grid) }, "
          ".block = .{ .x = warps * 32 } }, s, &a);\n")
OLD = ("    if (p) |pl| cuda.expert_log.note(s, if (kind == 0) \"int4_gate_up\" else \"int4_down\", max_items, "
       "pl.counts, @intCast(grid), n, kk, if (kind == 0) 2 else 1);\n")
NOTE = ("    if (p) |pl| cuda.expert_log.note(s, if (kind == 0) \"int4_gate_up\" else \"int4_down\", max_items, "
        "pl.counts, @intCast(grid), n, kk, if (kind == 0) 2 else 1, pl.items, w);\n")


def main() -> None:
    tree = sys.argv[1]
    cuda = os.path.join(tree, "zig", "src", "cuda")
    if not os.path.isdir(cuda):
        raise SystemExit(f"{tree}: no zig/src/cuda")
    shutil.copyfile(os.path.join(HERE, "expert_log.zig"), os.path.join(cuda, "expert_log.zig"))
    print("expert_log.zig: copied")

    root = os.path.join(cuda, "root.zig")
    s = io.open(root, encoding="utf-8", newline="").read()
    if "expert_log" not in s:
        at = s.index("\n", s.index("@import(\"")) + 1
        s = s[:at] + "pub const expert_log = @import(\"expert_log.zig\");\n" + s[at:]
        io.open(root, "w", encoding="utf-8", newline="").write(s)
        print("root.zig: export added")

    int4 = os.path.join(tree, "zig", "src", "families", "flashnext", "cuda_int4.zig")
    s = io.open(int4, encoding="utf-8", newline="").read()
    if NOTE in s:
        print("cuda_int4.zig: already seated")
        return
    if OLD in s:
        io.open(int4, "w", encoding="utf-8", newline="").write(s.replace(OLD, NOTE, 1))
        print("cuda_int4.zig: hook given the plan items and weight base")
        return
    if s.count(LAUNCH) != 1:
        raise SystemExit(f"{int4}: launch anchor appears {s.count(LAUNCH)} times, not once")
    io.open(int4, "w", encoding="utf-8", newline="").write(s.replace(LAUNCH, LAUNCH + NOTE, 1))
    print("cuda_int4.zig: seated")


if __name__ == "__main__":
    main()
