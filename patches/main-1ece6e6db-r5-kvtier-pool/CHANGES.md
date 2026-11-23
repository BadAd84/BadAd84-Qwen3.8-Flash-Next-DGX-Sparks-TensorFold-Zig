# `main-1ece6e6db-r5-kvtier-pool`: what it changes against the packages it sits on

## Against `patches/main-1ece6e6db-r5-kvtier` (0021 fp8, 0022 dedup)

One patch is added after the tier's two; nothing in the tier's two changes.

| file | sha256 |
|---|---|
| `main-1ece6e6db-r5-kvtier/0021-kv-tier-fp8.patch` | `47d90e3b5f71cd9a0404bb6f1ce836e09f709ebea44851308e8440e65d479dc7` |
| `main-1ece6e6db-r5-kvtier/0022-kv-tier-dedup.patch` | `cd5a336200f7c218fa53e52fdc11d51f2ee2b34a4010fcb4dda297e15ebda864` |

The tier's measured results stand unchanged: the fp8 image's first state (6813 tokens, 232 MiB, 294 ms write), the
append dedup at 115.1 MiB a turn against 228.1 MiB, and the five resumed replies equal to their no-tier twins
(`main-1ece6e6db-r5-kvtier/CHANGES.md`). This package changes no image, no sizing and no store rule; it adds one
refusal at plan time.

## Against `patches/main-1ece6e6db-r5-int4` (0021 autoround, 0022 serving pins)

The INT4 package's two are carried byte-identical, the tier's two follow them, and this one is last. The combined
package is `patches/main-1ece6e6db-r5-int4-kvtier`, whose five patches are the four above renamed in place:

| combined patch | source | sha256 |
|---|---|---|
| `0021-int4-autoround.patch` | `main-1ece6e6db-r5-int4/0021` | `3cffe99044c6ffd14820a8bc88085cc6e18990bddb5a5ab90d57223de4dda1a1` |
| `0022-int4-serving-pins.patch` | `main-1ece6e6db-r5-int4/0022` | `18ab81216fa104ea1853f27b60ccf9e88355ed7dde2aa976ff7d08b06bf11c26` |
| `0023-kv-tier-fp8.patch` | `main-1ece6e6db-r5-kvtier/0021` | `47d90e3b5f71cd9a0404bb6f1ce836e09f709ebea44851308e8440e65d479dc7` |
| `0024-kv-tier-dedup.patch` | `main-1ece6e6db-r5-kvtier/0022` | `cd5a336200f7c218fa53e52fdc11d51f2ee2b34a4010fcb4dda297e15ebda864` |
| `0025-kv-tier-pool.patch` | this package's `0023` | `e6a4872ed53041d3e5e4b850a3733dadba764b15c54941420bd4b480a9032589` |

The rename is the whole difference: the combined directory applies in glob order onto r5's twenty, which is how
`scripts/qwen38/zig/target/build_patches.sh` applies a directory, and it is the tree the device window builds.

## The measured evidence this change rests on

| fact | where |
|---|---|
| at production's shape the plan leaves the cache nothing: `model 68.31 GiB; 8 streams at once, the engine's own and 7 more taking 389 pages of 4096 rows (28.02 GiB) as they need them ..., no prompt cache` | the 2026-11-19 `int4-c8` arm, `--parallel 8 --context 262144` on the INT4 checkpoint, fp8 KV (quoted in `work/KvTierShip/STATUS.md`) |
| the pages are 28.02 GiB by the layout's own arithmetic: 389 x 4096 rows x 18,880 bytes a token = 30,082,334,720 bytes = 28.02 GiB | `kv_pool.Layout.pageBytes`, the same figure the startup line prints |
| a 0-byte cache keeps nothing, with its own log line: `kept nothing at {d} tokens: {d} MiB passes the {d} MiB budget` | `zig/src/core/prompt_cache_keep.zig:38` |
| a 0-byte cache resumes nothing | `zig/src/core/rows_read.zig:130` |
| no store is created at all when the cache is 0, so the flag's writer never exists | `zig/src/native/cuda.zig:398` |
| the automatic cache really is 0 when the plan spends the room on pages first: `automaticCache(left, 16 GiB)` is `@min(room, @max(minimum, room / 2))` | `zig/src/native/cuda_memory.zig:101`, called from `cacheBytes` at `cuda_memory.zig:210`, sized after `cuda_kv_pool.budgetOf` (`cuda_kv_pool.zig:165`) |
| a full-window state costs about 4.7 GiB at fp8: 113 MiB fixed plus 262,144 x 18,880 bytes = 4,949,268,480 bytes, 4.61 GiB, 4.72 GiB with the fixed part | `kv_pool.Layout.snap_bytes`, `token_bytes`; the witness test asserts the 4.7 GiB line |
| the pages and the contiguous image are byte-compatible, so a paged run is not the reason to refuse | `zig/src/families/flashnext/cuda_snap.zig:93` (`move`, "the same bytes in the same order as a contiguous cache's, a run a page"), pinned by `cuda_paging_snap_test.zig` |

## What the change is not

It is not a sizing change, and it does not make the tier work without a cache. A cache is the tier's home: the
refusal says so and names the flag that buys one. The staging ring (the design's item 8), the store pin (9), the
block-name lineage (10) and the `--parallel` scope (11) stay out, as they do in the tier package; the design makes the
ring a measurement before it is code (`work/KvTierRecon/DESIGN.md`).

## Two resolutions since the first gate round

Both were the patch's own wording, not behaviour, and both were fixed before the committed sha:

- `lean_new` read `2 new` on the first gated tree: two `multi-line comment` findings from the three-line doc comment
  above `learningRefusal`. Collapsed to one line (`/// --learn-conversations keeps a state in the prompt cache: a plan
  that leaves it no bytes is refused by name.`, 111 columns).
- the witness test was renamed from its working title to `CUDA cache default: a tier whose plan leaves the cache no
  bytes is refused by name`, so the existing `test-cuda-cache-budget-host` filter (`--test-filter "CUDA cache
  default"`) collects it. Nothing in `build.zig` changed.

The commit's patch sha256 above is of the fixed patch; the gate table for it is in `RECORD.md`.

## The trailing gate rows

The two steps still running when this package was first committed closed in the same run, with their own lines:

- `GATE nvcc_fatbins rc=0 wall=711s`: `Build Summary: 327/327 steps succeeded`, `FATBIN fn_int4: 1132920 bytes`
  sha256 `8080835ba1bccf4595f6ee21181e87fe8ed96f6d3d1da128bdfff8f81fa6beba`, `FATBIN images 125`. The package's
  kernels compile and link into the fatbins the image installs.
- `GATE test_cuda_cache_budget rc=0 wall=0s`: `Build Summary: 6/6 steps succeeded; 21/21 tests passed`. The step
  builds the witness test in and passes it; it reads 19 tests with this patch absent and 21 with it, and with one
  witness assertion planted false it fails and names the test (`20 pass, 1 fail (21 total)`).

The run's `GATE new_test_ran` check read red (`the pool guard's test ran in no host step`, `GATES-DONE bad=1`)
because it greps a summary that never prints a passing test's name; the check now runs the step's own binary and
reads the witness's line. `RECORD.md` carries the table, the three-tree counts and the planted-failure line.
