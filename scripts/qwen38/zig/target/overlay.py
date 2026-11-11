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
        "    \\\\  flashnext-kv8             Flash Next's --kv-cache fp8 write against its format model and its reads against the bf16 kernels\n"
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

print(f"overlay K={K}: " + ("; ".join(done) if done else "nothing to repair"))
