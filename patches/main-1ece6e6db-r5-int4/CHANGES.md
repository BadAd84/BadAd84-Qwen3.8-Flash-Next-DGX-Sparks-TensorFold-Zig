# `main-1ece6e6db-r5-int4`: what differs from `main-1ece6e6db-r2-int4`

This package is `patches/main-1ece6e6db-r2-int4` re-seated from `patches/main-1ece6e6db-r2` onto
`patches/main-1ece6e6db-r5`. Both patches are cut against the new series, so one directory holding r5's twenty patches
and these two applies in glob order. Everything not in the list below is the r2-int4 package's text, byte for byte, or
where the fix round rewrote it, that round's.

| item | r2-int4 package | this package |
|---|---|---|
| base series | `patches/main-1ece6e6db-r2` 0001-0020 (0001 holds r2's unprobed copy window) | `patches/main-1ece6e6db-r5` 0001-0020 (0001 is PR #4075's shape, 0008 carries the write-back fix and the `flashnext_hc_norm.cuh` split, the launch's five computed-usage records are filled) |
| `cuda_batch_hc.zig` | `writebackNorm`'s shared-direct branch calls `hcWriteback` in mode 3, width literals `10, 11` | `writebackNorm`'s shared-direct branch calls `hcWritebackNorm` in mode 3 (r4's fix: the launch must write NORM, which the fused read-out reads), width `slots - 1, slots` (this port's routing width) |
| `cuda_batch.zig` | pre-image has 0001's `const fused = ... and keep.log == 0 and ...` | pre-image has r3 0001's upstream-shaped condition (the pending-row log is refused by name after `cuts`); the INT4 hunks are unmoved |
| `cuda_mtp.zig` | pre-image is r2's file | pre-image is r3 0001's file (PR #4075's bytes, +110 lines); the INT4 `dtype` hunk lands unchanged on it |
| other 25 INT4 paths | - | byte-identical pre-images between the two series, so the same patch text applies; the applied files were the r2-int4 package's post-images byte for byte at the re-seat, and the fix round's comment pass then rewrote seven of them (see its section) |
| `0022-int4-serving-pins.patch` | 17 rows hashed from the r2-int4 tree | the same 17 rows, every hash from this tree (the fix round's comment pass moved all seventeen files); `cuda_batch_hc.zig` is still not a pinned row |
| `apply.sh` | series `../main-1ece6e6db-r2` | series `../main-1ece6e6db-r5`; the check/apply logic is unchanged |
| README/RECORD | the r2 base's record | this base's record: the re-seat's one conflict, its resolution, the per-file disposition against r2-int4, and the fix round's cleared debt with its gate lines |

## The one line the re-seat had to re-express, and why

`cuda_batch_hc.zig`'s `writebackNorm`, inside `if (pass.shared_direct)`, was two lines' worth of two different
changes:

- r4's fix (in r5) replaced the call with the writeback-with-normalize launch: `hcWritebackNorm(h, h, pss,
  s.shared_out + r0 * dims * 4, inj, y, wts, scale, norm, eps, rs, n, dims, streams, 3, 10, 11, 1)`. Without it the
  shared-direct write-back writes HOUT and PSS but no NORM, and the fused read-out reads NORM: 0 of 20 on the
  20-item answer set with the lever on, 20 of 20 with it off.
- This port's change (in both packages) replaced the routing widths at the five write-back call sites with
  `slots - 1, slots`, because the checkpoint routes five experts to a 1,280-wide shared expert and the build's slot
  count is 6, where the FP4 checkpoint's is 10 routed plus one shared.

A three-way merge cannot keep both halves of a line one parent rewrote wholesale, so the resolution is the
composite: `hcWritebackNorm` with mode 3 and `slots - 1, slots`. Neither half is dropped and neither is a compromise:
mode 3 is the only mode that writes NORM from the shared expert's fp32 row, and `slots - 1, slots` is the only pair
that indexes this checkpoint's experts. The kernel's mode-3 branch reads `SLOTS` from the launch's own arguments, so
6 slots means the shared expert sits at index 5 and `TOPK = 5` routed rows feed it, which is what the checkpoint
stores.

The other two moved files needed no hand work: `git apply --3way` merged the INT4 hunks onto r5's text and the
result keeps r5's change (the fused condition; PR #4075's MTP head bytes) intact, which the per-file diff in
`RECORD.md` states line by line.

## The fix round: the port's own style debt, cleared

The first cut of this package failed two gates, both inherited from `patches/main-964174ea05-int4` and never measured on
the r2 series either: `cuda_common_check` (`cuda common: 61 local copies, 6 violations`, all six the local `mma.sync`,
`ld.global.nc.L1::no_allocate` and `cp.async` asm in `fn_int4.cu`) and `lean_new` (`lean: 290 problems, 230 on the base,
60 new`). Both now read clean, and no kernel's arithmetic moves:

| file | the fix |
|---|---|
| `zig/kernels/cuda/fn_int4.cu` | #4183's file at head `582994e22` as the base: `qmm_frag::mma`, `tf_common::ld_nc` and `tf_common::cp16z` / `cp_commit` / `cp_wait` from `zig/kernels/cuda/common/`, whose instruction text is this file's own. What only this package needs is carried over: the four groups-of-64 instantiations and `tf_common::ld_nc2`, because `cuda_int4.zig` has symbol rows for gs 64 (a TP=2 rank's slice of the width cuts a group of 128), where #4183 builds groups of 128 alone. The lifted comment block becomes one-line comments. |
| `zig/src/families/flashnext/cuda_int4.zig` | its four settings (`TF_FLASHNEXT_INT4_TILE`, `TF_FLASHNEXT_INT4_PROMPT_GATE_UP`, `TF_FLASHNEXT_INT4_PROMPT_DOWN`, `TF_FLASHNEXT_HEAD_ROW_TILES`) read through `platform/environment.zig`; `headRowTiles` is gone, its refusal the table's |
| `zig/src/platform/environment.zig` and `docs/environment.md` | four `.flashnext` rows and their accepted forms (the table is 38 settings, and the doc says 38) |
| `zig/src/platform/environment_flashnext_test.zig` | the count test reads 38: 25 switches, 11 integers, 1 real, 1 structured; the integer sweep takes a value inside each rule's own bounds (the head's tiles are 1 or 2), and a dedicated test covers the tiles |
| `zig/src/families/flashnext/cuda_batch_state.zig` | back to 600 lines: the attention projection's BF16 tail width is `wt.attn_tail_n` in `cuda_prompt_wt.zig` (one owner for the shape), the local copy gone |
| `cuda_config.zig`, `cuda_fp8_experts_load.zig`, `cuda_int4_load.zig`, `cuda_ple.zig`, `cuda_projection.zig`, `cuda_shared_split.zig` | comment runs collapsed to one line each; no code line moves |

The two patches are re-cut from the fixed tree: `0021` is 31 paths, +1,488 / -44 (was 28 paths, +1,486 / -39), and `0022`
re-pins the same 17 rows. `work/R5Int4Fix/RESULT.md` carries the comparison of the old and the new `fn_int4.cu` compiled
with the same nvcc command and the same source path, with its verdict, and the observed gate lines for both the local
tree and the Paperclip run.

## What this package does not change

- No new behaviour beyond the r2-int4 package: the INT4 admission through `core.quant.gptq` (#3611), the collected
  packer tests, the `test-flashnext-int4-host` host step and the `cuda_int4.Source` loader are carried unchanged.
- No new pin rows: 0022 is hash-column only, as r2's 0020.
- The six steps of issue #3368 are untouched: the README's gap table keeps its dated upstream state (2026-11-21), and only its "in this package" column is filled in from this tree.
