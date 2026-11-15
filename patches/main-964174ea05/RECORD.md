# Provenance of this package

- **What it is:** our own levers on upstream TensorFold `main` at `964174ea05879e6dde1de1198a3aae3ef8b46a3b`
  (`v1.2.9-33-g964174ea05`, 2026-11-15 12:43 UTC), as 19 additive patches. Nothing here is another project's commit;
  the base tree is never edited in place. It is `patches/1.2.7` re-seated onto the new base (see below).
- **Base it applies to:** `ashhart/TensorFold` `964174ea05879e6dde1de1198a3aae3ef8b46a3b`. `apply.sh` refuses any
  other HEAD. The previous package, `patches/1.2.7`, applies to `93a2e93ecebff8aa52b88e58c5dd222516e69c5f`.
- **Where the text comes from:** `patches/1.2.7` (itself re-seated from `patches/1.2.6`). Each patch was re-seated one
  at a time in filename order on a worktree of the new base: `git apply --3way`, then the hand-written resolution
  below where the base changed the same lines, and patch N is the exact difference between the staged trees. The
  first pass was checked line for line: **every added and removed line of every code hunk was identical to
  `patches/1.2.7`**, only `CHANGELOG.md` placement and hunk context differing. The second pass (below) changed 0004's
  own code and tests and every `CHANGELOG.md` hunk, and nothing else.
