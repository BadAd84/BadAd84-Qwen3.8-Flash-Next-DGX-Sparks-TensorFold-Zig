# Parity-gap window: results

Status: both screens (C=1 and C=8, six arms) are complete; the first window's confirm pass (A2 and A4 at
C=2, C=4, C=6) and its restore follow, and this file is rewritten with them when the driver logs
`WINDOW-DONE`. Numbers come from the window's own artefacts
(`work/parity2/out`, copied to `work/ParityGap/partial/` for the C=1 pass) through `driver/score_arms.py`
and `driver/hash_cmp.py`; the driver is `driver/window2.sh`, the arms `driver/boot_env2.sh`.

## What ran

Six arms, one fresh boot a cell, on spark6 under one hold of `~/work/gpu.lock` (the driver takes it and its
EXIT trap restores production). Screen at C=1 and C=8, orders `c1: P A1 A3 D A2 A4`, `c8: D A2 A4 P A1 A3`
so P and D bracket the arms at each level; then the promotion rule (an arm outside 0.98-1.02 against its
family control in either prompt kind at either screen level) drives a confirm pass at C=2, C=4, C=6 with P
and D re-booted beside it.

| arm | family | lever |
|---|---|---|
| P | production | none (control) |
| D | dev | none (control) |
| A1 | dev | `TENSORFOLD_COPY_MISS=keep COPY_RAMP=jump COPY_SHARED=1 COPY_RESYNC=1 COPY_RESYNC_PROMPT_ONLY=1` (production's copy policy under the dev engine's own names) |
| A2 | production | `TF_FLASHNEXT_PROMPT_MM=0` (the captured prompt-matmul path off; the engine's own A/B switch) |
| A3 | production | `TF_FLASHNEXT_GRAPH_FAIL=1` (every graph instantiate fails; rounds run eagerly) |
| A4 | dev | `LEARN=0` (the persistent KV tier and its 6 GiB prompt-cache ask dropped) |

Every arm's lever is proved from its own boot, not asserted: `ARMCHECK <arm> c<C> OK` in the run log for
each cell, and the plan lines quote the effect - A1 `copy policy: miss keep, ramp jump, shared rounds ramp
prompt copies, resync prompt copies`; A2 `matmul K slices split with _reduce`; A3 `graph warm-up: 0 graphs
on 8 pooled sequences` against P's `384`; A4 argv without `--prompt-cache-gib` and no `conversation states
on disk` line.

## C=1 screen (complete)

| arm | prose | vs P | vs D | code | vs P | vs D | tok/round p | c | rounds/s p | c | ms/round p | c | cold1k | cold8k | cold32k | warm |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| P | 73.5 | 1.000 | 1.076 | 116.1 | 1.000 | 1.006 | 2.48 | 5.55 | 27.6 | 21.3 | 36.2 | 46.9 | 0.412 | 2.633 | 10.487 | 1.210 |
| D | 68.3 | 0.929 | 1.000 | 115.4 | 0.994 | 1.000 | 2.58 | 5.89 | 24.9 | 19.4 | 40.2 | 51.5 | 0.489 | 2.929 | 11.795 | 1.195 |
| A1 | 66.4 | 0.903 | 0.972 | 115.5 | 0.995 | 1.001 | 2.58 | 5.89 | 24.1 | 19.4 | 41.5 | 51.6 | 0.487 | 2.941 | 11.756 | 1.167 |
| A2 | 73.5 | 1.000 | 1.076 | 116.2 | 1.001 | 1.007 | 2.48 | 5.55 | 27.6 | 21.5 | 36.2 | 46.6 | 0.439 | 2.951 | 11.918 | 1.247 |
| A3 | 73.3 | 0.997 | 1.073 | 115.4 | 0.994 | 1.000 | 2.48 | 5.55 | 27.5 | 21.3 | 36.4 | 46.9 | 0.398 | 2.580 | 10.521 | 1.103 |
| A4 | pending | | | | | | | | | | | | | | | |

D against P at C=1: decode 0.929 prose, 0.994 code; cold TTFT 1.112 at 8k and 1.125 at 32k. That
reproduces the recorded window's direction and size (ParityAB: 0.914 prose, 0.984 code at C=1), with P
itself reproducing the recorded cell (73.5 against 71.8 prose, 116.1 against 115.4 code, 2.633 against
2.588 s at 8k, 10.487 against 10.490 s at 32k).

## A2: the captured prompt-matmul path is the cold-prefill gap (supported)

P with `TF_FLASHNEXT_PROMPT_MM=0` keeps its captured kernel set for everything else and runs Python's two
launches for the prompt matmuls instead (`split with _reduce`, boot line). Replies are byte-identical to P
(6/6 rows) and decode is identical to P (73.5/116.2 against 73.5/116.1, same tokens a round, same
ms a round), so the arm is a clean isolation of the prompt path. Its cold TTFT against P: **1.121 at 8k,
1.136 at 32k, 1.125/1.136 thinking on, and 1.066 at the 1k control cell**. D's own gap against P at the
same level is 1.112 at 8k and 1.125 at 32k.

The delta is in the prompt pass itself, not in admission or the transport: the harness's own split of
each sample (`ttft.out`, `summary ... prefill`) reads P 2.613 s at 8k and 10.459 s at 32k, A2 2.930 and
11.889, D 2.925 and 11.767. So A2's prefill is +12.1 and +13.7 percent over P, and D's is +11.9 and +12.5
percent: D's own prompt path is within 1 percent of P's two-launch fallback, and the captured form is the
whole of the prefill gap.

So the whole cold-prefill deficit is reproduced on production's own engine by turning off the captured
prompt matmul form, within one percentage point of the gap D shows, with identical replies and no decode
change. The mechanism: `_b16mm_ks`/`_fp4mm_ks` run all K slices of a tile in one program and add the slice
totals in slice order, with no `[SK, M, N]` fp32 buffer written and read back
(`production:zig/src/families/flashnext/cuda_prompt.zig:1-8`; the kernels are MiaAI's
`qwen4_exp/cuda/prompt_mm.py`, packed into the sm121 set by `tools/zig/aot_pack.py`, both arriving in
`3289c9eb recipe-patched`). D's tree contains no such form at all (`grep b16mm|fp4mm` over
`work/ParityGap/DevTree/zig` finds nothing) and it cannot load a captured set at fp8 KV
(`cuda_lanes_load.zig:33`).

## A1: production's copy policy is not a one-stream lever (refuted at C=1)

A1 is byte-identical to D on replies (6/6) and carries the production values in force (boot line above).
Decode: 0.972 of D on prose and 1.001 on code; tokens a round and acceptance are identical to D (2.58/5.89,
0.703/0.749), so the copy policy does not change drafting; cold TTFT is 1.004/0.997 of D. At one stream
the four copy levers are level to slightly negative, and they cannot explain the one-stream prose gap.
The C=8 screen is where the shared-round and resync parts of the policy act.

## A4: the persistent KV tier is not a decode lever (refuted at every level)

A4 (D with `LEARN=0`: no disk tier, no 6 GiB prompt-cache ask) reads 0.999 of D on prose and 0.994 on
code at C=1 (40.3/52.0 ms a round against D's 40.2/51.5), and over the five levels its decode is 0.997 of
D - a no-op; at C=6 it even reads 1.018 on code. Its only consistent effect is cold prefill, 1.009/1.016 of
D over five levels and 1.075/1.083 at C=8. So the tier block costs nothing measurable at one stream, in line with the tier's own
receipt (LEVEL on decode, blind below 2 percent at 1-4 streams). Its boot also shows what the 6 GiB ask
was: with `LEARN=0` the dev engine runs its own device prompt cache, planned at 16,384 MiB with 220 MiB
used (`2 states, 220 MiB and 0 MiB spare of 16384 MiB`), so the tier's ask was smaller than the engine's
own default budget, not an addition to it.

## A3: the captured graphs are not a one-stream lever (refuted at C=1)

A3 is byte-identical to P (6/6) and its boot proves the eager path (0 graphs warmed against 384). Decode:
0.997 of P on prose and 0.994 on code; cold TTFT 0.980/1.003 of P. At one stream the graphs are worth
nothing measurable, so they cannot be the one-stream prose gap. This arm doubles as the window's null
control for the P family: a one-name env change with identical bits lands within 0.3-0.6 percent.

## The C=1 deficit is per round, not drafting

Per-pass, P against D at C=1: prose 0.955, 0.929, 0.926; code 0.915, 0.994, 0.995 (the third prose pass is
a slow outlier on both arms; the median picks pass1 on both). From pass1: P prose 6.96 s / 194 rounds =
35.9 ms a round at 2.64 tokens; D 7.49 s / 189 = 39.6 ms at 2.71 (+10.4 percent a round, +2.6 tokens).
P code 4.41 s / 98 = 45.0 ms at 5.22 tokens; D 4.44 s / 88 = 50.4 ms at 5.82 (+12.0 a round, +11.5
tokens). On code D's deeper chains pay for the slower round exactly; on prose the chains are the same
length and the slower round is pure loss. So no "D drafts shallower" story holds at one stream - D drafts
MORE - and the one-stream prose gap is the engine's per-round decode cost.

## The per-round cost is level-independent: the recorded window's own counters

The recorded window's first-boot cells (run1) carry the same counters at every level, so the mechanism can
be read off all five at once (`work/ParityGap/rounds.py` over `work/ParityGap/ev`):

| level | kind | P ms/round | D ms/round | D/P | P tokens/round | D tokens/round |
|---:|---|---:|---:|---:|---:|---:|
| 1 | prose | 37.5 | 41.6 | 1.109 | 2.48 | 2.58 |
| 1 | code | 47.5 | 51.7 | 1.088 | 5.55 | 5.89 |
| 2 | prose | 24.0 | 25.4 | 1.062 | 2.52 | 2.49 |
| 2 | code | 29.6 | 33.7 | 1.136 | 4.88 | 5.28 |
| 4 | prose | 16.9 | 17.9 | 1.062 | 2.60 | 2.58 |
| 4 | code | 21.7 | 24.5 | 1.130 | 4.94 | 5.23 |
| 6 | prose | 13.8 | 14.8 | 1.070 | 2.57 | 2.53 |
| 6 | code | 17.0 | 18.9 | 1.108 | 4.91 | 4.83 |
| 8 | prose | 12.0 | 13.3 | 1.109 | 2.59 | 2.56 |
| 8 | code | 14.7 | 16.5 | 1.116 | 4.88 | 4.83 |

D's round costs 6 to 14 percent more at every level (median about 10) while tokens a round move within
plus or minus 8 percent and flip sign by level. The tok/s ratio swings from 0.86 to 1.01 because those two
terms interact, not because the mechanism changes. At the same tokens a round, D would be 4-6 percent
FASTER than P at one stream and 1 percent slower at eight: the whole decode gap is the round cost, and
closing it is worth about 10 percent of decode at every concurrency.

## C=8 screen (complete)

| arm | prose | vs P | vs D | code | vs P | vs D | ms/round p | c | cold8k vs P | cold32k vs P |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| P | 238.5 | 1.000 | 1.108 | 367.5 | 1.000 | 1.113 | 12.20 | 14.80 | 1.000 | 1.000 |
| D | 215.3 | 0.903 | 1.000 | 330.1 | 0.898 | 1.000 | 13.25 | 16.28 | 1.131 | 1.071 |
| A1 | 211.3 | 0.886 | 0.981 | 322.9 | 0.879 | 0.978 | 13.35 | 16.49 | 1.129 | 1.077 |
| A2 | 240.4 | 1.008 | 1.117 | 364.4 | 0.992 | 1.104 | 12.16 | 14.79 | 1.118 | 1.085 |
| A3 | 244.0 | 1.023 | 1.133 | 381.8 | 1.039 | 1.157 | 12.00 | 14.53 | 0.978 | 0.953 |
| A4 | 214.8 | 0.901 | 0.998 | 320.4 | 0.872 | 0.971 | 13.16 | 16.56 | 1.216 | 1.159 |

- The per-round penalty holds at eight streams: D 13.25/16.28 ms against P 12.20/14.80 (+8.6/+10.0
  percent) with tokens a round within 1 percent - the same finding as at one stream and as the recorded
  window's whole curve.
- A2 is P's decode at eight streams too (1.008/0.992) and its prefill reads 1.118/1.085 against P, the
  same gap D shows (1.131/1.071). Its lever is prefill only, as designed.
- A1 reads 0.981 prose and 0.978 code against D at eight streams with the same tokens a round (2.56/4.83).
  That is inside D's own boot-to-boot spread at C=8 in the recorded window (prose 209.1-214.0, code
  323.8-326.7: A1's 211.3/322.9 sits inside it), so the copy policy is LEVEL to slightly negative, not a
  win; the candidate is refuted at both screen levels.
- A4 is level on prose (0.998) and 2.9 percent slower on code here (0.971), but at C=6 it reads 1.018 on
  code, so the code effect is the cells' spread; its cold prefill is 7.5/8.2 percent worse than D's
  (1.216/1.159 against 1.131/1.071), the one repeatable cost. Its own boot gives the mechanism: with
  `LEARN=0` the dev engine's device prompt cache asks 16,384 MiB where the tier asked 6 GiB
  (`2 states, 220 MiB and 0 MiB spare of 16384 MiB`), so dropping the tier hands the pool's budget to a
  larger default cache. The candidate "the tier costs decode" is refuted: removing it never sped the serve
  and cost code and prefill at eight streams.
- A3 (graphs eager) is level at one stream (0.997/0.994) and reads 1.023 prose / 1.039 code with a 4.7
  percent faster cold-32k at eight. P's engine's own options explain why that cannot be a graph effect at
  eight streams: `multi_graphs` is 4 and `multi_verify` is min(4, `MULTI_VERIFY`=1) = 1
  (`cuda_engine.zig:169,674-676`), and `runMulti` takes the graph only when `segs.len <= widest`
  (`:2493`), so a verify round of 8 streams and an MTP step of 8 streams both run eagerly. At C=8 the
  graphs are bypassed by construction; the 2-4 percent reading is inside P's recorded boot-to-boot spread
  (prose 239.2-243.2, code 367.0-380.8). The graphs act on solo verify rounds and MTP steps up to 4
  streams, so the 2 and 4 stream confirm is the real test of them; it is queued (see below).

## Each arm differs from its control by its lever alone (the captured env)

From every boot's own `env.txt` and `cmd.json`, arm against its family control at C=1:

| arm vs control | names added | names removed | values changed | argv |
|---|---|---|---|---|
| A1 vs D | 5: `TENSORFOLD_COPY_MISS=keep`, `_RAMP=jump`, `_SHARED=1`, `_RESYNC=1`, `_RESYNC_PROMPT_ONLY=1` | 0 | 0 | same |
| A2 vs P | 1: `TF_FLASHNEXT_PROMPT_MM=0` | 0 | 0 | same |
| A3 vs P | 1: `TF_FLASHNEXT_GRAPH_FAIL=1` | 0 | 0 | same |
| A4 vs D | 0 | 0 | 0 | the five tier args (`--prompt-cache-gib 6 --prompt-cache-disk /cache/kv --learn-gib 60 --learn-daily-gib 200 --learn-min-free-gib 20`) present on D, absent on A4 |

So each arm is the control plus one lever, nothing else, and the boot lines quoted above show the lever in
force (`copy policy: miss keep ...`, `matmul K slices split with _reduce`, `graph warm-up: 0 graphs`,
`2 states, 220 MiB ... of 16384 MiB`).

## Every arm is output-neutral against its family control (the isolation is clean)

`driver/hash_cmp.py` over the screen's `dec.jsonl` token hashes: rows equal / rows compared at the same
(kind, pass, j).

| level | arm | vs P text | vs P tokens | vs D text | vs D tokens |
|---:|---|---:|---:|---:|---:|
| 1 | A1 | 0/6 | 0/6 | 6/6 | 6/6 |
| 1 | A2 | 6/6 | 6/6 | 0/6 | 0/6 |
| 1 | A3 | 6/6 | 6/6 | 0/6 | 0/6 |
| 1 | A4 | 0/6 | 0/6 | 6/6 | 6/6 |
| 8 | A1 | 5/48 | 5/48 | 48/48 | 48/48 |
| 8 | A2 | 48/48 | 48/48 | 5/48 | 5/48 |
| 8 | A3 | 48/48 | 48/48 | 5/48 | 5/48 |
| 8 | A4 | 5/48 | 5/48 | 48/48 | 48/48 |

A1 and A4 are byte-identical to D; A2 and A3 are byte-identical to P. P against D agrees on 5 of 48 rows at
C=8, the recorded engine-level behaviour difference (not any arm's lever). Golden 6/6 held on every cell of
every arm (`meta.txt` `gold=6/6 identical ...`), so each arm's speed number is measured on a serve whose
short replies match the stock reference.

Geometric means over the two screen levels (`score.md`, `--final`):

| arm | decode vs P | decode vs D | cold8k vs P | cold8k vs D | cold32k vs P | cold32k vs D |
|---|---:|---:|---:|---:|---:|---:|
| A1 | 0.915 | 0.983 | 1.123 | 1.001 | 1.099 | 1.001 |
| A2 | 1.000 | 1.075 | 1.120 | 0.998 | 1.110 | 1.012 |
| A3 | 1.013 | 1.089 | 0.979 | 0.873 | 0.978 | 0.891 |
| A4 | 0.921 | 0.990 | 1.162 | 1.036 | 1.141 | 1.039 |

Read across: A2's prefill equals D's to 0-1 percent (0.998/1.012 against D) while being 11-12 percent worse
than P - that is the mechanism in one line. A3's eager path is 2.1-2.2 percent faster than P on cold
prefill and 1.3 percent faster on decode at the two levels, while still 11-13 percent faster than D on
prefill (the graph difference is not the prefill gap).

## Confirm pass, level C=2 (fresh boots, P and D re-booted as controls)

| arm | prose | vs P | vs D | code | vs P | vs D | ms/round p | c | cold8k vs P | cold8k vs D | cold32k vs P | cold32k vs D |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| P | 107.1 | 1.000 | 1.084 | 174.4 | 1.000 | 1.025 | 23.70 | 29.98 | 1.000 | 0.876 | 1.000 | 0.899 |
| D | 98.8 | 0.923 | 1.000 | 170.1 | 0.975 | 1.000 | 25.41 | 33.38 | 1.142 | 1.000 | 1.113 | 1.000 |
| A2 | 106.3 | 0.993 | 1.076 | 176.0 | 1.009 | 1.035 | 23.88 | 29.73 | 1.158 | 1.013 | 1.126 | 1.012 |
| A4 | 100.1 | 0.935 | 1.013 | 168.6 | 0.967 | 0.991 | 25.37 | 33.63 | 1.165 | 1.021 | 1.127 | 1.013 |

At C=2 the mechanism repeats on fresh boots: D's prefill is 1.142/1.113 of P and A2's is 1.158/1.126
(matching within 1.5 points), while A2's decode is level (0.993/1.009). A4 is again worse than D on
prefill (1.021/1.013) and level on decode (1.013/0.991): the tier candidate stays refuted. D's round is
25.41 against P's 23.70 on prose (+7.2 percent) and 33.38 against 29.98 (+11.3) with tokens a round
2.49/5.28 against 2.52/4.91.

## Confirm pass, level C=4 (fresh boots)

| arm | prose | vs P | vs D | code | vs P | vs D | ms/round p | c | cold8k vs P | cold32k vs P |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| P | 166.6 | 1.000 | 1.091 | 257.7 | 1.000 | 1.069 | 16.77 | 21.65 | 1.000 | 1.000 |
| D | 152.7 | 0.917 | 1.000 | 241.0 | 0.935 | 1.000 | 17.92 | 24.55 | 1.195 | 1.127 |
| A2 | 170.1 | 1.021 | 1.114 | 257.5 | 0.999 | 1.068 | 16.51 | 21.42 | 1.149 | 1.136 |

D's prefill is 1.195/1.127 of P and A2's 1.149/1.136; A2's decode is level (1.021/0.999, its prose 2 percent
above P with the level's own spread). The per-round penalty again: 17.92/24.55 against 16.77/21.65
(+6.9/+13.4 percent) with tokens a round 2.58/5.23 against 2.60/4.94.

## Confirm pass, level C=6 (fresh boots)

| arm | prose | vs P | vs D | code | vs P | vs D | ms/round p | c | cold8k vs P | cold32k vs P |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| P | 207.8 | 1.000 | 1.102 | 315.9 | 1.000 | 1.116 | 13.71 | 17.07 | 1.000 | 1.000 |
| D | 188.6 | 0.908 | 1.000 | 283.1 | 0.896 | 1.000 | 14.70 | 18.80 | 1.138 | 1.120 |
| A2 | 206.0 | 0.991 | 1.092 | 315.3 | 0.998 | 1.114 | 13.88 | 17.09 | 1.143 | 1.138 |
| A4 | 184.6 | 0.888 | 0.979 | 288.1 | 0.912 | 1.018 | 14.96 | 18.70 | 1.144 | 1.120 |

At C=6 the prefill mechanism holds again (D 1.138/1.120 of P, A2 1.143/1.138) and A2's decode is level
(0.991/0.998). A4 is 2.1 percent FASTER than D on code and level on prose here (0.979/1.018), which is the
opposite sign to C=8's 0.971 code: A4's decode effect is inside the code cells' 4-8 percent spread at these
levels, so the tier is a decode no-op, not a cost.

## Five levels: what each arm delivered (window `score.md`, geometric means)

| arm | levels | decode vs P | decode vs D | cold8k vs P | cold8k vs D | cold32k vs P | cold32k vs D |
|---|---:|---:|---:|---:|---:|---:|---:|
| A1 | 1,8 | 0.915 | 0.983 | 1.123 | 1.001 | 1.099 | 1.001 |
| A2 | 1,2,4,6,8 | 1.001 | 1.080 | 1.138 | 0.995 | 1.124 | 1.012 |
| A3 | 1,8 | 1.013 | 1.089 | 0.979 | 0.873 | 0.978 | 0.891 |
| A4 | 1,2,4,6,8 | 0.924 | 0.997 | 1.153 | 1.009 | 1.129 | 1.016 |

A2 over all five levels: decode 1.001 of P (its lever is prefill only, as designed), prefill 1.138/1.124
of P and 0.995/1.012 of D - P's prompt path with the captured form off is D's prompt path to within half a
percent at 8k and 1.2 percent at 32k. A4 over all five: decode 0.997 of D (a no-op) and prefill 1.009/1.016
of D (1 to 1.6 percent worse, concentrated at C=8), so the tier is not a cost.

## Screen verdicts and what each arm still owes

| arm | lever | 1 stream | 8 streams | status | 2/4/6 |
|---|---|---|---|---|---|
| A2 | captured prompt matmul off | decode level; prefill +12.1/+13.6% | decode level; prefill +11.8/+8.5% | the candidate is SUPPORTED: it reproduces D's prefill gap on P with identical replies | in the first window's confirm pass |
| A4 | tier + 6 GiB ask off | decode level (0.999/0.994) | code 0.971, prefill 1.216/1.159 | refuted as a cost; a small loss at concurrency | in the first window's confirm pass |
| A1 | production copy policy under dev names | prose 0.972, code 1.001 | 0.981/0.978 | refuted: level within the control's boot spread at both levels | queued (second window) |
| A3 | captured graphs eager | 0.997/0.994 | 1.023/1.039 (inside P's boot spread) | refuted at 1 and 8; the graphs are bypassed above 4 streams by construction, so the 2/4 confirm is their real test | queued (second window) |

The second window (`driver/window3.sh`) is queued on `~/work/gpu.lock` behind the first window and two
other sessions' windows (`parityid`, `SharedDraftsMain`, both already waiting when it was queued at
19:11:26Z). It boots P, D, A1 and A3 at C=2, C=4 and C=6 and writes `~/work/parity2/out3`.

## What the numbers decide

1. **The cold-prefill gap is the captured prompt-matmul path.** D is 11.2/12.5 percent slower than P at
   cold 8k/32k (C=1 prefill components 2.925/11.767 s against 2.613/10.459). P with the captured path off
   (A2) is 12.1/13.7 percent slower than P at the same cells, byte-identical replies and decode unchanged;
   at C=2 A2 reads 1.158/1.126 against P where D reads 1.142/1.113. D's own prompt path therefore costs
   what P's two-launch fallback costs, to within 1.5 points at every level measured, and the captured form
   (`_b16mm_ks`/`_fp4mm_ks`: every K slice of a tile in one program, no [SK,M,N] fp32 partial buffer) is
   the missing piece. In wall time at C=1: +0.31 s per 8k prompt and +1.31 s per 32k prompt, prefill
   component only. The port target is `prompt_mm.py`'s form into the dev engine, or qualifying a captured
   set at fp8 KV, which the dev engine refuses today (`cuda_lanes_load.zig:33`).
2. **The decode gap is not any setting the diff can change.** D's decode round is 7 to 11 percent more
   expensive than P's at every level (this window: C=1 40.23/51.54 against 36.18/46.92 ms; C=2
   25.41/33.38 against 23.70/29.98; C=8 13.25/16.28 against 12.20/14.80), while tokens a round are within
   8 percent and flip sign by level. The four env arms that could have moved it did not: the copy policy
   (A1, level at both screen levels, output-identical), the tier (A4, level at C=1/C=2 and worse at C=8),
   the captured graphs (A3, level at C=1 and bypassed above four streams by construction), and the
   captured prompt matmuls (A2, decode unchanged). The remaining difference is the two engines' decode
   kernel arrangements - P launches through the captured Triton set where a variant exists plus its fn_
   kernels, D runs its own glue - and isolating it needs a kernel-level measurement (a per-op profile of
   one decode round on each engine, or `TF_FLASHNEXT_PROFILE`/`PASS_TIMES` on both), not another env arm.
   Closing it is worth about 10 percent of decode at every level, which would put D at 4-6 percent above P
   at one stream and within 1 percent at eight.
3. **The two candidates the assignment named as loads are refuted as costs.** The persistent KV tier and
   its 6 GiB ask cost nothing measurable on decode at any level (A4's five-level decode is 0.997 of D) and
   the ask is smaller than the engine's own default cache budget, so removing it costs cold prefill 1 to 1.6
   percent over five levels and 7.5-8.2 percent at C=8 (A4's boot asks 16,384 MiB where the tier asked 6
   GiB).
   The captured decode graphs are worth nothing on this workload at 1 and 8 streams and can only act at 2
   to 4 (MTP steps of up to four streams).
4. **The KV format is not a lever.** Both arms serve fp8 KV (argv and the engines' own lines); the printed
   widths measure different sets (P's 1056 B a position a full layer, 12.38 KiB a token over the 12 full
   layers of 48; D's 18.44 KiB a token for its full page group, which also carries the indexer keys P keeps
   in a ring). P's banner `bf16 KV` is hard-coded text and `PRODUCTION.md` repeats it; the served format is
   fp8.

## Pending at this copy

The first window's confirm pass (A2, A4, P and D at C=2, C=4 and C=6), its restore proof, and the second
window's A1/A3 confirm (queued on the lock behind two other sessions' windows). The final version of this
file adds those cells and the restore lines.
