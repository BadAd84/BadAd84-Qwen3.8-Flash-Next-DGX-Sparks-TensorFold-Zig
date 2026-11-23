# The draft-chain policy in the served tree, and which stop binds (read before measuring)

Source read: the tree that built the dev image `tensorfold-qwen38:qr-b-r5int4-1ece6e6d` (label
`tf.source=1ece6e6d...+r5-0001-0020+int4-0021-0022`, `tf.tree.manifest=ab6389fc2ab6...`). That tree is
`~/work/int4cf/t` on spark6 (the tree work/GapArms named as our tree); its cited files were fetched to
`work/ProseDraft/served/` and their sha256 match the box's own:

| file | sha256 |
|---|---|
| `families/flashnext/cuda_lanes.zig` | `1ebf522d252b795b15d58a15eb38d9d3227c341df80522ad8a89d5ff3cfbdac4` |
| `families/flashnext/cuda_lanes_draft.zig` | `44f1256a09f0997d99f603b55f31eb0388b84df097cf43a113fce4a809af923f` |
| `families/flashnext/cuda_mtp.zig` | `1349889f35d942b527361f2a62928945885bd42087609368fe8f6bf6f4938a04` |
| `families/flashnext/cuda_lanes_load.zig` | fetched with the same pack |
| `core/lanes/config.zig` | `04b0d86001f51a2a9b3a4d8aba3bf3971a1ba57d36ec32d7e56cbbe3d3f8cb51` |
| `core/lanes/depth.zig` | `a989d6b165ca6fa5db04f7cb9988809545cab8494b7f992b3d382d8e7966414a` |
| `core/lanes/engine.zig` | `11f1f476a6b6dc595f9e5d6da2b1f4bb120308f6a3d1dd010426dc407f00e170` |
| `platform/environment.zig` | `af18490a83ce581e45187eaf4a8ab535414f89483099feb6e37f3c152a3ace22` |

A newer main-tree copy (`work/KvTierW2/tree`, with the KV tier and later patches) was read first; it differs from the
served tree in files this window does not depend on (a decode read-ahead, copy_guard, boot-proven window widths), and
its stop rules are the same code. Every line number below is the served tree's, and every citation is to a fetched
file under `work/ProseDraft/served/`.

## 1. How many drafts a round asks for

