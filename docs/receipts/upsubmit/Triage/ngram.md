# 0004 (n-gram row cache) and 0012 (page-cache row reads), triaged on upstream main

Triage only: nothing was posted, nothing was pushed, no GPU job ran, nothing was compiled.

- **Upstream tip T** = `077998f7d9b14adebec3a2acc2caa47ff7ae6ec7`, 2026-11-16 15:26:10 +0000,
  `changelog: #3572 under Unreleased`, read with `timeout 90 git -C work/upmain fetch origin main`. T is 153 commits on
  from our series' base `964174ea05` (2026-11-15 12:43 UTC). Every apply, lean and grep result below is on T.
- **Trees**: `work/Triage-Ngram/wt-t` (pristine T; reset with `git reset --hard 077998f7d` after the prefix test) and
  `work/Triage-Ngram/wt-4alone` (T plus 0004 alone, with only 0004's three re-anchorings applied; see 0004 item 1).
- **Patch text** is `patches/main-964174ea05/0004-ngram-row-cache.patch` (20 files, +1,080/-25) and
  `patches/main-964174ea05/0012-gather-direct.patch` (5 files, +17/-1), both cut on `964174ea05`.

## Verdicts at a glance

| item | verdict | why |
|---|---|---|
| 0004: one pooled gather a shared pass (`TF_FLASHNEXT_GATHER_EARLY`) | **SUBMIT** (P1) | exact by construction, 5 files plus a test, measured load-bearing at 4 streams (-4.5% code, -4.3% prose when off) |
| 0004: prompt last-chunk evening (`TF_FLASHNEXT_PREFILL_TAIL`) | **SUBMIT** (P5) | exact on evidence, independent of the cache, measured never a loss (-0.2 to -0.5% when off), cold-prompt shape |
| 0004: the row cache (`TF_FLASHNEXT_GATHER_READ`, `_THREADS`, `_CACHE_MIB`) | **HOLD** (P2) | exact by construction, but the plain reader is equal or faster in every per-part measurement we have; its only large effect is inside a bundle we cannot attribute, and the stated memory mechanism does not survive inspection (see 0004 item 5) |
| 0004: drafted-token prefetch (`TF_FLASHNEXT_DRAFT_AHEAD`) | **HOLD** (P3, stacked on P2) | ~5% at one stream on 1.2.7, inert on 1.2.6; needs the cache, so it lands only with P2 and after it |
| 0004: next prompt chunk's rows (`warmNext`, under `TF_FLASHNEXT_WARM_AHEAD`) | **HOLD** (P4, stacked on P2) | needs the cache, and it also replaces upstream's own `WARM_AHEAD` hints when a cache is open: a semantics change that needs its own decision |
| 0004: `TF_FLASHNEXT_GATHER_LOG`, `GATHER_LOCK_SCALES`, `Stat`, `cuda_batch_gather_log.zig` | **RETIRE for upstream** | two more settings and 70 lines of diagnostics with no measured effect; ours to keep locally |
| 0012: `TF_FLASHNEXT_GATHER_DIRECT` | **HOLD, not a PR of its own** | a switch inside P2's code; its only measured effect is to make the cache tie the plain reader, which is an argument for P2 not existing, not for a second setting |

Rank of the SUBMIT items by expected gain on the owner's workload (decode at 2 to 8 streams and cold prompts on one
GB10): **P1 first**, **P5 second**. Of the HOLDs, P2 has the largest *claimed* effect and the weakest attribution; it is
the only one whose receipt could change the order.

## What upstream has today, and what these patches add

Upstream has no row cache and no `ple_cache`: `TF_FLASHNEXT_GATHER_READ`, `TF_FLASHNEXT_GATHER_CACHE_MIB`,
`TF_FLASHNEXT_GATHER_THREADS`, `TF_FLASHNEXT_DRAFT_AHEAD`, `TF_FLASHNEXT_PREFILL_TAIL`, `TF_FLASHNEXT_GATHER_EARLY`,
`TF_FLASHNEXT_GATHER_LOG`, `TF_FLASHNEXT_GATHER_LOCK_SCALES` and `TF_FLASHNEXT_GATHER_DIRECT` return 0 files at T
(`git grep -c <name> 077998f7d -- zig docs`), and no commit in T's history adds them (`git log -S` for `rowsMany`,
`prefillTail`, `aheadChunk`, `ple_cache`, `TF_FLASHNEXT_GATHER_READ`: no hits).

Upstream's own n-gram gather at T:

- **`Ngram.rows`** (`zig/src/families/flashnext/cuda_ple.zig`, 588 lines at T): `lastIds` hashes each token against the
  n - 1 token history into `tokens * heads` row ids, then for a non-MLX table calls `cuda_ple_gather.run`.
- **`cuda_ple_gather.zig`** sorts the ids, keeps one read a distinct row (in table order), spreads the distinct rows
  over the parked pool, joins, and copies duplicates from the first occurrence. So upstream already dedups; it dedups
  **within one `rows` call**.
- **`cuda_ple_reader.zig`** is the positional reader: `TF_FLASHNEXT_PLE_IO` is `pread` (the default on Linux) or `mmap`
  (the default elsewhere). `pread` is two `readPositionalAll` calls a distinct row (codes, then scales) through the
  page cache; `mmap` reads the row straight out of the mapping (`table.gather`) and takes a page fault a row part,
  which is why `GATHER_LOCK_SCALES` (ours) talks about a row faulting "one page, not two". `hint()` is a
  `POSIX_FADV_WILLNEED` a row.
- **`cuda_ple_ahead.zig`** (`TF_FLASHNEXT_WARM_AHEAD=1`, default 0) issues bounded `fadvise` hints for the next prompt
  chunk's rows, synchronously on the caller; it reads nothing into memory and leaves no worker. **`Ngram.warm`**
  (`TF_FLASHNEXT_TABLE_WARM=1`, default 0) is `MADV_WILLNEED` over the table in a thread.
- **The pool** is `host_pool.zig` now, re-exported by `cuda_ple_pool.zig` (`b0a3d76ba1`); the CUDA reader 0004 sits in
  front of is still v1.2.7's (`git diff 93a2e93ece 964174ea05` is empty for `cuda_ple_reader.zig`,
  `cuda_ple_gather.zig`, `cuda_ple_nvfp4_test.zig`, `core/direct_io.zig`).
- **Page-fault behaviour at T**: with `pread` (Linux default) a repeated n-gram row is a copy out of the page cache, so
  the table's touched pages stay resident and there is no bound on how much of it stays; with `mmap` each cold row part
  is a fault and the page is inserted into the same page cache. There is no userspace cache, no bound, and no
  distinction between the table's pages and the weights' beyond reclaim order.

What 0004 adds on top, in six behaviours:

1. **A row cache** (`cuda_ple_cache.zig`, 458 lines): a direct-mapped table of `2^n` slots of raw row bytes
   (96 bytes: 80 codes + 10 scales for a 160-wide head), an anonymous `mmap` sized from
   `TF_FLASHNEXT_GATHER_CACHE_MIB` (default 256), row ids hashed by `id * 0x9E3779B97F4A7C15 >> (64 - n)`,
   `O_DIRECT` file handles where the file system takes them, up to `TF_FLASHNEXT_GATHER_THREADS` (default 128) parked
   readers with a 16-deep batch ring, and `Ngram.fill` consulting it before the positional reader.
