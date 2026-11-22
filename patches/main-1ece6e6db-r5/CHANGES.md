# `main-1ece6e6db-r5`: what differs from `main-1ece6e6db-r4`

No behaviour changes. Two things the package was missing are fixed: 0008's writeback-with-normalize family now lives in
its own file, so the series never sits at a point the repository's own 600-line rule refuses, and the new launch's
five computed-usage records are filled from a five-SM build, so `test-kernel-contract` no longer reports the launch as
unmeasured. `CHANGES.md` r4's own note is kept below this one's story for the fix's mechanism.

## 1. The split: `flashnext_hc_norm.cuh`

At r4, 0008 took `zig/kernels/cuda/flashnext_hc.cu` from 589 to 610 lines. `tools/zig/lean_check.py` fails any file
past 600 (`MAX_LINES = 600`), so a tree at 0008 alone was refused by the repository's own style gate; only the full
series, finished, came back under it. A patch series is read one patch at a time, by a reviewer and by a bisect, so an
intermediate state that the repo's gate refuses is a defect in the series rather than a cosmetic wart.

The family moves whole: `hc_writeback_norm` and the four instantiations that wrap it (`fn_hc_writeback_norm0`,
`_moe`, `_moe_sh`, `_slices`), 89 lines, byte for byte, into `zig/kernels/cuda/flashnext_hc_norm.cuh`, which
`flashnext_hc.cu` includes where the block stood. The new file adds one opening comment and `#pragma once`; no
`#include`, `__LINE__` or `__FILE__` use is moved, so the preprocessed translation unit is what it was.

| file | before | after |
|---|---:|---:|
| `zig/kernels/cuda/flashnext_hc.cu` | 610 lines | 522 lines |
| `zig/kernels/cuda/flashnext_hc_norm.cuh` | absent | 92 lines |

- **The move is inert, measured on the build path rather than argued.** The repository's own
  `zig build fatbins install native -Dnvcc` (CUDA 13.3, sm_121) produces the same `flashnext_hc` image from both
  trees: `b2b966d95a3d4cbfc893e75740864d17261197a7c5f2930c1571bec3ca6932e0`, `cmp` identical.
- **Why a `.cuh` and not `flashnext_hcn.cu`.** That file builds a different image (`flashnext_hcn`), and
  `cuda_glue.zig:148` resolves `fn_hc_writeback_norm_moe_sh` from the `flashnext_hc` module, so moving the symbol
  there would need a second module loaded beside `hc` and would move the image boundary. The repository's own
  precedent for a split is `flashnext_hc_dense.cuh`, "included in place by flashnext_hc.cu (one image)", and this
  uses the same form.
- **Line map in the new file.** Template `:5`, the `MODE == 3` branch `:31`, `fn_hc_writeback_norm0` `:75`,
  `fn_hc_writeback_norm_moe_sh` `:84`, `fn_hc_writeback_norm_slices` `:89`.
- `flashnext_hc.cu` is `240a68de655a759cfa5c55d82a52887f1b4175714b0771a72dd879b114db8cb3` and
  `flashnext_hc_norm.cuh` is `cdce0edc85d215a6f807f6844cc194fac7b7edebe89e1031eb46ad60ccc110c3`.

## 2. The five computed-usage records

r4's 0008 registered the new launch (`flashnext_hc fn_hc_writeback_norm_moe_sh`) with `.usage = registry.none`, a
provisional row whose only purpose was to let the limits audit print the measured numbers. The registry's own test
refuses that state, one line per SM:

```
flashnext_hc fn_hc_writeback_norm_moe_sh on sm_80: no compiled usage recorded
flashnext_hc fn_hc_writeback_norm_moe_sh on sm_86: no compiled usage recorded
flashnext_hc fn_hc_writeback_norm_moe_sh on sm_89: no compiled usage recorded
flashnext_hc fn_hc_writeback_norm_moe_sh on sm_120: no compiled usage recorded
flashnext_hc fn_hc_writeback_norm_moe_sh on sm_121: no compiled usage recorded
expected 0, found 5
```

`tf-cuda-test kernel-contract-limits DIR` is the tool that produces the numbers, from the fatbins' own ELF images, and
it needs a device whose compute capability is in the build's SM list. This box's card is sm_121, so the five-SM build
(`-Dsm=80,86,89,120,121`) runs and the audit reads all five:

```
PASS limits sm_80 flashnext_hc fn_hc_writeback_norm_moe_sh: 64 registers, 1296 static shared bytes, bound 256 (record stale)
PASS limits sm_86 flashnext_hc fn_hc_writeback_norm_moe_sh: 64 registers, 1296 static shared bytes, bound 256 (record stale)
PASS limits sm_89 flashnext_hc fn_hc_writeback_norm_moe_sh: 64 registers, 1296 static shared bytes, bound 256 (record stale)
PASS limits sm_120 flashnext_hc fn_hc_writeback_norm_moe_sh: 64 registers, 1296 static shared bytes, bound 256 (record stale)
PASS limits sm_121 flashnext_hc fn_hc_writeback_norm_moe_sh: 64 registers, 1296 static shared bytes, bound 256 (record stale)
RECORD flashnext_hc fn_hc_writeback_norm_moe_sh: .usage = .{ .{ .regs = 64, .static = 1296, .bound = 256 }, .{ .regs = 64, .static = 1296, .bound = 256 }, .{ .regs = 64, .static = 1296, .bound = 256 }, .{ .regs = 64, .static = 1296, .bound = 256 }, .{ .regs = 64, .static = 1296, .bound = 256 }, }
```

