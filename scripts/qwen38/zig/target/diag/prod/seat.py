#!/usr/bin/env python3
"""seat.py TREE - put the in-process kernel log into the production engine tree (the ai-engine layout).

Copies kernel_log.zig beside the tree's other CUDA files and makes two edits: the one launch funnel waits for its
launch and books it, and a module records the name it resolved a handle under so the table can name its kernels.
Both are no-ops unless TF_FLASHNEXT_KERNEL_LOG=1. Idempotent: a tree already seated is left alone.
"""
from __future__ import annotations

import io
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def edit(path: str, old: str, new: str, mark: str) -> str:
    s = io.open(path, encoding="utf-8", newline="").read()
    if mark in s:
        return f"{os.path.basename(path)}: already seated"
    if s.count(old) != 1:
        raise SystemExit(f"{path}: anchor appears {s.count(old)} times, not once")
    io.open(path, "w", encoding="utf-8", newline="").write(s.replace(old, new, 1))
    return f"{os.path.basename(path)}: seated"


def main() -> None:
    tree = sys.argv[1]
    cuda = os.path.join(tree, "zig", "src", "cuda")
    if not os.path.isdir(cuda):
        raise SystemExit(f"{tree}: no zig/src/cuda")
    shutil.copyfile(os.path.join(HERE, "kernel_log.zig"), os.path.join(cuda, "kernel_log.zig"))
    print("kernel_log.zig: copied")

    launch = os.path.join(cuda, "launch.zig")
    print(edit(
        launch,
        "pub fn launch(f: Function, cfg: Config, stream: Stream, args: *Args) Error!void {\n    try cfg.validate();\n",
        "pub fn launch(f: Function, cfg: Config, stream: Stream, args: *Args) Error!void {\n"
        "    const log = kernel_log.on();\n"
        "    const t0 = if (log) kernel_log.now() else 0;\n"
        "    try launchQueued(f, cfg, stream, args);\n"
        "    if (log) kernel_log.booked(f, stream, t0, cfg.grid.x);\n"
        "}\n\n"
        "fn launchQueued(f: Function, cfg: Config, stream: Stream, args: *Args) Error!void {\n"
        "    try cfg.validate();\n",
        "kernel_log.booked",
    ))
    s = io.open(launch, encoding="utf-8", newline="").read()
    if "const kernel_log = @import(\"kernel_log.zig\");" not in s:
        at = s.index("\n", s.index("//!")) + 1
        s = s[:at] + "const kernel_log = @import(\"kernel_log.zig\");\n" + s[at:]
        io.open(launch, "w", encoding="utf-8", newline="").write(s)
        print("launch.zig: import added")

    mod = os.path.join(cuda, "module.zig")
    print(edit(
        mod,
        "        return .{ .d = self.d, .handle = f };\n",
        "        @import(\"kernel_log.zig\").note(f, name);\n        return .{ .d = self.d, .handle = f };\n",
        "kernel_log.zig\").note",
    ))


if __name__ == "__main__":
    main()
