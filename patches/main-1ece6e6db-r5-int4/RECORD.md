# Provenance of this package

- **What it is:** TensorFold `main` at `1ece6e6dbbc073582d50738ce8e73e3c3261a73b` with
  `patches/main-1ece6e6db-r5` applied first, then this package's two patches, built to serve production's checkpoint,
  `azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound`. It is `patches/main-1ece6e6db-r2-int4` re-seated from the r2
  series onto r5, so the INT4 arm can be compared against an FP4 arm built from the same series.
- **Base it applies to:** upstream `1ece6e6dbbc073582d50738ce8e73e3c3261a73b`, with `patches/main-1ece6e6db-r5`
  0001 to 0020 first. `apply.sh` applies exactly those, checks both `SHA256SUMS` and refuses any other HEAD.
- **Where the text comes from:** `patches/main-1ece6e6db-r2-int4/0021-int4-autoround.patch` (sha256
  `c02c6131e2f82d1b210de3f2281722e839432e39cf68d4dd871c5e3e473d42ec`), applied one file at a time with
  `git apply --3way` (`work/R5Int4/apply_int4_3way.sh`) to a shared clone holding the base plus r5 as one scratch commit
  (`d2cc2ed98`), with the r2 stack's tree (`1ece6e6db` plus `patches/main-1ece6e6db-r2` 0001-0020, scratch commit
  `35f25d33c`) fetched in, so every file's pre-image blob was present for the merge. The two patches are the exact
  difference between that commit and the resolved tree (`work/IntDev/mkpkg.py`, unchanged): 0021 every path but the
  serving fixture, 0022 the fixture.
- **Whether we edited it:** yes: one conflict resolved by hand, and the pin rows regenerated from the resolved tree.
  Every other added line is the r2-int4 package's.

## What moved under the INT4 patch between the two series

`git diff` between the r2-applied and r5-applied trees, limited to 0021's 28 paths, moves three files and nothing
else: `cuda_batch.zig` (2/2: r3 0001's upstream-shaped fused condition), `cuda_batch_hc.zig` (1/1: r4's write-back fix),
`cuda_mtp.zig` (110/6: r3 0001's PR #4075 bytes). The other 25 INT4 paths have byte-identical pre-images on both
series. The two files r4 and r5 added (`flashnext_hc_norm.cuh`, `flashnext_tile_records.zig`) and the file r5 split
(`flashnext_hc.cu`) are not INT4 paths, so the split and the records are orthogonal to this port.

## Per-file resolution on `1ece6e6db` + r5

`git apply --3way` one file at a time: **27 clean, 1 conflict, 0 failed.** The applied result differs from the r2-int4
package's tree on exactly those three moved paths (2/2, 1/1, 110/6); the other 25 INT4 files are the r2-int4 post-images
byte for byte.

| path (flashnext files under `zig/src/families/flashnext/`) | pre-image moved | result |
|---|---|---|
| `zig/build/cuda.zig`, `zig/build/cuda_kernels.zig`, `zig/src/cuda/kernels.zig`, `zig/kernels/cuda/fn_int4.cu` (new), `cuda_int4.zig` (new), `cuda_int4_load.zig` (new) | no | as written |
| `cuda_batch.zig` | +2 / -2 | 3-way merged: r5's fused condition and both INT4 arms (`lane`'s int4 and tail branches) present; the mode-2 write-back carries `slots - 1, slots` |
| `cuda_batch_kernels.zig`, `cuda_batch_side.zig`, `cuda_batch_state.zig`, `cuda_config.zig`, `cuda_fp8_experts_load.zig`, `cuda_launch.zig`, `cuda_mixed_experts.zig`, `cuda_modelopt_experts.zig`, `cuda_moe_native.zig`, `cuda_mtp_load.zig`, `cuda_ple.zig`, `cuda_projection.zig`, `cuda_projection_load.zig`, `cuda_prompt.zig`, `cuda_prompt_load.zig`, `cuda_prompt_step.zig`, `cuda_prompt_wt.zig`, `cuda_rank_memory.zig`, `cuda_shared_split.zig` | no | as written |
| `cuda_mtp.zig` | +110 / -6 | 3-way merged: r3 0001's PR #4075 bytes and the INT4 `dtype` line (`headIsInt4`, line 309) both present |
| `cuda_batch_hc.zig` | +1 / -1 | **conflict, resolved by hand** (below) |
| `zig/tests/fixtures/gradient-serving.tsv` | - | 0022: 17 rows re-hashed from the resolved tree |

