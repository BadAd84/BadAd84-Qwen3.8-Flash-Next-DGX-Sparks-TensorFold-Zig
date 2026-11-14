# TensorFold 1.2.7 patch series (our levers)

The TensorFold tree stays pristine at upstream v1.2.7 (`93a2e93ecebff8aa52b88e58c5dd222516e69c5f`) and every change
we own is one numbered patch here, one lever a patch, applied in filename order. Each patch builds on the ones
before it and on nothing after it: the tree compiles after every one of the first 15 and with all 19.

    ./apply.sh --check TREE     # the whole series applies, nothing written
    ./apply.sh TREE             # apply it
    build_patches.sh TAG git://192.168.99.16/up-pr/tf 93a2e93ecebff8aa52b88e58c5dd222516e69c5f <this directory>

`RECORD.md` says where the text comes from and which repairs it carries; `docs/CATCHUP-1.2.6.md` has every
measurement behind the table below. RETIRED: the 32-patch series and its integration tail (campaign repo history up
to `6b4cb3b`); it compiled at four points only and served with a stale chunk position.

The same 13 levers as `patches/1.2.6`, re-seated on v1.2.7 (see `RECORD.md`), each re-tested one rung at a time
(`scripts/qwen38/zig/target/v127.sh`, spark6, 2026-11-12: NVFP4 checkpoint, bf16 KV, 131,072-token window, one fresh
boot a cell, one decode pass of 512-token prose and code replies). Images: `up127` is v1.2.7 alone, `v<N>` the first N
patches. Aggregate tok/s, prose / code; every cell's golden is 6/6 identical to v1.2.6 stock's:

| arm | 1 stream | 4 streams | cold 8k / 32k prompt (s) |
|---|---|---|---|
| v1.2.6 stock | 54.5 / 74.5 | 105.4 / 153.7 | 3.49 / 14.30 |
| v1.2.7 stock (two runs) | 54.2 / 74.0, 53.4 / 73.4 | 105.9 / 154.0, 105.2 / 152.5 | 3.51 / 14.29, 3.49 / 14.31 |
| v1.2.6 + 0001-0007 (`g21`) | 60.9 / 80.4 | 111.4 / 164.6 | 3.52 / 14.28 |
| v1.2.7 + 0001 | 53.7 / 73.2 | 105.2 / 153.6 | 3.51 / 14.33 |
| v1.2.7 + 0001-0003 | 53.9 / 74.1 | 105.3 / 153.3 | 3.53 / 14.31 |
| v1.2.7 + 0001-0004 | 53.6 / 73.3 | 104.8 / 153.0 | 3.52 / 14.24 |
| v1.2.7 + 0001-0005 | 53.4 / 73.5 | 105.3 / 152.9 | 3.51 / 14.28 |
| v1.2.7 + 0001-0006 | 53.5 / 73.1 | 105.4 / 153.3 | 3.51 / 14.24 |
| **v1.2.7 + 0001-0007** | **60.5 / 80.0** | **111.4 / 164.7** | 3.51 / 14.24 |
| v1.2.7 + 0001-0008 | 60.7 / 80.5 | 111.5 / 163.6 | 3.40 / 13.74 |
| v1.2.7 + 0001-0009 | 60.3 / 80.1 | 111.4 / 163.9 | 3.35 / 13.79 |
| v1.2.7 + 0001-0010 | 60.6 / 79.8 | 111.2 / 164.2 | 3.35 / 13.74 |
| v1.2.7 + 0001-0011 | 60.7 / 80.0 | 111.3 / 164.0 | 3.46 / 13.82 |
| v1.2.7 + all 13 | 60.4 / 80.2 | 111.5 / 163.6 | 3.39 / 13.78 |

- v1.2.7 gives the same speed as v1.2.6 on this workload, and the series behaves the same on it: the 4-bit draft head
  (0007) is the whole decode gain (+11.6% prose, +8.1% code at one stream, +5.2% / +7.0% at four, against v1.2.7
  stock), the read-out fusion (0008) is the whole prompt gain (14.24 to 13.74 s at 32k, -3.5%), and every other patch
  is flat.
