# The pool and the KV tier at production's shape: the window's four answers

Spark6, one hold of `~/work/gpu.lock`, image `tensorfold-qwen38:kvtier-pool`
`sha256:f6c13c62ba23f69f72d4fb8d4da81e95b2ec20a7ddc731180aff3584de0f6427` built on the box from the gated tree
`head.tgz` `dba3520a2f12f7c86141660f61eac120b096aa848a5ccfb13422c8c917bcc46e` (13,319 files, the combined INT4 + tier +
pool package). Production was up before the window and its image and id are restored by the window's EXIT trap.

The shape: `--parallel 8`, `--context 262144`, fp8 KV, `TF_FLASHNEXT_KV_PAGES=4096`, the INT4-AutoRound checkpoint,
production's own 54-variable environment (source: the running container) plus the INT4 drafter arm; the tier arms add
`--prompt-cache-gib 6 --prompt-cache-disk /cache/kvs/... --learn-conversations --learn-gib 60 --learn-daily-gib 200
--learn-min-free-gib 20`, and the control arms carry the same plan (`--prompt-cache-gib 6`) with no tier flags.

## The gates on the tree the image was built from

Paperclip, x86-64, 16 threads, Zig 0.17.0, nvcc 13.3, one `flock ~/work/host.lock`, `~/work/KvTierShip2/gate-run.log`.

| step | verdict |
|---|---|
| the staged tree against the base listing | `entries 12601 blobs 12601 others 0 missing 0 mismatch 0 extra 0 mode_bad 0`; `STAGE tree 3a37e287...`; `STAGE HEAD 1ece6e6dbb... status 0` |
| `main-1ece6e6db-r5/apply.sh --check` | rc 0 |
| `main-1ece6e6db-r5-int4/apply.sh --check` | rc 0, `status after int4 --check: 0 paths` |
| `main-1ece6e6db-r5-int4/apply.sh` | rc 0 |
| `main-1ece6e6db-r5-int4-kvtier/apply.sh --check` | rc 0, `status after --check: 0 paths, scratch index 0` |
| `main-1ece6e6db-r5-int4-kvtier/apply.sh` | rc 0 |
| change counts | `head modified 114 new 24; base modified 109 new 24` |
| `HEAD-TREE` | `dba3520a2f12f7c86141660f61eac120b096aa848a5ccfb13422c8c917bcc46e  head.tgz files 13319` |
| lean pair | base `7017 files, 230 problems`; head `7017 files, 230 problems` |
| `lean_new` | `lean: 230 problems, 230 on the base, 0 new`, rc 0 |
| `git diff --check` | rc 0 |
| `zig fmt --check build.zig zig` | rc 0 |
| `cuda_common_check` | `cuda common: 55 local copies, 0 violations` |
| `cuda_fragment_check` | `cuda fragments: 2 fragments, 16 includes, 0 misses` |
| `pincheck` | `files 170 failing 0` |
| `test-environment-host` | `3/3 steps succeeded; 29/29 tests passed` |
| `test-gradient-serving test-qwen-serving-host` | `7/7 steps succeeded; 3/3 tests passed` |
| `test-flashnext-int4-host` | `4/4 steps succeeded; 26/26 tests passed` |
| `test-prompt-cache-host` | `3/3 steps succeeded; 707/707 tests passed` |
| `test-cache-store-host` | `3/3 steps succeeded; 154/154 tests passed` |
| `test-learn-recovery` | `3/3 steps succeeded; 719/719 tests passed` |
| `test-cuda-kept-host test-disk-identity-host test-cuda-disk-open-host` | `12/12 steps succeeded; 68/68 tests passed` |
| `test-kernel-contract` | `36/36 steps succeeded; 260/260 tests passed` |
| `compile-config-server -Dtarget=aarch64-linux-gnu` | `8/8 steps succeeded` |
| `compile-cuda-tests -Dtarget=aarch64-linux-gnu` | `10/10 steps succeeded` |

## 1. Does the reconciled build admit at 8 x 262,144 with the pool and a cache?

