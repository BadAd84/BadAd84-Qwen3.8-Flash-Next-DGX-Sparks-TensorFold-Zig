# TensorFold main `1ece6e6db` + r5 + the persistent KV tier + the plan's cache refusal

Applied on top of `patches/main-1ece6e6db-r5` (0001 to 0020) and `patches/main-1ece6e6db-r5-kvtier` (0021, 0022) on a
pristine checkout of upstream main at `1ece6e6dbbc073582d50738ce8e73e3c3261a73b`. One patch,
`0023-kv-tier-pool.patch`: it makes a plan that leaves the prompt cache no bytes refuse by name instead of serving
with `--prompt-cache-disk` accepted and the tier doing nothing.

    ./apply.sh --check TREE     # the series, the KV tier and this patch apply in order, nothing written
    ./apply.sh TREE             # apply them

The numbers sort after the tier's 0022, so one directory holding r5's twenty, the tier's two and this one applies in
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

- It does not size anything. The plan, the page count and the cache figure are unchanged; when the plan leaves zero
  bytes the serve stops instead of running with a dead tier.
- It does not refuse a budget that is merely too small for one full-window state. A nonzero cache keeps what fits and
  says so per turn (`kept nothing at {d} tokens: {d} MiB passes the {d} MiB budget`), so that shape is a tuning answer
  rather than a dead flag.
- It does not create a store when there is no cache; that is the plan's own rule and stays so.
- The staging ring (the design's item 8) is not here. `0021` declares `context` so a state's staging permit is priced
  at the window instead of the 1 GiB default, and a state above the ring is skipped as `StagingFull`; the ring is
  window 2's measurement, on the design's own terms (`work/KvTierRecon/DESIGN.md`).

## What the plan grants when the flag is named

`--prompt-cache-gib N` is an ask. At `--parallel 8 --context 262144` on the INT4 checkpoint asking 6 GiB, the plan's
own startup line reports **a 3.1 GiB prompt cache** and the pages take the rest of the room: `the engine's own at a
262144-token window (4.99 GiB, in the model's), 7 more taking 278 pages of 4096 rows (20.02 GiB) ... of 31.0 GiB left
after a 10.0 GiB reserve ... a 3.1 GiB prompt cache` (measured in `work/KvTierShip/RESULT.md`). 3.1 GiB holds a
100,000-token state, about 1.9 GiB by the layout's 18,880 bytes a token, and not a full 262,144-token one at about
4.7 GiB, so a serve that must resume full-window conversations trades pages, streams or window for the cache until the
plan's own line reports enough. The refusal's message quotes the state's cost for exactly that arithmetic.

## The witness test

The test is named `CUDA cache default: a tier whose plan leaves the cache no bytes is refused by name`, so the
repository's existing step `test-cuda-cache-budget-host` (`zig/build/cuda.zig:310`, the native module with
`--test-filter "CUDA cache default"`) collects it and runs it with no GPU: `zig build -Dfixed-cpu
test-cuda-cache-budget-host`. No build change is needed, and the gate script requires the test's own phrase in the
step's log, so a test that stops being collected fails the run.

## Serve settings this package is measured with

The INT4 checkpoint's own environment (`patches/main-1ece6e6db-r5-int4/README.md`), plus the pool beside the tier:

    TF_FLASHNEXT_KV_PAGES=4096          # 6 and 8 streams at a 262,144-token window with fp8 KV (r5 0015)
    --prompt-cache-gib 6                # the ask: the plan grants a 3.1 GiB cache at this shape (see above)
    --prompt-cache-disk <root> --learn-conversations --learn-gib 60 --learn-daily-gib 200 --learn-min-free-gib 20

The block belongs in `scripts/qwen38/zig/target/env/dev.env` only once it is measured on this engine; `prod.env` stays
production's.
