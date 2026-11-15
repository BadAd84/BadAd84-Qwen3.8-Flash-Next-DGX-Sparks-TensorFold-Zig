# Restack onto upstream main `964174ea05` (2026-11-15)

Upstream `ashhart/TensorFold` main moved from v1.2.7 (`93a2e93ecebff8aa52b88e58c5dd222516e69c5f`) to
`964174ea05879e6dde1de1198a3aae3ef8b46a3b` (`v1.2.9-33-g964174ea05`, 2026-11-15 12:43 UTC; 474 commits, latest
release v1.2.9 = `6b9de69510`). This is the whole stack re-seated onto it, decided patch by patch, as the repo's
conventions require. Nothing was posted or pushed outside this repo.

The sha was read from GitHub itself at the start of the work (`git ls-remote https://github.com/ashhart/TensorFold
refs/heads/main` = `964174ea05879e6dde1de1198a3aae3ef8b46a3b`), not from a stale ref: the previous session's note
("3a56d4eb9224 at 13:00 UTC") was an earlier tip of the same day.

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

## Measured on this base

See "Receipts" below.