Yes, on both arms. The plan grants the 6 GiB ask in full: naming it moved the pool's pages from 361 (the same shape
with no ask) to 278, 83 pages x 77,332,480 B = 5.98 GiB. The `3.1 GiB` the startup line prints, and the `3166 MiB`
the store reports, are `kv_pool.split`'s copied half - 27 snapshot slots of 110.28 MiB (2,977.7 MiB) are set aside for
slots this family never allocates, and 6,442,450,944 - 3,122,344,800 = 3,320,106,144 B = 3,166.29 MiB is the store's
budget. `work/TierFollowup/RESULT.md` section 1 has the arithmetic against the printed numbers, and the measured asks.

| cell | boot | the plan's own line (startup) |
|---|---|---|
| `levels/off` (control: pool + 6 GiB ask, no tier) | rc 0, 145.7 s, `/health` 200 | `model 69.39 GiB; 8 streams at once, the engine's own at a 262144-token window (4.99 GiB, in the model's), 7 more taking 278 pages of 4096 rows (20.02 GiB) as they need them, 0 MiB fixed each, of 31.0 GiB left after a 10.0 GiB reserve; prompts in passes of up to 3072 rows, a 3.1 GiB prompt cache; own glue kernels` |
| `levels/on` (the tier) | rc 0, 154.7 s, `/health` 200 | the same line, and the store's own report `prompt cache: 16 tokens, resumed at 0, kept 2; 2 states, 220 MiB and 0 MiB spare of 3166 MiB` |

Both arms therefore serve production's shape with the pool and a store budget of 3,166 MiB from the 6 GiB ask. The
tier engaged during the waves:
`imprint: 9 tokens on disk: 0 new blocks and its own 110 MiB`. The control arm logged no tier lines (`LINES levels/off 0`).

The two refusal cells, which are the other half of this answer:

| cell | boot | the line the engine refused with |
|---|---|---|
| `refuse/nocache` (pool + tier, no `--prompt-cache-gib`) | rc 1, 145.9 s, `/health` 000 | `tensorfold: --learn-conversations keeps each conversation state in the prompt cache before its disk writer takes it, and this shape's plan leaves the cache no bytes: 8 streams take 361 pages of 4096 rows of the 31.0 GiB the CUDA memory budget leaves; serve with --prompt-cache-gib N, where a state at the 262144-token window takes about 4.7 GiB, or without --learn-conversations` |
| `refuse/nopool` (tier, `TF_FLASHNEXT_KV_PAGES=0`) | rc 1, 145.8 s, `/health` 000 | `tensorfold: --parallel 8 needs 39.90 GiB for its streams at a 262144-token window, and the CUDA memory budget leaves 31.00 GiB: serve --parallel 6, or lower --context` |

So the shape that used to accept `--prompt-cache-disk` and keep nothing now stops at load with the flag that fixes it,
and the shape that cannot hold the streams still stops with the plan's own arithmetic. Neither cell served.

## 2. Decode at 1, 2, 4, 6 and 8 streams: tier on against tier off, the plan held equal

Ten cells, three timed waves each, the noise rule stated before the run (SLOWER or FASTER only when the two arms' ranges
do not overlap and the mean gap is over 1 percent; LEVEL otherwise). `out/tables.md` section 3 is the record.

| streams | kind | OFF mean | ON mean | ON/OFF | verdict |
|---:|---|---:|---:|---:|---|
| 1 | prose | 75.56 | 77.78 | +2.9% | LEVEL |
| 1 | code | 145.97 | 149.36 | +2.3% | LEVEL |
| 2 | prose | 84.38 | 85.92 | +1.8% | LEVEL |
| 2 | code | 193.47 | 196.29 | +1.5% | LEVEL |
| 4 | prose | 132.27 | 134.18 | +1.4% | LEVEL |
| 4 | code | 248.10 | 252.82 | +1.9% | LEVEL |
| 6 | prose | 183.42 | 183.76 | +0.2% | LEVEL |
| 6 | code | 337.02 | 337.50 | +0.1% | LEVEL |
| 8 | prose | 227.17 | 227.12 | -0.0% | LEVEL |
| 8 | code | 404.51 | 404.79 | +0.1% | LEVEL |

