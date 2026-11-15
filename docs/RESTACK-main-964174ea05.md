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
- **The n-gram gather's parked host workers moved to a shared `host_pool.zig` (`b0a3d76ba1`, a move:
  `cuda_ple_pool.zig` re-exports it), and the HIP reader gained page advice and a pool-spread decode gather
  (`f558a1d5d8`, `1bbc79e391`, `32ef95dbad` in `hip/tables.zig` and `host_pages.zig`, which no CUDA file imports;
  `28f03c23c8` adds a HIP test and a `calls` counter to the shared pool, nothing else).** The CUDA reader 0004 sits in
  front of is v1.2.7's: `git diff --stat 93a2e93ece 964174ea05` is empty for `cuda_ple_reader.zig`,
  `cuda_ple_gather.zig`, `cuda_ple_nvfp4_test.zig` and `core/direct_io.zig`, and `cuda_ple.zig` (5 lines) and
  `cuda_ple_ahead.zig` (16) changed only in how they read `TF_FLASHNEXT_WARM_AHEAD` and `TF_FLASHNEXT_TABLE_WARM`. So
  nothing upstream reads a row early into memory, caches one, or reads a drafted token's rows ahead: 0004 is not
  absorbed, and the A/B below decides whether it still pays.
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
same to the digit in every pair, which is the stronger statement: the two stacks do the same work. That window ran no
patch dropped; the one patch put to that test since is 0004, below.

## 0004 keep or retire: A/B on spark6 (2026-11-15)

Arms built from pristine `964174ea05` by `build_patches.sh` and relabelled `tf.kernels=embedded`: **A** (`r2a`) = the
re-seated package, all 19 patches; **B** (`r2b`) = the package without 0004 and without 0012, which only lets 0004's
cache read through the page cache and cannot stand alone (`0001-0003` plus one patch carrying `0005-0011` and
`0013-0019` re-cut without them; its tree is the A tree minus exactly 0004's and 0012's files and lines,
`restack2-checkb.py`). Both arms ran the recipe's settings with the FP4 launcher block, fp8 KV at 262,144
(`TF_FLASHNEXT_KV_PAGES=4096` at 6 and 8 streams), a fresh boot a cell bound to 127.0.0.1, golden 6/6 against the
previous window's replies, one decode pass of 512-token prose and code replies; A B B A at 1, 2, 4, 6 and 8 streams in
one window (`restack2-win.sh` through `restack2-chain.sh`, spark6 `~/work/restack2/win/w1`). The noise rule: an arm
is slower in a cell when both its runs are under both of the other's and the means differ by more than 1 percent.

Aggregate tok/s, prose / code, both runs of each arm (window 17:08 to 17:44 UTC; receipts in
`scripts/qwen38/zig/target/restack2-receipts/`):

| streams | A, with 0004 | B, without 0004 and 0012 | B against A, means | noise rule |
|---:|---|---|---|---|
| 1 | 62.6, 61.5 / 84.5, 82.8 | 56.0, 62.2 / 76.6, 83.0 | -4.8% / -4.6% | same (B's second run is over A's) |
| 2 | 87.6, 85.2 / 124.0, 123.5 | 82.3, 81.0 / 120.4, 117.3 | -5.5% / -4.0% | B slower, prose and code |
| 4 | 114.5, 116.3 / 166.2, 168.8 | did not boot, both runs | - | B refuses 4 full-window streams |
| 6 | 151.1, 148.4 / 216.0, 214.2 | 134.3, 134.1 / 199.9, 202.5 | -10.4% / -6.5% | B slower, prose and code |
| 8 | 168.2, 166.5 / 250.3, 246.0 | 149.9, 148.6 / 234.2, 233.3 | -10.8% / -5.8% | B slower, prose and code |

- **Exactness:** golden 6/6 identical to the previous window's replies in all 18 cells that served, A and B; every one
  of the 20 boots logs "window self-check: 1176 of 2080 rows byte-equal to their one-token steps (widths 1-64)"; the
  counters (rounds / drafted / accepted) are the same to the digit between the arms in every cell, so B does the same
  work, only slower.
- **B at 4 streams:** `--parallel 4 needs 20.15 GiB for its streams at a 262144-token window, and the CUDA memory
  budget leaves 17.79 GiB`, twice; A at 4 streams had 25.6 GiB left after the reserve (5.04 GiB a stream). Without
  0004 the n-gram rows are read through the page cache (0004's cache reads them `O_DIRECT`, leaving the page cache to
  the weights), which is the likely reason the budget at boot is 7.8 GiB smaller; not measured further.