- **Whether we edited it:** yes, by these resolutions and nothing else:
  - **0005, 0008:** `environment.zig` and/or `environment_test.zig` conflicted at the end of the rule and case arrays;
    both sides' entries are kept (the base's newest rules, then ours).
  - **0009:** `cuda_batch_kernels.zig`'s context line read `if (envOn(...))`, a helper v1.2.7 had; the base reads
    `const bf16 = try @import("sys").environment.read(bool, "TF_FLASHNEXT_PROMPT_BF16", true)`, so the re-seat keeps the
    base's form beside the added `k.q12 = ...` lane load.
  - **0010:** `environment.zig`'s `Kind` gains `text` (ours) while the base's `flashnext` scope stays.
  - **0004, second pass (2026-11-15):** its tests no longer depend on what the shell exports, and one latent bug is
    fixed; the served path is the same code. `ple_cache.close` (joins the prompt read-ahead, closes the cache) is what
    `Ngram.deinit` and the tests call; the tests take the table to a known state (`plain`: no cache, the mapping's
    rows), the first asserts that `init` follows `TF_FLASHNEXT_GATHER_READ` rather than that it is unset, and the
    cache tests open their readers at the default sizes explicitly (`openSized`); upstream's short-read test in
    `cuda_ple_nvfp4_test.zig` closes the cache before it poisons the positional readers (2 lines added). The bug:
    `TF_FLASHNEXT_GATHER_CACHE_MIB=0` gave 0 slots and `std.math.isPowerOfTwo(0)` asserts; `slotsFor` now rounds to two
    slots at the fewest and saturates, `Reader.create` refuses fewer than two, and the rule's text says two. Why: see
    `docs/RESTACK-main-964174ea05.md`, "Host suite". Its `cuda_mtp_nonfinite_more_test.zig` index line (stale since the
    hand fix in `8399d80`) is regenerated with the rest.
  - **Every `CHANGELOG.md` hunk, second pass:** rebuilt (`scripts/qwen38/zig/target/restack2-fixlog.py`) so each patch
    adds exactly its own bullets to the end of the base's `## Unreleased` list, one blank line apart, and 0015 edits
    0003's bullet in place. The first re-seat had left 0006 adding a second copy of upstream's own 1.2.6 note
    ("Internal: a CUDA family's disk module ..."), 0007 and 0014 each adding another copy of 0004's row-cache bullet,
    0010 deleting 0004's shared-pass bullet and carrying 0008's read-out bullet, 0015 losing its own bullet and
    appending an orphan line instead of editing 0003's, and ten blank lines before `## 1.2.9`. Every path other than
    `CHANGELOG.md` of every stage tree is unchanged by the rebuild (the script compares them before it writes).
  - **0002, 0012, 0013, 0016 to 0019:** no resolution needed (0012's text differs from the first pass only in two
    `index` lines and one context line, because 0004's `cuda_ple_cache.zig` and rule text changed under it).

## Per-patch verdicts on `964174ea05`

Every patch was tried on the pristine base (`git apply --check`), then re-seated with `--3way`, and each was checked
against upstream's tree, `CHANGELOG.md` and the release notes for a change that already does its work. **No patch is
retired: upstream has absorbed none of them.** The `C` column is empty by evidence, and the evidence for each "not
absorbed" is in the third column.

| patch | lever | verdict | evidence on `964174ea05` |
|---|---|---|---|
| 0001 | a lone copy window to the boot self-check's largest row-exact width; a log-carrying verify window on the row-by-row DeltaNet | B | `cuda_mtp.zig` still has `pub const max_rows: usize = 32`; no `TF_FLASHNEXT_WINDOW_CHECK`, `probeServed` or `windowCheck` in the tree. v1.2.8's #2934 (decode windows of 2 to 8 rows run at 4 or 8) is the batch row padding, not this window |
| 0002 | copy re-sync past an edit, the copy ramp and miss rules | A | applies cleanly; no `resync` field or `resyncFrom` in `core/lanes` at the base |
| 0003 | `--kv-cache fp8` for Flash Next (e4m3 rows with a scale a row) | B | `flashnext.Options` has no `kv8` field, so `native/cuda_refusal.zig` refuses `--kv-cache fp8` for this family by name; no `Fp8KvUnsupported` arm and no fp8 attention kernels for it |
| 0004 | n-gram rows through a direct-mapped row cache with parked readers, draft-ahead and one gather a shared pass | B, re-seated (second pass) | no row cache and no `TF_FLASHNEXT_GATHER_READ`; the CUDA reader it sits in front of is v1.2.7's (`cuda_ple_reader.zig`, `cuda_ple_gather.zig`, `core/direct_io.zig` unchanged since `93a2e93ece`); upstream's `cuda_ple_ahead.zig` issues bounded file *hints*, the pool only moved to `host_pool.zig` (`b0a3d76ba1`), and the page advice of `f558a1d5d8`/`1bbc79e391`/`32ef95dbad` is HIP-only. The keep/drop A/B against the package without 0004 (and 0012, which only extends its cache) is in `docs/RESTACK-main-964174ea05.md` |
| 0005 | prompt chunks without a drain, 3,072-row chunks, the relaxed MX128 prompt tile | B | no `TF_FLASHNEXT_PROMPT_MX128`, no `prompt_mx` kernels in `qmmf.cu` (the base's new prompt tile is an unsplit BF16 K32 one, a different tile) |
| 0006 | the MX128 tile in two stages, two blocks an SM | B | no `TF_FLASHNEXT_PROMPT_GEMM2`, no `prompt_mx2` instances |
| 0007 | the draft head's rows 4-bit by default (`TF_FLASHNEXT_DRAFT_HEAD`) | B | the base's `cuda_mtp_load.zig` still reads `else "bf16"`, one line above the `affine4` path it already carries; the issue for this default is not filed yet |
| 0008 | prompt passes' hyper-connection read-out as fused kernels, the shared expert read in place, wider head pieces | B | `flashnext_hc.cu` and `flashnext_hcn.cu` are ours (absent upstream); PR #3413 (`flashnext-readout-fused`) is OPEN and unmerged |
| 0009 | hyper-connection read-outs from a lossless 12-bit copy (`TF_FLASHNEXT_HC_Q12`) | B | no `qmmf_q12.zig`, `qmmf_q12.cuh` or `TF_FLASHNEXT_HC_Q12` |
| 0010 | a shared round priced from the environment (`TF_FLASHNEXT_ROUND_MS`, `DRAFT_ROW_MS`) | B | neither name exists; `Kind` has no `text` |
| 0011 | vision tower linears decoded at load, image rows up to 16,384 | B | `zig/src/vision/qwen_cuda_dequant.zig` is ours; no counterpart upstream |
| 0012 | the row cache can read through the page cache (`TF_FLASHNEXT_GATHER_DIRECT`) | B | the name does not exist |
| 0013 | the window self-check can log its first differing row (`TF_FLASHNEXT_CHECK_LOG`) | B | the name does not exist; `cuda_mtp_check.zig`'s differ log is ours |
| 0014 | the drafter's BF16 linears re-coded to MXFP8 at load (`TF_FLASHNEXT_MTP_WEIGHTS`) | B | the name does not exist in `zig/`, `CHANGELOG.md` or `docs/`; PR #3218 (`flashnext-mtp-weights`) is OPEN and unmerged |
| 0015 | fp8 KV on every served stream and in the shared page pool (`TF_FLASHNEXT_KV_PAGES` with fp8) | B | depends on 0003, which the base refuses, so pages with fp8 rows cannot arise; `TF_FLASHNEXT_KV_PAGES` itself is upstream's bf16 paging (#2244) |
| 0016 | 0009's 12-bit read-out tile loads two groups ahead | B | follows 0009 |
| 0017 | lane calls split over K on a cluster run on the fused form (`TF_FLASHNEXT_FUSED_SPLIT`) | B | the name does not exist; the branch `flashnext-fused-split-up` is not filed yet |
| 0018 | the read-out's reduce and mix inside its products (`TF_FLASHNEXT_READOUT_FUSE`) | B | the name does not exist |
| 0019 | the fused split's kernel contract | B | follows 0017 |

Pending upstream, recorded so they are never mistaken for absorbed: **0014 = PR #3218**, **0008 = PR #3413**,
**0007 = issue to be filed** (branch `flashnext-draft-head-affine4`), **0017 + 0019 = to be filed** (branch
`flashnext-fused-split-up`). All four branches are cut from an older main and are another lane's work; nothing was
posted or pushed by this re-seat. Verified read-only on 2026-11-15: both PRs are OPEN with `mergedAt` null.

## Checks this package has passed

- `patches/main-964174ea05/apply.sh --check` on a pristine worktree at the base (second pass): `apply.sh: 19 patches
  apply on 964174ea05879e6dde1de1198a3aae3ef8b46a3b in order (nothing written)`.
- Each patch is the exact `git diff` between consecutive stage trees (`scripts/qwen38/zig/target/restack2-stage.py`,
  `restack2-fixlog.py`); the second pass's final tree differs from the first pass's in 0004's paths and
  `CHANGELOG.md` only.
- `scripts/check-patch-reverts.py patches/main-964174ea05`: `19 patches, 89 findings, 89 allowed, 0 open, 0 stale`.
  The allow file is `patches/1.2.7`'s, and the finding set on the new base is exactly that set (88 line findings were
  compared; the 89th is the allow file's own header line), so the re-seat reverted nothing new.
- `zig build compile-config-server -Dtarget=aarch64-linux-gnu` (Zig 0.17.0, Windows, first pass): see
  `docs/RESTACK-main-964174ea05.md`. The second pass compiled in the spark6 host suites and in the image build.
- `scripts/check-patch-packages.sh`: `RECORD.md`, `SHA256SUMS` and the hashes.
- `zig build test-cuda-host` on spark6 (aarch64, second pass), in a clean shell and in the serve's (`config.sh`
  exported): 6,767 of 6,803 passed, 34 skipped, 2 failed in both, the same two the pristine base fails in both
  (`cli_config_test`, umask 0002; `listener`, no IPv6 on the box). Nothing of ours fails; details in
  `docs/RESTACK-main-964174ea05.md`.
