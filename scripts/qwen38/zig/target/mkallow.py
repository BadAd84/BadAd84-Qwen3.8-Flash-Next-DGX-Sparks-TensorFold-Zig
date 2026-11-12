#!/usr/bin/env python3
"""mkallow.py SERIES_DIR OUT - write REVERTS.allow for the 1.2.6 series: every open finding of
check-patch-reverts.py with the reason it was reviewed to. A finding with no rule here is left out, so the gate
keeps failing on it until someone reads it."""
from __future__ import annotations

import io
import subprocess
import sys

series, out = sys.argv[1], sys.argv[2]
# (lever name in the patch file, path fragment, text fragment) -> reason; first match wins
RULES = [
    ("copy-resync", "lanes/engine.zig", "", "the lone copy ramp moved into windows.rampCopy, which keeps the e.alone test and the same doubling"),
    ("copy-resync", "lanes/proposer.zig", "", "the suffix lookup is kept inside `if (s.index.get(key)) |list|` so a miss can go on to resyncFrom"),
    ("kv8", "cuda_glue.zig", "prep", "the paged-or-plain choice moved to the caller of attnPrepOn, shared with the fp8 cache's kernels"),
    ("kv8", "cuda_glue.zig", "", "the kernel choice and the launch moved into attnChunksOn, shared with the fp8 cache's kernels"),
    ("kv8", "cuda_lanes_load.zig", "", "the per-stream bytes moved into streamBytes, which prices the same parts by the cache's format"),
    ("kv8", "cuda_media.zig", "", "the paged-or-plain choice moved into View.attn, in front of attnWith"),
    ("kv8", "cuda_snap.zig", "pub fn order(", "the same function with the named return type Order, which orderFor returns too"),
    ("ngram-row-cache", "cuda_batch.zig", "thread = null", "gather_log.join joins the thread and returns null"),
    ("ngram-row-cache", "cuda_ple.zig", "read_mode", "the row cache goes in front; the reader choice is kept as the else branch on the next line"),
    ("prompt-chunk", "cuda_tiles.zig", "nativeMatmul", "kept as the else branch of the prompt-tile choice on the same line"),
    ("prompt-gemm2", "qmmf.cu", "", "the prompt tile's macro gains its stage and block counts; the two instances are re-declared with them"),
    ("prompt-gemm2", "qmmf_prompt_records.zig", "", "the record list is extended with the two-stage tile's records"),
    ("prompt-gemm2", "cuda/qmmf.zig", "", "the shared bytes and the launch take the stage count from the knob"),
    ("prompt-readout-fused", "cuda_batch.zig", "hcWritebackNorm", "moved into hc.mlpWriteback, which makes the same launch when the rows are not prompt-fused"),
    ("prompt-readout-fused", "cuda_mtp_ops.zig", "pss_n", "the constant had no user left in the file"),
    ("prompt-readout-fused", "cuda_mtp_ops.zig", "reserveRows", "the same value with the piece as a parameter (equal at the decode piece)"),
    ("gather-direct", "cuda_ple_cache.zig", "", "the open goes through the page cache when TF_FLASHNEXT_GATHER_DIRECT=0, direct otherwise"),
    ("check-log", "cuda_mtp_check.zig", "", "the count is kept; the first differing row is logged beside it"),
]

names = {}
import glob
import os

for p in glob.glob(os.path.join(series, "[0-9]*.patch")):
    b = os.path.basename(p)
    names[b.split("-", 1)[0]] = b.split("-", 1)[1].rsplit(".", 1)[0]
gate = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "check-patch-reverts.py")
r = subprocess.run([sys.executable, gate, series, "--allow", os.devnull, "--raw"], capture_output=True, text=True, encoding="utf-8")
lines, missing = [], 0
for raw in r.stdout.splitlines():
    num, path, text, _ = (raw.split("\t") + [""] * 4)[:4]
    lever = names.get(num, "")
    for want, frag, tfrag, why in RULES:
        if want == lever and frag in path and tfrag in text:
            lines.append(f"{num}\t{path}\t{text}\t{why}\n")
            break
    else:
        missing += 1
        print(f"no rule: {num} {lever} {path}: {text[:110]}")
head = (
    "# Reviewed findings of scripts/check-patch-reverts.py for this series: patch, path, the stripped line, why it is\n"
    "# right. Tab-separated. Written by scripts/qwen38/zig/target/mkallow.py; a finding with no reason there stays open.\n"
)
io.open(out, "w", encoding="utf-8", newline="\n").write(head + "".join(lines))
print(f"mkallow: {len(lines)} allowed, {missing} left open")
