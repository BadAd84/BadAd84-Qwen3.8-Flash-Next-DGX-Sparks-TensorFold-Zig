#!/usr/bin/env python3
"""seat_experts.py TREE - add the expert-count log to an engine tree beside the kernel log.

Copies expert_log.zig into zig/src/cuda and makes the expert launches report what the plan really made: the decode
call (`run`), the prompt-tile call with the decode form's sums (`runFact`) and the prompt call (`runPrompt`). All
three are no-ops unless TF_FLASHNEXT_EXPERT_LOG=1. Idempotent.
"""
from __future__ import annotations

import io
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MARK = "expert_log.zig\").note"


def edit(path: str, old: str, new: str) -> str:
    s = io.open(path, encoding="utf-8", newline="").read()
    if s.count(old) != 1:
        raise SystemExit(f"{path}: anchor appears {s.count(old)} times, not once")
    io.open(path, "w", encoding="utf-8", newline="").write(s.replace(old, new, 1))
    return f"{os.path.basename(path)}: seated"


def main() -> None:
    tree = sys.argv[1]
    cuda = os.path.join(tree, "zig", "src", "cuda")
    if not os.path.isdir(cuda):
        raise SystemExit(f"{tree}: no zig/src/cuda")
    shutil.copyfile(os.path.join(HERE, "expert_log.zig"), os.path.join(cuda, "expert_log.zig"))
    print("expert_log.zig: copied")

    experts = os.path.join(cuda, "experts.zig")
    s = io.open(experts, encoding="utf-8", newline="").read()
    if MARK in s:
        print("experts.zig: already seated")
    else:
        print(edit(
            experts,
            "        try launch_.launch(e.fns[ei], .{ .grid = .{ .x = @intCast(grid), .y = 1, .z = 1 }, "
            ".block = .{ .x = @intCast(e.warps * 32), .y = 1, .z = 1 } }, s, &a);\n",
            "        try launch_.launch(e.fns[ei], .{ .grid = .{ .x = @intCast(grid), .y = 1, .z = 1 }, "
            ".block = .{ .x = @intCast(e.warps * 32), .y = 1, .z = 1 } }, s, &a);\n"
            "        @import(\"expert_log.zig\").note(s, if (gate) \"nvfp4_run_up\" else \"nvfp4_run_down\", items, "
            "p.counts, @intCast(grid), if (gate) l.width else l.dims, if (gate) l.dims else l.width, "
            "if (gate and !l.relu2) 2 else 1, p.items, if (gate) l.up else l.down);\n",
        ))
        print(edit(
            experts,
            "        try launch_.launch(e.prompt_fns[fi], cfg, s, &a);\n",
            "        try launch_.launch(e.prompt_fns[fi], cfg, s, &a);\n"
            "        @import(\"expert_log.zig\").note(s, if (gate) \"nvfp4_prompt_up\" else \"nvfp4_prompt_down\", items, "
            "p.counts, cfg.grid.x, if (gate) l.width else l.dims, if (gate) l.dims else l.width, parts, p.items, if (gate) l.up else l.down);\n",
        ))

    fact = os.path.join(cuda, "experts_fact.zig")
    s = io.open(fact, encoding="utf-8", newline="").read()
    if MARK in s:
        print("experts_fact.zig: already seated")
    else:
        print(edit(
            fact,
            "    try launch_.launch(e.fact_fns[fi], cfg, s, &a);\n",
            "    try launch_.launch(e.fact_fns[fi], cfg, s, &a);\n"
            "    @import(\"expert_log.zig\").note(s, if (gate) \"nvfp4_fact_up\" else \"nvfp4_fact_down\", items, p.counts, "
            "cfg.grid.x, if (gate) l.width else l.dims, if (gate) l.dims else l.width, if (gate) 2 else 1, p.items, if (gate) l.up else l.down);\n",
        ))

    waves = os.path.join(cuda, "experts_waves.zig")
    s = io.open(waves, encoding="utf-8", newline="").read()
    if MARK in s:
        print("experts_waves.zig: already seated")
        return
    print(edit(
        waves,
        "    try launch_.launch(e.fns[fi], .{ .grid = .{ .x = @intCast(grid), .y = 1, .z = 1 }, "
        ".block = .{ .x = @intCast(e.warps * 32), .y = 1, .z = 1 } }, s, &a);\n",
        "    try launch_.launch(e.fns[fi], .{ .grid = .{ .x = @intCast(grid), .y = 1, .z = 1 }, "
        ".block = .{ .x = @intCast(e.warps * 32), .y = 1, .z = 1 } }, s, &a);\n"
        "    @import(\"expert_log.zig\").note(s, if (gate) \"nvfp4_waves_up\" else \"nvfp4_waves_down\", items, p.counts, "
        "@intCast(grid), if (gate) l.width else l.dims, if (gate) l.dims else l.width, if (gate) 2 else 1, p.items, if (gate) l.up else l.down);\n",
    ))
if __name__ == "__main__":
    main()
