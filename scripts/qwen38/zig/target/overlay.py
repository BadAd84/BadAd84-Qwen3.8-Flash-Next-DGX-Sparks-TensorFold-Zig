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


# The family's own host suite (zig build test-cuda-host) did not compile or pass on the old series; the server did.
# 0005 (rows) registers TF_FLASHNEXT_WINDOW_CHECK without a row in the environment test's table of valid forms,
# which that test asks of every rule.
if 5 <= K:
    sub(
        T + "/zig/src/platform/environment_test.zig",
        '    .{ .name = "TF_QMMF_HALF_BELOW", .raw = "0", .n = 0 },\n',
        '    .{ .name = "TF_QMMF_HALF_BELOW", .raw = "0", .n = 0 },\n'
        '    .{ .name = "TF_FLASHNEXT_WINDOW_CHECK", .raw = "0", .n = 0 },\n'
        '    .{ .name = "TF_FLASHNEXT_WINDOW_CHECK", .raw = "1", .n = 1 },\n',
        "environment test: TF_FLASHNEXT_WINDOW_CHECK has its valid forms",
    )

# 0012 (kv8) made snap.order a wrapper of orderFor with a second anonymous struct as its return type (two distinct
# types: its caller in cuda_disk.zig stops compiling), and calls three fp8 launches the paging test's fake backend
# does not have (an fp8 cache refuses pages at load, so that test never reaches them).
if 12 <= K:
    sub(
        FN + "cuda_snap.zig",
        "pub fn orderFor(format: Kv, at: usize, head: bool, h: Heads, head_format: Kv) struct { p: [11]Piece, len: usize } {\n",
        "pub fn orderFor(format: Kv, at: usize, head: bool, h: Heads, head_format: Kv) Order {\n",
        "snap: orderFor returns the named piece list",
    )
    sub(
        FN + "cuda_snap.zig",
        "pub fn order(at: usize, head: bool, h: Heads) struct { p: [11]Piece, len: usize } {\n",
        "pub fn order(at: usize, head: bool, h: Heads) Order {\n",
        "snap: order returns the named piece list",
    )
    sub(
        FN + "cuda_snap.zig",
        "pub const Piece = struct { layers: usize, n: usize, row: usize = 0, per: usize = 1 };\n",
        "pub const Piece = struct { layers: usize, n: usize, row: usize = 0, per: usize = 1 };\n"
        "/// `move`'s pieces and how many of them a state has (7, or 11 with the draft head).\n"
        "pub const Order = struct { p: [11]Piece, len: usize };\n",
        "snap: the piece list is one named type",
    )
    a = "_: anytype, "
    sub(
        FN + "cuda_paging_batch_test.zig",
        "    pub fn qsaPool(_: @This(), ",
        "    // an fp8 cache refuses pages at load: a paged pass never reaches its launches\n"
        "    pub fn attnPrepKv8(_: @This(), " + (a * 14)[:-2] + ") !void {\n        return error.TestUnexpectedResult;\n    }\n"
        "    pub fn attnChunksKv8(_: @This(), " + (a * 14)[:-2] + ") !void {\n        return error.TestUnexpectedResult;\n    }\n"
        "    pub fn attnFusedKv8(_: @This(), " + (a * 10)[:-2] + ") !void {\n        return error.TestUnexpectedResult;\n    }\n"
        "    pub fn qsaPool(_: @This(), ",
        "paging test: the fake backend has the fp8 launches",
    )
    # 0012b keeps the draft head's cache bf16 (0012 sized it as one row), so the fp8 cache saves 992 bytes a token
    # on the 12 layers' caches, not on 13: kv8's tests, recipe note and changelog still stated the 13-cache figures
    # (17.5 KiB a token, five full-window streams), which the code does not give.
    KT = T + "/zig/src/native/cuda_flashnext_kv8_test.zig"
    sub(KT, "7.8 GiB in bf16, 4.6 GiB in fp8, the rest the same", "7.8 GiB in bf16, 4.9 GiB in fp8, the rest the same", "kv8 test: a stream's fp8 bytes with a bf16 head")
    sub(
        KT,
        "    // 13 attention caches (12 layers and the head's) at 262,144 tokens save (2,048 - 1,056) bytes each\n"
        "    try std.testing.expectEqual(@as(usize, 13 * window * (2048 - 1056)), bf - f8);\n",
        "    // the 12 layers' attention caches at 262,144 tokens save (2,048 - 1,056) bytes each; the head's stays bf16\n"
        "    try std.testing.expectEqual(@as(usize, 12 * window * (2048 - 1056)), bf - f8);\n",
        "kv8 test: 12 caches save",
    )
    sub(KT, "admits five full-window streams in fp8 where bf16 admits three", "admits four full-window streams in fp8 where bf16 admits three", "kv8 test: four streams")
    sub(
        KT,
        "    try std.testing.expectEqual(@as(u32, 5), try memory.admit(room(24.36), f8, 0, 16, false));\n"
        "    // five at once is refused in bf16 as a fixed count, and admitted in fp8\n"
        "    try std.testing.expectError(error.TooMany, memory.admit(room(24.36), bf, 0, 5, true));\n"
        "    try std.testing.expectEqual(@as(u32, 5), try memory.admit(room(24.36), f8, 0, 5, true));\n",
        "    try std.testing.expectEqual(@as(u32, 4), try memory.admit(room(24.36), f8, 0, 16, false));\n"
        "    // four at once is refused in bf16 as a fixed count, and admitted in fp8\n"
        "    try std.testing.expectError(error.TooMany, memory.admit(room(24.36), bf, 0, 4, true));\n"
        "    try std.testing.expectEqual(@as(u32, 4), try memory.admit(room(24.36), f8, 0, 4, true));\n",
        "kv8 test: the admitted counts",
    )
    sub(KT, "dense - 13 * window * (2048 - 1056), f8", "dense - 12 * window * (2048 - 1056), f8", "kv8 test: the dense fp8 plan")
    sub(KT, "@as(usize, 13 * at * (2048 - 1056)), bf - f8", "@as(usize, 12 * at * (2048 - 1056)), bf - f8", "kv8 test: a kept state")
    sub(
        FN + "cuda_snap.zig",
        "        // a state at `at` tokens is smaller by (2,048 - 1,056) bytes a token of each of the 13 layers\n"
        "        try std.testing.expectEqual(at * 13 * (2048 - 1056), bytes(at, true, .full) - bytesFor(.fp8, at, true, .full));\n",
        "        // a state at `at` tokens is smaller by (2,048 - 1,056) bytes a token of each of the 12 layers; the head's rows stay bf16\n"
        "        try std.testing.expectEqual(at * 12 * (2048 - 1056), bytes(at, true, .full) - bytesFor(.fp8, at, true, .full));\n",
        "snap test: 12 caches save",
    )
    sub(
        FN + "cuda_kv.zig",
        'test "the README\'s per-token figures: 13 layers of 1,376 bytes, 17,888 fp8 against 30,784 bf16" {\n',
        'test "the recipe\'s per-token figures: 12 layers of 1,376 bytes and the head\'s 2,368, 18,880 fp8 against 30,784 bf16" {\n',
        "kv test: the per-token figures' name",
    )
    sub(
        FN + "cuda_kv.zig",
        "    try std.testing.expectEqual(@as(usize, 17888), 13 * (Kv.fp8.position(.full) + pooled));\n",
        "    try std.testing.expectEqual(@as(usize, 18880), 12 * (Kv.fp8.position(.full) + pooled) + Kv.bf16.position(.full) + pooled);\n",
        "kv test: the per-token figures",
    )
    sub(
        T + "/docs/recipes/flash-next-cuda.md",
        "so a token's caches take about 17.5 KiB instead of 30 KiB (12 layers and the MTP\n  head's). The indexer's keys",
        "so a token's caches take about 18.4 KiB instead of 30 KiB (the 12 layers';\n  the MTP head's cache stays bf16). The indexer's keys",
        "recipe note: the fp8 cache's bytes a token",
    )
    # 0027 (round cost) moved changelog bullets and cut this one off after its first line
    tail = (
        "  about 18.4 KiB instead of 30 KiB (the draft head's cache stays bf16) and a Spark's sequence memory admits four\n"
        "  full-window streams where bf16 admits three;\n"
        "  one rank, our own glue, not with `--slide`, a captured set, the KV pages or `--learn-conversations`. The indexer's keys,\n"
        "  pooled blocks and DeltaNet states stay bf16; attention reads the codes widened to bf16 exactly, so its sums are the bf16\n"
        "  kernels' on the dequantized rows, and a repeated prompt's reply is deterministic. bf16 stays the default.\n"
    )
    if K < 27:
        sub(
            T + "/CHANGELOG.md",
            "  about 17.5 KiB instead of 30 KiB and a Spark's sequence memory admits five full-window streams where bf16 admits three;\n"
            "  one rank, our own glue, not with `--slide`, a captured set, the KV pages or `--learn-conversations`. The indexer's keys,\n"
            "  pooled blocks and DeltaNet states stay bf16; attention reads the codes widened to bf16 exactly, so its sums are the bf16\n"
            "  kernels' on the dequantized rows, and a repeated prompt's reply is deterministic. bf16 stays the default.\n",
            tail,
            "changelog: the fp8 cache's figures with a bf16 head",
        )
    else:
        sub(T + "/CHANGELOG.md", "so a token's caches take\n- ", "so a token's caches take\n" + tail + "- ", "changelog: the fp8 cache's bullet whole again")

