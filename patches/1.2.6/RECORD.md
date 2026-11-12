# Provenance of this package

- **What it is:** our own levers on TensorFold v1.2.6, as 13 additive patches. Nothing here is another project's
  commit; the base tree is never edited in place.
- **Base it applies to:** `ashhart/TensorFold` v1.2.6, `6e9af930261a88bb28ac0bfb157ce8e57e9eea07`. `apply.sh` refuses
  any other HEAD.
- **Where the text comes from:** the 32-patch series this directory held before (campaign repo history up to
  `6b4cb3b`; its commits are the fork `ots/tensorfold-levers124`, branch `fix126` and the `archive/*` tags), re-cut
  one lever a patch. Old patch 0030 (the integration tail) is not applied at all.
- **Whether we edited it:** yes. `scripts/qwen38/zig/target/mkladder.sh` applies the old patches up to each lever's
  last one on a pristine tree, lets `overlay.py` make the repairs listed below at the rung where the damage
  happens, and writes patch N as the exact difference between rung N-1 and rung N (`mkseries.sh`). The series was
  replayed onto pristine and gives the last rung's tree bit for bit (tree `88469e734f1bc67ae9a83cf8757c1f4f9e282db3`).

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

## Checks this package passes

- `apply.sh --check TREE`: all 13 apply in order on the base, nothing written (run on spark6).
- Every prefix compiles: `zig build compile-config-server -Dtarget=aarch64-linux-gnu` on the tree after each of
  the 13 patches (laptop, Zig 0.17.0). The box built and booted images of prefixes 7, 8, 9, 10, 11 and 13 as they
  stand here (`g21`, `g25`, `g26`, `g27`, `g29`, `g32`), and of prefixes 1 and 3 to 6 before the two n-gram repairs,
  which do not touch 1 to 3.
- The family's host suite, `zig build test-cuda-host`, on Linux (Zig 0.17.0, WSL) on the applied series and on pristine
  v1.2.6: both end with the same three DeepSeek chat-golden mismatches and no other failure and no compile error. The
  old series did not compile that step (four errors) and failed seven tests besides; the repairs above are what
  changed. The type-check and the boxes' images are of the same sources apart from tests, the recipe note and the
  changelog, which no image contains.
- `scripts/check-patch-reverts.py patches/1.2.6`: 28 findings, each listed in `REVERTS.allow` with its reason.
- `scripts/check-patch-packages.sh`: `RECORD.md`, `SHA256SUMS` and the hashes.
