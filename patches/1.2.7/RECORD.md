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
  Nothing here has been built into an image or measured on v1.2.7 yet; `scripts/qwen38/zig/target/v127.sh` is the
  stage that does it.

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
- Not yet run: the aarch64 type-check of each prefix, any image build, any measurement.
- `scripts/check-patch-packages.sh`: `RECORD.md`, `SHA256SUMS` and the hashes.
