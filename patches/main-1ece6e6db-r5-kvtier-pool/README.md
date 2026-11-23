# TensorFold main `1ece6e6db` + r5 + the persistent KV tier + the plan's cache refusal + the whole ask as the store's

Applied on top of `patches/main-1ece6e6db-r5` (0001 to 0020) and `patches/main-1ece6e6db-r5-kvtier` (0021, 0022) on a
pristine checkout of upstream main at `1ece6e6dbbc073582d50738ce8e73e3c3261a73b`. Two patches:

- `0023-kv-tier-pool.patch` makes a plan that leaves the prompt cache no bytes refuse by name instead of serving with
  `--prompt-cache-disk` accepted and the tier doing nothing.
- `0024-kv-tier-full-ask.patch` budgets a family that declares no snapshot slots its whole `--prompt-cache-gib` ask:
  the split's slot half is set aside only for a family that declares `snap_slots`.

    ./apply.sh --check TREE     # the series, the KV tier and the two apply in order, nothing written
    ./apply.sh TREE             # apply them

The numbers sort after the tier's 0022, so one directory holding r5's twenty, the tier's two and these two applies in
glob order.

## Why: the flag was a no-op at production's shape

The KV tier never refused the KV page pool for this family. The two guards that name a conflict are
`zig/src/native/cuda.zig:336` (`kv_pages.ownCache`, a Loaded declaring `own_prompt_cache`, which is qwen3_5's
`TF_QWEN_KV_SHARE` only) and `zig/src/native/cuda.zig:341` (`prompt_pages.wanted`, a family declaring `share_attach`
with its `TF_KV_SHARE` count above 0: dory, gemma4, glm). Flash Next (`qwen4_exp`) declares neither
`own_prompt_cache`, `share_attach`, `share_pool` nor `kvPool`, so neither refusal can fire beside
`TF_FLASHNEXT_KV_PAGES`. The pages are byte-compatible with the contiguous image the store keeps:
`zig/src/families/flashnext/cuda_snap.zig`'s `move` copies a paged stream's rows run by run ("the same bytes in the
same order as a contiguous cache's, a run a page", line 111), pinned by
`zig/src/families/flashnext/cuda_paging_snap_test.zig`.

The real fault is the memory plan. With no `--prompt-cache-gib`, `cuda_kv_pool.budgetOf`
(`zig/src/native/cuda_kv_pool.zig:165`) sizes the pool's pages first and `cuda_memory.cacheBytes`
(`zig/src/native/cuda_memory.zig:210`) then answers `automaticCache(left, 16 GiB)`, which is
`@min(room, @max(minimum, room / 2))` (`cuda_memory.zig:101`) and therefore 0 when the room is 0. At
`--parallel 8 --context 262144` on the INT4 checkpoint that room is 0: the plan line reads
`model 68.31 GiB; 8 streams at once, the engine's own and 7 more taking 389 pages of 4096 rows (28.02 GiB) ...,
no prompt cache` (the 2026-11-19 `int4-c8` arm, `--parallel 8 --context 262144` on the INT4 checkpoint at fp8 KV;
the line is quoted in `work/KvTierShip/STATUS.md`).

A 0-byte cache is inert three times over, and none of it says so at startup:

| site | what a 0-byte budget does |
|---|---|
| `zig/src/core/prompt_cache_keep.zig:38` | keeps nothing: `kept nothing at {d} tokens: {d} MiB passes the {d} MiB budget` |
| `zig/src/core/rows_read.zig:130` | resumes nothing: `if (bytes > s.budget or s.most == 0) return have;` |
| `zig/src/native/cuda.zig:398` | never creates the store at all: `if (@hasDecl(F, "snap_save") and cache > 0 and ...)` |

So `--prompt-cache-disk` was accepted, the image loaded, the server answered, and the tier did nothing. The operator
had no way to tell that from a store that was working.

## What the patch carries

Three files, +55:

| file | what |
|---|---|
| `zig/src/native/cuda_streams.zig` | `learningRefusal`, public: given the open request, the ledger's `Count`, the plan's `Kept` and the room, it returns the refusal text when `--learn-conversations` is on with a learn root and the plan leaves the cache no byte, else null. Two texts: the pooled one names the streams, the pages, their rows, the room and the state's cost at the window; the plain one (no pool) names the room only |
| `zig/src/native/cuda.zig` | the call in `openWith`, after `kept` is known (`const cache = kept.copied;`) and before any store would be created: `problem.* = why; return null;` |
| `docs/recipes/flash-next-cuda.md` | the operator bullet: the tier composes with the pool, the plan spends the budget on the pages first, name `--prompt-cache-gib N` beside them, and a plan that leaves the cache no bytes is refused by name |

The refusal's numbers are the shape's own, computed at load: at `--parallel 8 --context 262144` on the INT4 checkpoint
at fp8 KV the window's own run refused with `8 streams take 361 pages of 4096 rows of the 31.0 GiB the CUDA memory
budget leaves`, and a state at the 262,144-token window takes about 4.7 GiB (113 MiB fixed plus 262,144 x 18,880
bytes). The witness test pins the same text at its own figures (389 pages, 33.1 GiB). The message names the state's
cost so an operator can size the flag; it is an ask rather than a grant, and the next section has the measured
difference.

## When it fires, and the cases it must not touch

The predicate is `o.learn_conversations and o.learn != null and kept.copied == 0`. The test pins all of the other
answers beside the firing one: a cache the plan leaves one byte of is not refused; `--learn-conversations` off is not
refused; a request with no learn root is not refused (no writer, no tier); and with no pool the message names the
budget and never pages. Three of those are `expectEqual(null, ...)` and the fourth is the plain message, so a refusal
that widened its condition fails the test rather than the operator.

## What it does not do

- `0023` does not size anything: the plan, the page count and the cache figure are unchanged, and when the plan leaves
  zero bytes the serve stops instead of running with a dead tier. The one sizing change in this package is `0024`'s
  (the store's share of an ask, below).
- It does not refuse a budget that is merely too small for one full-window state. A nonzero cache keeps what fits and
  says so per turn (`kept nothing at {d} tokens: {d} MiB passes the {d} MiB budget`), so that shape is a tuning answer
  rather than a dead flag.
- It does not create a store when there is no cache; that is the plan's own rule and stays so.
- The staging ring (the design's item 8) is not here. `0021` declares `context` so a state's staging permit is priced
  at the window instead of the 1 GiB default, and a state above the ring is skipped as `StagingFull`; the ring is
  window 2's measurement, on the design's own terms (`work/KvTierRecon/DESIGN.md`).

## The slot half a family without `snap_slots` never allocated (`0024`)

`kv_pool.split` (`zig/src/core/kv_pool.zig:120`) divides the prompt cache into snapshot slots and copied rows:
`snaps = @min(most_snaps, named orelse cache / 2 / snap_bytes, cache / snap_bytes)`. A null `named` is "half the cache
in slots", and `cuda_kv_pool.budgetOf` (`zig/src/native/cuda_kv_pool.zig:165`) passed `slots orelse named(o)` - the
TF_KV_SHARE count or `--keep`'s - and both are null at the served shape. So a family that declares no `snap_slots`
still had the half set aside: at the 262,144-token window `snap_bytes` is 115,642,368 B, so a 6 GiB ask reserved
27 x 115,642,368 = 3,122,343,936 B (2,977.65 MiB) and handed the store 6,442,450,944 - 3,122,343,936 = 3,320,107,008 B,
the figure the shipped store's `/stats` reported.
Flash Next (`qwen4_exp`) declares `snap_bytes`, `snap_save`, `snap_restore`, `snap_drop` and `kept_view` and no
`snap_slots` (`zig/src/families/flashnext/cuda_lanes.zig`), so nothing allocated that half: `cuda_kv_pool.store`
returns before `s.most = k.snaps` and `F.snap_slots(...)`, and the pages come out of the room anyway (`kv_pool.plan`
subtracts `snaps * snap_bytes + copied` from `left`), so those 2.98 GiB were neither the store's nor the streams'.

`0024` passes the count the family declares - `if (comptime @hasDecl(F, "snap_slots")) slots orelse named(o) else 0` -
and `split` returns the whole cache as copies when no slot is named or none fits (`snaps == 0`). A family that declares
slots keeps every behaviour: a null name is still half the cache, a named count is still that many, and `holds()`
reads no slots at all. A family without `snap_slots` that is given TF_KV_SHARE now makes its whole cache pool pages -
`share_kept_ppm`'s documented "all of it" - where before the null name left the store half of it; and
`--learn-conversations` with TF_KV_SHARE is already refused by name (`cuda.zig`), so no tier reads that half. The pages
are unchanged, because the plan already spent the whole cache before this patch; only the store's share of it changes
hands. Two witness tests pin it, both collected by existing steps: `kv_pool_test`'s
"a cache whose family declares no slots reserves none: the whole ask is copies and the pages are unchanged" (6 GiB ->
6,442,450,944 B copied; 27 slots -> 3,320,107,008 B; the same page count either way) and
`cuda_cache_capacity_test`'s "CUDA cache default: a family without snapshot slots budgets its whole ask, one that
declares them still half" (`zig build -Dfixed-cpu test-kv-pool` and `test-cuda-cache-budget-host`). The finding it
answers is `docs/receipts/Glm54Review/REPORT.md` F2: at 3,166 MiB a 261k state (4.70 GiB) "is never kept and pays
127.854 s cold", a second 100k conversation's fate was unmeasured, and "at 3,166 MiB the budget refused the rewind".

## What the plan grants when the flag is named

`--prompt-cache-gib N` is an ask. At `--parallel 8 --context 262144` on the INT4 checkpoint asking 6 GiB, the plan's
arithmetic gives the same 278 pages it gives without `0024` (the pages never included the slot half) and the whole
6,442,450,944 B to the store, so the startup line's cache figure is the ask and `/stats`'s `prompt_cache.budget_bytes`
is the ask itself; the boot line and the two figures are quoted in `docs/receipts/FullAsk/RESULT.md`. On the same tree
without `0024` the line read **a 3.1 GiB prompt cache** with a 3,320,107,008 B budget (measured in
`work/KvTierShip/RESULT.md`, the `kvtier-pool` window), which held a 100,000-token state (about 1.9 GiB by the
layout's 18,880 bytes a token) and not a full 262,144-token one (about 4.7 GiB).

## The witness tests

Two tests, each collected by an existing step and named for its filter: `CUDA cache default: a tier whose plan leaves
the cache no bytes is refused by name` (`0023`'s), and `CUDA cache default: a family without snapshot slots budgets
its whole ask, one that declares them still half` (`0024`'s, in `zig/src/native/cuda_cache_capacity_test.zig`). Both
are collected by `zig build -Dfixed-cpu test-cuda-cache-budget-host` (`zig/build/cuda.zig:310`, the native module with
`--test-filter "CUDA cache default"`); `0024`'s core-level witness is collected by `zig build -Dfixed-cpu test-kv-pool`.
No build change is needed. The gate run proves collection twice: it requires the core witness's own name in the
`zig test` log of its module, and it requires the cuda step's test count to rise above the five-patch head's 21, so a
test that stops being collected fails the run.

## Serve settings this package is measured with

The INT4 checkpoint's own environment (`patches/main-1ece6e6db-r5-int4/README.md`), plus the pool beside the tier:

    TF_FLASHNEXT_KV_PAGES=4096          # 6 and 8 streams at a 262,144-token window with fp8 KV (r5 0015)
    --prompt-cache-gib 6                # the ask: the store's budget at this shape with 0024 (3.1 GiB without it)
    --prompt-cache-disk <root> --learn-conversations --learn-gib 60 --learn-daily-gib 200 --learn-min-free-gib 20

The block belongs in `scripts/qwen38/zig/target/env/dev.env` only once it is measured on this engine; `prod.env` stays
production's.
