# KvTierW5: equal-depth exactness, the append write amplification, and rewrite reuse

Window 5 of the persistent NVMe KV tier for Qwen3.8 Flash Next on spark6, under `~/work/gpu.lock`, after
windows 1 to 4 proved the write, the read, the fleet rule and the agent shape (`work/KvTierW1` to `W4`).
Image: `tensorfold-qwen38:kv-w1`, id `sha256:ef6967ac57fb40a19f0c54c4788ac1e9f79fb73cf29b61ba3f19090a961108bb`,
labels `tf.patches 4144696f21e3`, `tf.kernels embedded` (the `patches/main-1ece6e6db-r5-kvtier` series). Every
boot used the running production container's own environment (53 `TENSORFOLD_`/`TF_FLASHNEXT_`/`KV_` variables
read from it), the NVFP4 checkpoint the image takes, fp8 KV, one slot at a 262,144-token window, `--dashboard`,
and the four store flags of `work/KvTierW4/SHIPPING.md` (`--prompt-cache-disk`, `--learn-gib 60`,
`--learn-daily-gib 200`, `--learn-min-free-gib 20`). Production was restored at every exit and is pinned by id
`sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f` (`PROD-IMAGE-OK`).

Every cell this file planned has a measured row. `work/KvTierW5/tables.md` carries the generated tables (all
twelve exactness pairs, the store listings, the per-turn accounting and the session projection); every claim
below names its instrument: the server's own log line, `/stats`, the store's trailer listing, or the request
record. The raw evidence tree is `work/KvTierW5/ev` (`out/` from the box), and `work/KvTierW5/notes.md` holds the
citations and the numbers as they landed.

## 0. The conversation and the cells

