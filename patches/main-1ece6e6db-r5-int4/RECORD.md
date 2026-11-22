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
  serving fixture, 0022 the fixture. The fix round re-cut them from the same seat with the same tool, after the style
  pass: 0021 is now 31 paths, the port's 28 plus `docs/environment.md`, `platform/environment.zig` and its Flash Next
  test, and 0022 re-pins the same 17 rows from this tree (`work/R5Int4Fix/` holds the round's scripts and its proofs).
- **Whether we edited it:** yes: one conflict resolved by hand, the pin rows regenerated from the resolved tree, and in
  the fix round the port's inherited style debt cleared (the six CUDA primitive copies, the four `getenv` reads, the
  comment runs, and the tail width's single owner). Every other added line is the r2-int4 package's.

## What moved under the INT4 patch between the two series

`git diff` between the r2-applied and r5-applied trees, limited to 0021's 28 paths, moves three files and nothing
else: `cuda_batch.zig` (2/2: r3 0001's upstream-shaped fused condition), `cuda_batch_hc.zig` (1/1: r4's write-back fix),
`cuda_mtp.zig` (110/6: r3 0001's PR #4075 bytes). The other 25 INT4 paths have byte-identical pre-images on both
series. The two files r4 and r5 added (`flashnext_hc_norm.cuh`, `flashnext_tile_records.zig`) and the file r5 split
(`flashnext_hc.cu`) are not INT4 paths, so the split and the records are orthogonal to this port.

## Per-file resolution on `1ece6e6db` + r5

`git apply --3way` one file at a time: **27 clean, 1 conflict, 0 failed.** The applied result differs from the r2-int4
package's tree on exactly those three moved paths (2/2, 1/1, 110/6); the other 25 INT4 files were the r2-int4
post-images byte for byte at the re-seat. The fix round then rewrote comments in seven of those 25 (six with no code
line moved, plus `cuda_int4.zig`, whose four readers changed), so their text is this package's now;
`work/R5Int4Fix/codediff.py` is the audit and `CHANGES.md` names each fix.

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

### Added lines retained (the RESEAT docs' count, and the fix round's re-audit)

`work/IntDev/plus_lines.py` against the old patch, per file, as a multiset of exact lines: **1,486** old `+` lines,
**1,485** present verbatim in the applied result. The **1** other is the composite line above, re-expressed on r5's fix.
**No lever line is lost**: every behaviour the old line carried (mode-3 NORM write-back, this checkpoint's widths) is
carried by the composite, and the 20-item device window is what holds it.

The fix round rewrote comments in eight of the port's files, so that multiset no longer describes `0021` (now 1,488
added lines). What the round added instead is a code-line audit of the old and the new applied trees
(`work/R5Int4Fix/codediff.py`: comments and blank lines dropped, one file at a time). Six of the fourteen files that
moved between the two cuts carry **zero** code lines changed (`cuda_config.zig`, `cuda_fp8_experts_load.zig`,
`cuda_int4_load.zig`, `cuda_ple.zig`, `cuda_projection.zig`, `cuda_shared_split.zig`), and the code that does move is
exactly the listed fixes: the helper calls in `fn_int4.cu`, the four settings' readers in `cuda_int4.zig`, the tail
width's move to `cuda_prompt_wt.zig`, and the four environment rows with their test and doc.

## The routing width, checked across the merge

The five hyper-connection write-back call sites now pass `slots - 1, slots`
(`cuda_batch.zig:203`, `cuda_batch_hc.zig:41`, `:71`, `:73`, `cuda_prompt_step.zig:198`); no `10, 11` write-back width
remains in the family's serving path. The literal widths left in the family are off the served path, as the r2-int4
RECORD's audit found them.

## The pins

`0022-int4-serving-pins.patch` re-hashes the 17 pinned rows 0021's changed paths move, every one from this tree's text
(the fix round's comment pass and the tail width moved all seventeen files). `cuda_batch_hc.zig`, which the conflict
touched, is still not a pinned row. `pincheck` reads `files 170 failing 0` on the applied tree (170 rows because r5's
0020 added `flashnext_hc_norm.cuh`'s).

## Checks this package has passed

Every line below was observed on Paperclip (`adam@paperclip.ots-int.net`) in the fix round's run: lane
`/srv/ssd/work/R5Int4Fix`, payload sha256 `9e360d90932cf65981e094a715a8555361680a190ba89268e600e4df83c4cacd`, under
`flock -w 14400 ~/work/host.lock` behind the first cut's run, from fresh trees built out of the base tarball (sha256
`5aedd735...`, the same one the r4/r5 lanes used) and verified against `git ls-tree -r -z` of `1ece6e6db` (`entries
12601 missing 0 mismatch 0 extra 0 mode_bad 0`) before any patch ran, for the package tree and for the r5-only tree the
lean pair's base side comes from (`STAGE tree 3a37e287...`, `STAGE HEAD 1ece6e6db...` for both). The run's log is
`work/R5Int4Fix/box/`.

| gate | result |
|---|---|
| `apply.sh --check` (r5 series + both INT4 patches, scratch index) | rc 0; `the series and 2 INT4 patches apply on 1ece6e6db... in order (nothing written)`; afterwards `status after --check: 0 paths, scratch index 0` |
| `apply.sh` | rc 0; `the series and 2 INT4 patches applied on 1ece6e6db...`; `modified 109 new 24 (109 modified + 24 new expected)` |
| the applied tree's manifest | `TREE ... entries 12625 mismatches 0 extra_files 0` against `head.manifest` (sha256 `ab6389fc...`) |
| the old and the new `fn_int4.cu` compiled with the same nvcc command and source path | rc 0; both `8080835b...`, 1,132,920 bytes, twice for the new file; `FATBIN VERDICT identical` (`RESULT.md` section 1) |
| the lean pair against r5 (each side's own `lean_check.py`) | `lean_base` 7014 files / 230 problems, `lean_head` 7017 / 230, `lean_new`: **0 new** |
| `git diff --check` | rc 0 |
| `zig fmt --check build.zig zig` | rc 0 |
| `tools/zig/cuda_common_check.py` | rc 0; `cuda common: 55 local copies, 0 violations` (was `61 local copies, 6 violations`) |
| `tools/zig/cuda_fragment_check.py` | rc 0 |
| `pincheck.py` | `files 170 failing 0` |
| `zig build test-environment-host` | rc 0; `3/3 steps succeeded; 29/29 tests passed` (28 before the two new settings tests) |
| `zig build -Dfixed-cpu test-gradient-serving test-qwen-serving-host` | rc 0; `7/7 steps succeeded; 3/3 tests passed` |
| `zig build -Dfixed-cpu test-flashnext-int4-host` | rc 0; `4/4 steps succeeded; 26/26 tests passed` |
| `zig build -Dfixed-cpu test-kernel-contract` | rc 0; `36/36 steps succeeded; 260/260 tests passed` (289 s) |
| `zig build -Dtarget=aarch64-linux-gnu compile-config-server` | rc 0; `8/8 steps succeeded` (235 s) |
| `zig build -Dtarget=aarch64-linux-gnu compile-cuda-tests` | rc 0; `10/10 steps succeeded` (168 s) |
| `zig build -Dnvcc=$NVCC compile-cuda-tests` | rc 0; `169/169 steps succeeded` (615 s) |
| `zig build -Dnvcc=$NVCC -Dtarget=aarch64-linux-gnu compile-cuda-tests` | rc 0; `169/169 steps succeeded` (577 s) |
| `zig build -Dnvcc=$NVCC -Doptimize=fast fatbins install native` | rc 0; `327/327 steps succeeded` (679 s), 125 images, `FATBIN fn_int4: 1132920 bytes sha256 8080835ba1bccf4595f6ee21181e87fe8ed96f6d3d1da128bdfff8f81fa6beba` in `fatbin/fn_int4.fatbin` |

The first cut's two failures are gone, and neither was the re-seat's: `cuda_common_check` moved from `61 local copies, 6
violations` to `55 local copies, 0 violations`, and `lean_new` from `60 new` to `0 new` (the 230 problems on both sides
are the base's own, flagged identically on r5's tree). `CHANGES.md` ("The fix round") has the cause and the per-file
fix; `RESULT.md` sections 1 to 3 have the fatbin comparison, the code-line audit and the lean pair.

### Not run here

Anything with a GPU (golden replies, decode timing, the 1,664-item comparison, the exactness cells): see
`work/R5Int4/PLAN.md` in this repo. The next Spark window runs those on the image this tree builds.
