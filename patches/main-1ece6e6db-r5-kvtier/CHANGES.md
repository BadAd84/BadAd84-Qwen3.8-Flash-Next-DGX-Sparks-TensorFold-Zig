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