- No patch is retired: v1.2.7 absorbed none of them (each lever's gain survives without a counterpart in the base).
- Not yet run on v1.2.7: the copy workload, fp8 KV at 262,144, the stock `DRAFT_HEAD` arm, the 2, 6 and 8 stream cells
  (all measured on v1.2.6 in `patches/1.2.6/README.md`, where the series gives the same results).
- Cell-to-cell noise is about 1% (the stock arm run twice: 54.2 and 53.4 at one stream).

## Against the production serve, at every stream count measured (2026-11-12)

The series' own arms, bf16 KV, a 131,072-token window, one fresh boot a cell, 512-token prose and code replies,
aggregate tok/s (`scripts/qwen38/zig/target/widetile.sh`, spark6 `~/work/target/widetile.log`, image `v14`, which
is this series plus a lever that measured flat and did not land). The target is the production serve's own table,
`production/SPEED-TARGET.md` on the `production` branch, measured at 262,144 tokens. (Corrected 2026-11-13: "fp8 and
bf16 KV decode the same on this box" rested on fp8 cells that ran bf16 caches; see 0015, defect 1.)

| streams | ours prose / code | production prose / code | gap prose / code |
|---|---|---|---|
| 1 | 60.8 / 80.4 | 70.9 / 113.0 | -14% / -29% |
| 2 | 86.5 / 119.2 | 103.3 / 173.7 | -16% / -31% |
| 4 | 111.7 / 165.0 | 162.3 / 254.0 | -31% / -35% |
| 6 | 144.7 / 202.3 | 202.2 / 311.8 | -28% / -35% |
| 8 | not served: 8 streams at 131,072 with bf16 KV does not fit | 237.1 / 370.5 | |

Every cell's golden is 6/6 identical to v1.2.6 stock's and its boot log reads "window self-check: 1176 of 2080".
Where the remaining time is, and what has been measured against it, is in `docs/CATCHUP-1.2.6.md`: the round's
read-outs already run at the memory roofline, and the drafter's 181.1 MB of BF16 linears are the row to take next.

## 0014: the drafter's BF16 linears, selectable format (`TF_FLASHNEXT_MTP_WEIGHTS`) (2026-11-12)

`TF_FLASHNEXT_MTP_WEIGHTS` names how the drafter's BF16 linears are kept: `bf16` (the default: the checkpoint's own
rows, as upstream) or `mxfp8` (re-coded at load to E4M3 codes with a power-of-two scale a row's 32 inputs). An unknown
word refuses to start. Another encoding is one more `Format` word in `cuda_mtp_mxfp8.zig` and one more arm in
`projection.dense`. The FP4 checkpoint quantizes the backbone and leaves the drafter alone: `mtp.*` holds 181.1 MB of
BF16 (`q_proj` 62.9, `o_proj` 31.5, `fc_embedding` and `fc_hidden` 13.1 each, its four hyper-connection matrices 6.55
each, the shared expert 3.28 each), and every draft pass walks it. The figures below are `mxfp8` against `bf16`
(measured under the first name of the switch, `TF_FLASHNEXT_MTP_MXFP8=1`, which this text replaced; the code path is
the same).

One binary (image `v16`), the switch off and on, one fresh boot a cell, bf16 KV, 131,072 tokens, aggregate tok/s
prose / code (`scripts/qwen38/zig/target/mtpchain.sh`, spark6 `~/work/target/mtp.log`):

| arm | C=1 | C=2 | C=4 | C=6 | rounds prose/code |
|---|---|---|---|---|---|
| off | 60.9 / 80.7 | 86.3 / 119.0 | 111.5 / 164.2 | 144.3 / 201.6 | 146 / 89 |
| on | 63.2 / 86.8 | 87.2 / 125.4 | 112.6 / 171.5 | 144.6 / 218.1 | 144 / 86 |
| off again | 60.6 / 79.7 | | 111.3 / 164.2 | | 146 / 89 |
| on again | 62.7 / 86.7 | | 112.9 / 170.5 | | 144 / 86 |

Eight streams do not fit at 131,072 with bf16 KV, so that pair ran on fp8 KV: 160.7 / 230.0 off against
162.5 / 246.2 on. Cold prompts do not move: 8k 3.425 off, 3.442 on, 3.414 off again; 32k 13.768, 13.798, 13.752.

That is +3.8% prose and +7.6% code at one stream, +1.0% and +5.4% at two, +1.0% and +4.4% at four, +0.2% and
+8.2% at six, +1.1% and +7.0% at eight, with the repeats holding and no cell slower. It is exact the way patch
0007 is exact: a draft is a proposal the verify forward checks, so every decode reply hash matches the off arm's
(ten at one and four streams, sixteen at two, six and eight), golden is 6/6 and the boot log reads "window
self-check: 1176 of 2080"; the rounds a 512-token reply takes move (146 / 89 to 144 / 86), which is the drafter
changing its proposals, not the model changing its tokens.

## Against the production target, at its settings (2026-11-12)

**Corrected 2026-11-13: every `KV_DTYPE=fp8` cell in this table ran bf16 caches** (0015, defect 1: served streams
kept bf16 rows while the memory check priced fp8). The real fp8 rows for 1, 2 and 4 streams are the unpaged column of
the 0015 table below (image `fp8pg2`, 61.2 / 81.4, 86.2 / 120.4 and 113.3 / 164.7), which supersede the rows here; the
6 and 8 stream rows ran at 131,072 and are superseded by that table's `KV_PAGES=4096` rows at 262,144.

`target127.sh` and `target127b.sh`, spark6: NVFP4 checkpoint, `KV_DTYPE=fp8`, a 262,144-token window, one fresh boot a
cell, one decode pass of 512-token replies; aggregate tok/s prose / code. Golden 6/6 identical to stock's in every
cell, window self-check 1,176 of 2,080. Production's figures are `production/SPEED-TARGET.md` on the `production`
branch.

| streams | accepted stack (0001-0007) | all 13 | production | accepted stack against production |
|---:|---|---|---|---|
| 1 | 61.8 / 81.7 (repeat 61.4 / 80.4) | 61.7 / 81.6 | 70.9 / 113.0 | -13% / -28% |
| 2 | 87.6 / 120.8 (86.8 / 120.3) | 87.1 / 120.7 | 103.3 / 173.7 | -15% / -30% |
| 4 | 113.4 / 166.7 (112.6 / 166.3) | 112.7 / 166.3 | 162.3 / 254.0 | -30% / -34% |
| 6 | 146.2 / 205.3 (131,072 window) | | 202.2 / 311.8 | -28% / -34% |
| 8 | 163.3 / 233.3 (131,072 window) | | 237.1 / 370.5 | -31% / -37% |

- **6 and 8 streams do not start at a 262,144 window.** The engine refuses them by name: 6 streams need 30.23 GiB of
  stream memory and 8 need 40.31 GiB against a 27.26 GiB budget (5 streams fit: 133.9 / 187.4). Production serves 8 at
  262,144 with `TF_FLASHNEXT_SEQ_POOL=8` (and `WARM_POOL=8`), a shared sequence pool this series does not carry. Those
  two cells ran at a 131,072 window, which does not change the decode work of a 512-token reply but is not the same
  setting; the capacity itself is a gap against production, apart from speed.
- Decode speed at fp8 KV and 262,144 is the same as bf16 and 131,072 (61.8 / 81.7 against 60.5 / 80.0 at one stream).
  Corrected 2026-11-13: before patch 0015 every served stream kept bf16 caches under `KV_DTYPE=fp8` (0015, defect 1),
  so these fp8 cells measured bf16 caches priced as fp8.
- The gap widens with streams (-13% at one prose stream, -31% at eight): the cost production saves a round grows with
  the rows verified, which points at per-row work (experts, dense projections and glue at 5 to 8 rows a stream), not at
  a fixed cost such as the drafter's weights alone.
- There is no patch 0015 for the expert path (2026-11-13): measured by expert id, every unique expert is read once a
  layer a round, our decode expert kernels stream at 195 to 222 GB a second (faster than production's at equal rows),
  and the 2.35 times the expert bytes a round at one stream is production's checkpoint routing 5 experts a token
  against our 10. `docs/CATCHUP-1.2.6.md`, "The decode round's expert traffic, measured by expert id".
- **The target serves a different model configuration (2026-11-13).** Production's checkpoint (azampatti INT4-AutoRound)
  routes 5 experts a token with a GPTQ int4 head; ours (nvidia FP4) routes 10 with a BF16 head. Neither engine loads
  the other's checkpoint, and on one harness the one-stream round splits as about 12 ms of routing width and up to
  5 ms of head format (the checkpoint's) against about 4.5 ms of engine work. Table and refusals in
  `docs/CATCHUP-1.2.6.md`, "The production target is a different model configuration".

## Draft-policy settings on this base, measured (2026-11-13)

Everything here is exact by construction - a draft is a proposal the verify forward checks - so the question is
only speed. Image `v16` (the series with 0014 on), bf16 KV, a 131,072-token window, one fresh boot a cell, 512-token
prose and code replies; counters are the engine's own `/metrics` (`~/work/target/bench/{cc,pr1,pr4,cp,gw,gf}-*`).

**The round's price (0010's `TF_FLASHNEXT_ROUND_MS` and `DRAFT_ROW_MS`) is inert on this workload.** A round costs
38 ms plus 3.75 ms a row on prose and 38 plus 3.85 on code, straight to 15 rows, so the price is `38+2.15` with
`DRAFT_ROW_MS=1.6` once the drafter's own 1.58 ms a row is taken out. Priced, the engine keeps exactly the same
drafts: one stream 61.18 / 80.50 against 61.48 / 81.61 and 61.16 / 81.25 unpriced with identical counters; four
streams 113.6 / 166.8 against 113.1 / 166.7 and 112.4 / 166.3, 1,853 drafts against 1,861. A steeper line (`38+3.0`)
and a flatter one (`38+1.5`) give the same 1,853. Corrected 2026-11-14: above one stream these runs had the shared
rounds' own stop rule in force (0.6 a draft, `cuda_lanes_draft.rule`, unless `TF_FLASHNEXT_SHARED_DRAFTS=0`), so
neither the price nor `CONFIDENCE` could reach a multi-stream chain; the next section measures them with it lifted.

**Our `TF_FLASHNEXT_CONFIDENCE=-0.4` default is the best of four.** At one stream: -0.15 gives 57.97 / 79.31,
-0.25 gives 61.01 / 80.11, -0.6 gives 59.22 / 82.71, against 61.48 / 81.61. Production runs -0.15, which costs 6%
on prose here. (Re-measured at one stream on image `rq18`, fp8 KV at 262,144, 2026-11-14, against the two defaults
cells' mean: -0.25 gives -2.7% / -1.0% and -0.15 -7.7% / -2.1%; -0.4 still wins at one stream.)

**The copy policy does not move it either.** `TENSORFOLD_COPY_MISS=keep`, `COPY_RAMP=jump`, `COPY_SHARED=1` and
`COPY_RESYNC=1`, alone and together, at one and four streams: every cell returns the default counters to the digit
and the same speed inside noise.

**`TF_FLASHNEXT_GREEDY_WIDE=8` buys code at six and eight streams and costs prose there.** The knob is the round
width up to which greedy chains keep their depth (default 4), so it does nothing below five streams and changes the
chain above it. Aggregate tok/s prose / code, six and eight streams on the shared page pool (`KV_PAGES=4096`):

| streams | default | `GREEDY_WIDE=8` | counters (code, default -> 8) |
|---|---|---|---|
| 1 | 61.26 / 80.88 (repeat 61.19 / 80.92) | 60.79 / 81.53 | identical: 89 rounds, 639 drafts, 422 accepted |
| 2 | 87.5 / 120.7 | 87.3 / 120.0 | identical: 190, 1,144, 832 |
| 4 | 112.2 / 166.8 | 112.4 / 166.0 | identical: 424, 2,265, 1,620 |
| 6 | 146.8, 147.5, 147.2 / 205.6, 206.2, 205.6 | 146.1, 145.3, 146.1 / **218.2, 218.7, 219.1** | 662 -> 612 rounds, 2,404 -> 2,454 accepted |
| 8 | 164.8, 164.0 / 235.9, 234.2 | 163.0, 163.5 / **247.8, 248.6** | 918 -> 866 rounds, 3,171 -> 3,222 accepted |

Three runs of each six-stream cell and two of each eight-stream cell: code gains **6.3%** at six (218.7 mean
against 205.8) and **5.6%** at eight (248.2 against 235.1), prose loses **0.9%** at six (145.8 against 147.2) and
**0.7%** at eight (163.3 against 164.4). The repeats are tight - every wide six-stream run returns 1,103 rounds,
2,806 drafts and 1,860 accepted, every default one 1,111, 2,788 and 1,852 - so the prose loss is a real effect of
the longer chain, not cell noise. Below five streams the counters are identical to the digit and the speeds differ
by less than 1% either way, which is the knob doing nothing there by construction.

There is no middle setting that takes the code gain without the prose cost, and that was tested rather than
assumed (`~/work/target/bench/gx-*`): at six streams `GREEDY_WIDE=6` gives 146.1 / 218.4 and `=16` gives
145.6 / 218.6, both on the same 1,103 rounds, 2,806 drafts and 1,860 accepted as `=8`, because any value at or
above the round width keeps the chain; at eight streams `=6` returns the default's own counters to the digit
(1,490 rounds, 3,630 drafts, 2,342 accepted) and the default's speed, because a value below the width shortens
the chain exactly as the default does. (`=8` with `CONFIDENCE=-0.5` gave 145.4 / 219.1 at six streams and 162.8 /
247.4 at eight, but that `CONFIDENCE` never reached the chains: above one stream the shared rounds' 0.6 rule held
them, see the next section.)

Golden is 6/6 identical to stock's at one stream with the knob on and off, and every boot log reads "window
self-check: 1176 of 2080", so replies are unchanged. On its own it stays **not a default** (the six and eight
stream prose cells regressed here); together with `TF_FLASHNEXT_SHARED_DRAFTS=0` the prose loss is gone (next
section).

## Draft settings on the FP4 checkpoint, multi-stream (2026-11-14)

`cuda_lanes_draft.rule`: while more than one stream is busy, a greedy chain stops at the first draft under 0.6
(`shared_stop`) whatever `TF_FLASHNEXT_CONFIDENCE` says, unless `TF_FLASHNEXT_SHARED_DRAFTS=0`. Measured on image
`rq18` (0001-0018; 0019 adds only the kernel contract), NVFP4 checkpoint, the recipe's settings, fp8 KV at 262,144,
`KV_PAGES=4096` at 6 and 8 streams, one fresh boot a cell, one decode pass of 512-token prose and code replies,
counters from `/metrics` (`scripts/qwen38/zig/target/int4/int4win.sh` with `CKPT=nvfp4`, `fp4sum.py`; spark6
`~/work/int4/bench-fp4a`, `bench-fp4b`, 01:22 to 02:11 UTC). Aggregate tok/s prose / code, against the defaults
(each defaults cell run twice; rounds are each stream's rounds, prose / code):

| streams | defaults (repeat) | `SHARED_DRAFTS=0` | `GREEDY_WIDE=8` | both | both, `CONFIDENCE=-0.25` |
|---:|---|---|---|---|---|
| 1 | 61.6 / 82.1 (61.7 / 81.7), 142 / 89 rounds | inactive at one stream | inactive | inactive | -0.25: 60.0 / 81.1; -0.15: 56.9 / 80.2 |
| 2 | 87.4 / 121.8 (85.7 / 120.5), 334 / 191 | 88.2 / 124.0 (87.2 / 122.0), 316 / 177 | inactive | as `SHARED_DRAFTS=0` | 84.6 / 121.9, 302 / 172 |
| 4 | 114.0 / 166.4 (112.6 / 163.9), 736 / 432 | 114.8 / 166.4 (113.5 / 163.8), 685 / 399 | inactive | as `SHARED_DRAFTS=0` | 109.7 / 164.9, 652 / 383 |
| 6 | 143.5 / 204.6 (144.2 / 205.5), 1,071 / 666 | 148.4 / 203.9, 988 / 626 | 144.7 / 210.8, 1,063 / 620 | **147.1 / 213.0**, 983 / 578 | 140.3 / 212.3, 932 / 553 |
| 8 | 160.5 / 234.6 (160.0 / 233.8), 1,457 / 914 | 164.0 / 232.6, 1,355 / 860 | 160.5 / 242.4, 1,448 / 857 | **162.7 / 246.0**, 1,349 / 803 | 155.4 / 239.1, 1,279 / 775 |

- **Exact.** Every decode reply's sha equals the defaults' at the same stream count in every arm (2, 4, 8, 12 and 16
  replies at 1, 2, 4, 6 and 8 streams), golden is 6/6 identical to the defaults' in every one-stream arm, and every
  boot log reads "window self-check: 1176 of 2080".
- **`TF_FLASHNEXT_SHARED_DRAFTS=0 TF_FLASHNEXT_GREEDY_WIDE=8` with the default `CONFIDENCE=-0.4` is the one setting
  that is no slower anywhere**, against the defaults' means: one stream unchanged (both switches act only above one
  stream; `GREEDY_WIDE` only above four), two streams +1.3% / +1.5% (two pairs), four +0.8% / -0.0% (two pairs),
  six +2.3% / +3.9%, eight +1.5% / +5.0%. The rounds a 512-token reply takes fall 5 to 13%.
- **A looser stop rule loses on this checkpoint at every stream count**: -0.25 and -0.15 draft more and land more,
  but a top-10 round's extra rows cost more than the extra tokens buy. Against the defaults' means: one stream -2.7%
  and -7.7% on prose; two and four streams -2% to -9% on prose and from +0.6% (-0.25 at two streams, 0.9% under
  `SHARED_DRAFTS=0` alone) to -11% on code; six and eight streams -2.5% / -3.0% on prose with code +3.5% / +2.1%, under
  the combined setting's +3.9% / +5.0%. No looser rule beats -0.4 at any stream count, so no stream-count gate is
  needed.
- `SHARED_DRAFTS=0` alone buys prose at six and eight streams (+3.2% / +2.3%) and costs code a little (-0.6% /
  -0.7%); `GREEDY_WIDE=8` alone buys code there (+2.8% / +3.5%); together each side keeps its gain. The combined
  setting's six and eight stream cells were repeated against the defaults in a second window (`bench-fp4c`, 02:13 to
  02:21 UTC): six streams 147.6 / 214.1 against 143.9 / 205.4 (+2.6% / +4.2%), eight 163.3 / 247.0 against
  160.7 / 234.5 (+1.6% / +5.3%), the counters the same as the first window's to the digit.
- **The priced round (0010) does not beat it.** With the shared rule lifted, the combined setting plus
  `TF_FLASHNEXT_ROUND_MS=38+2.15 TF_FLASHNEXT_DRAFT_ROW_MS=1.6` (the price measured above), a flatter `38+1.5` and a
  steeper `38+3.0`, against the combined setting run twice in the same window (`bench-fp4p`, 02:22 to 02:47 UTC;
  every reply's sha equal): four streams 113.4 to 113.8 / 163.7 to 164.5 against 113.7 to 114.1 / 164.0 to 165.1;
  six 146.7 to 147.5 / 213.4 to 213.8 against 146.9 / 212.2 to 212.5; eight 162.4 to 162.7 / 245.6 to 246.1 against
  162.6 to 162.8 / 246.1 to 246.5. The three lines take the same rounds as each other, a few more than unpriced
  (687 / 399, 989 / 582 and 1,358 / 814 against 685 / 399, 983 / 578 and 1,349 / 803): the price trims drafts
  slightly. The only cells above the unpriced pair are at six streams (code +0.4% to +0.8%, one prose cell +0.4%),
  where the priced arms run more rounds than the pair and sit inside the ~1% cell noise; four and eight streams are
  inside or under the pair. So the price stays unset.

## 0015: fp8 KV on every served stream and in the shared page pool (`TF_FLASHNEXT_KV_PAGES` with fp8) (2026-11-13)

`TF_FLASHNEXT_KV_PAGES=n` was refused with fp8 KV. With 0015 the pool's pages hold the 12 attention layers' rows in
the geometry 0003 writes (544-byte key rows with their scales, 512-byte value rows, bf16 indexer rows; the MTP head's
layer stays bf16): 18,880 bytes a token against 30,784. The fp8 prep, chunk and fused kernels write and read through
each stream's page table (four new launches, nvcc resources measured for the five SM targets in
`flashnext_kv8_pending.zig`), and the host test in `cuda_pages.zig` checks the geometry and the kernels' addresses.
Unset, nothing changes; the pool is a capacity switch and stays off by default.

Writing it found three defects in 0003, which 0015 repairs:

1. **Served streams never held fp8 rows.** The lane-parts constructor (`cuda_seq_parts.newSeqIn`, every stream unless
   `TF_FLASHNEXT_LANE_PARTS=0`) and the pool lane built bf16 caches while the memory check priced fp8, so every
   "fp8 KV" cell measured before 0015 ran bf16 caches.
2. **The fp8 staging took its head arguments swapped** (slot `key * hk + HK` for `key * HK + hk`). Measured with the
   fp8 device test (`tf-cuda-test flashnext-kv8`, spark6 `~/work/target/fp8vis.log`): it fails in `v16` ("fp8
   attention dense: first difference at byte 0, 2975 of 3072 words differ") and passes with 0015 ("the widening reads
   equal the bf16 kernels on the dequantized rows, dense and sparse, chunked and fused"); defect 1 had kept served
   streams away from it.
3. **A pass's kept-state marks wrote the n-gram tail at the bf16 offset**, past an fp8 state's buffer. With the prompt
   cache on (1, 2 and 4 streams) the first request failed with `cuMemcpyDtoDAsync: CUDA_ERROR_INVALID_VALUE`: image
   `fp8pg` (0015 without this repair) failed so in every such cell, and `v16` with `TF_FLASHNEXT_LANE_PARTS=0`, the
   one route into 0003's fp8 caches, failed the same way (golden 0/6). That run overlapped another lane's GPU use
   (06:14 to 06:33 UTC); its failures were first-request errors, and none of its timings are quoted.

Image `fp8pg2` (the 14 patches + 0015), NVFP4, `KV_DTYPE=fp8`, a 262,144-token window, one fresh boot a cell, one
decode pass of 512-token prose and code replies, aggregate tok/s prose / code (`scripts/qwen38/zig/target/fp8pages.sh
fp8pg2 g8` and `fp8q.sh`, spark6 `~/work/target/fp8pages-fp8pg2.{log,sum}` and `fp8q.log`, 06:41 to 07:14 UTC):

| streams | unpaged fp8 | `KV_PAGES=4096` | every stream on pages (`KV_PAGES_ALL=1`) | production | pages against production |
|---:|---|---|---|---|---|
| 1 | 61.2 / 81.4 (repeat 61.0 / 80.9) | 60.9 / 81.0 (61.1 / 80.7) | 61.1 / 81.0 (60.9 / 81.0) | 70.9 / 113.0 | -14% / -28% |
| 2 | 86.2 / 120.4 | 86.4 / 120.1 | exactness only: one pool lane | 103.3 / 173.7 | -16% / -31% |
| 4 | 113.3 / 164.7 | 113.4 / 164.6 | exactness only: three pool lanes | 162.3 / 254.0 | -30% / -35% |
| 6 | refused (30.23 GiB against 27.26) | **144.2 / 204.8** | | 202.2 / 311.8 | -29% / -34% |
| 8 | refused (40.31 GiB) | **160.5 / 234.3** | | 237.1 / 370.5 | -32% / -37% |

- **Exact.** Golden is 6/6 identical to stock's in every cell and every boot log reads "window self-check: 1176 of
  2080". Paged against unpaged, every decode reply's sha is identical: every stream on pages 2 of 2 at one stream, 4 of
  4 at two and 8 of 8 at four; the pool beside the engine's own stream 2/2, 4/4 and 8/8; each one-stream repeat 2/2.
  Six and eight streams have no unpaged cell to compare with; their pages are the ones checked at 1 to 4 streams.
- **Capacity.** Six and eight streams boot at 262,144 with fp8 KV: "8 streams at once, the engine's own at a
  262144-token window (5.04 GiB, in the model's), 7 more taking 308 pages of 4096 rows (22.18 GiB) as they need them
  ... of 27.2 GiB left after a 9.0 GiB reserve", and "KV page groups: one page 73.75 MiB, 4096 rows ... 18.44 KiB a
  token". The lanes share 308 pages (1,261,568 positions); a request waits for pages when the pool is full. Unpaged,
  6 and 8 streams are still refused at the price above (0015 does not change it).
- **Speed.** No cost shows at one stream: the pool beside the own stream reads 60.9 / 81.0 and 61.1 / 80.7 against
  61.2 / 81.4 and 61.0 / 80.9 unpaged, and the one stream itself on pages 61.1 / 81.0 and 60.9 / 81.0, inside the ~1%
  cell noise (bf16 pages measured -2.4% / -5.6% at one stream on `v16`); two and four streams are flat too. Even so
  the pool stays opt-in: it is a capacity switch. `KV_PAGES_ALL=1` gives the pool one lane fewer than the streams (the
  boot line's "1 more" at two), so its 2- and 4-stream cells queue a stream and are exactness checks only.
- **Against production** the six and eight stream gap is the speed gap the series already had at 131,072 (-28% / -34%
  and -31% / -37% in the table above); the capacity gap is closed.
- `KV_DTYPE=fp8` without pages now keeps fp8 rows on every stream: golden is still 6/6 identical to stock's and one
  stream decodes 61.2 / 81.4, against 61.8 / 81.7 and 61.4 / 80.4 for the accepted stack on 2026-11-12, when those
  cells ran bf16 caches.
- **Vision.** With vision on, fp8 KV, a 262,144 window and every stream on pool pages, one image request (a 64x64 PNG,
  red left half, blue right half, temperature 0) is answered "The left half of the image is filled with a solid,
  bright red color ... The right half ... blue", and the same request to an unpaged fp8 boot returns the identical
  reply (`fp8vis.sh`, `bench/vis-{vpa,vu}.json`).
- **Host suite.** `zig build test-cuda-host` on a native Linux filesystem (WSL ext4, Zig 0.17.0): the 15-patch tree
  passes every step, as pristine v1.2.7 does on the same machine. Its first run crashed five pool tests ("switch on
  corrupt value" in `Kv.keyRow`: their `Engine` is `undefined` but for a few fields, and the pool lane now reads its
  format); those tests now set `kv = .bf16`, as 0003 did for the others.
  A mutant of the new page test (18,881 bytes a token for 18,880) fails it by name, so the suite does run it.


## 0016 and 0017: the read-outs' 12-bit blocks two groups ahead, and split-K projections on the fused form (2026-11-13)

Both aim at rows of the per-kernel table in `docs/CATCHUP-1.2.6.md` ("The 4.23 ms by tensor shape"), and both are
exact by construction: they change when bytes are loaded or which block adds the K slices, never a product or an
addition order.

- **0016** (no new switch: it is the path of 0009's `TF_FLASHNEXT_HC_Q12=1`): the 12-bit read-out tile loaded and
  decoded each group's blocks inside the group loop, one group at a time; it now loads them two groups ahead.
- **0017** `TF_FLASHNEXT_FUSED_SPLIT=1` (default off): a lane call split over K on a cluster, 2,048 columns or more
  below 256 rows, runs on the fused form, one block a 64-column tile adding its K slices in slice order, which is
  the cluster's order. Production's launcher runs the same form (`TF_FLASHNEXT_FP8_FUSED_SPLIT=4`). Here it takes
  out_proj and o_proj (MXFP8 [2560, 6144], 8 slices) and the drafter's BF16 2,560-column projections.

Kernel log, one stream (image `rq17x`: the 17 patches plus v16x's logs; bf16 KV, 131,072, graphs eager; spark6
`~/work/target/bench/rk-*`, `scripts/qwen38/zig/target/readout/rtab.py`), us a launch:

| arm | read-out down | read-out up | out_proj, o_proj | in kernels a round |
|---|---|---|---|---|
| base | 43.6 (BF16) | 36.5 (BF16) | 84.3 (cluster) | 69.92 ms |
| `HC_Q12=1` | 40.2 (0009 alone: 41.0) | 34.2 (0009 alone: 34.2) | 85.0 | 69.45 ms |
| `HC_Q12=1 FUSED_SPLIT=1` | 40.1 | 34.0 | 79.7 (fused) | 69.00 ms |

Served, image `rq17`, one fresh boot a cell, fp8 KV at 262,144 for 1, 2 and 4 streams, `TF_FLASHNEXT_KV_PAGES=4096`
for 6 and 8, one decode pass of 512-token prose and code replies, aggregate tok/s prose / code
(`scripts/qwen38/zig/target/readout/chain17.sh`, spark6 `~/work/target/readout/chain17.{log,sum}`, 21:01 to 21:41
UTC):

| streams | base | `HC_Q12=1` | `HC_Q12=1 FUSED_SPLIT=1` | `FUSED_SPLIT=1` alone |
|---:|---|---|---|---|
| 1 | 62.4 / 82.8 (repeat 61.8 / 82.0) | 62.7 / 82.9 | 62.8 / 82.7 (repeat 62.9 / 83.2) | 62.2 / 82.7 |
| 2 | 87.9 / 122.6 | 88.6 / 123.4 | 88.4 / 123.2 | |
| 4 | 115.3 / 167.7 (114.3 / 166.4) | 115.6 / 167.9 | 115.8 / 167.8 (115.2 / 167.9) | 115.1 / 167.2 |
| 6 | 147.1 / 209.6 | 147.1 / 208.9 | 147.7 / 210.7 | |
| 8 | 163.8 / 239.3 | 163.3 / 238.4 | 164.5 / 242.3 | |

- **Exact.** Golden is 6/6 identical to stock's in all 21 cells, every boot log reads "window self-check: 1176 of
  2080", and every decode reply's sha equals the base arm's: 2, 4, 8, 12 and 16 at 1, 2, 4, 6 and 8 streams for both
  arms, 2 and 8 for the fused split alone and for the repeats.
- **Speed.** Both together against the base: +1.2% / +0.7% at one stream (two pairs), +0.6% / +0.5% at two,
  +0.6% / +0.5% at four (two pairs), +0.4% / +0.5% at six, +0.4% / +1.3% at eight, no cell slower. In kernels, 0.47
  ms a round from the 12-bit read-outs and 0.45 more from the fused form. Each alone moves less than the ~1% cell
  noise: `HC_Q12=1` reads 0.0% / -0.3% at six and -0.3% / -0.4% at eight, the fused split alone -0.3% / -0.1%
  against the first base cell and +0.6% / +0.9% against its repeat at one stream.
- **Defaults stay off.** Neither lever alone shows a gain outside the cell noise at every stream count, and the
  12-bit copies take 1.07 GB of device memory (the boot line's model 73.29 to 74.31 GiB). Together they are a
  setting that measured no slower anywhere: `TF_FLASHNEXT_HC_Q12=1 TF_FLASHNEXT_FUSED_SPLIT=1`.
- **The prefetch is not why the 12-bit read-outs trail production's.** Two groups ahead moved the down from 41.0 to
  40.2 us and the up not at all; our 12-bit tiles stream 125 and 145 GB/s against production's 139 and 156, so what
  is left is the decode work inside the group loop, not load latency.

## 0018 and 0019: the read-out's reduce and mix inside its products, and the fused split's kernel contract (2026-11-13)

- **0018** `TF_FLASHNEXT_READOUT_FUSE=1` (default off): the decode read-out's `fn_hc_reduce_act` runs in the down's
  cluster epilogue (`qmmf.cu` TF_HCACT: the cluster tile's K slices and sums, then the reduce's act, inject gates and
  32-column act sums from the same f32 row) and `fn_hc_dense_mix8` in the up (TF_UPMIX: a block a 32-column group of
  the four streams, warp s stream s, each column's m16n8k16 chain as the lane's one-slice tile runs it, the up rows
  rounded to bf16 as the lane stores them, then the mix and its sums op for op). BF16 and 12-bit weights, row tiles
  16 and 32 (and 64 for BF16); a call those kernels do not carry runs the four launches.
- **0019**: the fused split's (0017) kernel contract (`tf-cuda-test kernel-contract "fused form"`): MXFP8 and BF16,
  bf16 and fp32 out, 16 shapes bit-equal to the cluster kernel's K slices, exact sums at k 10,240; its control (a
  1.5x tensor scale posing as the cluster kernel) fails from byte 0, as it must. Image `rq18`, exit 0.

Kernel log, one stream, both existing switches on (image `rq18x`; bf16 KV, 131,072, graphs eager; spark6
`~/work/readout/bench/rk8-*`):

| arm | the read-out's kernels, ms a round | launches a round | in kernels a round |
|---|---|---|---|
| `HC_Q12=1 FUSED_SPLIT=1` | down 4.556 + reduce 0.724 + up 3.904 + mix 0.754 = 9.938 | 1,649.5 | 68.97 ms |
| + `READOUT_FUSE=1` | down with act 4.733 + up with mix 4.303 + 0.094 at other row tiles = 9.130 | 1,420.0 | 68.29 ms |

Served, image `rq18`, one fresh boot a cell, fp8 KV at 262,144 for 1, 2 and 4 streams, `TF_FLASHNEXT_KV_PAGES=4096`
for 6 and 8, aggregate tok/s prose / code (`scripts/qwen38/zig/target/readout/chain18.sh`, spark6
`~/work/readout/chain18.{log,sum}`, 22:21 to 22:47 UTC):

| streams | `HC_Q12=1 FUSED_SPLIT=1` | + `READOUT_FUSE=1` | `READOUT_FUSE=1` alone |
|---:|---|---|---|
| 1 | 61.2 / 82.4 (repeat 62.7 / 82.6) | 61.7 / 81.9 (repeat 62.6 / 82.4) | 62.0 / 82.3 |
| 2 | 88.0 / 122.6 | 87.2 / 122.8 | |
| 4 | 115.6 / 168.2 (115.4 / 167.9) | 114.6 / 167.0 (115.0 / 167.9) | 114.8 / 166.1 |
| 6 | 138.6 / 196.4 | 146.6 / 208.3 | |
| 8 | 161.7 / 237.5 | 164.6 / 241.8 | |

- **Exact.** Golden is 6/6 identical to stock's in all 16 cells, every boot log reads "window self-check: 1176 of
  2080", and every decode reply's sha equals the base arm's: 2, 4, 8, 12 and 16 at 1, 2, 4, 6 and 8 streams, 2 and 8
  for each repeat and for `READOUT_FUSE=1` alone, whose BF16 kernels serve the 1- and 4-stream rows.
- **Speed.** Inside the cell noise at 1, 2 and 4 streams (means of two pairs: +0.3% / -0.4% at one, -0.6% / -0.4%
  at four; -0.9% / +0.2% at two) and +1.8% / +1.8% at eight. The six-stream base cell (138.6 / 196.4) sits 6% under
  the 17-patch run of the same switches (147.7 / 210.7), so that row is not read as a gain.
- **Memory.** 0018 adds none: the boot line's model is 74.31 GiB with and without it from 2 to 8 streams. The pool a
  6- or 8-stream boot takes moved between 154 and 293 pages from cell to cell with the host's free memory (16.1 to
  26.2 GiB left after the reserve), more than the 12-bit copies' own cost of 1.02 GiB (73.29 against 74.31 GiB,
  about 14 pages of 73.75 MiB).
- **Defaults stay off.** 0018 takes 0.81 ms a round of kernel time and 229.5 launches out of a one-stream round but
  shows no served gain outside the noise at 1 to 4 streams. `HC_Q12` cannot flip either: its 1.02 GiB is a capacity
  cost, which counts as a regression.

## The FP4 stack against production (2026-11-14)

Every switch this series measured as no slower, on at once, in one window with the defaults and with production's own
serve. Image `rq18` (0001-0018; 0019 adds only the kernel contract, and no newer series image exists), NVFP4
checkpoint, the recipe's settings, fp8 KV at 262,144, one fresh boot a cell, one decode pass of 512-token prose and
code replies, counters from `/metrics` (`scripts/qwen38/zig/target/int4/fp4stack.sh` through `int4win.sh`,
`fp4stack.py`; spark6 `~/work/fp4stack/win.log` and `bench/`, 09:21 to 10:10 UTC). Order: production at 1, 2, 4, 6
and 8 streams; then at each stream count the defaults, the stack, the stack again and the defaults again; then
production again. The stack, as each cell's `env.txt` shows it reached the container:

    TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_HC_Q12=1 TF_FLASHNEXT_FUSED_SPLIT=1 TF_FLASHNEXT_READOUT_FUSE=1
    TF_FLASHNEXT_SHARED_DRAFTS=0 TF_FLASHNEXT_GREEDY_WIDE=8
    # both arms at 6 and 8 streams: TF_FLASHNEXT_KV_PAGES=4096; TF_FLASHNEXT_CONFIDENCE stays the recipe's -0.4
    # recipe: IMAGE=tensorfold-qwen38:rq18 CHECKPOINT=nvfp4 VISION=0 TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=fp8 \
    #         PARALLEL=<streams> CONTEXT=262144 HOST=127.0.0.1 MEM_CHECK=0 PREPARE=0 ./start.sh restart

Production runs its own launcher (`~/qwen6-start-prod.sh` with `PARALLEL=<streams> HOST=127.0.0.1`) on its own
checkpoint (azampatti INT4-AutoRound, 5 experts a token), through the same decode harness and prompts. Aggregate
tok/s, prose / code; the percentages compare the means of the two runs on each side:

| streams | defaults (repeat) | stack (repeat) | production (again at the end) | stack against production | stack against defaults |
|---:|---|---|---|---|---|
| 1 | 61.8 / 81.9 (61.1 / 80.8) | 63.4 / 84.5 (62.5 / 83.4) | 71.8 / 129.1 (70.2 / 127.2) | -11.3% / -34.5% | +2.4% / +3.2% |
| 2 | 86.0 / 119.8 (86.0 / 120.0) | 90.1 / 125.2 (90.6 / 125.0) | 120.3 / 178.7 (118.8 / 177.9) | -24.4% / -29.8% | +5.1% / +4.3% |
| 4 | 112.5 / 164.1 (112.6 / 164.3) | 117.4 / 168.6 (117.7 / 168.5) | 167.4 / 259.9 (163.7 / 256.0) | -29.0% / -34.7% | +4.4% / +2.6% |
| 6 | 143.7 / 204.1 (143.8 / 204.7) | 150.4 / 208.0 (150.5 / 208.2) | 210.3 / 332.9 (209.3 / 320.0) | -28.3% / -36.3% | +4.7% / +1.8% |
| 8 | 160.0 / 234.4 (160.0 / 234.4) | 168.1 / 240.6 (168.2 / 241.0) | 241.7 / 380.5 (237.8 / 378.3) | -29.9% / -36.5% | +5.1% / +2.7% |

Rounds a 512-token reply takes (each stream's rounds summed), then drafted and accepted tokens a round, prose / code.
Each repeat of ours returned its first run's counters to the digit; production's second runs are within one round:

| streams | defaults | stack | production |
|---:|---|---|---|
| 1 | 142 / 89, 4.02 / 6.98, 2.61 / 4.74 | 145 / 89, 3.91 / 6.97, 2.53 / 4.74 | 186 / 81, 2.67 / 7.43, 1.75 / 5.31 |
| 2 | 334 / 191, 2.95 / 5.69, 2.06 / 4.35 | 317 / 181, 3.33 / 6.30, 2.23 / 4.65 | 355 / 193, 2.65 / 5.73, 1.88 / 4.30 |
| 4 | 736 / 432, 2.61 / 5.04, 1.69 / 3.73 | 686 / 401, 3.01 / 5.82, 1.89 / 4.10 | 738 / 405, 2.45 / 5.20, 1.63 / 4.05 |
| 6 | 1,071 / 666, 2.67 / 4.60, 1.80 / 3.60 | 994 / 590, 3.10 / 6.05, 2.02 / 4.20 | 1,098 / 596, 2.48 / 5.35, 1.70 / 4.14 |
| 8 | 1,457 / 914, 2.55 / 4.43, 1.68 / 3.47 | 1,353 / 808, 2.98 / 5.83, 1.89 / 4.06 | 1,468 / 816, 2.42 / 5.16, 1.62 / 4.01 |

- **Exact.** Every decode reply's sha in both stack runs and in the defaults' repeat equals the first defaults run's
  at the same stream count (2, 4, 8, 12 and 16 replies at 1, 2, 4, 6 and 8 streams); golden is 6/6 identical to the
  defaults' for both stack runs and the repeat (`fp4stack.py`, and `python3 ~/work/zgold_cmp.py`); every boot log of
  ours reads "window self-check: 1176 of 2080".
- **Against the defaults the stack is faster in every cell, outside the repeat spread**: each stack run is above both
  defaults runs in all ten, so no switch had to be dropped. The two defaults runs differ by at most 1.4% at one
  stream and 0.3% at two to eight, the two stack runs by 1.4% and 0.6%; the closest pair is one-stream prose (62.5
  against 61.8). At one stream only the MXFP8 drafter and the three read-out switches act: the code counters are
  unchanged (89 rounds, 422 accepted), so its +3.2% is round time alone, and prose takes 145 rounds against 142 and
  still gains 2.4%. (0014's +3.8% / +7.6% ran bf16 KV at 131,072 on `v16`, where the MXFP8 drafter also cut code
  from 89 rounds to 86.) From two streams `SHARED_DRAFTS=0` cuts the rounds by 5 to 7%, and from six
  `GREEDY_WIDE=8` cuts code's by 11 to 12%.
- **Against production**: -11.3% / -34.5% at one stream, -24.4% / -29.8% at two, -29.0% / -34.7% at four,
  -28.3% / -36.3% at six, -29.9% / -36.5% at eight. Production's second run is slower than its first in every cell,
  by 0.4% to 3.9% (six-stream code 332.9 then 320.0 on the same 596 rounds), where ours repeat within 1.4%. On this
  harness production also runs faster than its target table (`production/SPEED-TARGET.md`, 70.9 / 113.0 at one
  stream to 237.1 / 370.5 at eight), most at one-stream code (128.2 here against 113.0) and two-stream prose (119.6
  against 103.3), so measured like for like the gap is wider than the earlier tables against that target showed.
  Production's prose replies at 4, 6 and 8 streams come to 1,938, 2,962 and 3,843 tokens (a stream ends before
  512); ours are 512 a stream.
- **Memory.** The stack's model is 74.23 GiB against the defaults' 73.29 at 2 to 8 streams (76.87 against 75.93 at
  one): 0.94 GiB, which is the 12-bit copies' 1.02 GiB (74.31 with `HC_Q12=1 FUSED_SPLIT=1` in the 0016 to 0018
  runs) less what the MXFP8 drafter linears save (181.1 MB of BF16 against about 93 MB). The budget left after the
  9.0 GiB reserve falls from 27.2 or 27.3 GiB to 26.2 or 26.3 (24.5 to 23.4 or 23.5 at one stream). At 1 to 4
  streams no pool is used and every boot serves the streams asked for. At 6 and 8 streams every stack boot's pool
  takes 294 pages of 4096 rows (21.17 GiB) against 308 (22.18 GiB) in every defaults boot: 14 pages, 57,344
  positions (4.5%) fewer, and both still boot at 262,144 with `KV_PAGES=4096` ("8 streams at once, the engine's own
  at a 262144-token window (5.04 GiB, in the model's), 7 more taking 294 pages of 4096 rows (21.17 GiB) as they need
  them, 0 MiB fixed each, of 26.3 GiB left after a 9.0 GiB reserve").
- **The stack does not keep the draft setting's code gain at six and eight streams.** `SHARED_DRAFTS=0
  GREEDY_WIDE=8` alone, same image and settings, in four runs over three windows (`bench-fp4b`, `bench-fp4c`,
  `bench-fp4p`, above): six streams 146.9 to 147.6 / 212.2 to 214.1, eight 162.6 to 163.3 / 246.0 to 247.0. The
  stack: 150.4 to 150.5 / 208.0 to 208.2 and 168.1 to 168.2 / 240.6 to 241.0, so prose +2.3% and +3.3% and code
  -2.3% at both against those runs' means. The defaults reproduce across those windows within 0.7% (143.7 / 204.1
  and 143.8 / 204.7 here against 143.5 / 204.6, 144.2 / 205.5 and 143.9 / 205.4; 160.0 / 234.4 twice against
  160.5 / 234.6, 160.0 / 233.8 and 160.7 / 234.5). The stack's code takes 590 and 808 rounds against 578 and 803, so
  the MXFP8 drafter's proposals account for at most 2.1% at six and 0.6% at eight; the rest is round time on code's
  longer rounds.
