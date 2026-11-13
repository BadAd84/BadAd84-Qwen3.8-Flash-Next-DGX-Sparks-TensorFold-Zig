# Provenance of this package

- **What it is:** our own levers on TensorFold v1.2.7, as 13 additive patches. Nothing here is another project's
  commit; the base tree is never edited in place.
- **Base it applies to:** `ashhart/TensorFold` v1.2.7, `93a2e93ecebff8aa52b88e58c5dd222516e69c5f`. `apply.sh` refuses
  any other HEAD.
- **Where the text comes from:** `patches/1.2.6`, re-seated by `scripts/qwen38/zig/target/reseat.py` (one patch at a
  time: `git apply --3way`, the hand-written resolution in `reseat127/` where v1.2.7 changed the same lines, our
  changelog bullets moved under `## Unreleased`; patch N is the exact difference between the staged trees). The
  resolutions: 0004 (`cuda_mtp_ops.zig`: v1.2.7 moved the draft loop into a module-level `draftMany`; our draft-ahead
  argument and three calls go in it), 0005 and 0006 (`qmmf.cu`: v1.2.7 appended a native FP4 check at the file's end),
  0010 (the lane core: v1.2.7's `rowTerm` and `least_rows` and our `draft_row_ms` pricing both stay).
- **Whether we edited it:** yes, by those resolutions only. The repairs of `patches/1.2.6` are part of the text.
  The rungs were built into images and measured on spark6 on 2026-11-12 (`scripts/qwen38/zig/target/v127.sh`; the
  table is in `README.md`); the patch text then gained only test, recipe-note and changelog repairs from
  `patches/1.2.6`, which no image contains.

## Repairs `overlay.py` makes, by the old patch that needed them

| from old patch | repair |
|---|---|
| 0012 (kv8) | `0012b`: the draft head stays BF16 under an fp8 cache, in place of the old tail's blanket reset of the draft files, which also deleted the rows lever's window guards, the n-gram draft-ahead argument and the 4-bit draft head |
| 0013 (n-gram row cache) | `Ngram.fill`: the row cache goes in front of the base's reader choice instead of replacing it (a cached row was gathered twice, the rest went to the positional reader whatever `TF_FLASHNEXT_PLE_IO` said) |
| 0013 | `Ngram.deinit` joins the warm thread and destroys the gather pool again |
| 0018 (GEMM2) | `promptGemm2` defined once (it was defined twice, so nothing between 0018 and 0030 compiled) |
| 0022 (fused read-out) | `Pass.chunk` stores its position again (`self.pos0 = pos0`); `prefillChunk` records the prompt's last row again; the relaxed MX128 tile stays off by default as 0017 left it; merge residue (`22: @both` ...) in the test registry and the changelog replaced by the real lines; a head piece of 0 means the decode piece |
| 0023 (fused read-out) | the tile-kernel fields the old tail carried move here |
| 0005 (rows) | `TF_FLASHNEXT_WINDOW_CHECK` gets the valid-form rows the environment test asks of every rule |
| 0012 (kv8) | `snap.order` and `orderFor` return one named type; the paging test's fake backend has the three fp8 launches; every host test that builds an `Engine` undefined sets `kv = .bf16`; the tests, the recipe note and the changelog bullet state the fp8 cache's bytes with the draft head kept bf16 (12 layers save 992 bytes a token, 18,880 bytes a token against 30,784, four full-window streams against bf16's three), and the changelog bullet 0027 had cut off is whole again |
| 0015 (n-gram row cache) | its host test stores the reader `ple_cache.open` returns the way `Ngram.fill` does, and calls `aheadChunk` as the module's function |

## Checks this package has passed

- All 13 seat on v1.2.7 with the resolutions above; the seated tree is `f3f911ec6c3981ee59c2f7f324dcb443c5433666`.
- `scripts/check-patch-reverts.py patches/1.2.7`: 28 findings, each in `REVERTS.allow` (copied from `patches/1.2.6`;
  every line still matches).
- `zig build test-cuda-host` on the applied series, Windows, Zig 0.17.0: 5,327 of 5,445 tests pass, 118 skipped; one
  step does not compile, `cuda_ple_cache.zig`'s anonymous `std.posix.mmap`, which is Linux-only code (the same site is
  in `patches/1.2.6`). The Linux run of this step could not be repeated: the WSL volume went read-only. The Windows
  and Linux results for `patches/1.2.6` agree on every other test.
- Each of the 11 prefixes 1, 3 to 11 and 13 built on spark6 (image `up127` for v1.2.7 alone and `v1` to `v13`) and booted
  with the window self-check at 1,176 of 2,080 and golden 6/6 identical to stock's; decode and cold prompt time in
  `README.md`.
- `scripts/check-patch-packages.sh`: `RECORD.md`, `SHA256SUMS` and the hashes.
- **0014 (added 2026-11-12):** written here, not re-seated: the drafter's BF16 linears re-coded to MXFP8 at load
  (`TF_FLASHNEXT_MTP_WEIGHTS=bf16|mxfp8`, default `bf16`). Its encoder and host test are the load-time MXFP8 coder of the rejected
  `TF_FLASHNEXT_HC_MXFP8` experiment (`work/ladder/rungs/gm21.patch`), re-pointed from the read-out matrices at the
  drafter's projections; the hook is one flag in `cuda_projection.zig` set only while `cuda_mtp.zig` loads. Built as
  image `v16` on spark6 and measured in `README.md`; `v16k` carries the round and kernel logs.
- **0015 (added 2026-11-13):** written here, not re-seated: fp8 KV on every served stream and in the shared page pool
  (`TF_FLASHNEXT_KV_PAGES` with `KV_DTYPE=fp8`, pool off by default). It carries three repairs of 0003 found on the way
  (lane-parts and pool-lane streams kept bf16 caches; the fp8 staging's swapped head arguments; the marks' bf16 tail
  offset), described and measured in `README.md`. Built as image `fp8pg2` on spark6 from this text less its kernel
  contract records and the two pool tests' `kv = .bf16` lines, which no image contains; the records hold the nvcc 13.3 resources `scripts/qwen38/zig/target/fp8res.sh`
  measured for that image's `flashnext_attn.cu` (`fn_attn_chunks_kv8` re-measured at 80 registers on sm_120 and sm_121).
  `zig build compile-config-server -Dtarget=aarch64-linux-gnu` passes on the laptop and `zig build test-cuda-host`
  passes on a native Linux filesystem (as pristine v1.2.7 does); the fp8 device test passes in image `fp8pg2` and
  fails in `v16`; `scripts/check-patch-reverts.py`: every finding allowed (the 0015 reasons are in `mkallow.py`).
- **0016 (added 2026-11-13):** written here: 0009's 12-bit read-out tile loads each warp's blocks two groups ahead of
  their products (`warp_load`, `warp_decode` and `group_block` replace `warp_tiles` in `qmmf_q12.cuh`; the decode
  and the products are unchanged). `scripts/check-patch-reverts.py`: its 10 findings (the split `warp_tiles`)
  allowed, the reasons in `mkallow.py`.
- **0017 (added 2026-11-13):** written here: `TF_FLASHNEXT_FUSED_SPLIT=1` (default off) runs lane calls split over K
  on a cluster, 2,048 columns or more, on the fused form, one block a 64-column tile adding its K slices in slice
  order (the cluster's order). Eight new `qmmf_kernel` instances (MXFP8 and BF16, row tiles 16 and 32, bf16 and fp32
  out) carry no kernel contract records, as 0009's Q12 instances carry none; the knob is registered in
  `platform/environment.zig` and covered in its test. Both patches built as image `rq17` on spark6 (`rq17x` with
  v16x's kernel and expert logs) and measured in `README.md`; `zig build compile-config-server
  -Dtarget=aarch64-linux-gnu` passes on the laptop; `zig build test-cuda-host` passes on WSL ext4 (Zig 0.17.0) for the
  17-patch tree, as it does for pristine v1.2.7 and the 15-patch tree (`scripts/qwen38/zig/target/readout/host17.sh`:
  rc 0 on all three, 330, 215 and 264 s).