### The hand resolution: `cuda_batch_hc.zig`, `writebackNorm`'s shared-direct branch

- **What conflicted:** both series rewrote the same line. r4 (in r5) replaced the call with the
  writeback-with-normalize launch, `hcWritebackNorm(h, h, pss, s.shared_out + r0 * dims * 4, inj, y, wts, scale, norm,
  eps, rs, n, dims, streams, 3, 10, 11, 1)`, because the shared-direct write-back otherwise writes HOUT and PSS but no
  NORM, and the fused read-out reads NORM (measured 0 of 20 with the lever on, 20 of 20 with it off). The INT4 patch
  rewrote the same call's routing widths to `slots - 1, slots`, because this checkpoint routes five experts to a
  1,280-wide shared expert with six slots where the FP4 checkpoint has ten routed plus one shared.
- **What was kept, and why:** both halves, in one composite line:
  `return pass.tri.hcWritebackNorm(h, h, pss, s.shared_out + r0 * dims * 4, inj, y, wts, scale, norm, eps, rs, n, dims, streams, 3, slots - 1, slots, 1);`
  Mode 3 is the only mode that writes NORM from the shared expert's fp32 row, and `slots - 1, slots` is the only pair
  that indexes this checkpoint's experts. The kernel's mode-3 branch reads `SLOTS` from its arguments
  (`flashnext_hc_norm.cuh`, `MODE == 3`), so 6 slots means the shared expert sits at index 5 and `TOPK = 5` routed rows
  feed it, which is what the checkpoint stores.
- **Reach:** the branch runs only with `shared_direct`, a prompt pass on one GPU (`native.world == 1`); the INT4 loader
  refuses `world != 1` (`cuda_mixed_experts.zig`), so every prompt pass of this image reaches it, and the r5 device
  window's 20-item arms exercised it with the FP4 widths; this window's X cells exercise it with these.

### Added lines retained (the RESEAT docs' count)