**Verdict: LEVEL 10, FASTER 0, SLOWER 0.** No cell's ranges are disjoint, so no cell earns a direction. The rule is
weak exactly where the tier costs most, and the record says so: ON read slower in 9 of the 10 cells, by 1.4 to 2.9
percent at 1 to 4 streams, and the reason no cell earned SLOWER is the control's own first wave - its waves read
`70.72, 77.86, 78.10` at 1 prose and `80.81, 86.19, 86.14` at 2 prose, while the tier arm is stable (`77.39, 77.89,
78.06` and `86.04, 85.82, 85.90`), so the range stayed wide enough to swallow a 2 percent cost at those widths.
Dropping the control's cold first wave, the two arms' warm-wave means agree within 0.4 percent (1 prose: 77.98 against
77.78, -0.3 percent; 2 prose: 86.17 against 85.92, -0.3 percent), and that agreement, not the disjoint-range rule, is
what supports LEVEL at 1 to 4 streams. From four streams up the two arms' waves interleave within 0.2 percent. Ten of
ten cells are LEVEL on that rule, which is the answer the tier needs: it buys resume time and store bytes, not decode,
and a cost under about 2 percent at 1 to 4 streams is not excluded by these cells.

The replies are the same on both arms at every level, checked from the two `dec.jsonl` files rather than from the log:
all 30 (streams, kind, wave) cells carry identical per-stream `sha` lists and identical `drafted` and `accepted`
totals, and the eight distinct shas (four prose prompts, four code prompts) recur across streams and waves on both
arms, so the tier changed no token and no draft of any level's work.

## 3. The 100k conversation's append turns on the tier

One seed boot writes turns 1 to 5 (prompts 100,040 to 105,204 tokens; turns 3 to 5 resume from RAM at 100,092, 101,795
and 103,496 tokens, with TTFT 1.026, 1.014 and 1.019 s), then each append is a fresh boot that resumes from disk:

| turn | prompt tokens | resumed at | read from disk | TTFT | prefill | state file | new block | store growth |
|---:|---:|---:|---|---:|---:|---:|---:|---:|
| 6 | 105,271 | 105,197 | 2,004 MiB in 728 ms | **1.042 s** | 0.306 s | 116,969,808 B (111.5 MiB) | 4,833,376 B (4.6 MiB) | **121,803,184 B (116.16 MiB)** |
| 7 | 105,631 | 105,264 | 2,006 MiB in 777 ms | **1.226 s** | 0.435 s | 118,934,768 B (113.4 MiB) | 4,833,376 B (4.6 MiB) | **123,768,144 B (118.03 MiB)** |
| baseline (`work/KvTierW5/RESULT.md`, NVFP4, one slot) | | 105,202 | | 1.032 s | 0.327 s | | | 115.1 MiB |

- **Turn 6 is level with the baseline**: 1.042 s against 1.032 s (+1.0 percent) and 116.16 MiB against 115.1 MiB
  (+0.9 percent), on a different checkpoint (INT4 at eight streams) from the arm the baseline was measured on.
- **Turn 7 writes one state because the budget cannot hold two, not because of the dedup's boundary rule**: 118.03 MiB,
  where the baseline arm's boundary case wrote 231.2 MiB for the same position, and its TTFT is 1.226 s against that
  arm's 1.297 s. Turn 6's reply is 320 tokens, so the rewind sits 331 tokens above the resume point, past the dedup's
  `min_gap` of 256: the boundary rule was SATISFIED here, and at the dedup window's 16 GiB budget the same shape kept
  two states on both arms (`work/KvTierDedup/RESULT.md` 25-28 and 155-172). What stopped the rewind is the 3,166 MiB
  budget: the store charges a state its rows plus its fixed part, 115,642,400 + 105,631 x 18,880 = 2,109,955,680 B =
  2,012 MiB at the endpoint (the state read nearest it measured 2,004 MiB), so the endpoint alone leaves
  3,166 - 2,012 = 1,154 MiB and `prompt_cache.zig:323-324` proposes a rewind only when
  `rewind_bytes <= s.budget - priority_bytes`; a second ~2.0 GiB state cannot, so no rewind was proposed (the log's
  `kept 1`, `3 states, 2232 MiB and 0 MiB spare of 3166 MiB ... evicted 1`, and the single
  `imprint: 105624 tokens on disk` line are the whole of it). The endpoint bytes in that sum are arithmetic over the
  measured 18,880 B a row and the 110.28 MiB fixed part `[D]`; the 2,004 MiB charge, the 3,166 MiB budget, the 0 MiB
  spare and the single write are measured `[M]`.
