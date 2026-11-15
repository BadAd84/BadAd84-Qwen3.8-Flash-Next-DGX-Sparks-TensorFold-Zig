# Restack onto upstream main `964174ea05` (2026-11-15)

Upstream `ashhart/TensorFold` main moved from v1.2.7 (`93a2e93ecebff8aa52b88e58c5dd222516e69c5f`) to
`964174ea05879e6dde1de1198a3aae3ef8b46a3b` (`v1.2.9-33-g964174ea05`, 2026-11-15 12:43 UTC; 474 commits, latest
release v1.2.9 = `6b9de69510`). This is the whole stack re-seated onto it, decided patch by patch, as the repo's
conventions require. Nothing was posted or pushed outside this repo.

The sha was read from GitHub itself at the start of the work (`git ls-remote https://github.com/ashhart/TensorFold
refs/heads/main` = `964174ea05879e6dde1de1198a3aae3ef8b46a3b`), not from a stale ref: the previous session's note
("3a56d4eb9224 at 13:00 UTC") was an earlier tip of the same day.

**Upstream moved again while this ran:** at 15:00 UTC `main` was `5c82ef28a6c8ea2094563266e47d1b7b3051b129`
(18 commits on, 14:39 UTC). None of them touches our surface: `git diff --stat 964174ea05 up/main --
zig/src/families/flashnext zig/kernels/cuda` is empty, and the commits are pull, cluster, server, DeepSeek-V4.1 on
Metal and docs work. The package stays on `964174ea05` for this run; the next re-seat starts from `5c82ef28a6`.

## What moved upstream that matters to us