# A host test builds its Engine undefined, which drops the field defaults; 0012 added `kv`, whose reader panics on
# an undefined value (keyRow, reached through newSeq). Each such test names the format, as it names its other fields.
if 12 <= K:
    import glob, re
    n_sites = 0
    for path in sorted(glob.glob(FN + "*_test.zig")):
        t = rd(path)
        eol = "\r\n" if "\r\n" in t else "\n"
        pat = re.compile(r"^([ \t]*)(?:var|const) (\w+): prompt\.Engine = undefined;" + eol, re.M)
        if not pat.search(t):
            continue
        t, c = pat.subn(lambda m: m.group(0) + m.group(1) + m.group(2) + ".kv = .bf16;" + eol, t)
        wr(path, t)
        n_sites += c
    assert n_sites > 0
    done.append(f"host tests: {n_sites} undefined engines get kv = .bf16")
    sub(
        FN + "cuda_snap.zig",
        "    try std.testing.expectEqual(@as(usize, 13 * per_layer), bytesFor(.fp8, 1, true, .full) - bytesFor(.fp8, 0, true, .full));\n",
        "    // 12 layers' caches as fp8 rows and the draft head's as bf16 rows\n"
        "    try std.testing.expectEqual(@as(usize, 12 * per_layer + 2048 + 256), bytesFor(.fp8, 1, true, .full) - bytesFor(.fp8, 0, true, .full));\n",
        "snap test: an fp8 state's draft head rows are bf16",
    )

