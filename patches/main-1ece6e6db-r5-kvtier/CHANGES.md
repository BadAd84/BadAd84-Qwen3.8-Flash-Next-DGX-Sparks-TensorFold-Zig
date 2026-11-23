# `main-1ece6e6db-r5-kvtier`: what it changes against `main-1ece6e6db-r5`

r5's twenty patches are byte-identical here; this package appends one, `0021-kv-tier-fp8.patch`, cut against r5's
tree. Five files at +112 / -31:

| file | what the patch does |
|---|---|
| `zig/src/families/flashnext/cuda_disk.zig` | pass the KV format through the image: `partsOf`/`body`/`attention` take it and size keys by `keyRow(kv)` and values by `valueRow(kv)`; the view's `parts` passes `c.engine.kv`, `blank` allocates `bytesFor(kv, at, head, .full)` and sets `st.kv`, `facts` carries `kvWord(kv)` beside the head flag, `context` is declared so `Kept.longest` prices a state, and the two image tests loop over both formats against `cuda_snap.orderFor` |
| `zig/src/native/cuda_kept.zig` | the copy hands the target to a view's `copyable` (`V.copyable(t, st)`), so the format it must match is in scope |
| `zig/src/native/cuda_kept_test.zig` | a view whose states carry a format their target must match, and the test that a mismatched state is refused before any driver call is made |
| `docs/recipes/flash-next-cuda.md` | fp8's operator contract: `--learn-conversations` is no longer in the not-with list, and the arms' namespaces are the identity's facts |

## The design's list, item by item

`work/KvTierRecon/DESIGN.md` section 11.5 numbers five correctness prerequisites and calls them one patch, plus item 7
as a sixth prerequisite for any cell above the 1 GiB permit:

| design item | in the patch | why it alone is not enough |
|---|---|---|
| 1 `facts` carries the KV format | yes (`facts`, `kvWord`) | 1 without 4 sizes a bf16 buffer for fp8 rows |
| 2 the image sizes keys and values by the format | yes (`attention`) | 2 and 3 without 4 size the image past that buffer |
| 3 `parts` passes the target's format | yes (`parts`) | - |
| 4 `blank` sizes by `bytesFor(kv)` and sets `st.kv` | yes (`blank`) | 5 without 1 collides the namespaces |
| 5 the bf16 refusal lifts | yes (`copyable`, `Kept.copy`) | lifted without 1, a bf16 and an fp8 state share a namespace |
| 6 the words gain the format | no | the design marks it optional: `facts` already separates the namespaces, and item 5's format comparison refuses a state of another format before any byte moves |
| 7 `context` declared, so the permit prices a state | yes (`context`) | required before any 262,144-token cell: without it the permit stays at the store's 1 GiB default and the state is skipped as `StagingFull` |
| 12 the recipe's not-with-`--learn-conversations` | yes (the doc's fp8 bullet) | the operator contract changes with the code |

The ring (item 8), the pin (item 9), the block-name lineage (item 10) and the `--parallel` scope (item 11) stay out:
the design makes the first a measurement and the others out of window 1's scope.

## The refusal, kept as a comparison

The old guard refused every state that was not bf16, which is why `--kv-cache fp8` could not load with
`--learn-conversations`. Deleting it outright would have lost the invariant at the one place that had it, so the copy
now compares the state's format with the target's resolved one (`st.kv != c.engine.kv` is `error.KvFormat`). In-tree
that cannot fire (every state is saved from, or blanked for, the engine's own format); it is the belt beside the
namespace's braces, and it costs the target pointer the copy already had.

## Two defects this package's first gate round caught

Both were mine, both in the new code, and both are exactly what the gates exist for:

- `cuda_kept_test.zig`'s `copyable` parameter was named `t`, shadowing the file's `const t = std.testing`; the kept,
  cross-config and cross-tests gates all failed on it (`function parameter shadows declaration of 't'`). Renamed `c`.
- One doc comment in `cuda_disk.zig` measured 122 columns against the repository's 120-column rule for comment lines,
  the only `lean_new` finding of the round. Reworded to 115.

The second round's gate lines are in `RECORD.md`; nothing else in the package moved.

## `0022-kv-tier-dedup.patch`: the append turn keeps one state, not two

Window 5 attributed the append write amplification (`work/KvTierW5/RESULT.md` section 2): `lookupUserAt` decides the
rewind keep by asking `keptNear`, which scans the RAM store only, BEFORE `rows.read.recall` reads a state back from
disk. On a fresh boot the state the pass is about to resume from is therefore invisible at that decision, so an
append keeps a second, nearly identical state beside the endpoint: measured 227.5 MiB a turn against 116.3 MiB for
the boundary-only shape, at the same resume depth and with the same reply, at the cost of 0.17 s of extra prefill on
a last-message edit turn.

Two files at +52 / -2:

| file | what the patch does |
|---|---|
| `zig/src/core/prompt_cache.zig` | the RAM `find` is named, the recall keeps it as its floor, and after the recall a state that is not that RAM entry, sits at or under `active_rewind_at` and less than `min_gap` below it is made the rewind state: `rewind` tagged, `active_rewind_at` re-pointed, `active_rewind_key` recomputed, `keptNear`'s rule applied to the disk state. With no disk tier the recall returns the RAM find and nothing changes |
| `zig/src/core/prompt_cache_rewind_test.zig` | a fresh boot that recalls a state two tokens under the rewind point (min_gap 4) plans ONE keep: `marks {13}`, `counts.kept 1`, the recalled entry tagged `rewind`. Against the 0021 code the same test plans `{8, 13}` |

The test is the before/after witness: it fails on the 0021 tree (`slices differ ... instead found [0]: 8 [1]: 13`,
706 of 707 passing) and passes on the 0022 tree, so the fix is load-bearing and the failure is the measured defect
shape rather than a compile error.

Measured on spark6 (`work/KvTierDedup/RESULT.md`): the same 100k conversation seeded once and then appended to in
fresh boots writes **115.1 MiB a turn** (120,652,172 B) on the four appends whose previous reply is under
`min_gap`, against **228.1 MiB** (239,147,228 B) on the 0021 image `kv-w1` and the recorded **227.5 MiB** baseline;
TTFT at the recorded depth is 1.032 s against the recorded 1.068 s; all five resumed replies equal their no-tier
cold twins' token ids; a 60 GiB budget goes from 257 to **508** append turns. An append after a 320-token reply
sits over `min_gap` and correctly keeps both states (231.2 MiB on both arms).