`work/IntDev/plus_lines.py` against the old patch, per file, as a multiset of exact lines: **1,486** old `+` lines,
**1,485** present verbatim in the applied result. The **1** other is the composite line above, re-expressed on r5's fix.
**No lever line is lost**: every behaviour the old line carried (mode-3 NORM write-back, this checkpoint's widths) is
carried by the composite, and the 20-item device window is what holds it. New `+` lines this package adds: none.

## The routing width, checked across the merge

The five hyper-connection write-back call sites now pass `slots - 1, slots`
(`cuda_batch.zig:203`, `cuda_batch_hc.zig:41`, `:71`, `:73`, `cuda_prompt_step.zig:198`); no `10, 11` write-back width
remains in the family's serving path. The literal widths left in the family are off the served path, as the r2-int4
RECORD's audit found them.

## The pins

`0022-int4-serving-pins.patch` re-hashes the 17 pinned rows 0021's changed paths move. 15 of the 17 rows carry the
r2-int4 package's own after-hash because their files are identical across the two series; `cuda_batch.zig` and
`cuda_mtp.zig` carry hashes of this tree's text. `cuda_batch_hc.zig`, which the conflict touched, is still not a pinned
row. `pincheck` reads `files 170 failing 0` on the applied tree (170 rows because r5's 0020 added
`flashnext_hc_norm.cuh`'s).

## Checks this package has passed

Base and tree, on Paperclip (`adam@paperclip.ots-int.net`), from `git archive` trees verified blob by blob: the base
tarball (sha256 `5aedd735...`, the same one the r4/r5 lanes used) was checked against `git ls-tree -r -z` of
`1ece6e6db` (`entries 12601 missing 0 mismatch 0 extra 0 mode_bad 0`) and made a repository at the base commit
(`STAGE tree 3a37e287...`, `STAGE HEAD 1ece6e6db...`).

| gate | result |
|---|---|
| `apply.sh --check` (r5 series + both INT4 patches, scratch index) | rc 0; `the series and 2 INT4 patches apply on 1ece6e6db... in order (nothing written)`; afterwards 0 changed paths, no scratch index left |
| `apply.sh` | rc 0; `the series and 2 INT4 patches applied on 1ece6e6db...`; modified 107, new 24 (as expected) |
| the applied tree's manifest | `TREE ... entries 12625 mismatches 0 extra_files 0` against `head.manifest` (sha256 `660f5431...`) |
| `git diff --check` | rc 0 |
| `zig fmt --check build.zig zig` | rc 0 |
| `tools/zig/cuda_common_check.py` | **rc 1**: `cuda common: 61 local copies, 6 violations`, all in `fn_int4.cu` (the port's lifted asm: `mma.sync`, two `ld.global.nc.L1`, `cp.async.commit_group`/`wait_group`) |
| `tools/zig/cuda_fragment_check.py` | rc 0 |
| `pincheck.py` | `files 170 failing 0` |
| `zig build test-environment-host` | rc 0, `3/3 steps succeeded; 28/28 tests passed` |
| `zig build -Dfixed-cpu test-gradient-serving test-qwen-serving-host` | rc 0, `7/7 steps succeeded; 3/3 tests passed` |
| `zig build -Dfixed-cpu test-flashnext-int4-host` | rc 0, `4/4 steps succeeded; 26/26 tests passed` |
| `zig build -Dfixed-cpu test-kernel-contract` | rc 0, `36/36 steps succeeded; 260/260 tests passed` (289 s) |
| `zig build -Dtarget=aarch64-linux-gnu compile-config-server` | rc 0 (235 s) |
| `zig build -Dtarget=aarch64-linux-gnu compile-cuda-tests` | see the gate table in this repo's `work/R5Int4/GATES.md` |
| `zig build -Dnvcc=$NVCC compile-cuda-tests` | see `work/R5Int4/GATES.md` |
| `zig build -Dnvcc=$NVCC -Dtarget=aarch64-linux-gnu compile-cuda-tests` | see `work/R5Int4/GATES.md` |
| `zig build -Dnvcc=$NVCC -Doptimize=fast fatbins install native` | see `work/R5Int4/GATES.md` (must produce `fatbin/fn_int4.fatbin`) |
| the lean pair against r5 (each side's own `lean_check.py`) | base `7014 files, 230 problems`, head `7017 files, 290 problems`, `lean_new`: **60 new** |

### The two failing gates, and whose they are

Both failures are the INT4 port's own, inherited from `patches/main-964174ea05-int4` and never measured on the r2
series either; the re-seat did not introduce them and does not change them.

- **`cuda_common_check`, 6 violations.** `fn_int4.cu` carries its own `mma.sync`, `ld.global.nc.L1` and
  `cp.async` group asm instead of `zig/kernels/cuda/common/`'s helpers. The tool reads `61 local copies, 6 violations`
  in this file (the file is a lift of production's kernel, which predates the shared helpers).
- **`lean_new`, 60 new.** 55 are adjacent `//` comment lines and one `/*`-looking word in the port's own files
  (`fn_int4.cu` 36, `cuda_int4.zig` 12, `cuda_config.zig` 2, `cuda_int4_load.zig` 1, `cuda_fp8_experts_load.zig` 1,
  `cuda_projection.zig` 1, `cuda_ple.zig` 1, `cuda_shared_split.zig` 1 past 120 columns), 4 are direct `getenv` reads in
  `cuda_int4.zig` (`TF_FLASHNEXT_INT4_TILE`, `TF_FLASHNEXT_INT4_PROMPT_GATE_UP`, `TF_FLASHNEXT_INT4_PROMPT_DOWN`,
  `TF_FLASHNEXT_HEAD_ROW_TILES`), and 1 is `cuda_batch_state.zig` at 603 lines (594 on the base; the port's 9 lines
  cross 600).

A style pass for both is drafted in the lane's scratch seat (`work/R5Int4/seat`, scratch): the four settings moved to
`platform/environment.zig` rows and `environment.read`, the comment runs collapsed to one line each, and the remaining
`cuda_batch_state.zig` split still to do. It is NOT in this package, because a re-cut needs the whole gate run again
(the kernel-contract leg alone is 289 s) and this package's gate run was still holding the host lock. Until it lands,
this package carries the port's debt as measured above.

### Not run here

Anything with a GPU (golden replies, decode timing, the 1,664-item comparison, the exactness cells): see
`work/R5Int4/PLAN.md` in this repo. The next Spark window runs those on the image this tree builds.
