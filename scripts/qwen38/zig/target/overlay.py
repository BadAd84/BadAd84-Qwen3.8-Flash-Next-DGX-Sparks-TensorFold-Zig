#!/usr/bin/env python3
"""overlay.py K TREE - repairs that make the old series correct at rung K (the tree holds old patches 0001..K).

The old series only compiled at 0005, 0012, 0015 and 0030: each lever's fix-ups were dumped into a final
"integration tail" (0030) or happened to be repaired by an unrelated later patch. These overlays put each repair
where the damage happens, so every rung builds on the rung before it. Each edit asserts the text it expects.
"""
from __future__ import annotations

import io
import sys

K = int(sys.argv[1])
T = sys.argv[2].rstrip("/\\")
FN = T + "/zig/src/families/flashnext/"


def rd(p: str) -> str:
    return io.open(p, encoding="utf-8", newline="").read()


def wr(p: str, s: str) -> None:
    io.open(p, "w", encoding="utf-8", newline="").write(s)


done: list[str] = []


def sub(path: str, old: str, new: str, what: str) -> None:
    s = rd(path)
    eol = "\r\n" if "\r\n" in s else "\n"
    o, n = old.replace("\n", eol), new.replace("\n", eol)
    assert s.count(o) == 1, f"{what}: expected text found {s.count(o)} times in {path}"
    wr(path, s.replace(o, n, 1))
    done.append(what)


# 0013 (the n-gram row cache) replaced Ngram.deinit's two base lines instead of adding to them: the table's warm
# thread is no longer joined and the gather pool is never destroyed. Its hook in Ngram.fill also replaced the base's
# reader choice instead of going in front of it: a row the cache had filled was gathered again from the mapping, a
# row it had not went to the positional reader whatever TF_FLASHNEXT_PLE_IO said.
if 13 <= K:
    sub(
        FN + "cuda_ple.zig",
        "    pub fn deinit(g: *Ngram) void {\n        if (g.ahead_thread) |th| th.join();\n        if (g.cache) |c| c.destroy();\n",
        "    pub fn deinit(g: *Ngram) void {\n        g.waitWarm();\n        if (g.ahead_thread) |th| th.join();\n"
        "        if (g.pool) |p| p.destroy();\n        if (g.cache) |c| c.destroy();\n",
        "ple: deinit joins the warm thread and destroys the pool again",
    )
    sub(
        FN + "cuda_ple.zig",
        "                .nvfp4, .fp8 => if (!try ple_cache.row(g, ids[i], loc, row))\n"
        "                    try g.readers[loc.shard].read(g.gpa, loc.local, row)\n",
        "                .nvfp4, .fp8 => if (try ple_cache.row(g, ids[i], loc, row)) {\n"
        "                    // the row cache filled it\n"
        "                } else if (g.read_mode == .pread)\n"
        "                    try g.readers[loc.shard].read(g.gpa, loc.local, row)\n",
        "ple: the row cache goes in front of the base's reader choice",
    )

# 0018 defines promptGemm2 twice; 0022 deletes one copy. Rungs 18..21 need the single definition.
if 18 <= K:
    p = FN + "cuda_knobs.zig"
    s = rd(p)
    eol = "\r\n" if "\r\n" in s else "\n"
    dup = eol.join(
        [
            "/// TF_FLASHNEXT_PROMPT_GEMM2=1: the relaxed prompt tile runs two stages and two blocks an SM, same arithmetic and bits.",
            "pub fn promptGemm2() sys.environment.Error!bool {",
            '    return sys.environment.read(bool, "TF_FLASHNEXT_PROMPT_GEMM2", false);',
            "}",
            "",
        ]
    )
    dup = eol + dup  # the blank line that separates it from the first copy; the copy ends the file at 0018
    if s.count("pub fn promptGemm2()") == 2:
        assert dup in s, "the second promptGemm2 copy is not where 0018 put it"
        wr(p, s.replace(dup, "", 1))
        done.append("knobs: one promptGemm2")

