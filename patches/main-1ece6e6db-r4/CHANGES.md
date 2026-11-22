# `main-1ece6e6db-r4`: what differs from `main-1ece6e6db-r3`

One behaviour changes: **patch 0008's shared-direct write-back now writes the normalized rows in the same launch as
the written-back rows and their square sums.** r3's 0008 is byte-identical to r2's (both
`10688fa54b7b50c75f9687a41cc4f00409801bb3d04265295e57d10b17e32612`), so this is the first change to 0008 since r2.
Under `TF_FLASHNEXT_PROMPT_SHARED_DIRECT=1` a fused hyper-connection read-out ran `writebackNorm` and then
`readoutNative` (`zig/src/families/flashnext/cuda_batch.zig:548-550`); the lever's branch in `writebackNorm`
(`cuda_batch_hc.zig:69-71`) called `pass.tri.hcWriteback`, mode 3 of `hc_writeback` (`zig/kernels/cuda/flashnext_hc.cu:61`,
branch at `:81-83`), whose signature has no NORM argument, while `readoutNative` reads `s.norm + r0 * wide * 2`
(`cuda_batch_hc.zig:84`, feeding the down at `:94`). The normalized rows were never written on that route.

## The defect's measurement

On the r2 image (`tensorfold-qwen38:s2-1ece6e6d`,
`sha256:fe5a33931b63506103eb08d8d2e8b244efadc65b8fae028255235fc22781f044`), the recipe's own environment read back
from `docker inspect` and diffed with an empty result on every boot, 20 GSM8K items of 1,330-1,494 prompt tokens,
exact text hashes against the 2026-11-19 reference:

| arm | delta | exact vs the reference |
|---|---|---:|
| defaults | none | 0/20 (twice) |
| `TF_FLASHNEXT_HC_FUSE=0` | one line | **20/20** |

`TF_FLASHNEXT_PROMPT_SHARED_DIRECT` stayed 1 in both arms, so the broken step is inside the fused read-out, not in
the shared down's values. The values are separately not the difference: the 128-row prompt tile's fp32 output is
byte-identical to the strided route's at 400, 513, 600, 1,330 and 3,072 rows (0 differing elements of up to
7,864,320, both routes 16-20 times inside the contract's float64 bound; a planted 1.5x scale differs everywhere).

Mode 3 and mode 2 run the same multiply-add chain on the same operands - mode 3 substitutes
`BR[(long long)r * D + d]` for the `k == TOPK` slot value - so the only observable difference the write-back can
carry is the missing NORM, and `readoutNative` consumes it.

## Exactly what 0008 now contains

Four edits, all in the lever's own surface, plus the two contract files that pin it:

| file | change |
|---|---|
| `zig/kernels/cuda/flashnext_hc.cu` | `hc_writeback_norm` (line 128) gains the same `MODE == 3` branch `hc_writeback` has at line 81 (new branch at line 153: `BR[(long long)r * D + d]` for the `k == TOPK` term), so one launch writes HOUT, PSS and NORM; `fn_hc_writeback_norm_moe_sh` is instantiated at line 206 as `hc_writeback_norm<3, 10, 4>` beside `fn_hc_writeback_norm_moe` (mode 2) and `fn_hc_writeback_norm_slices` (mode 4) |
| `zig/src/families/flashnext/cuda_glue.zig` | `wbn_moe_sh` beside `wbn_moe` (field line 42, loaded line 148), and a `3 =>` case in `hcWritebackNorm`'s switch (lines 531-537) passing the shared fp32 rows as `branch` and the routed slots as `y`/`wts` |
| `zig/src/families/flashnext/cuda_batch_hc.zig` | line 71 (the `pass.shared_direct` branch of `writebackNorm`) calls `hcWritebackNorm(..., mode 3, ...)` instead of the norm-less `hcWriteback` |
| `zig/tests/cuda/contract_flashnext_wbnorm.zig` | the contract's `Mode` gains `moe_sh` (mode 3): `prepare` puts the shared fp32 row in the last slot (the copy `fn_shared_scatter` makes), `theirs` runs the same fused launch in mode 2, and gate 1's rule and gate 3 compare the written-back rows, the square sums and the normalized rows byte for byte |
| `zig/tests/cuda/contract_flashnext_more.zig` | the `wbnorm` set holds four modes (`[4]`), so the new entry is registered with the others |