- **Verdict: 0004 stays (re-seated).** Retiring it needs B exact and slower nowhere; B is exact, but slower at 2, 6
  and 8 streams in both passes by 4.0% to 10.8% (both its runs under both of A's) and cannot serve 4 streams at all.
  The noise rule's rerun confirms a loss before it is counted against a kept arm; it was not run, because no rerun
  result could make B serve 4 streams or meet the retirement condition. 0012 stays with it. Production was restored
  at 17:44:18 UTC, `/health` 200, and the arm images were removed.

## Host suite on spark6 (native aarch64, Zig 0.17.0, `zig build test-cuda-host -j8`, 2026-11-15)

Run on the box, not the laptop (`scripts/qwen38/zig/target/restack2-host.sh`, spark6 `~/work/restack2/host`, 16:36 to
16:53 UTC): pristine `964174ea05` against the same tree with this package applied, Zig from
`~/qwen-zig/scripts/config.sh` (sha-checked, its two values read in a subshell), umask 0002, each environment with its
own local cache so every test runs again. "clean" has no `TF_` or `TENSORFOLD_` variable; "prod" has the 25 that
`config.sh` exports, `TF_FLASHNEXT_GATHER_READ=pread` among them.

| tree | environment | steps | tests | failed |
|---|---|---|---|---|
| base `964174ea05` | clean | 406 of 408 | 6,724 of 6,759 passed, 33 skipped | 2 |
| base `964174ea05` | prod | 406 of 408 | 6,724 of 6,759 passed, 33 skipped | 2, the same two |
| base + this package | clean | 406 of 408 | 6,767 of 6,803 passed, 34 skipped | 2, the same two |
| base + this package | prod | 406 of 408 | 6,767 of 6,803 passed, 34 skipped | 2, the same two |

- **Inherited from main, in every run, and both about the box:** `cli_config_test` "serve --config: expand reads the
  file, passes other commands through and names what it cannot read" (umask 0002 leaves the test's config file group
  writable and `cli_config.zig:40` refuses a config other users can write) and `listener` "accepted IPv4 and IPv6 TCP
  streams disable Nagle for incremental responses" (spark6 has no IPv6, `/proc/sys/net/ipv6` is absent, so
  `Listener.open` returns `SocketFailed` at `listener.zig:25`). The three DeepSeek-V4.1 hashes printed as "expected
  this output" above them come from `deepseek_fixture_test`'s "namespace pins reject unrelated prompt drift", which
  provokes those mismatches on purpose (`expectError(error.TestExpectedEqual, ...)`) and passes; the first count
  named them as the two failures in error.
- **0004's three failures of the first run, and why.** That run sourced `config.sh` for its Zig version, so the
  tests ran with `TF_FLASHNEXT_GATHER_READ=pread`, and `Ngram.init` opens the row cache on that switch (the serve's
  way of turning it on). Then `cuda_ple_cache_test.zig:17` asserted `g.cache == null`, a statement about the shell;
  "slots collide" put its own reader over the one `init` had opened, and the 4 leaked allocations are that reader
  (`Reader`, its files, shards and starts); and upstream's short-read test poisons the positional readers' offsets,
  but with a cache open the rows come through the cache's own offsets, so no read is short. The same tests had the
  same dependence on 1.2.7, whose host runs were on WSL with no such variable.
- **Fixed in 0004, so the suite gives one answer in either shell** (the table: `prod` was the failing setting):
  the tests take the table to a known state (`plain`: any cache `init` opened is closed through the new
  `ple_cache.close`, which `Ngram.deinit` now calls too, and the reference rows are the mapping's); the first test
  asserts that `init` follows `TF_FLASHNEXT_GATHER_READ` instead of asserting the variable unset; the cache tests open
  their readers at the default sizes explicitly (`openSized`), so `TF_FLASHNEXT_GATHER_CACHE_MIB` and `_THREADS`
  cannot change them (`_THREADS=0` made the first test panic at `g.ahead_thread.?`); and upstream's short-read test
  closes the cache before it poisons the positional readers, as it already pins `read_mode` (2 lines). The test
  binary that holds these tests, run directly in both environments: 304 passed, 1 skipped (the real-checkpoint test),
  0 failed, each time.
- **A latent bug fixed on the way:** `TF_FLASHNEXT_GATHER_CACHE_MIB=0`, documented as rounding up to one slot, gave
  0 slots, and `Reader.create` handed 0 to `std.math.isPowerOfTwo`, which asserts; one slot cannot work either (`slotOf`
  would shift a 64-bit hash by 64). `slotsFor` now rounds to two slots at the fewest and saturates an overflowing MiB
  count, `create` refuses fewer than two, and the rule's text says two. New test: "the row cache's address space is a
  power of two of slots, two at the fewest".
- **The new slot test is load-bearing** (`restack2-mutants.sh`, spark6, clean shell; receipts
  `restack2-receipts/mutants-summary.txt`): unmutated, the package fails only main's two; M1, the old rounding, fails
  it ("expected 2, found 0" at `cuda_ple_cache_test.zig:123`); M2, `create` without its two-slot guard, crashes it
  (`std.math.isPowerOfTwo` asserts); M3, the MiB count shifted instead of saturated, fails its saturation check. The
  M1 run also failed `cuda_disk_test` "kept states written to disk read back byte-equal after a restart" once; it
  passed in the unmutated, M2 and M3 runs and is not 0004's, and it was not looked into further.
- The served path is unchanged: the same `init`, `fill`, `row` and read-ahead code. `deinit` now joins the prompt
  read-ahead and closes the cache before it stops the gather pool rather than after; both are idle at that point.
- Laptop note: the first host run (WSL) also caught a real 0004 re-seat defect, a third `draftMany` call site upstream
  added in `cuda_mtp_nonfinite_more_test.zig`; fixed in the package (commit `8399d80`).