The conversation is a 100,000-word reference text in the system message and six turns: turns 1 and 2 carry a
short instruction, turns 3, 4 and 5 each carry a DISTINCT 1,200-word passage (so a resume one turn behind
recomputes that turn's text; X2 measured 1,781 tokens), and turn 6 asks for a 400-line count
decoded greedily for 320 tokens (so two replies compare over hundreds of tokens, not two). Every arm builds each
turn's messages from the reference build arm's own `h<N>.json`, so the prompts are identical by construction and
the analysis compares the prompt token counts of every pair.

| cell | what it is | what it proves |
|---|---|---|
| build | turns 1 to 5 in one boot, tier on, default prompt cache | the store every cell resumes from, and the per-turn write bytes |
| X1 | turn 6, fresh boot, store = turns 1 to 5 | a resume from the BOUNDARY state (turn 5's endpoint) |
| X2 | turn 6, fresh boot, turn 5's stored state deleted | a resume ONE TURN BEHIND (turn 4's endpoint) |
| X3 | turn 6 with turn 3's passage edited | a resume whose stored tails no longer match, so `Rows.matches` truncates to turn 2's endpoint |
| C1, C2 | turn 6, fresh no-tier boots (twice) | the cold twin, and the cold decode's determinism |
| C3 | turn 6 with turn 3's passage edited, no tier | the cold twin of X3 |
| C4 | turn 6 with the last message edited, no tier | the cold twin of W1a and W1b |
| R1 | no tier, turns 1 to 5 then turn 6 in ONE boot | the RAM state at X1's depth: the strict equal-depth pair |
| R2 | no tier, turns 1 and 2 then the edited-passage turn | the RAM state at X3's depth: the strict equal-depth pair |
| W1b | turn 6, then the last message edited, two boots | a last-message edit resuming from turn 6's own rewind state |
| W1a | the last message edited with no turn-6 state on disk | the same edit without a rewind state: the rewind's value |
| M1a, M1b | turns 1 to 5, then turn 6, under a prompt cache budget that refuses the second kept state | the boundary-only mitigation: bytes a turn, and its restore trade |
| W2 | turn 6 with the SYSTEM message edited | a first-message rewrite: no state can match |

## 1. Equal-depth exactness

### 1.1 The rule, preregistered before the core chain ran

A pair is exact only when the two token id lists are equal. Both arms of every pair send the SAME messages file
(`out/conv/msgs/t6.json`, `t6edit.json` or `t6alt.json`), so the prompts are identical by construction, and the
analysis quotes both token counts as the check that they were the same on the wire. Cold determinism is
established by C1 against C2. Then, for each tier cell, three comparisons decide the cause of any difference:

| observation | conclusion |
|---|---|
| tier ids equal to the cold twin | exact at that depth |
| differ, and the RAM twin at the SAME resume depth equals the cold twin | the disk state differs from the RAM state in a way the reply exposes: a store defect, to be named by span and path |
| differ, and the RAM twin at the same depth equals the tier cell | the engine's depth numerics, not the store: exact at equal depth, but the shipping gate "resumed equals fresh" fails |
| all three differ | both effects, each span named |

The instrument is the reply's own token ids (`return_token_ids`), not the store's read-back check: the recipe's
environment (69 variables, read from the production container) carries no `TF_IMPRINT_VERIFY`, so
`rows_store.zig:135` leaves `verify` off and `/stats` reports `verified 0` on every arm. A run that agrees
byte for byte therefore proves the write and read paths together, which a verified flag would not.

### 1.2 The smoke cell (final, measured at 2,098 tokens)

A 2,000-word reference and two turns: turn 1 on a fresh store, then turn 2 on a second boot (tier on) and on a
third boot (no tier).

| cell | prompt tokens | probe from | disk tokens | disk bytes read | TTFT s | prefill s | ids |
|---|---:|---|---:|---:|---:|---:|---:|
| s2 tier on | 2,098 | disk | 2,033 | 154,033,524 (146.9 MiB) | 0.232 | 0.183 | 27 |
| s3 no tier | 2,098 | off (404) | - | - | 1.035 | 1.033 | 27 |

The 27 ids are equal and the prompts are equal, so a boundary resume at 2,098 tokens reproduces the cold reply
byte for byte. The tail recomputed after the state is 65 tokens (7 of the assistant header, the 28-token reply,
the 30-token new message).

### 1.3 The three depths at 100k

Measured on the 105k conversation, all with the same 320-token greedy request (or its edited twin), each on a
fresh boot of the store built by turns 1 to 5:

| cell | prompt tokens | resume depth | tail recomputed | TTFT s | prefill s | 320 ids sha16 |
|---|---:|---:|---:|---:|---:|---|
| X1 boundary (turn 5's endpoint) | 105,279 | 105,202 | 77 | 1.125 | 0.397 | 277412fd297b56aa |
| W1b last-message edit (turn 6's rewind) | 105,279 | 105,245 | 34 | 0.990 | 0.267 | 277412fd297b56aa |
| X2 one turn behind (turn 4's endpoint) | 105,279 | 103,498 | 1,781 | 1.905 | 1.205 | 277412fd297b56aa |
| X3 stale tails (turn 2's endpoint) | 105,142 | 100,092 | 5,050 | 3.350 | 2.668 | 277412fd297b56aa |
| cold, no tier (C1) | 105,279 | - | 105,279 | 46.917 | 46.853 | 277412fd297b56aa |
| X4 truncated state (deepest file cut in half) | 105,279 | 103,498 | 1,781 | 1.956 | 1.221 | 277412fd297b56aa |
| cold, repeat (C2, determinism) | 105,279 | - | 105,279 | 47.014 | 46.978 | 277412fd297b56aa |
| cold, edited passage (C3) | 105,142 | - | 105,142 | 47.066 | 46.996 | 277412fd297b56aa |
| cold, edited last message (C4) | 105,279 | - | 105,279 | 47.120 | 47.055 | 277412fd297b56aa |
| RAM twin of X1 (R1, same boot) | 105,279 | 105,202 | 77 | 0.376 | 0.350 | 277412fd297b56aa |
| RAM twin of X3 (R2, same boot) | 105,142 | 100,092 | 5,050 | 2.746 | 2.740 | 277412fd297b56aa |

The four resumed replies are identical to each other, and every cold twin produces the same ids: C1 and C2, two
independent no-tier boots of the 105,279-token prompt (so the cold decode itself is deterministic and the control
is not vacuous), C3 for the edited-passage prompt, and C4 for the edited last message. A resume at a 77-token
tail therefore reproduces a 46.85-second cold prefill byte for byte in 1.125 s, and a resume at a 5,050-token
tail reproduces its own 47.0-second cold prefill in 3.35 s. `work/KvTierW5/tables.md` sections 2 and 2b carry the
generated comparisons with both prompts quoted.

What that buys, in the user's units: a resumed turn answers in 1.125 s at the boundary and 1.905 s one turn
behind (1,781 tokens recomputed), against 46.92 s and 47.01 s cold, 41.7 times and 24.7 times faster, on
identical replies.

**A damaged state file is refused, not resumed.** The third depth's literal reading is a store whose state file
is truncated: the cell copies the base store, cuts its deepest state file (at 105,202) from 120,630,616 to
60,315,308 B, and boots. The store's own log says `imprint: a disk state failed its check (RowsRead); it is
forgotten` and `6 disk blocks no kept state names are removed`, so the state is unlinked and the blocks only it
named are collected, and the request then resumed at 103,498 (the next state) with a 1.221 s prefill and the cold
reply's ids. A truncated state can therefore never become a reply.

**Verdict: exact.** Both strict equal-depth pairs hold. R1, with no tier at all, resumed turn 6 from the RAM
store at exactly 105,202 tokens (`prompt cache: 105279 tokens, resumed at 105202` in its own log) and produced
the same 320 ids as X1's disk resume at 105,202 and as the two cold boots; R2 resumed the edited-passage prompt
from RAM at 100,092 (`prompt cache: 105142 tokens, resumed at 100092`) and produced the same ids as X3's disk
resume at 100,092 and as C3. So the disk image and the RAM state at the same depth produce the same 320 token ids
in reply, the tier's writes and reads preserve the computation for the two states this window compared, and every
resumed reply this window could construct equals the no-tier reply at the same prompt: tails of 34, 77, 1,781 and
5,050 tokens, five cold twins, two equal-depth RAM pairs and a damaged state file. Byte equality of the stored rows
themselves is NOT shown: no cell compares a disk state's bytes against the RAM state's, only the replies the two
produce, and every cell in the table above generates the same 320-token count and shares sha16
`277412fd297b56aa`, so those ids prove the instruction and the prompt survived, not that the restored rows are
right. `work/KvTierW5/tables.md` section 2 carries all twelve pairs, every one EQUAL.

A further check on the histories themselves: the RAM twin R1 runs turns 1 to 5 with no tier at all, and its
replies to those five turns (sha16 `052beccc2fc3c430`, `81adacd4eeead45c`, `b732c5c07f27d37a`, ...) are the ones
the tier arm's build produced (`work/KvTierW5/tables.md`, section 1), so the conversation the two arms resume is
the same conversation and not merely the same token count.

What this does NOT prove: one conversation, one template, fp8 KV, one checkpoint, one window (262,144) and
replies of 320 greedy tokens. It does not test bf16 KV, a prompt at the 262,144-token edge, a second checkpoint, or a reply
long enough for a late flipped argmax (window 4's divergent pair was 512 tokens). Those are named as scope, not
as results.

### 1.4 The relation to window 4's divergent pair

Window 4's only divergent pair compared a tier resume at a 6-token tail with a no-tier RAM resume at a 2,061-token
tail at 261k, and its report refuses to attribute the difference because the depths differed
(`work/KvTierW4/RESULT.md` section 6). This window's four depths (tails 34, 77, 1,781 and 5,050) all produce the
same reply at the agent shape, and the cold twins at 105,279 agree with them, so a depth effect of the size
window 4's pair implies is not general here. Window 4's pair is therefore either a 261k-specific effect or a
pair that differed in something other than depth; this window does not settle which, and it says so rather than
claiming the question closed.

## 2. The append write amplification

### 2.1 What an append turn writes, from the writer

In the agent shape (a boot per turn) an append turn keeps two states; in a single boot it keeps one, and section
2.2 shows why. Each state's own file is dominated by a fixed part that does not shrink with the number of new
tokens:

- the mark list (`core/prompt_cache.zig:433-434`) is the history's endpoint (`prompt - 7` for this template's
  7-token assistant header) and the rewind state at the start of the last user message minus one; the
  "stable" mark at the previous prompt's end and the shared system cuts are dropped because they are within
  `min_gap` of the resume point or behind it;
- a state's own file (`core/rows_image.zig:78-104` `ownRanges`) holds the row-0 parts whole plus each row part's
  rows outside whole blocks. The row-0 parts are `36 * 61,440 + 36 * 3,145,728 + 184,320 = 115,642,368 B`
  (110.28 MiB: the DeltaNet conv windows, the DeltaNet recurrent states and the n-gram tail,
  `families/flashnext/cuda_disk.zig:20-24`); the attention rows are content-addressed blocks of 256 tokens
  (`core/rows_store.zig:18`) shared by every later state (`core/rows_chain.zig:61-79`), so an append writes no
  block it already has;
- measured: the state at 2 tokens in this window's smoke is 115,678,616 B, which is the fixed part itself, and
  the state at 2,033 tokens is 119,822,212 B, the fixed part plus its partial block and metadata.

So the amplification is not shared blocks rewritten: it is two state files, each paying the 110.28 MiB fixed
part plus its partial block and 4 bytes a token of metadata, for however few tokens the turn added.

Measured in this window's smoke (final): turn 1 wrote 5 state files (2 probe states at 2 and 9 tokens, and the
pass's 3 marks: a shared system cut at 1,502, the rewind at 2,013 and the endpoint at 2,033) and 7 blocks,
625,184,212 B in the identity directory. Turn 2
(prompt 2,098, 58 new tokens over turn 1's 2,040) wrote exactly TWO states, the endpoint at 2,091 and the
rewind at 2,071, plus 1 new block: the directory grew by 237,376,136 B (226.4 MiB), and the writer's own lines
read `2091 tokens on disk: 1 new blocks and its own 111 MiB (115 MiB this state, 36 MiB of rows it shares)` and
`2071 tokens on disk: 0 new blocks and its own 110 MiB (110 MiB this state, 36 MiB of rows it shares)`. The
58 new tokens' rows are 1,095,040 B (1.04 MiB), so that turn wrote 216.8 times the bytes its new tokens needed.
The same lines at 100k are in section 2.2, where the turn adds 70 tokens to a 1.9 GiB row set and writes
227.5 MiB.

### 2.2 Where the second state comes from: the rewind keep is deduplicated only against RAM

The two marks are not intrinsic to an append. `lookupUserAt` sets `active_rewind_at` to the rewind point
(`core/prompt_cache.zig:319-324`), and then asks `keptNear` (`:241-252`) whether a kept state sits within
`min_gap` (256 tokens) below it: if one does, the rewind is re-pointed at that state and no new copy is made
("a state kept under min_gap before it is the rewind state: no new copy", `:325-327`). `keptNear` scans the RAM
store only. On a fresh boot the disk recall happens AFTER this decision (`:333-335`), so at the moment the
rewind is judged, the RAM store holds nothing but the load probe's two tiny states: the state the boot is
about to resume from, which sits 35 to 60 tokens below the rewind point, is invisible, and the pass keeps a
second, nearly identical state.

Measured in this window: the same five turns, two shapes.

| shape | turn 2's kept states | turn 2's write | tail a resume would recompute |
|---|---|---|---|
| one boot, turns 1 to 5 (build) | 1 (the endpoint at 100,092) | `0 new blocks and its own 115 MiB`, 120,800,640 B total, for 59 new tokens | 65 tokens |
| a boot per turn (agent shape; X1) | 2: the endpoint at 105,272 and the rewind at 105,245 | `105272 tokens on disk: 1 new blocks and its own 111 MiB (116 MiB this state, 1894 MiB of rows it shares)` and `105245 tokens on disk: 0 new blocks ... (111 MiB this state)`; the directory grew 238,564,436 B (227.5 MiB) for 70 new tokens | 77 tokens |

In the one-boot turn, the rewind was satisfied by turn 1's endpoint state at 100,033, which is 35 tokens below
the rewind point at 100,068, inside `min_gap`. In a fresh boot the same state exists on disk at the same
distance and is not consulted, so a second 113 MiB file is written whose token slice differs from the resumed
state by 35 tokens.

The store's own accounting after the five build turns: 10 state files totalling 1,187,097,432 B (1.11 GiB, the
two probe states plus each turn's endpoint and the seed's three other marks) and 410 blocks totalling
1,981,684,160 B (1.85 GiB), 3,168,781,600 B (2.95 GiB) in the identity directory. The blocks are 63 percent of
it and are paid once per token of conversation; the state files are the per-turn part.

Window 4's agent table shows the same two files on every append turn at 100k, written by boots that resumed
from disk: `100091 tokens on disk: 0 new blocks and its own 115 MiB` and `100071 tokens on disk: 0 new blocks
and its own 114 MiB` on turn 2, and the same pair 57 to 58 tokens apart on turns 3, 4, 6 and 7
(`work/KvTierW4/tables.md`, the agent section). The 20 tokens between its endpoint and its rewind are window 4's
short user message; the mechanism is the same.

### 2.3 The mitigation: keep the boundary only

There are two ways to stop paying for the second state, and only one of them is shippable.

**The no-code knob, as an experiment.** `active_rewind_at` is set only when the rewind's state fits the prompt
cache budget beside the endpoint (`core/prompt_cache.zig:324`), and `fittingRewind`
(`core/prompt_cache_fit.zig:22-34`) keeps it after that. A budget that fits the endpoint (1,911 MiB at 105k) and
not both (3,822 MiB) therefore refuses the rewind keep. M1a and M1b run the same turns and the same final request
at `--prompt-cache-gib 3.4`, and the boot's own line reports the budget it took (`a 3.4 GiB prompt cache`, and
the store reports `3481 MiB`); the writer's lines report the states kept, and M1b's request records the resume
depth and the restore time.

Measured at 3,481 MiB (the boot line's own figure): the seed's pass kept ONE state, the endpoint at 100,033,
and its report line reads `kept 1; ... trimmed 2`, so the budget cut the rewind and both shared system cuts
rather than only the rewind; every append turn then kept one state (`100092 tokens on disk: 0 new blocks and its
own 115 MiB`, `101793 ... 7 new blocks ... 145 MiB this state`, and so on), and the store held 7 states
(829,147,652 B) after the five turns, against 10 states (1,187,097,432 B) at the default budget. That is the
boundary-only write shape, and it is also exactly what the one-boot turns of section 2.2 already do.

This knob cannot ship as the mitigation: it caps the RAM prompt cache to one state, so at the production window
(262,144 tokens, 4.72 GiB a state) it would refuse every state, and it also drops the shared system cuts that
other conversations resume from. It is a way to MEASURE the boundary-only policy, not a setting to deploy.

**The code change, four lines.** The rewind keep exists so that an edit of the last message resumes just before
it. When the boot has just resumed from a state within `min_gap` below the rewind point, that state already
serves the purpose: it is 35 to 60 tokens shallower and it is already on disk. The one-boot turns in this window
prove the behaviour is correct and cheap (section 2.2: one state, 115 MiB, the same 65-token tail). The smallest
change is to let the disk recall participate in the deduplication: after
`rows.read.recall` (`core/prompt_cache.zig:334-335`) returns the entry, clear `active_rewind_at` when
`e.at <= active_rewind_at and active_rewind_at - e.at < s.rules.min_gap`, before the marks are built
(`:343-347`). Then a fresh-boot append keeps exactly the endpoint, which is what the one-boot turns already do.

**The mitigated append, measured.** M1b is a fresh boot on the boundary-only store, asked for the same turn 6:
it resumed at 105,202 (the same depth as X1), in 1.068 s TTFT and 0.358 s prefill, produced the same 320 ids, and
wrote ONE state, `105272 tokens on disk: 1 new blocks and its own 111 MiB (116 MiB this state)`. The store grew
by 121,954,256 B (116.3 MiB) against X1's 238,564,436 B (227.5 MiB): half the bytes for the same reply at the same
depth and the same restore time.

**The trade, measured.** A last-message edit loses the rewind resume: W1a (the edit with no turn-6 state on disk,
so it resumes from turn 5's endpoint at 105,202) pays 0.437 s of prefill and 1.149 s TTFT, against W1b (the same
edit resuming from turn 6's rewind at 105,245) at 0.267 s and 0.990 s. The rewind state's whole value on an edit
turn is those 0.17 s, and it costs 111 MiB on every append turn: 0.17 s once, against 116 MiB a turn.

### 2.4 What a real session needs

An agent session is one conversation whose turns each arrive in a fresh boot: the seed writes its blocks and
four or five states, every later append writes its states plus the blocks its new text needs. The measured
bytes, from this window (a boot per turn):

| shape | bytes an append turn writes | 100-turn session (seed + 99 appends) | turns to 60 GiB | turns a day to 200 GiB |
|---|---:|---:|---:|---:|
| default, two states (X1) | 238,564,436 (227.5 MiB) | 24.4 GiB | 259 | 889 |
| boundary only (M1b) | 121,954,256 (116.3 MiB) | 13.7 GiB | 506 | 1,739 |

The general figure, in terms of that formula: an append turn writes two state files of 111 to 116 MiB each
(110.28 MiB of fixed part, the partial block and 4 bytes a token) plus 18,880 B for every token the conversation
grows, which is one 4.83 MB block per 256 new tokens. X1's 227.5 MiB is exactly that for a turn adding 70 tokens
(two states and one block). A coding agent whose turn adds 2,000 tokens writes about 2 x 113 MiB + 37 MB = 263
MiB, and the two fixed state files are 86 percent of it.

The seed measured 2,594,142,332 B (2.42 GiB: 382 blocks plus six state files) at 100,040 tokens. Against the
box: `/home` held 110.6 GiB free before the window (937,291 MiB total, 776,383 used) and 104.7 GiB while the
stores were in place (782,438 used); the tier's cap is 60 GiB and its floor 20 GiB, so the cap binds well before
the floor, and the daily ledger binds only for a session that runs hundreds of turns a day.

## 3. Rewrite reuse

- A last-message edit (W1a, W1b): the prefix is untouched, so every state up to and including turn 5's endpoint
  (or turn 6's rewind state when the previous turn ran) matches `Rows.matches`
  (`core/rows_store.zig:286-292`), the pass resumes there, and the write reuses the prefix's blocks.
  Measured: W1b (the last message edited after X1 ran) resumed at 105,245, the rewind state the previous turn
  wrote, with a 34-token tail: TTFT 0.990 s and prefill 0.267 s, against X1's resume at 105,202 with a 77-token
  tail, TTFT 1.125 s and prefill 0.397 s, on the same prompt length (105,279) and with the same reply ids. So
  the rewind state buys 0.17 s on an edit turn. W1a (the same edit with no turn-6 state on disk) resumes at
  105,202 instead and pays 0.437 s of prefill (measured), which is the price of dropping the rewind state.
- A middle-message edit (X3): the divergence starts inside turn 3, so every state after turn 2's endpoint is
  refused and the span from turn 2's endpoint is recomputed. Measured: the probe chose 100,092, the pass
  recomputed 5,050 tokens in 2.668 s, and its write line reads
  `105135 tokens on disk: 19 new blocks and its own 113 MiB (201 MiB this state, 1889 MiB of rows it shares)`:
  the 1,889 MiB of blocks below the edit were reused untouched, and only the 19 blocks after it (91.8 MB, one
  for every 256 tokens of the recomputed span) were written. So a middle-message edit is a delta on disk and a
  span in compute, not a second copy of the conversation.
- A first-message (system) edit (W2): every token differs from position 0, so no state on the old prefix can
  match. Measured: the probe answered `none`, the turn paid 47.104 s of prefill (TTFT 47.108 s, the cold cost),
  and its write line reads `97969 tokens on disk: 382 new blocks and its own 113 MiB (1874 MiB this state, 1760
  MiB of rows it shares) in 3800 ms`, followed by `105248 ... 29 new blocks ...`: 411 new blocks, the whole row
  set, and the store went from 410 blocks to 821. This is by construction, not a defect: a block's name chains
  the digest of every block before it (`core/rows_chain.zig:61-79`), so a change at token 0 renames every block,
  and a state is keyed to its token prefix (`:82-89`). For a system rewrite the smallest change that would allow
  reuse is none: there is no common prefix.
- What an edit costs, in one line: an edit AFTER the last kept state's position resumes from that state and
  writes only the blocks the edited span needs (X3: 19 blocks for 5,050 tokens); an edit AT or before it pays
  the cold prefill and a fresh block set (W2).

## 4. What gates shipping, and what is an optimisation

Against `work/KvTierW4/SHIPPING.md`, which proposes
`--prompt-cache-disk /cache/kv --learn-gib 60 --learn-daily-gib 200 --learn-min-free-gib 20` beside the
unchanged `PARALLEL` and `CONTEXT`, with `KV_DTYPE=fp8` and the default writer:

- **A PREREQUISITE: equal-depth exactness, and it holds in this window.** The line's claim is that a resumed
  prompt is the same computation resumed, so a resumed reply must equal a cold one. Measured: at 2,098 tokens a
  boundary resume equals the cold reply (section 1.2), and at 105,279 tokens four different resume depths
  (tails 34, 77, 1,781 and 5,050 tokens) all produce the same 320-token reply as the cold no-tier boot, sha16
  `277412fd297b56aa`, against a 46.85 s cold prefill answered in 1.125 s at the boundary (section 1.3). The
  two strict equal-depth pairs (disk at 105,202 against RAM at 105,202, and disk at 100,092 against RAM at
  100,092) complete the attribution and both hold, so the store's state image and read path are exact and the
  exactness prerequisite is met on this base.
- **A PREREQUISITE, still open from window 4 and outside this window: the checkpoint.** The tier image refuses
  production's INT4-AutoRound checkpoint by name (`UnsupportedCheckpoint`), so the series must be built on a base
  that accepts it before the flag can go on the production serve. Every number here is on the NVFP4 checkpoint.
- **A PREREQUISITE, still open from window 4: the stream shape.** This base reserves a whole window per stream
  and refuses the KV page pool beside the store, so production's 8 slots at 262,144 cannot boot with the tier
  on; this window runs 1 slot at 262,144.
- **AN OPTIMISATION: the append write amplification.** It changes no reply. It bounds how long a session can run
  under `--learn-gib 60` and how much write endurance a day spends under `--learn-daily-gib 200`. Measured: a
  100-turn 100k agent session needs 24.4 GiB at the shipped shape (227.5 MiB a turn, 259 turns to the 60 GiB
  cap, 890 a day once the seed's 2.42 GiB is taken out of the 200 GiB ledger) or 13.7 GiB boundary-only
  (116.3 MiB a turn, 506 turns, 1,739 a day). SHIPPING's "about 850
  append turns" a day is the same division and the correction is 889.
- **AN OPTIMISATION: rewrite reuse.** Append-only agent traffic never edits a message, so the last-message path
  only matters for edit-heavy clients; a first-message rewrite cannot reuse anything by construction (section 3).

Two sentences of `SHIPPING.md` should be corrected from these measurements (the file itself is window 4's and is
not edited here): "each later append turn writes about 0.23 GiB" is 0.222 GiB at the agent shape on this
conversation, and `--learn-daily-gib 200` therefore allows about 889 appends, not 850; and the reason it is two
states rather than one is the RAM-only rewind deduplication (section 2.2), which is worth a line beside the
writer knob because it is the difference between 0.222 and 0.113 GiB a turn.

## 5. Reproducing this window

Payload is `work/KvTierW5/payload` (staged to `~/work/KvTierW5/payload` with `SHA256SUMS` verified both ways):
`run.sh` (cells), `w5lib.sh` (boot, store operations, evidence), `w5req.py` (one request plus the
`/v1/imprint/resume` probe, saving the reply's token ids), `w5conv.py` (the conversation, deterministic from
100,000 words and seed 2), `stls.sh` and `delat.sh` (the store's own file set, read from each state file's
trailer, and the eviction-shaped deletion used to build X2), `analyse5.py` (the tables).

    ssh spark6 'cd ~/work/KvTierW5 && flock -o -w 43200 ~/work/gpu.lock bash payload/run.sh all'

runs the smoke (3 boots), the build (5 turns in one boot), the exactness cells (10 boots) and the amplification
and rewrite cells (4 boots), restoring production from the EXIT trap. `bash payload/run.sh core` runs everything
after the smoke, `bash payload/run.sh trunc` the truncated-state cell (`trunc.sh` cuts the deepest state file in
half), and `bash payload/run.sh clean` removes the store roots.

Two void passes are recorded in section 6 so the ledger of what ran is complete: a missing `msgs/` directory
in the first smoke, and a wrong evidence path in the smoke's gate in the second. Neither touched a store.

## 6. The two void passes, and unrun cells

Two passes before the core chain are recorded rather than hidden:

- **Run 0** (03:59Z): the smoke's conversation builder did not create its `msgs/` directory, so its three
  requests failed on a missing prompt file and the chain stopped at the smoke gate. The builder now creates it.
- **Run 1** (04:03Z): the smoke itself ran and produced the cell in section 1.2, but the gate's equality check
  read `out/s2/t2.json` where the stage writes `out/smoke/s2/t2.json`, so the gate failed on a path and the
  chain stopped. The cell's evidence is kept: it is the 2,098-token exactness row.
- **Run 2** (04:10Z, `run.sh core`) is the build, the exactness cells and the amplification and rewrite cells.
- **Run 3** (04:31Z, `run.sh trunc`) is the damaged-state-file cell (X4).

No planned cell is unrun. The cells that shared a store root removed it as they finished, and the store roots
were removed at the end of the window, so nothing of this lane's disk state remains on spark6. Disk discipline:
`/home` had 113,224 MiB free before the window and 113,225 MiB after the cleanup; the 3.0 GiB of store roots and
the 9.6 MB payload were removed, no `.part` file remained, and the lane's `~/INVENTORY.md` entry was deleted.

Which payload ran, by sha256: w5lib.sh `e56ac71b...`, w5conv.py `67c50062...`, w5req.py `cd1f7a31...`, stls.sh
`506d338c...`, delat.sh `b33c68a4...`, analyse5.py `9f3dd169...`, trunc.sh `5aa59832...`; run.sh was `060afbaf...`
for the build, exact and amplification cells and `18798eb2...` for the truncated-state cell (the trunc stage is
the only change). `payload/SHA256SUMS` holds the final set.
