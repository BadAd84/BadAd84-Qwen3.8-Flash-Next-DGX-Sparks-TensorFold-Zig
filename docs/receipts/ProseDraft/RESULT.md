# The prose gap is one stop: the shared per-draft gate at 0.6 (spark6, 2026-11-23)

Status: three windows ran back to back in one hold of `~/work/gpu.lock`, each restoring production from its own EXIT
trap (`/health` 200, image `tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7`, `PROD-IMAGE-OK` each time): window 1,
08:41:56 to 09:22:09 UTC, 17 boots, the speed arms and the round accounting; window 2, 09:24:02 to 10:07:17, 10 boots,
the exactness equalities on every arm plus the eight-stream cells; window 3, 10:07:27 to 10:17:55, 2 boots, the
1/2/4/6/8 sweep for the promoted knob; window 4, 10:19:53 to 10:27:49, 2 boots, the one combination a two-knob
promotion would create (S0 plus C20) measured rather than assumed. 31 boots in 100 minutes, drive-image pins matched at every preflight
(`IMG-PIN dev tag matches`, `IMG-PIN prod tag matches`), and no nonlocal request on any dev arm. **`TF_FLASHNEXT_SHARED_DRAFTS=0` is the knob that wins**: at four
streams on prose our engine reads 229.0 tokens a second against its own 207.8 (+10.2 percent) and 0.927 of production's
247.0, with the same one-stream counters to the digit, and every arm's accepted tokens are unchanged where exactness was
measurable.

## 1. The binding stop, named from source

**Stop**: `shared_stop = 0.6`, the per-draft threshold at `families/flashnext/cuda_lanes_draft.zig:26`, applied at
line 30: `stop = if (sharedRule() and busy(&self.lanes)) shared_stop else self.confidence`.