- **TTFT is the disk read plus the tail's prefill**: 0.728 + 0.306 = 1.034 s against the 1.042 s measured, and
  0.777 + 0.435 = 1.212 s against 1.226 s. The 2 GiB read (728 and 777 ms) is two thirds of the resume; the prefill is
  the 74 and 367 tokens past the resume point.
- **The store's own lines** for turn 6: `imprint: read 105197 tokens from disk (2004 MiB in 728 ms)`, then
  `prompt cache: 105271 tokens, resumed at 105197, kept 1; 3 states, 2226 MiB and 0 MiB spare of 3166 MiB (hits 1,
  misses 1, evicted 1, ...)`, then `imprint: 105264 tokens on disk: 1 new blocks and its own 111 MiB (116 MiB this
  state, 1894 MiB of rows it shares) in 141 ms`. Turn 7 is the same shape with (2006 MiB in 777 ms) and
  `118 MiB this state, 1899 MiB of rows it shares ... in 139 ms`.
- The store grows by nine states over the window (7 after the seed, 8 after turn 6, 9 after turn 7), 2,810,738,232 B to
  3,056,309,560 B, and every growth is one state file plus one 4.6 MiB block: the tier is writing the endpoint only.

## 4. Exactness: each resumed reply against its no-tier cold twin

| turn | prompt tokens (tier / twin) | reply tokens (tier / twin) | ids equal | ids sha16 | tier TTFT | twin TTFT |
|---:|---|---|---|---|---:|---:|
| 6 | 105,271 / 105,271 | 320 / 320 | **yes** | `277412fd297b56aa` | 1.042 s | 44.206 s |
| 7 | 105,631 / 105,631 | 32 / 32 | **yes** | `af913cc499e378a6` | 1.226 s | 44.305 s |

Both resumed replies are token for token identical to their no-tier cold twins: the `ids` lists compare equal as lists,
not only as hashes, over all 320 and 32 tokens. The two hashes are also the ones `work/KvTierW5/RESULT.md` recorded for
the same prompts, so the INT4 arm at eight streams reproduces the NVFP4 arm's replies as well. What the tier buys at
this depth is the time to the first token: 1.042 s and 1.226 s against 44.21 s and 44.31 s of cold prefill, 42 and 36
times less, with the same output. Both replies are counts ("OK, then count from ..."), so this equality proves the
prompt and the instruction survived the disk round trip; it does not prove the restored rows hold the right values,
which needs a reply that depends on the passage (see the corrected note in `work/KvTierW5/tables.md` section 1).

## 5. Production after the window

The window's EXIT trap restored production and its own lines are the record, verbatim from `out/window.log`:

    RESTORE prod_rc 0 /health 200 image tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 id sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f
    PROD-IMAGE-OK sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f

So production came back on the pinned image and the exact id it went down with, `/health` answered 200, and the
trap's own check agreed (`PROD-IMAGE-OK`). A `window.sh clean` run afterwards re-enters the same trap, so a curl taken
during that second reload reads 000 for the model's load window; the 200 above is the restore's own reading.

The `/home` readings: 129,548 MiB free at preparation, 126 GiB at `DISK-START`, 121 GiB after the tier stage and 121
GiB after the twins, 124,831 MiB with the stores still in place. `window.sh clean` removes the store root
(`rm -rf /k/kvs`), the build stage and the conversation, and the evidence below is pulled before it.

Evidence: `work/KvTierShip/ev2.tgz`, sha256 `d871f5d24c0c13bb56c0f376f16cc1b71e6f61b33b727c77140d656f0555c0d1`, 37
files (the window log, `tables.md`, both arms' `dec.jsonl` and boot records, both refusal cells, every tier and twin
record, and the store listings).