- **The FP8 expert loader was replaced (v1.2.8, #2892, commit `1bc80c5f78`).** One block-FP8 reader in
  `core/quant/fp8.zig` now loads Flash Next's MTP head, Drama 3 and Kolibri-1; `flashnext/cuda_fp8_experts_load.zig`
  lost 14 lines to it. This is the same function the INT4 diagnostic port had its own copy of - the one place the
  INT4 re-seat needed a real decision (`patches/main-964174ea05-int4/RECORD.md`).
- **Flash Next CUDA draws and draft lanes were reworked (v1.2.9, #2927 `6b9de69510` and `325a1a795a`, `f2d4a74731`,
  `b5764e39ec`, `56882545b4`):** a lone stream draws on its own path, shared verify draws go behind one completion,
  draft-lane reductions join before keyed picks. None of these is one of our levers, but they all move decode work.
- **The prompt cache gained a bounded ladder of intermediate checkpoints (`78140ea84f`, `TF_PROMPT_INTERMEDIATE`,
  off by default).** Off in every arm here; it is a lead for long agent turns, not a re-seat question.
- **The n-gram gather's parked host workers moved to a shared `host_pool.zig`** and gained hint-based read-ahead
  (`cuda_ple_ahead.zig`, `cuda_ple_pool.zig`, `cuda_ple_gather.zig`; HIP work `f558a1d5d8`, `b0a3d76ba1`,
  `28f03c23c8`). Our 0004's row cache and draft-ahead read rows; theirs issues file hints, so both stay, but the
  integration point moved and the re-seat had to land on the new files.
- **Qwen3.8 CUDA work in v1.2.8 (#2934 `c247ca278e`, #2933) is the `qwen3_5` family**, not Flash Next: 2-8-row
  windows bucketed at 4 and 8, and a one-row step that no longer copies its recurrent state. It does not touch our
  patch surface.
- **`flashnext/cuda_lanes.zig` is held at 600 lines upstream (`1d5e7af63f`).** The base is 597; our series (0001's
  window comment and 0010's pricing hook) takes it to 603. Nothing here enforces it, but a future upload of 0001 or
  0010 would have to move those lines.

## Per-patch verdicts

The full table with the evidence for each verdict is `patches/main-964174ea05/RECORD.md`. In short: **19 patches,
1 applied cleanly (0002), 18 re-seated with `--3way` (13 of those needed only their `CHANGELOG.md` hunk moved), and
none retired - upstream absorbed none of them.** The four that are pending upstream rather than absent are 0014
(PR #3218, OPEN), 0008 (PR #3413, OPEN), 0007 (issue to be filed) and 0017 + 0019 (to be filed); both PRs were
checked read-only and neither is merged.

The re-seat itself changed no behaviour: every added and removed line of every code hunk is identical to
`patches/1.2.7`, and the applied tree is byte-identical to the staged tree the patches were cut from (106 paths, 0
differ). `scripts/check-patch-reverts.py` finds exactly the same 88 line findings as the 1.2.7 package, all allowed.

## Gates

- `apply.sh --check` on a pristine worktree at the base: `19 patches apply on 964174ea05879e6dde1de1198a3aae3ef8b46a3b
  in order (nothing written)`.
- aarch64 type-check (`zig build compile-config-server -Dtarget=aarch64-linux-gnu`, Zig 0.17.0, Windows) on the
  base and on the applied tree: both `rc 0` (856 s for the base).
- the images themselves: the spark6 docker build of the series compiles the fatbins, the native binary and the
  server from the applied tree - it is the same compile on aarch64 with nvcc (`build_patches.sh`).
- `scripts/check-patch-packages.sh`: CLEAN.

# Restack onto upstream main `964174ea05` (2026-11-15)

Upstream `ashhart/TensorFold` main moved from v1.2.7 (`93a2e93ecebff8aa52b88e58c5dd222516e69c5f`) to
`964174ea05879e6dde1de1198a3aae3ef8b46a3b` (`v1.2.9-33-g964174ea05`, 2026-11-15 12:43 UTC; 474 commits, latest
release v1.2.9 = `6b9de69510`). This is the whole stack re-seated onto it, decided patch by patch, as the repo's
conventions require. Nothing was posted or pushed outside this repo.

The sha was read from GitHub itself at the start of the work (`git ls-remote https://github.com/ashhart/TensorFold
refs/heads/main` = `964174ea05879e6dde1de1198a3aae3ef8b46a3b`), not from a stale ref: the previous session's note
("3a56d4eb9224 at 13:00 UTC") was an earlier tip of the same day.

**Upstream moved again while this ran:** at 15:00 UTC `main` was `5c82ef28a6c8ea2094563266e47d1b7b3051b129`
(18 commits on, 14:39 UTC). None of them touches our surface: `git diff --stat 964174ea05 up/main --
zig/src/families/flashnext zig/kernels/cuda` is empty, and the commits are pull, cluster, server, DeepSeek-V4.1 on
Metal and docs work. The package stays on `964174ea05` for this run; the next re-seat starts from `5c82ef28a6`.

## What moved upstream that matters to us

- **The FP8 expert loader was replaced (v1.2.8, #2892, commit `1bc80c5f78`).** One block-FP8 reader in
  `core/quant/fp8.zig` now loads Flash Next's MTP head, Drama 3 and Kolibri-1; `flashnext/cuda_fp8_experts_load.zig`
  lost 14 lines to it. This is the same function the INT4 diagnostic port had its own copy of - the one place the
  INT4 re-seat needed a real decision (`patches/main-964174ea05-int4/RECORD.md`).
- **Flash Next CUDA draws and draft lanes were reworked (v1.2.9, #2927 `6b9de69510` and `325a1a795a`, `f2d4a74731`,
  `b5764e39ec`, `56882545b4`):** a lone stream draws on its own path, shared verify draws go behind one completion,
  draft-lane reductions join before keyed picks. None of these is one of our levers, but they all move decode work.
- **The prompt cache gained a bounded ladder of intermediate checkpoints (`78140ea84f`, `TF_PROMPT_INTERMEDIATE`,
  off by default).** Off in every arm here; it is a lead for long agent turns, not a re-seat question.
- **The n-gram gather's parked host workers moved to a shared `host_pool.zig`** and gained hint-based read-ahead
  (`cuda_ple_ahead.zig`, `cuda_ple_pool.zig`, `cuda_ple_gather.zig`; HIP work `f558a1d5d8`, `b0a3d76ba1`,
  `28f03c23c8`). Our 0004's row cache and draft-ahead read rows; theirs issues file hints, so both stay, but the
  integration point moved and the re-seat had to land on the new files.
- **Qwen3.8 CUDA work in v1.2.8 (#2934 `c247ca278e`, #2933) is the `qwen3_5` family**, not Flash Next: 2-8-row
  windows bucketed at 4 and 8, and a one-row step that no longer copies its recurrent state. It does not touch our
  patch surface.
- **`flashnext/cuda_lanes.zig` is held at 600 lines upstream (`1d5e7af63f`).** The base is 597; our series (0001's
  window comment and 0010's pricing hook) takes it to 603. Nothing here enforces it, but a future upload of 0001 or
  0010 would have to move those lines.

## Per-patch verdicts

The full table with the evidence for each verdict is `patches/main-964174ea05/RECORD.md`. In short: **19 patches,
1 applied cleanly (0002), 18 re-seated with `--3way` (13 of those needed only their `CHANGELOG.md` hunk moved), and
none retired - upstream absorbed none of them.** The four that are pending upstream rather than absent are 0014
(PR #3218, OPEN), 0008 (PR #3413, OPEN), 0007 (issue to be filed) and 0017 + 0019 (to be filed); both PRs were
checked read-only and neither is merged.

The re-seat itself changed no behaviour: every added and removed line of every code hunk is identical to
`patches/1.2.7`, and the applied tree is byte-identical to the staged tree the patches were cut from (106 paths, 0
differ). `scripts/check-patch-reverts.py` finds exactly the same 88 line findings as the 1.2.7 package, all allowed.

## Gates

- `apply.sh --check` on a pristine worktree at the base: `19 patches apply on 964174ea05879e6dde1de1198a3aae3ef8b46a3b
  in order (nothing written)`.
- aarch64 type-check (`zig build compile-config-server -Dtarget=aarch64-linux-gnu`, Zig 0.17.0, Windows) on the
  base and on the applied tree: both `rc 0` (856 s for the base).
- the images themselves: the spark6 docker build of the series compiles the fatbins, the native binary and the
  server from the applied tree - it is the same compile on aarch64 with nvcc (`build_patches.sh`).
- `scripts/check-patch-packages.sh`: CLEAN.

## Measured on this base (2026-11-15, spark6)

One decode pass of 512-token prose and code replies a cell, one fresh boot a cell, aggregate tok/s, golden 6/6
identical in every cell (`~/work/restack/win2`, images `um96` upstream main alone, `rs96` this package, `rq7` the
1.2.7 package).

**This base against upstream main alone, bf16 KV at 131,072** (upstream main refuses `--kv-cache fp8` for this
family, so the like-for-like arm is bf16):

| streams | um96 | rs96 | rs96 against um96 |
|---:|---|---|---|
| 1 | 52.1 / 73.2 | 64.6 / 88.8 | +24.0% / +21.3% |
| 2 | 80.8 / 108.6 | 90.9 / 130.1 | +12.5% / +19.8% |
| 4 | 106.4 / 155.2 | 116.8 / 177.6 | +9.8% / +14.4% |

**This base against the 1.2.7 package, fp8 KV at 262,144** (the production setting, `KV_PAGES=4096` at 6 and 8):

| streams | rs96 | rq7 | rs96 against rq7 | counters (rounds / drafted / accepted) |
|---:|---|---|---|---|
| 1 | 63.7 / 85.3 | 63.9 / 85.4 | -0.3% / -0.1% | identical, 143/574/369 and 88/628/423 |
| 2 | 89.6 / 127.0 | 90.1 / 126.4 | -0.6% / +0.5% | identical, 321/1089/702 and 177/1169/845 |
| 4 | 117.2 / 170.1 | 116.8 / 169.3 | +0.3% / +0.5% | identical, 697/2092/1285 and 400/2384/1644 |
| 6 | 151.5 / 216.5 | 150.5 / 214.7 | +0.7% / +0.8% | identical, 994/3160/2010 and 582/3534/2484 |
| 8 | 169.2 / 249.8 | 167.1 / 247.1 | +1.3% / +1.1% | identical, 1356/4128/2546 and 802/4646/3286 |

Every `rs96` and `rq7` boot logs "window self-check: 1176 of 2080 rows byte-equal to their one-token steps (widths
1-64)". One run an arm, so no cell meets the noise rule's two-runs condition for a slowdown; the counters are the
same to the digit in every pair, which is the stronger statement: the two stacks do the same work. **No patch is
retired**, so no cell was run with one dropped.

## Host suite on spark6 (native aarch64, Zig 0.17.0, `zig build test-cuda-host -j8`, 2026-11-15)

Run on the box, not the laptop: pristine `964174ea05` against the same tree with this package applied, the toolchain
the image builds use (`~/qwen-zig/scripts/config.sh`, sha-checked).

| tree | steps | tests | failed |
|---|---|---|---|
| base `964174ea05` | 406 of 408 | 6,724 of 6,759 passed, 33 skipped | 2 |
| base + this package | 405 of 408 | 6,764 of 6,802 passed, 34 skipped | 4, and 1 leak |

- **Inherited from main (both trees):** the two DeepSeek-V4.1 encoder fixture hashes in
  `zig/src/server/fixtures/deepseek_v41_encoder/` (`recorded_prompt_sha256` `b4cfdbdc...` and `d8e86eef...` do not
  match the rendered prompts). None of our patches touches the server or that family.
- **Ours, patch 0004 (the n-gram row cache), NOT fixed in this run:**
  - `cuda_ple_cache_test`: "NVFP4 rows read by pread equal the mapped rows, cold, ahead and after eviction" fails at
    `cuda_ple_cache_test.zig:17`, `try std.testing.expect(g.cache == null);`
  - `cuda_ple_cache_test`: "NVFP4 rows read by pread stay exact when slots collide" leaks 4 allocations
  - `cuda_ple_nvfp4_test`: "PLE positional reads: mapped bytes, pool callers and short reads preserve history and
    destination" fails at `cuda_ple_nvfp4_test.zig:171`, `expected error.PleShortRead, found void`
  The re-seated 0004 applies and the served path measured exact (golden 6/6 in every cell, counters identical to the
  1.2.7 package's), but upstream reworked the same reader and pool (`host_pool.zig`, page advice `1bbc79e391`,
  `32ef95dbad`, the cold-gather pool `28f03c23c8`) and 0004's own tests no longer hold on this base. The package is not
  green until 0004 is re-seated against that work; its test expectations and the reader's short-read path are where to
  start.
- Laptop note: the first host run (WSL) also caught a fourth 0004 defect, a third `draftMany` call site upstream added
  in `cuda_mtp_nonfinite_more_test.zig`; fixed in the package (commit `8399d80`).