2. **Drafted-token prefetch** (`ple_cache.Ahead`, `TF_FLASHNEXT_DRAFT_AHEAD`, default off): a draft step's next tokens'
   row ids are pushed to the cache's workers as the head drafts; `cuda_mtp_ops.draft` and `draftMany` gain an `ahead`
   parameter (null keeps today's behaviour) and flush it around each head step.
3. **Next-chunk prefetch** (`ple_cache.warmNext`/`aheadChunk`, under `TF_FLASHNEXT_WARM_AHEAD`): with a cache open, the
   next prompt chunk's row ids are hashed and read on a helper thread while the current chunk runs, and upstream's own
   `warmAhead` hint call is skipped (`if (e.ngram.cache == null) e.ngram.warmAhead(...)`).
4. **Prompt last-chunk evening** (`cuda_chunk.prefillTail`/`tailRows`, `TF_FLASHNEXT_PREFILL_TAIL`, default 0): a final
   chunk under the threshold takes about half of what remains, so the last two chunks are of about equal rows.
5. **One gather a shared pass** (`cuda_ple_gather_lanes.early`/`rowsMany`, `TF_FLASHNEXT_GATHER_EARLY`, default off): a
   shared pass's lanes are hashed and gathered in one call (`rowsMany`) instead of one `rows` call a stream, with the
   dedup and the pool run shared; `cuda_batch_state.Gather.main` calls it first and returns.
6. **Instrumentation**: `TF_FLASHNEXT_GATHER_LOG` (a `Stat` in `cuda_ple_gather_lanes.zig` plus
   `cuda_batch_gather_log.zig` and the `Pass.chunk` join hook) and `TF_FLASHNEXT_GATHER_LOCK_SCALES` (`mlock` of the
   scale arrays at load).

Settings, code default against our serve (`scripts/qwen38/zig/target/int4/fp4conf-summary.txt` line 83 records the
launch environment; `AGENTS.md`'s config.sh gotcha lists the recipe's exports):

| setting | code default at T plus 0004 | our serve |
|---|---|---|
| `TF_FLASHNEXT_GATHER_READ` | `0` (plain reader) | `pread` (row cache on) |
| `TF_FLASHNEXT_GATHER_THREADS` | `128` | not exported (default) |
| `TF_FLASHNEXT_GATHER_CACHE_MIB` | `256` | not exported (default) |
| `TF_FLASHNEXT_DRAFT_AHEAD` | `0` | `1` |
| `TF_FLASHNEXT_WARM_AHEAD` (upstream's) | `0` | `1` |
| `TF_FLASHNEXT_PREFILL_TAIL` | `0` | `512` |
| `TF_FLASHNEXT_GATHER_EARLY` | `0` | `1` |
| `TF_FLASHNEXT_GATHER_LOG` | `0` | not exported |
| `TF_FLASHNEXT_GATHER_LOCK_SCALES` | `0` | not exported |
| `TF_FLASHNEXT_GATHER_DIRECT` (0012 only) | `1` (O_DIRECT) | not exported |

So every behaviour here is already behind a default-off setting, and our ON is a recipe export, not a code default.
The one exception is 0012's `GATHER_DIRECT`, whose default is on and which is inert until a row cache exists.

---

# 0004, the six answers

## 1. Applies on T?

`git apply --check` of 0004 alone on pristine T fails on exactly three files, and the other 17 check clean:

```
error: patch failed: CHANGELOG.md:37
error: CHANGELOG.md: patch does not apply
error: patch failed: zig/src/platform/environment.zig:51
error: zig/src/platform/environment.zig: patch does not apply
error: patch failed: zig/src/platform/environment_test.zig:67
error: zig/src/platform/environment_test.zig: patch does not apply
```

Dependencies, established rather than assumed:

- **Code: none.** All 15 modified files and all 5 new files are untouched by 0001 to 0003 except the two setting
  tables. 0004 creates `cuda_knobs.zig`, `cuda_ple_cache.zig`, `cuda_ple_cache_test.zig`, `cuda_ple_gather_lanes.zig`
  and `cuda_batch_gather_log.zig`, so it cannot sit behind anything that also creates them.
- **Context: 0001 only, in two hunks.** `environment.zig @@ -51,6 +51,14 @@` and `environment_test.zig
  @@ -67,7 +67,22 @@` are anchored on `TF_FLASHNEXT_WINDOW_CHECK`, a line **0001** adds. That is the whole dependency.
- With the prefix applied (`git apply --3way` of 0001, 0002, 0003 on T, each clean and with no unmerged file),
  `git apply --3way 0004` leaves **zero unmerged files**. T added one rule inside the same region
  (`TENSORFOLD_LFM2_KV_PAGES`, between `TF_PROMPT_INTERMEDIATE` and `TF_ROCE_GID_INDEX`), which is why the plain
  `--check` still fails at `environment.zig:51` after 0001: the hunk's trailing context is no longer adjacent.
- **Standalone on T (what a PR branch actually is)**: 0004 with `--3way` leaves three unmerged files, and the
  resolution is re-anchoring only, no code change. `environment.zig`: keep the eight added rules and drop 0001's
  `TF_FLASHNEXT_WINDOW_CHECK` line from the incoming block. `environment_test.zig`: the same for its two
  `WINDOW_CHECK` cases. `CHANGELOG.md`: place the two 0004 bullets in T's flat `## Unreleased` list (T separates
  bullets with blank lines; the patch's hunk assumes our staged ordering and also carries 0001's and 0003's bullets).
  I built exactly that tree (`work/Triage-Ngram/wt-4alone`) with `work/Triage-Ngram/resolve4.py`; the script drops the
  `WINDOW_CHECK` lines from the conflict's incoming side and nothing else. The result is 20 files, +1,090/-25 against
  T (the 10 lines over the patch's own +1,080 are the two sibling CHANGELOG bullets the 3-way carried in).

## 2. Absorbed upstream?

**No, in whole and in every part.** Evidence on T: the nine setting names and five new file names return 0 files
(`git grep`); no commit in T's history introduces them (`git log -S`); upstream's gather is v1.2.7's
(`git -C work/upmain diff --stat 964174ea05 077998f7d` over `cuda_ple_reader.zig`, `cuda_ple_gather.zig`,
`cuda_ple_ahead.zig`, `cuda_ple.zig` and `core/direct_io.zig` is empty, so the reader 0004 sits in front of is exactly
the one our base measured); the
prompt-chunk tail rule has no counterpart (`cuda_chunk.zig` at T is 74 lines, no tail function; the only `tailRows` in
the tree are `deepseek_v41/metal/prompt.zig` with its test `zig/tests/dsv41_metal/prompt_test.zig`, and
`qwen3_5/cuda_train.zig`, unrelated families).

**One neighbouring PR exists and must be cited, not confused**: upstream **#3467 is OPEN**,
"flashnext cuda: the mixed PLE shard and the nested shards leave the page cache after load" (head `fe9b4fc908`, base
`d2b37227a8`). It releases load-only checkpoint pages with `fadvise`-style advice after load and keeps the n-gram
tensor ranges; it changes page-cache *hygiene at load*, not how a row is read at serve time. It is complementary, and
it is the mechanism upstream currently prefers for page-cache pressure. Its numbers matter to this triage and are used
in item 5. (Read-only `gh api`; nothing was posted.)

## 3. What it changes at run time

Two sentences a behaviour:

- **Row cache (behaviour 1)**: on every PLE gather (a prompt chunk's host gather, or a decode round's, on the gather
  thread or a pool worker) `Ngram.fill` asks the cache for each distinct row before the positional reader, and the
  cache serves it from its slots, reads it with two `O_DIRECT` reads on a miss, or (busy slot, another row's write in
  flight) reads it without keeping it. It changes where a row's 90 bytes come from, not which rows are asked for or
  how they are dequantized, so replies are byte-identical by construction (see item 6).
- **Drafted-token prefetch (2)**: `cuda_mtp_ops.draft`/`draftMany` flush a batch of the drafted token's row ids to the
  cache's parked readers right after each head step, so the next round's gather finds them; with `DRAFT_AHEAD` unset
  the parameter is null and the code is today's. No arithmetic is touched, so replies are identical by construction.
- **Next-chunk prefetch (3)**: at a prompt chunk boundary `cuda_lanes` and `cuda_prompt` call `ple_cache.warmNext`,
  which hashes the next chunk's ids on a helper thread and prefetches them; when a cache is open upstream's
  `warmAhead` hint call is skipped, so this is also a **behaviour swap** for `TF_FLASHNEXT_WARM_AHEAD=1` (reads
  instead of hints), not only an addition. Prefetching writes cache slots only: replies identical by construction.
- **Last-chunk evening (4)**: `cuda_lanes` replaces `passRows` with `tailRows(pass, ids.len, at)` when `PREFILL_TAIL`
  is set, so the final prompt chunk is cut to about half of what remains. This changes which rows share a prompt pass,
  so it is **not** exact by construction; it is exact on evidence (golden 6/6 and identical counters in every cell we
  ran, and its own unit test pins the cut plan).
- **One gather a shared pass (5)**: `cuda_batch_state.Gather.main` calls `rowsMany` once with every lane's rows
  instead of `rows` a lane, so the hash inputs, the dedup set and the pool run are shared by the pass; each row is
  still hashed from its own stream's history and dequantized by the same one-row gather, so replies are identical by
  construction.
- **Instrumentation (6)**: `GATHER_LOG` prints a line per 100 shared passes; `GATHER_LOCK_SCALES` `mlock`s the scale
  arrays at load. Neither touches rows.

Launches: `Ngram.init`/`deinit` (cache open/close), the PLE gather of every prompt chunk and decode round, the decode
draft loop, the prompt chunk loop, and `Pass.chunk`'s gather join. Settings and defaults: the table above; all code
defaults keep today's path.

## 4. Upstream-ready?

Against `AGENTS.md`'s "Contributing upstream" section, item by item:

- **Lossy?** No. Nothing here changes a format, a cache's contents or a token. The cache holds the file's own bytes.
- **A new setting read through `platform/environment.zig`?** Yes, correctly: eight new rules in the `.cuda` scope and
  eight reads through `sys.environment.read`, plus 15 cases in `environment_test.zig`. The only `getenv` in the patch
  are two test-only ones (`TF_PLE_REAL_DIR`, `TF_PLE_SEED`) in a `_test.zig` file, which upstream's lean tool skips.
- **Kernel contract?** Not applicable: the patch touches no `.cu`, `zig/kernels` or kernel instance. No planted control
  is needed for a host-side change.
- **Lean, as upstream runs it** (base against head, each side's own `lean_check.py`, `lean_new.py`). I ran it on T and
  on the standalone-0004 tree:
  - base T: `6575 files, 221 problems`.
  - T + 0004: `6580 files, 223 problems`.
  - `lean_new.py`: `lean: 223 problems, 221 on the base, 2 new`, and the two are:
    `zig/src/families/flashnext/cuda_knobs.zig:1: multi-line comment` (the file's two-line `//!` header) and
    `zig/src/families/flashnext/cuda_ple.zig: 609 lines (split past 600)`.
  So **0004 as one PR fails upstream's lean gate on T today**, on two counts, one of them structural: `cuda_ple.zig`
  is 588 lines at T and 0004 takes it to 609, and the 600-line rule has no waiver.
- **Size**: 20 files, +1,080/-25; 5 new files (920 lines), 232 of the added lines a test file. That is far past one
  behaviour: its own two CHANGELOG bullets each cover three behaviours.
- **Must be split**: yes. Concretely into the four PRs below (P1 to P5, with 0012 held), because "if the one-sentence
  description needs *and*, split it" and because the 600-line rule forces the `cuda_ple.zig` hooks apart anyway.
- **Tests it brings**: `cuda_ple_cache_test.zig` (232 lines): rows by pread equal the mapped rows cold, warm, ahead and
  after eviction; rows stay exact when slots collide; the slot count is a power of two with two at the fewest; and a
  skipped real-checkpoint timing test (`TF_PLE_REAL_DIR`). Plus the tail plan test in `cuda_chunk.zig` and the setting
  cases. The re-seat added the assertions that make them independent of the shell (see the host-suite item below).
- **Tests missing** (one a behaviour, named in each PR block): no test for `rowsMany` at all (0 tests in
  `cuda_ple_gather_lanes.zig`); none for `GATHER_LOG`/`Stat` (0 tests in `cuda_batch_gather_log.zig`); none for the
  buffered-open path (0012); none that a busy slot's waiter gets the right bytes (the `waited` and overwrite-retry
  path in `Reader.get`); none that a failed row read falls back to the caller's reader; none that `DRAFT_AHEAD=1`
  issues prefetches and `0` issues none; none that the next chunk's rows are present when `WARM_AHEAD=1` and that
  upstream's hint path is still taken with no cache.

## 5. Our evidence so far, and what it does and does not show

**The bundle A/B on our base (`docs/RESTACK-main-964174ea05.md`, "0004 keep or retire", spark6 17:08 to 17:44 UTC,
A = all 19 patches, B = the package without 0004 and 0012, A B B A, fp8 KV at 262,144, one decode pass of 512-token
prose and code replies a cell):**

| streams | A, with 0004 | B, without 0004 and 0012 | B against A, means | noise rule |
|---:|---|---|---|---|
| 1 | 62.6, 61.5 / 84.5, 82.8 | 56.0, 62.2 / 76.6, 83.0 | -4.8% / -4.6% | same (B's second run is over A's) |
| 2 | 87.6, 85.2 / 124.0, 123.5 | 82.3, 81.0 / 120.4, 117.3 | -5.5% / -4.0% | B slower, prose and code |
| 4 | 114.5, 116.3 / 166.2, 168.8 | did not boot, both runs | n/a | B refuses 4 full-window streams |
| 6 | 151.1, 148.4 / 216.0, 214.2 | 134.3, 134.1 / 199.9, 202.5 | -10.4% / -6.5% | B slower, prose and code |
| 8 | 168.2, 166.5 / 250.3, 246.0 | 149.9, 148.6 / 234.2, 233.3 | -10.8% / -5.8% | B slower, prose and code |

Golden 6/6 identical in all 18 cells that served; every one of the 20 boots logged "window self-check: 1176 of 2080
rows byte-equal to their one-token steps"; the counters (rounds / drafted / accepted) were the same to the digit
between the arms in every cell. B's 4-stream refusal, quoted from the doc: "`--parallel 4` needs 20.15 GiB for its
streams at a 262144-token window, and the CUDA memory budget leaves 17.79 GiB"; A at 4 streams "had 25.6 GiB left
after the reserve (5.04 GiB a stream)".

**This prices the bundle, not the cache.** 0004 also carries the one-pass gather, the tail rule and draft-ahead, and
B removed all of them. The per-part measurements we already have point the other way for the cache specifically:

- **1.2.6 drop-one (`docs/CATCHUP-1.2.6.md`, the "completed set" table, C1 code / C4 code / C1 prose / C4 prose):**
  `GATHER_READ=0` (plain reader, cache off) is **+4.2% / +1.8% / +7.5% / +4.3%**, repeated A/B/A
  **+3.2% / +1.8% / +7.2% / +4.0%**, "the plain reader is faster: serve with it off"; `GATHER_DIRECT=0` (buffered
  cache) is +2.9% / +1.9% / +6.3% / +3.8%, "ties the plain reader". The doc's mechanism paragraph: "With the table's
  working set already resident, that path costs more than the faults it avoids, so the plain reader (page faults
  through the mapping) wins." That is exactly the arithmetic of `O_DIRECT`: `direct_io.alignment` is 4096 and a row is
  90 bytes, so a miss is two 4 KiB reads (codes, scales) for 90 bytes of data, and a row is 16 heads a token, so a
  miss is about 128 KiB of NVMe traffic a token.
- **The other parts at the same time**: `GATHER_EARLY=0` is **-0.3% / -4.5% / -0.3% / -4.3%**, "keep: it is
  load-bearing at four streams"; `GATHER_THREADS=0`, `GATHER_CACHE_MIB=32`, `PREFILL_TAIL=0`, `DRAFT_AHEAD=0` and
  `GATHER_LOCK_SCALES=0` all landed inside the noise (0.0 to 0.5%).
- **1.2.7 rung (`patches/1.2.7/README.md`)**: `v1.2.7 + 0001-0004` is 53.6 / 73.3 at one stream and 104.8 / 153.0 at
  four against stock 54.2 / 74.0 and 105.9 / 154.0, so the cache rung is flat to -0.9% there.
- **1.2.6 patch row (`patches/1.2.6/README.md` line 24)**: "exact; decode level with the base's own readers
  (61.6 / 81.3 against 62.1 / 81.9); cold 32k prompt 14.1 s against 14.3. On the full series: with `DRAFT_AHEAD=0`
  57.3 / 76.8 against 60.5 / 80.1 at one stream (draft-ahead is worth about 5%); `GATHER_EARLY=0` and all three off
  are level with on (60.8 / 80.3 and 60.9 / 80.4, noise about 1%)".

So the honest state: the cache is exact everywhere and never measured *faster* on its own; draft-ahead is worth about
5% at one stream on one base; the one-pass gather is the only part with a measured concurrency win; and the bundle's
2, 6 and 8 stream losses are real but unattributed.

**The 4-stream memory difference is not explained, and our doc's stated cause does not survive the code and a
neighbouring PR.** The doc says the 7.8 GiB is "the likely reason ... the n-gram rows are read through the page cache
(0004's cache reads them `O_DIRECT`, leaving the page cache to the weights)", and marks it "not measured further".
Three facts argue against it:

1. The admission arithmetic reads **MemAvailable**, and the code says so in its own words: `cuda_memory.zig`'s
   `MemInfo` is "what /proc/meminfo says: MemTotal and MemAvailable in bytes (**the page cache counts as available**)",
   and `cuda_family_memory.zig` derives the room from it (`available.available` then `room(model)`), with parked
   per-CPU pages added back (`parked_pages.zig`). A page cache of table pages should therefore not shrink the budget.
2. **The table is small on this checkpoint.** PR #3467 measured "shard 15, which holds the n-gram table (1.26 GiB)"
   and "about 3 GiB of checkpoint pages stay in the page cache" on the NVIDIA NVFP4 export, with `Cached` 3.65 and
   5.09 GiB on main. The 28.7 GiB figure in our tree (`cuda_ple_cache_test.zig`'s real-checkpoint comment, and
   `docs/CATCHUP-1.2.6.md`'s "28.7 GiB n-gram mapping") is the **FP8** checkpoint's table (`UPSTREAM-WATCHLIST.md`
   line 36 quotes 47.7 GiB for the MLX one), not the FP4 checkpoint the A/B served.
3. GB10's accounting is not ordinary: `zig/src/native/fixtures/gb10_parked/meminfo_at_budget` shows MemAvailable
   ~27.9 GB beside `Cached` ~28.35 GB and MemTotal ~127.5 GB, so what MemAvailable reports on this box is not simply
   free plus reclaimable.

Therefore B's 7.8 GiB is an open question to be measured, not a property of the cache. A P2 receipt must print the
boot line plus `Cached`, `MemFree`, `MemAvailable` and `nvidia-smi` per pid at 10 s after load and after a served
turn, for each arm, exactly as #3467 did.

## 6. Verdict

**SPLIT.** 0004 is six behaviours in one 20-file patch, it fails upstream's lean gate as one PR (`cuda_ple.zig` 609
lines; a two-line `//!` in the new knobs file), and its own evidence prices a bundle we cannot attribute. It becomes:

- **P1 SUBMIT**: one pooled gather a shared pass. Branch `flashnext-ple-gather-early`, title
  **"flashnext cuda: a shared pass gathers every stream's n-gram rows in one pool call"**.
- **P5 SUBMIT**: prompt last-chunk evening. Branch `flashnext-prompt-tail`, title
  **"flashnext cuda: a prompt's short last chunk takes half of what remains"**.
- **P2 HOLD**: the bounded row cache. Branch `flashnext-ple-row-cache`, title
  **"flashnext cuda: the NVFP4 n-gram table's rows through a bounded row cache"**. Blocks on its own receipt on T
  (item 5's memory readings plus P2's arms below) showing no loss at any admitted stream count and a measured benefit;
  also on `cuda_ple.zig` reaching 600 lines or below: measured with all of 0004 applied it is 609, and P2's own share
  is about 602 (the 609 also carries P1's `gather_lanes` import, P4's `ahead_thread` field and the retired `Stat` and
  `lockScales` hooks), so moving `openCache` into `cuda_ple_cache.zig` as a free function covers it.
- **P3 HOLD**: drafted-token prefetch, stacked on P2. Branch `flashnext-ple-draft-ahead`, title
  **"flashnext cuda: ask for a drafted token's n-gram rows as the head drafts"**.
- **P4 HOLD**: next-chunk prefetch, stacked on P2, and it needs an explicit decision because it changes what
  `TF_FLASHNEXT_WARM_AHEAD=1` does when a cache is open. Branch `flashnext-ple-chunk-ahead`, title
  **"flashnext cuda: read the next prompt chunk's n-gram rows while this one runs"**.
- **RETIRE for upstream**: `GATHER_LOG` + `Stat` + `cuda_batch_gather_log.zig` + the `Pass.chunk` join hook, and
  `GATHER_LOCK_SCALES` + `lockScales` (about 70 lines and two settings, no measured effect). Keep them in our stack.

## Exactness by construction, and the cache's memory cost

**Exact by construction: yes.** Which rows and which bytes are unchanged:

- The row ids are `lastIds(hash, history, token)` on the same n - 1 token history, before and after.
- `ple_cache.row` reads the raw row at the same file offsets the positional reader uses
  (`codes_at + local * row_codes`, `scales_at + local * row_scales`, 80 and 10 bytes for a 160-wide head) and
  dequantizes it with the same `core.nvfp4_rows.Table.gather` over a one-row table of the same `width` and `global`
  scale that `cuda_ple_reader.read` builds. A cache hit and a cache miss therefore produce the same u16 row; the cache
  only decides *where the 90 bytes were read from*.
- `sumGroups` (the FP32 group sums into `xs`) and the history write-back stay in `Ngram.rows`, after the gather, in
  the same order, untouched by the patch.
- The prefetches (draft-ahead, next chunk) write cache slots only; they never write `out`, `xs` or a history.
- `ple_cache.row` returns false for `.fp8` and `.mlx`, so those tables cannot be affected at all.
- Evidence agrees: 6/6 golden and identical counters in every cell of the A/B, and `cuda_ple_cache_test.zig` compares
  every row of a 513-token gather against the mapped path, cold, warm, ahead and with collisions.

**Memory cost of the cache**: an anonymous private mapping of `slots * 104 bytes` (a `u64` tag plus 12 `u64` words of
row bytes, `Slot = extern struct { tag: u64, data: [12]u64 }`). At the default 256 MiB setting `slotsFor(256)` returns
2^21 slots, which is 218,103,808 bytes = **208 MiB of address space**; nothing is resident until a slot is touched,
and the kernel faults it in 4 KiB pages (about 39 slots a page), so the resident set grows with the number of distinct
rows touched and saturates at 208 MiB. A prompt chunk of 3,072 tokens is 49,152 rows (16 heads a token), so a few
chunks of a long prompt make most of it resident. Nothing of the table stays in the page cache while `GATHER_DIRECT`
is on, which is the whole point of the `O_DIRECT` open; with `GATHER_DIRECT=0` the table's pages go back into the page
cache as well, and the 208 MiB mapping stays.

## The host-suite fix noted in RECORD.md: inside 0004, item by item

1. **`ple_cache.close`**: present at `cuda_ple_cache.zig:360` (joins `ahead_thread`, destroys the cache, nulls it),
   called from `Ngram.deinit` (`cuda_ple.zig:437`) and from the tests.
2. **Tests that set their own state**: `cuda_ple_cache_test.zig:11` `plain()` (close plus `read_mode = .mmap`) and
   `:17` `openDefault()` through `openSized(slotsFor(256), max_workers)`, so `GATHER_CACHE_MIB` and `_THREADS` in the
   shell cannot change what the tests open; the first test asserts `gatherRead()` equals `g.cache != null` at `:30`
   instead of asserting the variable unset. Node: `openSized` exists for this.
3. **The `GATHER_CACHE_MIB=0` assert**: fixed in `slotsFor` (`cuda_ple_cache.zig:350`, floors to a power of two with
   two at the fewest and saturates an overflowing MiB count), in `Reader.create` (`:68`, refuses `slot_count < 2`), in
   the rule text ("0 rounds up to two slots") and in a new test ("the row cache's address space is a power of two of
   slots, two at the fewest", `:122`). The re-seat's mutant runs are quoted in `RECORD.md`: M1 (old rounding) fails
   the test with "expected 2, found 0", M2 (no guard) crashes in `isPowerOfTwo`, M3 (shift instead of saturate) fails
   the saturation check.
4. **Upstream's short-read test closes the cache before poisoning the positional readers**: present,
   `cuda_ple_nvfp4_test.zig:154` (`@import("cuda_ple_cache.zig").close(&g)`), and `fixture` is made `pub` (`:9`) so
   the cache tests can reuse it.

All four are inside 0004, and the host suite on spark6 gives one answer in either shell: base `964174ea05` 6,724 of
6,759 with main's two failures, the package 6,767 of 6,803 with the same two (`docs/RESTACK-main-964174ea05.md`,
"Host suite"). The one latent bug fixed on the way (`GATHER_CACHE_MIB=0`) is described in `RECORD.md`.

---

# 0012, the six answers

## 1. Applies on T?

- **Alone on pristine T: no.** `git apply --check` fails because its files do not exist yet
  (`cuda_knobs.zig: No such file or directory`, `cuda_ple_cache.zig: No such file or directory`) and because
  `environment.zig` and `environment_test.zig` conflict on context.
- **After 0004: clean.** With the series prefix applied (`0001` to `0004`), `git apply --check
  0012-gather-direct.patch` returns **rc 0** with no output, and `git apply` leaves no unmerged file. Its only
  dependency is 0004, which creates `cuda_knobs.zig` and `cuda_ple_cache.zig`. It cannot be its own PR before P2
  lands.

## 2. Absorbed upstream?

**No.** `TF_FLASHNEXT_GATHER_DIRECT`, `gatherDirect` and `openBuffered` return 0 files at T; there is no
`openBuffered` in `core/direct_io.zig` and no direct/buffered switch in `Reader`.

## 3. What it changes at run time

`cuda_ple_cache.Reader.create` chooses `direct_io.File.open` (O_DIRECT, with its own buffered fallback when the file
system refuses) or the new `direct_io.File.openBuffered` (never O_DIRECT, always the page cache), from
`TF_FLASHNEXT_GATHER_DIRECT` (code default `true`). It changes one fd flag: the same bytes are read from the same
offsets and dequantized the same way, so replies are byte-identical by construction; what moves is where the table's
pages land (NVMe straight into the process, or the page cache).

## 4. Upstream-ready?

Size 5 files, +17/-1. It adds one setting through `environment.zig` with two test cases. But as a PR it is a switch on
another switch that does not exist upstream yet: it has no value before P2 lands, it has **no test** (the buffered
branch of `direct_io.read` is unexercised), and its only measured effect is to make the cache tie the plain reader
(1.2.6: +2.9% / +1.9% / +6.3% / +3.8% over the O_DIRECT cache). If P2 lands and its receipt shows that the buffered
arm is the one worth having, the right move is to make that the cache's read path inside P2 (or a follow-up commit),
not to add a third setting. `docs/recipes/flash-next-cuda.md`'s added paragraph would then need rewording too, since
it currently sells the O_DIRECT open.

## 5. Our evidence

`patches/1.2.6/README.md` line 32: "the row cache can read through the page cache | `GATHER_DIRECT` (1) | switch
only". The one measurement is the 1.2.6 arm quoted in item 3 of 0004 (+2.9% / +1.9% / +6.3% / +3.8%, "ties the plain
reader", 6/6 identical). No 1.2.7 or main-base A/B of 0012 alone exists; in the main A/B it was removed together with
0004 and cannot be separated.

## 6. Verdict

**HOLD**, not a PR of its own. Fold into P2 only if P2's own receipt answers it: if `GATHER_READ=pread` with O_DIRECT
is slower than `GATHER_DIRECT=0` at equal memory, then a bounded cache that reads through the page cache is a
contradiction (the bound is the point), and the honest outcome is to drop the cache, not to add the switch. If the
O_DIRECT arm wins on memory and loses on speed, the switch is a real trade and belongs in P2's PR as a second commit
with its own test (a row-for-byte comparison through `openBuffered`) and a receipt covering both arms.

---

# The proposed PRs

Each block names the exact content taken from 0004 (or 0012), so a branch can be cut without re-deriving the split.
All of them keep the code defaults off except where stated.

## P1: one pooled gather a shared pass

- **Title**: `flashnext cuda: a shared pass gathers every stream's n-gram rows in one pool call`
- **Branch**: `flashnext-ple-gather-early`, cut from T alone (no dependency).
- **Content from 0004**:
  - new `zig/src/families/flashnext/cuda_ple_gather_lanes.zig`, lines 1 to 14 (imports) plus the `Part` struct
    (line 35) and `early` plus `rowsMany` (lines 38 to 53 and 74 to 153), about 100 lines; **without** `Stat`
    (lines 15 to 30), `maybeLockScales` and `lockScales` (54 to 72).
  - `cuda_batch_state.zig`: the import and the two added lines in `Gather.main` (`if (gather_lanes.early(g)) return;`).
  - `cuda_ple.zig`: the `gather_lanes` import and the `Split`/`part` visibility (`const Split` to `pub const Split`,
    `fn part` to `pub fn part`); **without** the `Stat` timing hooks inside `part`.
  - the `TF_FLASHNEXT_GATHER_EARLY` knob (its own reader; in the first PR it can be a one-line
    `sys.environment.read` in `cuda_ple_gather_lanes.zig` instead of a new `cuda_knobs.zig`, which also avoids the
    lean finding), its `environment.zig` rule and its two `environment_test.zig` cases.
- **Size**: about 110 added lines in 5 files, 1 of them new.
- **Setting**: `TF_FLASHNEXT_GATHER_EARLY`, default `0`, reads nothing else.
- **Exactness**: identical by construction (same ids per stream, same dedup, same one-row dequantizer; only the call
  that carries them is shared).
- **Tests to add** (today there are none): `rowsMany` over two parts equals two successive `rows` calls on the NVFP4
  fixture, byte for byte in `out`, `xs` and the history, with tokens chosen to collide across lanes so the cross-lane
  dedup is exercised; a 65-lane call falls through to the per-lane path; a non-consecutive `out` returns
  `UnexpectedTensor`. Expected `GATHER_EARLY=0` behaviour must stay identical (the null case is today's code).
- **Receipt on T**: T against branch at 1, 2, 4, 6 and 8 streams (one fresh boot a cell, golden 6/6, `bench_openai.py`
  plus our `qf_run.py`), ABBA at 4 streams because the 1.2.6 evidence for this part is one pass; the four exactness
  contracts (drafted equals `"draft": false`, resumed equals fresh, concurrent equals solo, cancel and reset leave the
  next request valid); cold prompts at 2k, 8k, 32k and 64k (`bench_cache.py --require-cold --prompt-cache-gib 0`).
- **GPU windows**: one window of about 40 minutes (2 arms at 5 stream counts is 10 cells; `restack2` did 20 cells in
  36 minutes) plus a second window only if the 4-stream ABBA is needed.

## P5: prompt last-chunk evening

- **Title**: `flashnext cuda: a prompt's short last chunk takes half of what remains`
- **Branch**: `flashnext-prompt-tail`, cut from T alone.
- **Content from 0004**: `cuda_chunk.zig`'s `tail_rows`/`prefillTail`/`tailRowsFor`/`tailRows` and the `planTail`
  test (42 lines, of which about 22 are the test); the two-line call-site change in `cuda_lanes.zig`
  (`passRows` plus `tailRows`); the knob, its `environment.zig` rule and its two cases.
- **Size**: about 47 added lines in 4 files (about 22 of them the `planTail` test).
- **Setting**: `TF_FLASHNEXT_PREFILL_TAIL`, default `0` (off).
- **Exactness**: not by construction, because the cut changes which rows share a prompt pass; it is exact on evidence
  (golden 6/6 and identical counters in our cells) and the PR must say so and carry its own golden.
- **Tests**: the `planTail` unit test is present and covers the cut plans; add one case where `tail` exceeds the total
  and one where the total is a single short chunk (both already in the table), and a golden at the head.
- **Receipt on T**: same five stream counts plus cold prompts (this change is a prompt-shape change, so the cold
  cells are the point); one window, shared with P1 because both are cut from T: arms T, T+P1, T+P5 at 5 stream counts
  is 15 cells, about 30 minutes.
- **GPU windows**: shares P1's window.

## P2 (HOLD): the bounded row cache

- **Title**: `flashnext cuda: the NVFP4 n-gram table's rows through a bounded row cache`
- **Branch**: `flashnext-ple-row-cache`, cut from T; depends on nothing else.
- **Content from 0004**: `cuda_ple_cache.zig` lines 1 to 367 (the `Reader`, `row`, `open`, `openSized`, `slotsFor`,
  `workers`, `close`; **without** `warmNext`, `aheadChunk`, `AheadJob` and `Ahead`, which are P3 and P4);
  `cuda_ple_cache_test.zig` without its ahead sections; `cuda_ple.zig`'s cache field, `openCache`, the `fill` hook and
  the `deinit` close (**without** the `Stat` hooks and the `Split` visibility, which are P1); `cuda_ple_nvfp4_test.zig`'s
  `pub fixture` and its two-line close; the three knobs and their rules and cases.
- **Size**: about 540 added lines in 6 files, 2 of them new (`cuda_ple_cache.zig` 367, its test about 150).
- **Setting**: `TF_FLASHNEXT_GATHER_READ` (default `0`), `TF_FLASHNEXT_GATHER_CACHE_MIB` (default `256`),
  `TF_FLASHNEXT_GATHER_THREADS` (default `128`).
- **Lean**: `cuda_ple.zig` is 588 lines at T and must stay at or below 600. Measured with all of 0004 applied it is
  609; P2's own share is about 602 (the 609 also carries P1's `gather_lanes` import, P4's `ahead_thread` field and the
  retired `Stat` and `lockScales` hooks), so P2 is 2 lines over as it stands. Move `openCache` into
  `cuda_ple_cache.zig` as a free function over `*Ngram` and drop the extra import, and keep the `//!` header of any new
  knobs file to one line (upstream's lean tool flags a multi-line comment).
- **Tests to add**: the busy-slot waiter and overwrite-retry path in `Reader.get`; a failed row read returning `false`
  so the caller's reader still fills the row; `GATHER_CACHE_MIB=0` (present) and `GATHER_THREADS=0` (the cache opens
  with no workers and every row is read by the caller) at the `Ngram` level rather than through `openSized`.
- **Receipt on T**: three arms (T, branch with `GATHER_READ=pread`, the same with `GATHER_DIRECT=0`) at 1, 2, 4, 6 and
  8 streams, plus, at every boot, the boot line and `Cached`, `MemFree`, `MemAvailable`, `nvidia-smi` per pid at 10 s
  after load and after one served turn; cold prompts at four sizes; ABBA on any cell inside 1%.
- **Blocks it**: (a) a per-part receipt that shows it no slower than T at every admitted stream count and a measured
  benefit, which no measurement we have today does (0004 item 5); (b) the lean fix above; (c) a decision on whether the
  PR claims a memory benefit, which can only be claimed if the receipt shows the page-cache and MemAvailable story
  from item 5 measured rather than inferred. Note that the 4-stream capacity case cannot be transferred to upstream's
  bf16 KV configuration, so it cannot carry the PR.
- **GPU windows**: one window of about 45 minutes (3 arms at 5 stream counts is 15 cells plus the memory readings), a
  second if the noise rule forces an ABBA.

## P3 (HOLD, on P2): drafted-token prefetch

- **Title**: `flashnext cuda: ask for a drafted token's n-gram rows as the head drafts`
- **Branch**: `flashnext-ple-draft-ahead`, based on P2's head; the PR is a draft and says it sits on P2.
- **Content from 0004**: `ple_cache.Ahead` (the end of `cuda_ple_cache.zig`, about 37 lines); `cuda_mtp_ops.zig`'s
  `ahead` parameter on `draft`, `draftMany` and the module-level `draftMany` plus its three flushes; `cuda_lanes_draft.zig`'s
  `one` and its `batched` hook (about 40 lines); the two `cuda_lanes.zig` call-site changes to `lanes_draft.one`; the
  `null` arguments in `cuda_mtp_nonfinite_more_test.zig` and `flashnext_mtp_parity_tests.zig`; the knob, rule and cases.
- **Size**: about 87 added lines in 8 files (37 in `cuda_ple_cache.zig`, the rest plumbing and two test files' null arguments).
- **Setting**: `TF_FLASHNEXT_DRAFT_AHEAD`, default `0`.
- **Exactness**: by construction (prefetch only).
- **Tests to add**: with `DRAFT_AHEAD=1` a `draft` of N tokens issues the expected number of prefetches (read
  `take().ahead_rows`), with `0` none; the existing parity tests already pin that the drafts are unchanged.
- **Receipt**: P2's head against P3's head at 1, 2, 4, 6, 8 streams plus the exactness contracts. One window, about 40
  minutes. Evidence it would carry: about 5% at one stream on 1.2.7 (`patches/1.2.6/README.md` line 24), inert at one
  and four streams on 1.2.6 (`docs/CATCHUP-1.2.6.md`), so one stream is the cell that matters and the owner's 2 to 8
  stream workload is not where it pays.

## P4 (HOLD, on P2): next-chunk prefetch

- **Title**: `flashnext cuda: read the next prompt chunk's n-gram rows while this one runs`
- **Branch**: `flashnext-ple-chunk-ahead`, based on P2's head; draft, says it sits on P2.
- **Content from 0004**: `warmNext`, `aheadChunk`, `AheadJob` and the `ahead_thread` field (about 60 lines);
  `cuda_lanes.zig`'s `warmNext` call and the `if (cache == null)` guard around `warmAhead`; `cuda_prompt.zig`'s
  `warmNext` call and import; the knob and cases.
- **Size**: about 71 added lines in 4 files (60 of them the prefetch helpers in `cuda_ple_cache.zig`).
- **Setting**: it reads upstream's existing `TF_FLASHNEXT_WARM_AHEAD` (default `0`) and changes what it does when a
  cache is open (reads into the cache instead of `fadvise` hints). The PR must state that swap in its first paragraph
  and either keep the hint call as a fallback or make the swap explicit.
- **Exactness**: by construction (prefetch only).
- **Tests to add**: with a cache open and `WARM_AHEAD=1`, the next chunk's gather reports 0 own reads; with
  `WARM_AHEAD=0` no prefetch is issued and, with no cache, `warmAhead` is still called.
- **Receipt**: P2's head against P4's head, cold prompts the focus (2k, 8k, 32k, 64k), decode at five stream counts.
  One window, about 40 minutes. Evidence: no isolated measurement exists; its effect is inside the 0004 bundle and the
  1.2.6 "all three off are level with on" line.

---

# Receipts: the arms, the cells and the windows

Upstream's own rules (from `AGENTS.md`, "Receipts, for a change that can reach inference") govern: main against branch
on one machine and one checkpoint, token hashes equal on the default path, the four exactness contracts, decode with
`tools/bench_openai.py`, cold prompts with `tools/bench_cache.py --require-cold --prompt-cache-gib 0` at 2k, 8k, 32k
and 64k, arms alternated when the difference is a few percent, no slower at one stream or at the widest admitted, and
the machine named by chip with unrun platforms labelled.

Our own fleet rule adds: 1, 2, 4, 6 and 8 streams, one fresh boot a cell, golden 6/6, the boot self-check line, and the
noise rule (a cell is slower only when both runs of one arm are under both of the other's and the means differ by more
than 1%, with one rerun to confirm a loss).

- **Window 1 (P1 and P5)**: arms T, T+P1, T+P5, 5 stream counts, 15 cells, about 30 to 40 minutes by `restack2`'s rate
  (20 cells in 36 minutes); then cold prompts on the same three images (4 sizes each) if the boots can be reused, or
  about 15 minutes more. This is the only window needed before showing the owner P1 and P5.
- **Window 2 (P2, P3, P4)**: arms T, P2, P2+P3, P2+P3+P4 at 5 stream counts is 20 cells, about 40 to 45 minutes, plus
  the memory readings at each boot and the cold prompts; ABBA on any cell inside 1% is a second window.
- Either window must run with sparkDash stopped and `:8888` firewalled (our benchmark hygiene), and record the GPU
  temperature at the start of every timed window.

---

# Open gaps, stated plainly

1. **The 4-stream memory difference is unattributed.** 17.79 GiB against 25.6 GiB after the reserve, with the doc's
   page-cache explanation contradicted by the admission code (MemAvailable) and by PR #3467's measured page cache
   (3.65 to 5.09 GiB). It needs the memory readings above, on both arms, before any PR claims it.
2. **The n-gram table's size on our checkpoint is stated two ways in our own tree** (28.7 GiB in the cache test's
   comment and `docs/CATCHUP-1.2.6.md`, 1.26 GiB in upstream PR #3467 for the NVFP4 export). The 28.7 GiB is the FP8
   table's; ours is the small one. Any PR text must use the measured size for the checkpoint it serves.
3. **No per-part A/B of 0004 exists on this base.** The 1.2.6 drop-one table is the only per-knob evidence, and it
   contradicts the bundle's headline for the cache. The P2 window is the first place that can be settled.
4. **`O_DIRECT` amplification is a design question, not a tuning one**: 4 KiB a read for 80 bytes of codes and 10 of
   scales means a miss is about 128 KiB of NVMe traffic a token. A page-granular cache (4 KiB pages of codes and
   scales instead of 90-byte rows) would remove it; nothing in 0004 does. This is worth stating in P2's PR as the
   alternative that was not taken.

---

# Appendix: commands and their decisive output

All paths relative to the campaign repo; `P=patches/main-964174ea05`.

```
$ cd work/upmain && timeout 90 git fetch origin main; git log -1 --format='%H %ci %s' origin/main
077998f7d9b14adebec3a2acc2caa47ff7ae6ec7 2026-11-16 15:26:10 +0000 changelog: #3572 under Unreleased
$ git -C work/upmain log --oneline 964174ea05..077998f7d | wc -l
153

$ git -C work/upmain worktree add --detach ../Triage-Ngram/wt-t 077998f7d9b14adebec3a2acc2caa47ff7ae6ec7
HEAD is now at 077998f7d changelog: #3572 under Unreleased

$ cd work/Triage-Ngram/wt-t && git apply --check $P/0004-ngram-row-cache.patch
error: patch failed: CHANGELOG.md:37 ... environment.zig:51 ... environment_test.zig:67
$ git apply --3way $P/0001-rows.patch   # on T
Applied patch to 'CHANGELOG.md' cleanly. ... (10 files, no "with conflicts")
$ git apply --3way $P/0002-copy-resync.patch && git apply --3way $P/0003-kv8.patch
(Falling back to direct application ... no unmerged file)
$ git apply --check $P/0004-ngram-row-cache.patch
error: patch failed: zig/src/platform/environment.zig:51
$ git apply --3way $P/0004-ngram-row-cache.patch
Falling back to direct application ... (5x), no unmerged file: git diff --name-only --diff-filter=U  -> empty
$ git apply --check $P/0012-gather-direct.patch    # after 0004
(no output) rc=0

$ git apply --check $P/0012-gather-direct.patch    # on pristine T
error: .../cuda_knobs.zig: No such file or directory
error: .../cuda_ple_cache.zig: No such file or directory
error: patch failed: zig/src/platform/environment.zig:54 ... environment_test.zig:73

$ cd work/Triage-Ngram/wt-4alone && git apply --3way $P/0004-ngram-row-cache.patch
Applied patch to 'CHANGELOG.md' with conflicts. ... environment.zig with conflicts ... environment_test.zig with conflicts
U CHANGELOG.md, U zig/src/platform/environment.zig, U zig/src/platform/environment_test.zig
$ python ../resolve4.py ../wt-4alone      # drops 0001's WINDOW_CHECK lines from the incoming side
resolved
$ wc -l zig/src/families/flashnext/cuda_ple.zig
609 zig/src/families/flashnext/cuda_ple.zig
$ git diff --shortstat 077998f7d -- .
 20 files changed, 1090 insertions(+), 25 deletions(-)

$ python wt-t/tools/zig/lean_check.py > lean-base.txt; tail -1 lean-base.txt
6575 files, 221 problems
$ python wt-4alone/tools/zig/lean_check.py > lean-head4.txt; tail -1 lean-head4.txt
6580 files, 223 problems
$ python wt-t/tools/zig/lean_new.py lean-base.txt lean-head4.txt
zig\src\families\flashnext\cuda_knobs.zig: multi-line comment (1 new)
zig\src\families\flashnext\cuda_ple.zig: over 600 lines (1 new)
lean: 223 problems, 221 on the base, 2 new

$ git apply --numstat $P/0004-ngram-row-cache.patch   # 20 files, +1080/-25; the 5 new files 34+43+458+232+153=920
$ git apply --numstat $P/0012-gather-direct.patch     # 5 files, +17/-1

$ for s in TF_FLASHNEXT_GATHER_READ TF_FLASHNEXT_GATHER_CACHE_MIB ple_cache gatherDirect DRAFT_AHEAD \
           GATHER_EARLY PREFILL_TAIL GATHER_THREADS GATHER_LOG GATHER_LOCK_SCALES openBuffered; do
    printf '%-32s %s files\n' "$s" "$(git grep -c "$s" 077998f7d -- zig docs | wc -l)"; done
TF_FLASHNEXT_GATHER_READ         0 files      TF_FLASHNEXT_GATHER_CACHE_MIB    0 files
ple_cache                        0 files      gatherDirect                     0 files
DRAFT_AHEAD                      0 files      GATHER_EARLY                     0 files
PREFILL_TAIL                     0 files      GATHER_THREADS                   0 files
GATHER_LOG                       0 files      GATHER_LOCK_SCALES               0 files
openBuffered                     0 files
$ git log --oneline -S'rowsMany' 077998f7d | head -3        (no output)
$ git log --oneline -S'prefillTail' 077998f7d | head -3     (no output)
$ git log --oneline -S'aheadChunk' 077998f7d | head -3      (no output)

$ gh api 'repos/ashhart/TensorFold/pulls?state=open&per_page=100' --jq '.[].title' | grep -i 'ple\|ngram\|gather\|cache'
3587 xpu(flashnext): serve Qwen3.8 Flash Next (qwen4_exp) at TP={1, 2, 4} with host-RAM PLE and MTP
3467 flashnext cuda: the mixed PLE shard and the nested shards leave the page cache after load
$ gh api repos/ashhart/TensorFold/pulls/3467 --jq '.body' | head -3
... "about 3 GiB of checkpoint pages stay in the page cache ... shard 15, which holds the n-gram table (1.26 GiB) ..."

$ git show 077998f7d:zig/src/native/cuda_memory.zig | grep -n 'meminfo'
/// What /proc/meminfo says: MemTotal and MemAvailable in bytes (the page cache counts as available).
$ git show 077998f7d:zig/src/families/flashnext/cuda_ple.zig | sed -n '470,520p'   # fill: pread or the mapping
$ git show 077998f7d:zig/src/families/flashnext/cuda_ple_reader.zig | grep -n 'fn mode\|fn hint\|readPositionalAll'
pub fn mode(text: ?[]const u8) !Mode { ... if (os.tag == .linux) .pread else .mmap }
$ git show 077998f7d:zig/src/families/flashnext/cuda_ple_ahead.zig | head -6
//! Future token hashes issue bounded file hints synchronously; no detached worker borrows a prompt or shard.

$ grep -n 'GATHER_READ=pread\|DRAFT_AHEAD=1\|GATHER_EARLY=1\|PREFILL_TAIL=512\|WARM_AHEAD=1' \
       scripts/qwen38/zig/target/int4/fp4conf-summary.txt | head -1
env d-c1: ... TF_FLASHNEXT_DRAFT_AHEAD=1 TF_FLASHNEXT_GATHER_EARLY=1 TF_FLASHNEXT_GATHER_READ=pread ...
          TF_FLASHNEXT_PREFILL_TAIL=512 ... TF_FLASHNEXT_WARM_AHEAD=1 ... (no GATHER_DIRECT, _THREADS, _CACHE_MIB,
          _LOG or _LOCK_SCALES)
```

Trees removed after the triage: `git -C work/upmain worktree remove ../Triage-Ngram/wt-t` and
`... wt-4alone` (no junction in either). `work/upsubmit/Triage/ngram.md` is this file.