# 0015's row-cache test calls ple_cache.open as a statement; it returns the reader, so the test never compiled.
if 15 <= K:
    PT = FN + "cuda_ple_cache_test.zig"
    s = rd(PT)
    eol = "\r\n" if "\r\n" in s else "\n"
    old = "    try ple_cache.open(&g, io);" + eol
    assert s.count(old) == 3, f"ple cache test: expected 3 open statements, found {s.count(old)}"
    wr(PT, s.replace(old, "    g.cache = try ple_cache.open(&g, io);" + eol))
    done.append("ple cache test: open's reader is stored as Ngram.fill stores it")
    # aheadChunk is a function of the cache's module taking the table first, not a method of Ngram
    s = rd(PT)
    for old, rep in (
        ("    g.aheadChunk(&[_]i64{99}, tokens[0..300]);", "    ple_cache.aheadChunk(&g, &[_]i64{99}, tokens[0..300]);"),
        ("    g.aheadChunk(&hist, tokens[n..]);", "    ple_cache.aheadChunk(&g, &hist, tokens[n..]);"),
    ):
        assert s.count(old) == 1, f"ple cache test: {old} found {s.count(old)} times"
        s = s.replace(old, rep)
    wr(PT, s)
    done.append("ple cache test: aheadChunk called as the module's function")

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