`(record stale)` is the pre-fill reading: the row the tree carried was the provisional one. The five tuples above are
the row this patch's `flashnext_tile_records.zig` now holds, and the record file's own sha256 is
`0ad1c4b3a7eb4892cfa7f804f8d02c8d653f56a733ccc4e04434b0920586ad8a`.

The rows go where the family's own rows live, `zig/src/core/contract/flashnext_tile_records.zig`, in `limits.sms`'
order. On the filled record the second `kernel-contract-limits` pass read `record current` on all five SMs, and
`test-kernel-contract` read `Build Summary: 36/36 steps succeeded; 260/260 tests passed`; section 5 records both
beside the device re-verify.

## 3. Why still 20 patches

A separate 0021 carrying the move would have kept the defect it exists to remove: 0008's tree would still be 610
lines. The move touches only files 0008 already owns, so it folds into 0008, and the pin rows the move changes go into
0020, which is the package's own receipts patch. The cut is mechanical and was proved by application, not by reading:
0008's unchanged sections are r4's own bytes, the four files it shares with the move are cut as base-to-final diffs,
and applied in filename order to a pristine base the series reproduces the final tree entry for entry.

## 4. The gate this package is held to

With the fix built into an image, the same 20 GSM8K items and the same comparison r4 used: 
`TF_FLASHNEXT_PROMPT_SHARED_DIRECT=1` must read 20/20 twice, `TF_FLASHNEXT_PROMPT_SHARED_DIRECT=0` 20/20, and
`TF_FLASHNEXT_HC_FUSE=0` 20/20; the contract's `writeback_norm` filter must report the new entry passing with no gate
and no control failure. Every boot's environment is read back from `docker inspect` and diffed against the recipe's own
block with the arm's delta applied, and each boot's image id is gated.

## 5. The device result (spark6, 2026-11-22)

The records above are measured, and the tree was then built into the serve image (`tensorfold-qwen38:sdlimits-r5`,
`sha256:17cfdc9a93c9bb8b0f4508d9dc84b08d17dfb98b9d9b26e44d26f837d3e9d3d5`, relabelled `embedded`) and held to the
same gate r4 was, with the recipe's own serving shape and the same 20 GSM8K items of 1,330 to 1,494 prompt tokens:

| arm | delta | exact vs the 2026-11-19 reference |
|---|---|---:|
| r5 | `TF_FLASHNEXT_PROMPT_SHARED_DIRECT=1` | 20/20, twice |
| r5 | `TF_FLASHNEXT_PROMPT_SHARED_DIRECT=0` | 20/20 |
| r5 | `TF_FLASHNEXT_PROMPT_SHARED_DIRECT=1`, `TF_FLASHNEXT_HC_FUSE=0` | 20/20 |
| the pre-fix control image `s2-1ece6e6d`, no delta | none | 0/20 (marker 3, gold 1) |

Every boot's container environment was read back from `docker inspect` and diffed against the recipe's recorded block
with the arm's delta applied, empty in all five, and each boot's image id was gated: the four arms on this image's
`sha256:17cfdc9a...`, the control on `s2-1ece6e6d`'s `sha256:fe5a3393...`. On the filled record the second
`kernel-contract-limits` pass read `record current` on all five SMs with the tuples above, and `test-kernel-contract`
read `Build Summary: 36/36 steps succeeded; 260/260 tests passed`. The contract's `kernel-contract writeback_norm`
reported

```
(filtered) SUMMARY 4 kernels: 4 pass gates 1-4, 0 fail, 0 known findings; 0 controls: 0 red as planted, 0 missed; 0 limit problems; gates 258 ms, limits 0 ms
```

with the new entry's live line `PASS limits live flashnext_hc fn_hc_writeback_norm_moe_sh: 256 threads launched, the
driver allows 256; 64 registers, 1296 + 0 shared bytes (recorded 64, 1296)`. The window's control step then stopped on
a defect in its own driver (the verdict call declared `local label=$1 d=$OUT/$label`, which `set -u` rejects because
bash expands every word before assigning), so the control's 20 raw rows above were scored by the same `compare.py`;
the four gate arms and the contract had already passed, and the window's trap restored production (`/health` 200, the
pinned image and id).

## 6. What is not proven

- The 1,664-item text comparison (`docs/QUALITY-A-VS-B-2026-11-18.md`) was measured on a different image
  (`tensorfold-qwen38:t5-b-c0eb2126`), before this write-back was fixed. Any text-quality statement about the FP4 arm
  with the lever on is void for this build until that comparison is re-run on it; this window proves the 20-item
  answer set and the contract, not a benchmark-scale quality claim.
- Cold-TTFT and decode numbers in r4's `RESULT.md` stay r4's numbers. This window rebuilt the image, so re-timing was
  out of scope for it and none is quoted here.
- The five rows are nvcc 13.3's, the compiler the serve image builds with; a 13.0 toolchain is not on this box. Where a
  compiler changes a launch's rows, `registry_cuda_sets.zig` is where a later release's set belongs.