1. `families/flashnext/cuda_lanes.zig:230-247` `facts()`, the model config the lanes engine consumes:
   - line 233 `.exact_width = if (drafting) mtp.max_rows else 2`, and `cuda_mtp.zig:72` fixes `max_rows = 32`: the
     verify window is at most 32 rows.
   - line 239 `.drafts = if (drafting) @intCast(@max(self.depth, self.depth_greedy)) else 0`: the two depth settings
     collapse to the larger one (8 at the recipe's 6 and greedy 8).
   - line 240 `.draft_probabilities = drafting`, which becomes `Config.node_probabilities = true`.
   - line 246 `.draft_streams = drafting and lanes_draft.batchHeads()`: a shared round drafts its streams in one
     batched head pass.
   - No `.window_costs`, no `.draft_confidence`, no `.granted_depth` and no `.head_trees` are set here.
2. `core/lanes/config.zig:166` `.most_drafts = @min(m.drafts, @min(width - 1, max_draft))`. At the recipe's
   `TF_FLASHNEXT_DRAFTS=6` with greedy 8 this is 8; at 15/15 it is 15 (still under width - 1 = 31).
3. `core/lanes/engine.zig:225` (the early path) and `engine.zig:379-381` (`draftLate`) ask
   `e.rule.headDepth(&w, budget, win.probe(e))` for the next round's depth; the answer rides the DraftRequest as
   `r.depth`.
4. `core/lanes/depth.zig:219-229` `headDepth`:
   - `who.finished` gives 0 (line 220); a supplied budget wins (line 220);
   - `r.granted_depth` is false for us (`config.zig:172` needs `draft_probabilities` AND `granted_depth`);
   - lines 222-223: `r.node_probabilities` is true and a greedy stream is not `sampled`, so the condition holds and it
     returns `@min(most_drafts, @max(1, who.draft_room - 1))`. For our greedy benchmark streams that is the full 8.
   - line 225 `r.depth(who)` (the cost model) is reached only for streams that fail line 222, that is sampled
     streams. With `family_costs` empty (no `.window_costs` in `facts()`), `depth()` is the heuristic at
     `depth.zig:155-158`: 1 draft if the learned first-draft keep rate is under 0.8, 2 if under 0.9, else 3.
5. `families/flashnext/cuda_lanes_draft.zig:91` (batched) and `families/flashnext/cuda_lanes.zig:535` (one stream a
   call): the chain length is `@min(@min(r.depth, mtp.depthFor(sampling, self.depth, rule.greedy)), room)`, where
   `depthFor` (`cuda_mtp.zig:44-46`) is the greedy depth for a greedy stream.

Consequence: for greedy decoding the numeric depth cannot bind below 8, and both 6/8 and 15/15 sit above whatever the
stop rule allows. That is why work/GapArms measured digit-identical round counters at the two depths.

## 2. The stop rules that end a chain early

6. `families/flashnext/cuda_lanes_draft.zig:24-32` `Rule` and `rule(width)`:
   - line 26 `pub const shared_stop: f64 = 0.6;`
   - line 29 `greedy = if (width <= wideStreams()) depth_greedy else @min(depth_greedy, mtp.default_depth)`; the width
     is the call's draft-request count, `wideStreams()` is `TF_FLASHNEXT_GREEDY_WIDE` default 4 (lines 39-43).
   - line 30 `stop = if (sharedRule() and busy(&self.lanes)) shared_stop else self.confidence`.
   - `sharedRule()` is `TF_FLASHNEXT_SHARED_DRAFTS`, default true (lines 45-48); `busy()` is true when more than one
     lane is neither finished nor paused (lines 50-60).
7. `families/flashnext/cuda_lanes_draft.zig:34-37` `stopFor`: a greedy stream takes the round's `greedy_stop`; a
   sampled stream always takes `self.confidence`.
8. `families/flashnext/cuda_mtp.zig:51-69` `Stop.take(j, p)`:
   - `c > 0`: draft j is proposed only at or above c; at j = 0 it is always proposed and the chain ends
     (`more = false`) when it is below c. This is a per-draft threshold, and 0.6 is one.
   - `c < 0`: the running product of the drafts' probabilities, ending the chain at the first product below `-c`; the
     draft that crosses is not proposed except at j = 0. This is a product threshold.
   - `c == 0`: every draft in the requested chain is proposed.
9. `families/flashnext/cuda_mtp.zig:48` `default_confidence = -0.4`; our launcher exports
   `TF_FLASHNEXT_CONFIDENCE=-0.15` (`scripts/qwen38/zig/target/env/dev.env:6`, read at `cuda_lanes_load.zig:91`), and
   production's launcher exports the same -0.15.

## 3. The accounting the harness reads

10. `core/lanes/engine.zig:279-284`: in `conclude`, for a window of `rows`, `drafted += rows - 1` and
    `accepted += path.len - 1`, per engine and per stream; `rounds += 1` at line 354 (and the pipelined path's at
    470). The `done` line prints them (`server/chat_generation.zig`: `rounds={d} accepted={d}/{d}`). So drafted/round
    is the mean number of draft tokens actually submitted for verification, which is the chain length after the stops.

## 4. The guess this window tests

At 4 streams `busy()` is true, the gate is on (dev.env does not set `TF_FLASHNEXT_SHARED_DRAFTS`; its own comment
lists the name as not yet measured on this stack), and every greedy chain ends at the first draft whose probability
is below 0.6. On prose that is about two proposals a round, which is the 1.92 work/GapArms measured. At 1 stream
`busy()` is false and the chain is the product rule at 0.15, which allows about three (3.07 measured in
work/DevVsProd).

**Expected binding stop**: `shared_stop = 0.6` (`cuda_lanes_draft.zig:26`, applied at line 30 through `sharedRule()`
and `busy()`), for greedy streams only, whenever a call has more than one open lane.

Arms that test it, one knob each:
- `S0` `TF_FLASHNEXT_SHARED_DRAFTS=0` removes the 0.6 gate and leaves the product rule (-0.15) at every width. This is
  our equivalent of production's permissive PROPOSE 0.05 plus CONTINUE 0.20.
- `C0` `TF_FLASHNEXT_CONFIDENCE=0` removes the product stop (every draft in the requested chain): the 1-stream probe.
- `C20` `TF_FLASHNEXT_CONFIDENCE=-0.20` sets production's CONTINUE value on our product rule.
- `G8` `TF_FLASHNEXT_GREEDY_WIDE=8` keeps greedy depth past four streams; by lines 29-30 it cannot matter at 1 or 4.
- `PN` production's six draft names at values that would change behaviour if any were read (0.99 / 1 / 0.99 / 1 / 0 /
  0). This is the inert-name control, and it is needed because every dev boot already carries production's 54 names
  at production values (`in/prod.env`, exported on every boot): a same-value arm would prove nothing.

## 5. Production's names against our readers

| production name | production value (launcher lines 51-56) | reader in the served tree | our equivalent and value |
|---|---|---|---|
| `TF_FLASHNEXT_DEPTH` | 15 | none; the only DEPTH string is the `TF_FLASHNEXT_DEPTH_LOG` diagnostic (`cuda_lanes_draft.zig:19,116-135`) | `TF_FLASHNEXT_DRAFTS` / `_DRAFTS_GREEDY` feed `most_drafts`, 6 and 8 from the recipe, both above the gate |
| `TF_FLASHNEXT_DRAFT_CONTINUE` | 0.20 | none (grep: 0 files) | `TF_FLASHNEXT_CONFIDENCE`, the product line, -0.15 |
| `TF_FLASHNEXT_DRAFT_PROPOSE` | 0.05 | none (grep: 0 files) | the 0.6 per-draft gate; no knob of its own, removed by `TF_FLASHNEXT_SHARED_DRAFTS=0` |
| `TF_FLASHNEXT_DRAFT_DEPTH_SHARED` | 7 | none (grep: 0 files) | `TF_FLASHNEXT_GREEDY_WIDE`, default 4 |
| `TF_FLASHNEXT_MULTI_MAX` | 192 | none (grep: 0 files) | none |
| `TF_FLASHNEXT_NGRAM_LATE` | 1 | none (grep: 0 files) | none |
| `TF_FLASHNEXT_NGRAM_PREFETCH` | 1 | none (grep: 0 files) | none |
| `TF_FLASHNEXT_WINDOW` | 64 | none; WINDOW_ROWS is a different name (`environment.zig:202`) | the verify window's rows, `mtp.max_rows` = 32 |

The grep counts come from the box precheck over the served tree's `zig/src` (0 files for each of the six names).
