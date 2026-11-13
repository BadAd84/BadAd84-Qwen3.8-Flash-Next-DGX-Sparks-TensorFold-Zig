# TensorFold 1.2.7 patch series (our levers)

The TensorFold tree stays pristine at upstream v1.2.7 (`93a2e93ecebff8aa52b88e58c5dd222516e69c5f`) and every change
we own is one numbered patch here, one lever a patch, applied in filename order. Each patch builds on the ones
before it and on nothing after it: the tree compiles after every one of the 13.

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
`production/SPEED-TARGET.md` on the `production` branch, measured at 262,144 tokens; fp8 and bf16 KV decode the
same on this box, so the two are comparable.

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
- The gap widens with streams (-13% at one prose stream, -31% at eight): the cost production saves a round grows with
  the rows verified, which points at per-row work (experts, dense projections and glue at 5 to 8 rows a stream), not at
  a fixed cost such as the drafter's weights alone.
- There is no patch 0015 for the expert path (2026-11-13): measured by expert id, every unique expert is read once a
  layer a round, our decode expert kernels stream at 195 to 222 GB a second (faster than production's at equal rows),
  and the 2.35 times the expert bytes a round at one stream is production's checkpoint routing 5 experts a token
  against our 10. `docs/CATCHUP-1.2.6.md`, "The decode round's expert traffic, measured by expert id".

## Draft-policy settings on this base, measured (2026-11-13)

Everything here is exact by construction - a draft is a proposal the verify forward checks - so the question is
only speed. Image `v16` (the series with 0014 on), bf16 KV, a 131,072-token window, one fresh boot a cell, 512-token
prose and code replies; counters are the engine's own `/metrics` (`~/work/target/bench/{cc,pr1,pr4,cp,gw,gf}-*`).

**The round's price (0010's `TF_FLASHNEXT_ROUND_MS` and `DRAFT_ROW_MS`) is inert on this workload.** A round costs
38 ms plus 3.75 ms a row on prose and 38 plus 3.85 on code, straight to 15 rows, so the price is `38+2.15` with
`DRAFT_ROW_MS=1.6` once the drafter's own 1.58 ms a row is taken out. Priced, the engine keeps exactly the same
drafts: one stream 61.18 / 80.50 against 61.48 / 81.61 and 61.16 / 81.25 unpriced with identical counters; four
streams 113.6 / 166.8 against 113.1 / 166.7 and 112.4 / 166.3, 1,853 drafts against 1,861. A steeper line (`38+3.0`)
and a flatter one (`38+1.5`) give the same 1,853.

**Our `TF_FLASHNEXT_CONFIDENCE=-0.4` default is the best of four.** At one stream: -0.15 gives 57.97 / 79.31,
-0.25 gives 61.01 / 80.11, -0.6 gives 59.22 / 82.71, against 61.48 / 81.61. Production runs -0.15, which costs 6%
on prose here.

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
| 6 | 146.8 / 205.6 (repeat 147.5 / 206.2) | 146.1 / **218.2** | 662 -> 612 rounds, 2,404 -> 2,454 accepted |
| 8 | 164.8 / 235.9 | 163.0 / **247.8** | 918 -> 866 rounds, 3,171 -> 3,222 accepted |

Code gains 5.9% at six streams and 5.0% at eight by accepting more over fewer rounds; prose pays 0.5 to 1.1% at
those widths and nothing measurable below them, where the counters are identical to the digit. Golden is 6/6
identical to stock's at one stream with the knob on and off, and every boot log reads "window self-check: 1176 of
2080". It is therefore exact but **not a default**: the rule for this series is no regression at any stream count,
and the six and eight stream prose cells regress. It is recorded here as a setting for a code-heavy multi-stream
serve, for the owner to take or leave.