# 0022 wrote merge residue ("22: @both" ...) over real lines; 0027 repaired the test registry.
if 22 <= K:
    p = T + "/zig/tests/cuda/main.zig"
    s = rd(p)
    fixes = {
        "22: @both\n": 'const flashnext_attn_tests = @import("flashnext_attn_tests.zig");\n'
        'const flashnext_kv8_tests = @import("flashnext_kv8_tests.zig");\n'
        'const flashnext_hc_fuse_tests = @import("flashnext_hc_fuse_tests.zig");\n',
        "23: @both\n": "    \\\\  flashnext-attn            Flash Next's own attention glue, pooling and block scores against float64 (synthetic)\n"
        "    \\\\  flashnext-kv8             Flash Next's --kv-cache fp8 write against its format model and its reads against the bf16 kernels (synthetic)\n"
        "    \\\\  hc-fuse                   the fused native hyper-connection read-out against the five-launch chain: bytes, then times\n",
        "24: @both\n": '    if (std.mem.eql(u8, cmd, "flashnext-attn")) return flashnext_attn_tests.run(gpu);\n'
        '    if (std.mem.eql(u8, cmd, "flashnext-kv8")) return flashnext_kv8_tests.run(gpu);\n'
        '    if (std.mem.eql(u8, cmd, "hc-fuse")) return flashnext_hc_fuse_tests.run(gpu);\n',
    }
    eol = "\r\n" if "\r\n" in s else "\n"
    n = 0
    for junk, real in fixes.items():
        junk_e, real_e = junk.replace("\n", eol), real.replace("\n", eol)
        if junk_e in s:
            s = s.replace(junk_e, real_e, 1)
            n += 1
    if n:
        wr(p, s)
        done.append(f"tests/cuda/main.zig: {n} residue lines replaced")
    # the changelog: 0022 replaced two bullets with "25: @both"; put back the lines its own hunk deleted
    p = T + "/CHANGELOG.md"
    s = rd(p)
    eol = "\r\n" if "\r\n" in s else "\n"
    if "25: @both" + eol in s and len(sys.argv) > 3:
        import glob

        src = io.open(glob.glob(sys.argv[3] + "/0022-*.patch")[0], encoding="utf-8").read().split("\n")
        at = src.index("+25: @both")
        gone = []
        i = at - 1
        while i >= 0 and src[i].startswith("-") and not src[i].startswith("---"):
            gone.insert(0, src[i][1:])
            i -= 1
        assert gone, "0022 deleted nothing before its changelog residue"
        wr(p, s.replace("25: @both" + eol, eol.join(gone) + eol, 1))
        done.append(f"CHANGELOG: {len(gone)} lines restored")

# 0022 (the fused read-out) was cut against an older tree and carries three reversions of the 1.2.6 base:
# Pass.chunk no longer stores its position, prefillChunk no longer records the prompt's last row (the first draft
# then reads address 0), and the relaxed MX128 tile is back on by default (0017 had switched it off).
if 22 <= K:
    sub(
        FN + "cuda_batch.zig",
        "            self.rows = n;\n            self.pending = null;\n            self.pending_f32 = false;\n            self.shared_direct = false;\n",
        "            self.rows = n;\n            self.pos0 = pos0;\n            self.pending = null;\n            self.pending_f32 = false;\n            self.shared_direct = false;\n",
        "batch: chunk stores its position again",
    )
    sub(
        FN + "cuda_mtp_ops.zig",
        "d.streams.ptr, false, knobs.headPiece() catch piece_rows);\n        }\n",
        "d.streams.ptr, false, knobs.headPiece() catch piece_rows);\n"
        "            if (last) d.prompt_last = d.streams.ptr + (stop - 1 - at) * wide * 2;\n        }\n",
        "mtp: the prompt's last row recorded again",
    )
    sub(
        FN + "cuda_mtp_ops.zig",
        "            const piece_max = @min(piece_req, @max(piece_rows, e.chunk / 2));\n",
        "            const piece_max = @min(if (piece_req == 0) piece_rows else piece_req, @max(piece_rows, e.chunk / 2));\n",
        "mtp: a head piece of 0 keeps the decode piece",
    )
    sub(
        FN + "cuda_knobs.zig",
        "/// TF_FLASHNEXT_PROMPT_MX128: the narrowest MXFP8 projection taking the relaxed 128 x 128 prompt tile; 0: none.\n"
        "pub fn mx128MinN() sys.environment.Error!usize {\n"
        '    return sys.environment.read(usize, "TF_FLASHNEXT_PROMPT_MX128", 1024);\n',
        "/// TF_FLASHNEXT_PROMPT_MX128=N: the narrowest MXFP8 projection taking the relaxed tile; default 0: the exact kernels.\n"
        "pub fn mx128MinN() sys.environment.Error!usize {\n"
        '    return sys.environment.read(usize, "TF_FLASHNEXT_PROMPT_MX128", 0);\n',
        "knobs: the relaxed MX128 tile off by default again",
    )

print(f"overlay K={K}: " + ("; ".join(done) if done else "nothing to repair"))