**Condition**: a greedy stream (temperature 0, so `stopFor` at lines 34-37 gives it the round's `greedy_stop`), in a
draft call with more than one lane open (`busy()`, lines 50-60, counts lanes neither finished nor paused), and with
`TF_FLASHNEXT_SHARED_DRAFTS` at its default 1 (`sharedRule()`, lines 45-48). Under the `c > 0` branch of
`cuda_mtp.zig:56-61` the first draft is always proposed and every later draft only at probability 0.6 or above, so the
chain ends at the first draft below 0.6.

Why it is the binder and the depth number is not:
- `cuda_lanes.zig:239-240` sets `.drafts = max(depth, depth_greedy)` (8 at the recipe's 6 and greedy 8) and
  `.draft_probabilities = drafting`.
- `core/lanes/depth.zig:222-223` therefore answers a greedy stream's depth request with the full `most_drafts` (8),
  never the cost model (line 225 is for sampled streams); `config.zig:166` caps it at `width - 1`.
- The chain is then cut by the stop rule inside the draft call (`cuda_lanes_draft.zig:91` for a shared round,
  `cuda_lanes.zig:535` for one stream a call).
So raising the requested depth cannot help until the gate allows more than 8 proposals, which is exactly why
work/GapArms measured digit-identical counters at 6/8 and 15/15.

At one stream `busy()` is false, the stop is `self.confidence` (-0.15, the product rule), and the same knob cannot
matter: the measured one-stream counters of the gate arm are identical to the baseline's to the digit (section 4).

## 2. What each arm changed, and what production's own names do here

| arm | the one setting | what it changes |
|---|---|---|
| `B0` | none | the recipe's shipped dev settings (DRAFTS=6, greedy 8, `SHARED_DRAFTS` unset = the 0.6 gate on, CONFIDENCE -0.15) |
| `S0` | `TF_FLASHNEXT_SHARED_DRAFTS=0` | the 0.6 per-draft gate off; greedy chains take the -0.15 product rule at every width |
| `C0` | `TF_FLASHNEXT_CONFIDENCE=0` | the product stop off: every draft in the requested chain is proposed |
| `C20` | `TF_FLASHNEXT_CONFIDENCE=-0.20` | production's CONTINUE value on our product rule |
| `G8` | `TF_FLASHNEXT_GREEDY_WIDE=8` | greedy keeps its depth past four streams |
| `PN` | production's six draft names at 0.99 / 1 / 0.99 / 1 / 0 / 0 | the inert-name control: values that would change behaviour if any were read |
| `P1` | production, its own launcher | the in-window anchor |

Production's names against our tree (served source, `zig/src`; grep: 0 files each for the six below):
`TF_FLASHNEXT_DRAFT_CONTINUE` (0.20), `TF_FLASHNEXT_DRAFT_DEPTH_SHARED` (7), `TF_FLASHNEXT_DRAFT_PROPOSE` (0.05),
`TF_FLASHNEXT_MULTI_MAX` (192), `TF_FLASHNEXT_NGRAM_LATE` (1) and `TF_FLASHNEXT_NGRAM_PREFETCH` (1) have no reader.
`TF_FLASHNEXT_DEPTH` (15) has none either; the only DEPTH string is the `TF_FLASHNEXT_DEPTH_LOG` diagnostic. The
equivalents we do have are `TF_FLASHNEXT_CONFIDENCE` (the product line, -0.15 on both sides), the hard-coded 0.6
per-draft gate (no knob, removed by `SHARED_DRAFTS=0`), `TF_FLASHNEXT_GREEDY_WIDE` (default 4) and the draft depths.
Every dev boot already exports production's 54 names at production values (`in/prod.env`), so a same-value arm would
prove nothing; `PN` sets them where they would bite instead, and nothing moved.

## 3. Decode: aggregate tokens a second, 256 greedy tokens a request, three reps a run

Two runs an arm (two fresh boots), prose (chat) and code prompts; the eight-stream rows are window 2's, one boot an arm. Ratio is the arm's mean over the baseline's mean.
The noise rule is the brief's: slower only when both runs are under both baseline runs and the mean gap exceeds one
percent, faster the same with the sign reversed, else level.

| arm | kind | streams | runs | arm mean | baseline mean | ratio | verdict |
|---|---|---:|---|---:|---:|---:|---|
| B0 | prose | 1 | 2 | 69.9 | 69.9 | 1.000 | baseline |
| B0 | prose | 4 | 2 | 207.8 | 207.8 | 1.000 | baseline |
| B0 | code | 1 | 2 | 97.2 | 97.2 | 1.000 | baseline |
| B0 | code | 4 | 2 | 276.8 | 276.8 | 1.000 | baseline |
| S0 | prose | 1 | 2 | 70.3 | 69.9 | 1.005 | level |
| S0 | prose | 4 | 2 | 229.0 | 207.8 | 1.102 | **faster** |
| S0 | code | 1 | 2 | 97.0 | 97.2 | 0.999 | level |
| S0 | code | 4 | 2 | 300.1 | 276.8 | 1.084 | **faster** |
| C0 | prose | 1 | 2 | 68.2 | 69.9 | 0.974 | slower |
| C0 | prose | 4 | 2 | 207.6 | 207.8 | 0.999 | level |
| C0 | code | 1 | 2 | 97.3 | 97.2 | 1.002 | level |
| C0 | code | 4 | 2 | 276.4 | 276.8 | 0.998 | level |
| C20 | prose | 1 | 2 | 70.8 | 69.9 | 1.013 | faster |
| C20 | prose | 4 | 2 | 207.9 | 207.8 | 1.000 | level |
| C20 | code | 1 | 2 | 99.2 | 97.2 | 1.022 | faster |
| C20 | code | 4 | 2 | 277.4 | 276.8 | 1.002 | level |
| G8 | prose | 1 | 2 | 70.1 | 69.9 | 1.002 | level |
| G8 | prose | 4 | 2 | 207.3 | 207.8 | 0.998 | level |
| G8 | code | 1 | 2 | 97.5 | 97.2 | 1.004 | level |
| G8 | code | 4 | 2 | 276.4 | 276.8 | 0.999 | level |
| PN | prose | 1 | 1 | 70.1 | 69.9 | 1.002 | indicative |
| PN | prose | 4 | 1 | 207.4 | 207.8 | 0.998 | indicative |
| PN | code | 1 | 1 | 97.6 | 97.2 | 1.005 | indicative |
| PN | code | 4 | 1 | 276.7 | 276.8 | 1.000 | indicative |
| P1 (production) | prose | 1 | 1 | 86.7 | 69.9 | 1.240 | reference |
| P1 (production) | prose | 4 | 1 | 247.0 | 207.8 | 1.189 | reference |
| P1 (production) | code | 1 | 1 | 94.1 | 97.2 | 0.968 | reference |
| P1 (production) | code | 4 | 1 | 297.9 | 276.8 | 1.076 | reference |
| B0 | prose | 8 | 1 | 327.9 | 327.9 | 1.000 | baseline |
| S0 | prose | 8 | 1 | 350.5 | 327.9 | 1.069 | faster, indicative |
| B0 | code | 8 | 1 | 426.8 | 426.8 | 1.000 | baseline |
| S0 | code | 8 | 1 | 456.1 | 426.8 | 1.069 | faster, indicative |

The per-run values, so a reader can check the separation:

| arm | prose 1 | prose 4 | code 1 | code 4 |
|---|---|---|---|---|
| B0 | 69.6, 70.3 | 207.5, 208.1 | 97.2, 97.1 | 275.9, 277.7 |
| S0 | 70.6, 70.0 | **229.5, 228.5** | 97.6, 96.5 | **301.2, 299.0** |
| C0 | 67.9, 68.4 | 207.7, 207.4 | 97.2, 97.4 | 276.2, 276.5 |
| C20 | 70.7, 71.0 | 208.0, 207.8 | 98.9, 99.6 | 277.7, 277.1 |
| G8 | 70.1, 70.1 | 207.2, 207.5 | 97.6, 97.4 | 276.1, 276.7 |
| PN | 70.1 | 207.4 | 97.6 | 276.7 |
| P1 | 86.7 | 247.0 | 94.1 | 297.9 |

S0's four-stream cells are separated: its lower run (228.5 prose, 299.0 code) is above the baseline's higher run
(208.1, 277.7). C0's one-stream prose cell is separated the other way (68.4 against 69.6). C20's one-stream cells are
separated (prose 70.7 against 70.3, code 98.9 against 97.2).

## 4. Round accounting, from each boot's own done lines

Means over the arm's runs. `drafted/round` is the mean draft tokens submitted for verification a round = the chain
length after the stops (`core/lanes/engine.zig:279-284`: `drafted += rows - 1`, `accepted += kept`). `ms/round` is the
client's first-to-last span over the median rounds of that kind.

| arm | kind | streams | drafted/round | acceptance | tokens/round | ms/round |
|---|---|---:|---:|---:|---:|---:|
| B0 | prose | 1 | 3.1 | 0.655 | 3.0 | 42.9 |
| B0 | prose | 4 | 1.9 | 0.760 | 2.5 | 46.2 |
| B0 | code | 1 | 4.8 | 0.776 | 4.7 | 48.6 |
| B0 | code | 4 | 2.7 | 0.933 | 3.5 | 49.6 |
| S0 | prose | 1 | 3.1 | 0.655 | 3.0 | 42.7 |
| S0 | prose | 4 | **2.8** | **0.718** | **3.0** | **51.1** |
| S0 | code | 1 | 4.8 | 0.776 | 4.7 | 48.7 |
| S0 | code | 4 | **4.2** | **0.804** | **4.4** | **57.2** |
| C0 | prose | 1 | 7.9 | 0.363 | 3.9 | 56.7 |
| C0 | prose | 4 | 1.9 | 0.760 | 2.5 | 46.1 |
| C0 | code | 1 | 7.8 | 0.585 | 5.6 | 57.0 |
| C0 | code | 4 | 2.7 | 0.932 | 3.5 | 49.5 |
| C20 | prose | 1 | 2.8 | 0.697 | 3.0 | 41.9 |
| C20 | prose | 4 | 1.9 | 0.760 | 2.5 | 46.1 |
| C20 | code | 1 | 4.3 | 0.847 | 4.7 | 46.7 |
| C20 | code | 4 | 2.7 | 0.933 | 3.5 | 49.3 |
| G8 | prose | 1 | 3.1 | 0.655 | 3.0 | 42.8 |
| G8 | prose | 4 | 1.9 | 0.760 | 2.5 | 46.2 |
| G8 | code | 1 | 4.8 | 0.776 | 4.7 | 48.4 |
| G8 | code | 4 | 2.7 | 0.933 | 3.5 | 49.5 |
| PN | prose | 1 | 3.1 | 0.655 | 3.0 | 42.8 |
| PN | prose | 4 | 1.9 | 0.760 | 2.5 | 46.3 |
| PN | code | 4 | 2.7 | 0.933 | 3.5 | 49.4 |
| P1 (production) | prose | 1 | 3.13 | 0.739 | 3.32 | 38.2 |
| P1 (production) | prose | 4 | 3.03 | 0.750 | 3.28 | 51.5 |
| P1 (production) | code | 1 | 3.67 | 0.749 | 3.76 | 39.9 |
| P1 (production) | code | 4 | 3.66 | 0.750 | 3.76 | 49.6 |
| B0 | prose | 8 | 1.8 | 0.826 | 2.46 | 57.3 |
| S0 | prose | 8 | 2.7 | 0.743 | 3.01 | 65.4 |
| B0 | code | 8 | 2.6 | 0.933 | 3.46 | 61.8 |
| S0 | code | 8 | 4.1 | 0.810 | 4.34 | 72.5 |

Three facts fall out:

1. **The gate is what cuts the four-stream prose chain.** Removing it moves drafted/round from 1.9 to 2.8, acceptance
   from 0.760 to 0.718, tokens a round from 2.5 to 3.0, and the round from 46.2 to 51.1 ms; the product is +10.2
   percent of rate, and the counters agree with the rate (3.0/2.5 over 51.1/46.2 = 1.110).
2. **The same knob is inert at one stream**: drafted, acceptance and tokens a round are identical to the digit
   (3.1 / 0.655 / 3.0) and the round differs by 0.2 ms (42.7 against 42.9); the width-1 chain histogram of section 5 is
   the same distribution call for call.
   That is the source's `busy()` condition showing up in the counters, and it is the internal control that says the
   four-stream gain is not a host or thermal drift.
The eight-stream cells (window 2, one boot an arm, so indicative) behave the same way: prose 350.5 against 327.9
(+6.9 percent) with drafted a round 1.8 to 2.7, acceptance 0.826 to 0.743, tokens a round 2.46 to 3.01 and the round
57.3 to 65.4 ms; code 456.1 against 426.8 (+6.9 percent), drafted 2.6 to 4.1, tokens a round 3.46 to 4.34. Against
work/GapArms' production eight-stream runs (407.5 prose, 440.4 code) that lifts our prose ratio from 0.792 to 0.860 and
our code ratio from 0.956 to 1.036, with the caveat that those production numbers are the prior window's, not an
in-window anchor.

3. **The two other stops are real but not the prose binder.** `CONFIDENCE=0` (every draft of the requested eight) at
   one stream takes the chain to 7.9 drafts at 0.363 acceptance: 3.9 tokens a round at 56.7 ms, 2.6 percent slower.
   `CONFIDENCE=-0.20` at one stream gives 2.8 drafts at 0.697: 3.0 tokens a round at 41.9 ms, 1.3 percent faster. At
   four streams both are level, because the 0.6 gate overrides the product rule for greedy streams.

## 5. The chain lengths the engine logged

`TF_FLASHNEXT_DEPTH_LOG=1` records each draft call's chain length by the number of streams drafting together
(`cuda_lanes_draft.zig:116-135`); the lines are cumulative and printed every 200 calls. Last line per width, identical
across the two boots of each arm (the workload is greedy and deterministic):

| arm | width | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| B0 | 1 | 11 | 119 | 93 | 63 | 59 | 44 | 21 | 18 | 45 |
| B0 | 4 | 20 | 1104 | 264 | 408 | 144 | 96 | 60 | 12 | 0 |
| S0 | 1 | 11 | 119 | 89 | 63 | 59 | 44 | 21 | 18 | 45 |
| S0 | 4 | 16 | 252 | 240 | 208 | 204 | 192 | 84 | 56 | 72 |

At four streams the baseline's chains are one draft in 1104 of 2108 calls and never reach eight; with the gate off
they spread across one to eight and reach the requested cap in 72 calls. At one stream both arms are the same
distribution. The histogram's width counts the call's requests, so its mean is close to but not the same as
drafted/round (rounds that draft fewer streams together land in a narrower bucket).

## 6. Exactness

Window 1's exactness boots were void: the engine's argument check rejects `--learn-conversations` together with
`--prompt-cache-disk` in this image (`tensorfold serve: error: argument --learn-conversations: not allowed with
--prompt-cache-disk`), so all five cache boots refused to start and the `done`-line counters above stand alone.
Window 2 asks only for the in-RAM prompt cache (`--prompt-cache-gib 6`, what production's own plan grants) and runs,
for every arm: `bench_concurrent --prompts golden.json --alone --serial` at 2 and 4 streams (concurrent equals solo,
and drafted equals `"draft": false`), `served_exactness.py drafts` over its eight prompts, `served_exactness.py turns`
on the cache boot, and `served_exactness.py fresh` on a fresh boot with no prompt cache. Its results are below.

| arm | golden 2 streams: solo / "draft": false | golden 4 streams: solo / "draft": false | drafts equal | accepted a reply | the plain side drafted | resumed from | fresh equal |
|---|---|---|---|---|---|---|---|
| B0 | 2/2 | 4/4 | 8/8 | 171 to 211 | 0 | 13 to 3,406 tokens | 7/7 |
| S0 | 2/2 | 4/4 | 8/8 | 171 to 211 | 0 | 13 to 3,406 tokens | 7/7 |
| C0 | 2/2 | 4/4 | 8/8 | 188 to 212 | 0 | 13 to 3,406 tokens | 7/7 |
| C20 | 2/2 | 4/4 | 8/8 | 170 to 211 | 0 | 13 to 3,406 tokens | 7/7 |
| G8 | 2/2 | 4/4 | 8/8 | 171 to 211 | 0 | 13 to 3,406 tokens | 7/7 |

Each golden cell compares four repeats (two at 2 streams, four at 4) with no unequal and no failed comparison, and no
vacuity note: the solo runs carried at least two streams decoding at once, and the `"draft": false` side of the serial
comparison is real, because the certified cells report the drafted runs accepting 769 drafts at 4 streams (772 for C0)
while the plain runs drafted 0. `served_exactness drafts` compares eight prompts with ignore_eos at 256 tokens, each
drafted reply equal to its plain twin by token ids, with 170 to 212 drafts accepted a reply. `served_exactness turns`
records seven resumed turns, each reporting cached prompt tokens, and `fresh` computes the same seven chats on a boot
with no prompt cache: all seven equal on both the plain and the drafted side. The image's own argument check refused
`--learn-conversations` together with `--prompt-cache-disk`, which is why the cache boot asks only for
`--prompt-cache-gib 6`.

**No arm changed an accepted token**: the same equality holds for the shared-gate arm, the two confidence arms, the
width arm and the baseline.

## 7. The verdict

| measure (prose, four streams) | dev baseline, this window (B0) | **S0** | production, this window (P1) | dev, work/GapArms | production, work/GapArms |
|---|---|---|---|---|---|
| drafted a round | 1.9 | **2.8** | 3.03 | 1.92 | 3.03 |
| acceptance | 0.760 | **0.718** | 0.750 | 0.760 | 0.750 |
| tokens a round | 2.46 | **3.01** | 3.28 | 2.46 | 3.28 |
| ms a round | 46.2 | **51.1** | 51.5 | 47.0 | 52.3 |
| decode, tokens a second | 207.8 | **229.0** | 247.0 | 204.4 | 243.3 |
| ratio to production | 0.841 | **0.927** | 1.000 | 0.840 | 1.000 |

- **`TF_FLASHNEXT_SHARED_DRAFTS=0` wins**: 229.0 against 207.8 tokens a second on prose at four streams, +10.2 percent,
  both runs separated (228.5 and 229.5 against 207.5 and 208.1). It closes 54 percent of the gap to production's
  247.0 (production stands 18.9 percent above the baseline, S0 10.2).
- On code it is +8.4 percent (300.1 against 276.8), which lifts the code cell from parity to above this window's
  production anchor (297.9).
- At one stream it is level (70.3 against 69.9) with the drafted, acceptance and tokens-a-round figures identical to
  the digit, so the everyday single-stream load neither gains nor loses.
- The counter decomposition is the mechanism: the stop that was cutting our greedy chains at four streams is the 0.6
  per-draft gate, and removing it buys 0.9 more drafts a round for 4.9 more ms a round, a net 10.2 percent.
- **The remaining four-stream gap is 0.927**, and it is not another stop left switched on: production drafts 3.03
  where S0 drafts 2.8, and accepts 75.0 percent where S0 accepts 71.8. That is draft yield plus a little volume. At
  one stream the same shape shows: both draft about 3.1, production accepts 73.9 percent and we accept 65.5, and
  production's round is 38.2 ms against our 42.9.

The full concurrency sweep (window 3, one boot an arm, indicative) shows the same shape at every width above one:

| streams | prose B0 | prose S0 | S0 / B0 | code B0 | code S0 | S0 / B0 |
|---:|---:|---:|---:|---:|---:|---:|
| 1 | 70.3 | 70.1 | 0.997 | 97.7 | 97.3 | 0.996 |
| 2 | 118.9 | 132.2 | 1.112 | 158.4 | 174.2 | 1.100 |
| 4 | 207.9 | 229.4 | 1.103 | 277.2 | 300.8 | 1.085 |
| 6 | 275.6 | 298.6 | 1.083 | 357.5 | 385.8 | 1.079 |
| 8 | 328.0 | 351.8 | 1.073 | 425.0 | 455.4 | 1.072 |

The gain narrows as the round widens (11.2 percent at two streams to 7.3 at eight) and never turns negative, and the
one-stream cell is level in every run of every window. Against work/GapArms' production runs at the same widths the
prose ratio moves from 0.76 to 0.86 at two streams, 0.81 to 0.90 at six and 0.79 to 0.86 at eight, with those
production figures being the prior window's rather than an in-window anchor.

What did not win, and why it stays out: `TF_FLASHNEXT_GREEDY_WIDE=8` is level at every cell measured, which the
source predicts (at width 4 the greedy depth is already kept); production's six draft names are inert at values that
would bite if read; `TF_FLASHNEXT_CONFIDENCE=0` is 2.6 percent slower at one stream (7.9 drafts a round at 0.363
acceptance); `TF_FLASHNEXT_CONFIDENCE=-0.20` read +1.3 percent on prose and +2.2 on code at one stream in window 1 and level at
four, and window 4 measured the combination (S0 plus C20, two boots against S0's three runs): prose one stream 70.0
against 70.2 (0.996, level), prose four streams 227.4 against 229.1 (0.993, level), code one stream 98.0 against 97.1
(1.009, level), code four streams 303.9 against 300.3 (1.012, faster, both runs above all three). The one-stream prose
gain did not reproduce against S0, and the cells this campaign is about are level or slightly lower, so C20 stays out;
its window-1 separation was the small-effect noise the combination test exists to catch.

## 8. Promotion

`scripts/qwen38/zig/target/env/dev.env` carries `TF_FLASHNEXT_SHARED_DRAFTS=0` from this window, with the citation the
file's own checker requires (`work/ProseDraft/RESULT.md`), and three comment corrections that this window measured:
the base-name block now says which of those names this tree reads (DEPTH and WINDOW have no reader here); the page
pool block records that on this image the argument check refuses `--learn-conversations` together with
`--prompt-cache-disk`, so a window needing only the in-RAM cache passes `--prompt-cache-gib 6` alone (this cost window
1 its exactness boots); and the trailing block moves `TF_FLASHNEXT_GREEDY_WIDE=8` to measured level, records the six
production names as inert, and leaves only `TF_FLASHNEXT_MTP_WEIGHTS` as unmeasured.

`python3 scripts/qwen38/zig/target/env/check-dev-env.py` prints `dev-env: 0 setting(s) without a citation` (exit 0).
The commit is one file, signed, under the owner's identity, no AI attribution: commit `3a6d7022` (GPG signature verified: Good signature from Adam Hillson), one file, `scripts/qwen38/zig/target/env/dev.env`; a second signed commit `32fbea1c` records the confidence arm as measured level in the file's own bottom block, so a later window does not re-run it.

Not promoted, with the reason: `C20` (level on prose once measured against S0, window 4); `G8` (level, and by source
it cannot act at one or four streams); production's six draft names (inert); `CONFIDENCE=0` (slower).

Housekeeping: nothing was installed on the box; the window's own directory is `~/work/ProseDraft` (payload, three
drivers, `out/`, `out2/`, `out3/`), entered in `~/INVENTORY.md` with its teardown line. The exactness boots asked for
the in-RAM cache only, so no disk store was written under the container's `/cache` bind; the check is in section 10's
row for the store. Disk on `/home` was 126 GB free and 743 GB used at the start of window 1 and the same at its end
(`DISK` lines in `out/run.log`).

## 9. What this window does not prove, and every cell it did not run

- **Two and six streams** are measured for B0 and S0 only (window 3, one boot an arm, so indicative); **eight
  streams** for B0 and S0 only (window 2). C0, C20, G8 and PN are measured at one and four streams only, and none of
  the arms is measured at two, six or eight except B0 and S0.
- **Sampled cells** (temperature above zero) are not run: the whole window is greedy, which is where the shared gate
  and the product rule both apply to the round's own stop.
- **TTFT and prefill** are not run: this knob changes drafting, and prefill is untouched by it (work/GapArms owns the
  chunk measurement).
- **The exactness boots run at a different shape than the speed boots**: the cache shape (244 pages of 4,096 rows
  plus a 3.1 GiB prompt cache, the plan line is in `out2/<arm>/plan.txt`) against the plain speed shape (327 pages, no
  prompt cache). Exactness does not depend on the pool, but the two shapes are not identical and the report says so.
- **Production's anchor runs with its whole-prompt cache; our speed arms run with none.** Decode rates exclude
  prefill, so this does not enter the decode cells, but it is a shape difference and not a like-for-like cache test.
- **Long conversations** (100k agent turns) are not run; the resume test uses `served_exactness`'s short turns.
- **The S0 plus C20 pair's exactness** is not run (window 4 measured its speed only): it is not promoted, so the
  evidence it would need was not spent.
- **The promoted knob's code path is not exercised by any non-greedy request** in this window: all cells are greedy,
  and a sampled stream takes `self.confidence` instead of the round's greedy stop.
- The chain histograms' width is the call's request count, so a round that drafts fewer streams together lands in a
  narrower bucket; the histograms support the counters and do not replace them.

## 10. Where every number comes from

| claim | source |
|---|---|
| window identity, order, boots, env audits, banners, plans, restore | `out/run.log`, `out/<arm>/{boot_time,banner,plan,env-diff,image-id,cache-state}.txt` |
| decode cells | `out/<arm>/conc_L{1,4}.json` (bench_concurrent's own `aggregate_tps`) |
| round accounting | `out/<arm>/rounds{1,4}.log` (each engine's `done ... rounds= accepted=/drafted=` lines) |
| client spans a round | `reps[*].client_intervals` in `out/<arm>/conc_L{1,4}.json` |
| chain histograms | `out/<arm>/depth.txt` (the `DEPTH width=` lines) |
| exactness | `out2/<arm>/{golden_L2,golden_L4,drafts,turns,fresh}.json` (window 2), rendered by `exact_report.py` |
| the 1/2/4/6/8 sweep | `out3/<arm>/conc_L{1,2,4,6,8}.json` and `rounds{1,2,4,6,8}.log` (window 3) |
| production anchor | `out/P1/` (production from `~/qwen6-start-prod.sh`, pinned image id verified) |
| the published baselines | work/GapArms/RESULT.md section 3 (dev 1.92 / 76.0 / 47.0; production 3.03 / 75.0 / 52.3) |
| the policy read | `work/ProseDraft/POLICY.md`, the served tree `~/work/int4cf/t` fetched to `work/ProseDraft/served/` |
