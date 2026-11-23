# TensorFold main `1ece6e6db` + r5 + the persistent KV tier (fp8 image, then the append dedup)

Applied on top of `patches/main-1ece6e6db-r5` (0001 to 0020) on a pristine checkout of upstream main at
`1ece6e6dbbc073582d50738ce8e73e3c3261a73b`. Two patches: `0021-kv-tier-fp8.patch` carries the five correctness
prerequisites window 1 of the NVMe KV tier design
(`work/KvTierRecon/DESIGN.md` section 11.5, items 1 to 5 and item 7) and the recipe sentence that named fp8's
`--learn-conversations` refusal; `0022-kv-tier-dedup.patch` is cut on top of 0021 and stops a fresh-boot append from
keeping a second state beside the endpoint (window 5's write amplification).

    ./apply.sh --check TREE     # r5's twenty and these two apply in order, nothing written
    ./apply.sh TREE             # apply them

The numbers sort after r5's 0020, so one directory holding r5's twenty patches and these two applies in glob order.

## What the patch carries

The tier already exists at r5: `zig/src/native/cuda_kept.zig` (the shared image engine), Flash Next's view in
`zig/src/families/flashnext/cuda_disk.zig`, and the store in `zig/src/core/rows_*`. What the served configuration
could not do is `--kv-cache fp8` with `--learn-conversations`: `copyable` refused every state whose KV format is not
bf16, and the attach probe copies the state it just saved, so the server refused at load. The patch makes the image
fp8-capable and separates the two formats' namespaces:

| # | change | where |
|---|---|---|
| 1 | `facts` returns the head flag and the KV format, so bf16 and fp8 states never share a namespace | `families/flashnext/cuda_disk.zig` (`facts`, `kvWord`) |
| 2 | the image sizes keys and values by `keyRow(kv)` and `valueRow(kv)` instead of one `sh.kv_row` for both planes | `cuda_disk.zig` (`attention`) |
| 3 | `parts` passes the target's resolved format into the image | `cuda_disk.zig` (`parts`) |
| 4 | `blank` allocates `bytesFor(kv, at, head, .full)` and sets `st.kv`, so a state read back is the format it was kept in | `cuda_disk.zig` (`blank`) |
| 5 | the bf16 refusal lifts; the copy keeps the invariant it protected as a format comparison against the target | `cuda_disk.zig` (`copyable`), `native/cuda_kept.zig` (`Kept.copy`) |
| 6 | the view declares `context`, so the store prices a whole state for its staging permit instead of the 1 GiB default | `cuda_disk.zig` (`context`; `native/cuda_kept.zig` `longest` already reads it) |

Item 6 of the design's checklist (the words gaining the format) is not in the patch: the design marks it optional,
`facts` already separates the namespaces, and the copy's format comparison refuses a state of another format before
any bytes move. `docs/recipes/flash-next-cuda.md` no longer lists `--learn-conversations` as unsupported with fp8 and
says what the tier now does with it.

No setting is added, so `platform/environment.zig` and `docs/environment.md` are untouched.

## The order the design fixes

Two constraints, both from the code: the staging ring must land before the permit raise is removed (otherwise every
state above the ring is `StagingFull`, which is today's behaviour at 1 GiB), and `context` must land before any
262,144-token cell is attempted, or the cell silently tests a skipped save. This package takes the second and leaves
the first to window 2, where the design's measurement decides whether the ring or the in-tree sliced writer
(`TENSORFOLD_ROWS_SYNC=1`) is the answer.

## What 0022 carries

Window 5 attributed the append write amplification: on a fresh boot the rewind keep is judged by `keptNear`
(`core/prompt_cache.zig`), which scans the RAM store only, BEFORE `rows.read.recall` reads a disk state back, so the
state the pass is about to resume from is invisible and a second, nearly identical state is written beside the
endpoint (227.5 MiB a turn against 116.3 MiB for the boundary-only shape, `work/KvTierW5/RESULT.md` section 2).
0022 lets the disk recall take part in that deduplication: a recalled state at or under the rewind point and less
than `min_gap` below it is the rewind state, so the pass keeps the endpoint alone. One test file pins it: a fresh
boot recalls a state two tokens under the rewind and the plan keeps one state (`{13}`) rather than the endpoint and
the rewind (`{8, 13}`).