There is no host test for this writeback: `hcWritebackNorm` returns `error.NativeGlueRequired` without the native
glue (`zig/src/families/flashnext/cuda_launch.zig:390-393`), and `Glue.load` refuses a build without kernels
(`cuda_glue.zig:117`), so the kernel body runs only on a device. The contract entry above is the pin, and the boot
gate below is the served-model gate.

## The boot gate this package is held to

With the fix built into an image, the same 20 items and the same comparison: `TF_FLASHNEXT_PROMPT_SHARED_DIRECT=1`
must read 20/20 twice, `TF_FLASHNEXT_PROMPT_SHARED_DIRECT=0` 20/20, and `TF_FLASHNEXT_HC_FUSE=0` 20/20; the
no-delta control (r3's defaults) stays 0/20. The contract run's `kernel-contract wbnorm` must report the new entry
passing with no gate and no control failures. The device evidence and the lever's measured prefill value are in
`work/SDFix/RESULT.md` of the repo this package lives in.

## The device result (spark6, 2026-11-22)

The r4 image (`tensorfold-qwen38:sdfix-r4`, relabelled `embedded`) with the recipe's own serving shape and 20 GSM8K
items of 1,330-1,494 prompt tokens:

| arm | delta | exact vs the 2026-11-19 reference |
|---|---|---:|
| the pre-fix r3 image, defaults | none | 0/20 (marker 3, gold 1) |
| r4 | `TF_FLASHNEXT_PROMPT_SHARED_DIRECT=1` | 20/20 twice |
| r4 | `TF_FLASHNEXT_PROMPT_SHARED_DIRECT=0` | 20/20 |
| r4 | `TF_FLASHNEXT_PROMPT_SHARED_DIRECT=1`, `TF_FLASHNEXT_HC_FUSE=0` | 20/20 |

Every boot's container environment was read back and diffed against the recipe's recorded environment plus its one
delta, with an empty diff; the no-delta control is the r3 image at those defaults, so the reference is live in the
same window. The contract's `kernel-contract writeback_norm` reported `4 kernels: 4 pass gates 1-4, 0 fail, 0 known
findings; 0 controls: 0 red as planted, 0 missed; 0 limit problems`, with the mode-3 entry's nonfinite, repeat and
shapes gates passing and its three shapes bit-equal to mode 2.

The lever's value on the fixed build, two boots an arm, orders alternating: cold TTFT 3.651 s at 8k against 3.695 s
with it off (+1.2 percent) and 14.773 s at 32k against 14.915 s (+1.0 percent); decode is flat (the table and every
per-boot figure are in `work/SDFix/RESULT.md` of the repo this package lives in). That is about a fifth of the margin
the broken build showed: the 4.6-4.9 percent it was credited with came partly from the NORM work it never did.

## The two re-pinned rows of 0020

0020 re-hashes the rows of `zig/tests/fixtures/gradient-serving.tsv` the series moves. Two of them are files this
fix edits; the base-side (`-`) values are unchanged, the series-side (`+`) values are the new hashes:

| row | r3 `+` | r4 `+` |
|---|---|---|
| `zig/kernels/cuda/flashnext_hc.cu` | `f420761f731ccc82f8202899b65cc89d0aee5fc052de3d9f7bf2e5105d6ef71c` | `028871750f6e38af9726487227810e83d1c1b96b39c2756c21e2aad854227157` |
| `zig/src/families/flashnext/cuda_glue.zig` | `f9cc870bf96c38073c0301f809151d14e44bfff4f4fead173ddc12395522ad4d` | `6e33cea696f8cb42261844bd3eb13a4dc015cf9f9b6436fd0fe025de3de51c6b` |

`cuda_batch_hc.zig` carries no row in that fixture, and neither contract test file does.

## Proof the series is still the same series

- Eighteen of the twenty patches are byte-identical to r3's; only `0008-shared-direct-head-piece.patch` (sha256
  `f5298a56a03a9ba9bf7a3eab504dd0111989d62aeb55173d9fbfca7d06c8b75c`) and `0020-serving-pins.patch` differ.
- The package applies in order on a pristine `1ece6e6dbbc073582d50738ce8e73e3c3261a73b`: `apply.sh --check` writes
  nothing and reports 20 patches; a full `apply.sh` applies 20/20, and the tree has 94 modified files and 20 new
  ones (r3 had 92 modified; the two contract files are the difference).
- The new 0008 applied on base plus 0001-0007 reproduces the edited tree file for file (12,621 files, 0
  mismatches), so the regenerated patch is exactly the change described above.
