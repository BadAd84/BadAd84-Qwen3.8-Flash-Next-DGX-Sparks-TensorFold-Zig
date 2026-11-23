# Dev against production, now that INT4 runs: both at production's served shape, one window (spark6)

Status: the window ran on spark6 on 2026-11-22 inside one hold of `~/work/gpu.lock`. Every number below is parsed from
that window's own run files by `analyze_devvsprod.py` (frame 1) or from the recorded files it names (frame 2). A cell
with no run file is written not-taken; a cell with one run a side is indicative.

Window identity: one hold of `~/work/gpu.lock`, queued 2026-11-22T20:03:35+00:00 behind the `KvTierW2` lane, taken
20:12:50, `RUN-DONE 21:16:28 elapsed 63 min`, driver `window.sh` sha256 `80385ca8f07b6941...`, exit 0. Host kernel
`7.0.0-1019-nvidia-64k`, Ubuntu 24.04.5, NVIDIA GB10 driver 580.178.04, 123 GiB RAM. The follow-up `depth.sh` (the
depth-15 pair and the warm cell) queues behind the same lock; its state is stated where its cells appear.

Now that INT4 runs on our engine at production's own serving shape (8 slots, a 262,144-token stream window, fp8 KV,
production's 54-name environment, plus 0015's page pool so the shape fits our admission), decode is level to slightly
behind on code and about 0.8 on prose: at 1, 2, 4, 6 and 8 streams our code cells read 96.0, 156.1, 272.7, 351.9 and
419.6 tokens a second against production's 92.6, 149.5, 272.3, 359.3 and 440.1 (ratios 1.04, 1.04, 1.00, 0.98, 0.95),
and our prose cells read 69.1, 115.8, 203.0, 268.8 and 322.0 against 86.3, 153.2, 242.4, 331.1 and 407.1 (0.80,
0.76, 0.84, 0.81, 0.79), a geometric mean of 0.895 over the ten cells, with our four boots repeating within 0.6
percent and production's three shots within 1 percent except its 2- and 4-stream code cells (21 and 11 percent, which
is why those two verdicts are level). Cold prefill is level at 1k (0.473 against 0.445 s) and 19 to 22 percent slower
at 8k and 32k (3.178 against 2.675, 13.063 against 10.674 s); the warm turn on a kept 100k conversation is measured on
production only (1.123 s), because the 4096-page pool leaves no prompt cache and the smaller-pool boot that would
measure ours did not get the lock in this run. The campaign frame's 0.64 at eight streams is therefore mostly the
shape it was measured in (4 x 131,072 bf16 and 8 x 32,768 bf16 against production's 8 x 262,144 fp8), not the INT4
engine: at production's shape the same build reads 0.79 on prose and 0.95 on code at eight streams, and the remaining
prose gap is in the rounds (our chat reply runs 85 rounds of 3.01 tokens at 43 ms against the code reply's 54 rounds
of 4.72 at 49 ms), not in prefill.

## 1. What ran, and the deviations that made it like for like

| arm | checkpoint | engine | image | shape it booted with |
|---|---|---|---|---|
| `P1`, `P2`, `P3` | `azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound` @ `14642741` | its own launcher, `~/qwen6-start-prod.sh` | `tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7` `sha256:235211ea77ee...` | 8 at once, 262144 per stream, fp8 KV, vision on, its own 54 `TF_`/`TENSORFOLD_` names |
| `D1a`, `D1b`, `D2a`, `D2b` | the same | our r5 + INT4 package | `tensorfold-qwen38:qr-b-r5int4-1ece6e6d` `sha256:578911ca84d4...`, `tf.tree.manifest` `ab6389fc2ab6...`, `tf.source` `1ece6e6db...+r5-0001-0020+int4-0021-0022` | 8 at once, 262144 per stream, fp8 KV, vision on, production's 54 names plus `TF_FLASHNEXT_KV_PAGES=4096` |

Order: `P1` (production live), `D1a`, `D1b`, `P2` (production booted from its own launcher, shot, stopped), `D2a`,
`D2b`, `P3` (the restore boot, shot). Each shot ran `bench_openai` (256 greedy tokens, 3 reps), `bench_concurrent`
(1, 2, 4, 6 and 8 streams, prose and code, 256 greedy tokens, 3 reps, `--alone --serial`) and `ttft.py` (cold 1k, 8k
and 32k thinking off at idle, 3 reps, plus the warm 2k turn after a kept 100k conversation, 2 reps).

Three decisions, each checkable:

- **The dev tree is `patches/main-1ece6e6db-r5` plus `patches/main-1ece6e6db-r5-int4`** (the image above, reused, not
  rebuilt). Not `patches/main-1ece6e6db-r5-kvtier`: that package is r5 plus `0021-kv-tier-fp8.patch` only, with no
  INT4 port, and the base engine refuses the INT4 checkpoint by name (`num_experts_per_tok`), so it cannot serve
  production's checkpoint. The KV tier is also a lever production does not run.
- **Vision could not be honoured.** Our image passed `--vision` and its banner says `vision on`, but its log carries
  only the JPEG/WebP decoder warnings and no `[vision-helper] ready` line, no tower and none of production's `2.00 GiB
  kept free for the image tower's workspace`, so the arm served text only with no tower reserve (about 2 GiB more KV
  budget than production). Text cells do not use the tower, so the cells stand; the deviation is named and it is an
  image gap, not a flag.
- **`TF_FLASHNEXT_KV_PAGES=4096` is the one added setting.** Our r5 admission prices a stream at 18,880 bytes a token
  (the 12 attention layers plus the draft head's bf16 layer and the prompt scratch) where production's build prices
  only the 12 layers (1,056 bytes a position a layer); eight dense streams therefore demand 40.56 GiB against a
  29.23 GiB budget and the boot is refused. The page pool is 0015's own capacity switch and serves the same shape.
  The one environment value that differs from production's is `TENSORFOLD_CUDA_KERNELS=native` (production's names a
  prebuilt directory in its own image); the per-boot env audit allows exactly that pair and nothing else.

### Per-boot readback

The dev rows' `ENVAUDIT FAIL ... extra 16` is our recipe's own lever defaults, not drift; section 2 explains it.

| arm | image (tag, id short) | boot wall | banner | pool | env audit |
|---|---|---|---|---|---|
| P1 | `tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7` `235211ea77ee` | - | - | "max_batch_size": 8 | ENVAUDIT ok expected 54 read 54 match 54 allow 0 mismatch 0 missing 0 extra 0 |
| P2 | `tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7` `235211ea77ee` | - | - | "max_batch_size": 8 | ENVAUDIT ok expected 54 read 54 match 54 allow 0 mismatch 0 missing 0 extra 0 |
| P3 | `tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7` `235211ea77ee` | - | - | "max_batch_size": 8 | ENVAUDIT ok expected 54 read 54 match 54 allow 0 mismatch 0 missing 0 extra 0 |
| D1a | `tensorfold-qwen38:qr-b-r5int4-1ece6e6d` `578911ca84d4` | wall_s 148.7 | azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound · 8 at once · 262144-token window · fp8 KV · vision on · drafts MTP · port 8080 | "max_batch_size": 8 | ENVAUDIT FAIL expected 55 read 71 match 54 allow 1 mismatch 0 missing 0 extra 16 |
| D1b | `tensorfold-qwen38:qr-b-r5int4-1ece6e6d` `578911ca84d4` | wall_s 145.7 | azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound · 8 at once · 262144-token window · fp8 KV · vision on · drafts MTP · port 8080 | "max_batch_size": 8 | ENVAUDIT FAIL expected 55 read 71 match 54 allow 1 mismatch 0 missing 0 extra 16 |
| D2a | `tensorfold-qwen38:qr-b-r5int4-1ece6e6d` `578911ca84d4` | wall_s 145.7 | azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound · 8 at once · 262144-token window · fp8 KV · vision on · drafts MTP · port 8080 | "max_batch_size": 8 | ENVAUDIT FAIL expected 55 read 71 match 54 allow 1 mismatch 0 missing 0 extra 16 |
| D2b | `tensorfold-qwen38:qr-b-r5int4-1ece6e6d` `578911ca84d4` | wall_s 151.7 | azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound · 8 at once · 262144-token window · fp8 KV · vision on · drafts MTP · port 8080 | "max_batch_size": 8 | ENVAUDIT FAIL expected 55 read 71 match 54 allow 1 mismatch 0 missing 0 extra 16 |

The planner lines each boot printed (the pool, the cache and the draft head):

```
- P1: `sequence memory: 24.84 GiB (36.84 GiB free, 10.0 GiB kept free); fp8 KV cache, 1056 bytes a position a layer`
- P1: `prompt cache: whole-prompt states from 1024 tokens (that very prompt again resumes with no prompt pass)`
- P2: `sequence memory: 23.89 GiB (35.89 GiB free, 10.0 GiB kept free); fp8 KV cache, 1056 bytes a position a layer`
- P2: `prompt cache: whole-prompt states from 1024 tokens (that very prompt again resumes with no prompt pass)`
- P3: `sequence memory: 25.55 GiB (37.55 GiB free, 10.0 GiB kept free); fp8 KV cache, 1056 bytes a position a layer`
- P3: `prompt cache: whole-prompt states from 1024 tokens (that very prompt again resumes with no prompt pass)`
- D1a: `8 streams at once, the engine's own at a 262144-token window (5.07 GiB, in the model's), 7 more taking 327 pages of 4096 rows (23.55 GiB) as they need them, 84 MiB fixed each, of 29.2 GiB left after a 10.0 GiB reserve; prompts in passes of up to 3072 rows, no prompt cache; own glue kernels`
- D1a: `KV page groups: one page 73.75 MiB, 4096 rows of the full group; full: layers not named, 18.44 KiB a token, 4096 rows a page, 0 B padding (0.0 %); state run, in the pool: 387.39 MiB on 6 pages, 55.11 MiB padding (12.5 %); snapshot, outside the pool: 110.29 MiB on 2 pages, 37.21 MiB padding (25.2 %)`
- D1b: `8 streams at once, the engine's own at a 262144-token window (5.07 GiB, in the model's), 7 more taking 327 pages of 4096 rows (23.55 GiB) as they need them, 84 MiB fixed each, of 29.2 GiB left after a 10.0 GiB reserve; prompts in passes of up to 3072 rows, no prompt cache; own glue kernels`
- D1b: `KV page groups: one page 73.75 MiB, 4096 rows of the full group; full: layers not named, 18.44 KiB a token, 4096 rows a page, 0 B padding (0.0 %); state run, in the pool: 387.39 MiB on 6 pages, 55.11 MiB padding (12.5 %); snapshot, outside the pool: 110.29 MiB on 2 pages, 37.21 MiB padding (25.2 %)`
- D2a: `8 streams at once, the engine's own at a 262144-token window (5.07 GiB, in the model's), 7 more taking 327 pages of 4096 rows (23.55 GiB) as they need them, 84 MiB fixed each, of 29.2 GiB left after a 10.0 GiB reserve; prompts in passes of up to 3072 rows, no prompt cache; own glue kernels`
- D2a: `KV page groups: one page 73.75 MiB, 4096 rows of the full group; full: layers not named, 18.44 KiB a token, 4096 rows a page, 0 B padding (0.0 %); state run, in the pool: 387.39 MiB on 6 pages, 55.11 MiB padding (12.5 %); snapshot, outside the pool: 110.29 MiB on 2 pages, 37.21 MiB padding (25.2 %)`
- D2b: `8 streams at once, the engine's own at a 262144-token window (5.07 GiB, in the model's), 7 more taking 327 pages of 4096 rows (23.55 GiB) as they need them, 84 MiB fixed each, of 29.2 GiB left after a 10.0 GiB reserve; prompts in passes of up to 3072 rows, no prompt cache; own glue kernels`
- D2b: `KV page groups: one page 73.75 MiB, 4096 rows of the full group; full: layers not named, 18.44 KiB a token, 4096 rows a page, 0 B padding (0.0 %); state run, in the pool: 387.39 MiB on 6 pages, 55.11 MiB padding (12.5 %); snapshot, outside the pool: 110.29 MiB on 2 pages, 37.21 MiB padding (25.2 %)`
```


## 2. Why production's shape needed patch 0015's pool on our build

Production's own restore boot says `info: sequence memory: 25.31 GiB (37.31 GiB free, 10.0 GiB kept free); fp8 KV
cache, 1056 bytes a position a layer` and serves 8 at once at a 262,144-token window: eight times 262,144 positions
times 12 layers times 1,056 bytes is 24.7 GiB, so its planner charges the sequence and nothing else a stream (3.06
GiB a stream, or 12,672 bytes a token). This window's three production boots planned 24.84, 23.89 and 25.55 GiB by
the same rule.

Our plan's own price for the same shape is 5.07 GiB a stream (20,760 bytes a token: the 18,880 the page table records,
which includes the draft head's bf16 layer and the prompt scratch, plus 1,880 more), and eight of those are the 40.56
GiB the refusal quotes. The page pool pays for seven streams out of a shared 23.55 GiB and keeps one dense stream
beside them.

Our r5 build's refusal at the same shape, from the earlier attempt's `~/work/QRerun/out/PS/boot.log`
(2026-11-22T18:07Z), verbatim:

```
tensorfold: --parallel 8 needs 40.56 GiB for its streams at a 262144-token window, and the CUDA memory budget leaves 29.23 GiB: serve --parallel 5, or lower --context
```

`patches/1.2.7/README.md` records the same price (`40.31 GiB`) for the older series and the pool as its fix: with
`TF_FLASHNEXT_KV_PAGES=4096` six and eight streams boot at 262,144 with fp8 KV, the lanes sharing 308 pages of 4,096
rows, and every decode reply's sha identical to the unpaged boot at 1, 2 and 4 streams. This window's dev arm is that
arrangement on the r5 base: the served shape is production's, and the pool is how our build pays for it.

The dev arms' audit reads `FAIL ... extra 16` because our recipe exports sixteen lever defaults of our own engine
that production's build does not have at all: `TF_FLASHNEXT_DRAFT_AHEAD=1`, `GATHER_EARLY=1`, `GATHER_READ=pread`,
`GDN_LANES=1`, `HEAD_PIECE=1536`, `HOST_DRAW_THREADS=7`, `KEEP_LATE=1`, `PROMPT_EXPERT_TILE_ROWS=256`,
`PROMPT_GEMM2=1`, `PROMPT_HC2=1`, `PROMPT_SHARED_DIRECT=1`, `SAMPLED_HEADS=1`, `SAMPLE_CAND=1`, `SHARED_SIDE=1`,
`WARM_AHEAD=1` and `DRAFTS=6`. Production's own 54 names all match on every dev boot (54 of 54), so the environment's
only differences are those sixteen and the one allowed value `TENSORFOLD_CUDA_KERNELS=native` (production names a
prebuilt directory that our image also carries; the recipe's own value for our image is `native`). The 2026-11-19
like-for-like INT4 window ran the same arrangement, its own note calling the arm "the recipe's settings plus" its
draft block.


## 3. Frame 1, like for like: decode at production's served shape

Both arms boot 8 slots at a 262,144-token stream window with fp8 KV, vision on and drafts on. A cell is 256 greedy
tokens a request, 3 reps, all streams started together; the aggregate figure is the completion tokens over the
batch's own wall time and the per-stream figure after the semicolon is the median of the requests' own rates
((tokens - 1) / (elapsed - ttft)), both as `bench_concurrent.py` computes them. Every boot of each arm is shown.
Production's three shots are its live serve, a boot of its own launcher, and the restore boot; our four boots are
two pairs. The verdict is the maintainer's noise rule over the ten cells (both runs of one arm under both of the
other and a mean gap past one percent).

Our arm runs the drafts block the recipe configures for this engine: `TF_FLASHNEXT_DRAFTS=6` (sampled) and the
engine's greedy default of 8. Production's own name for that lever is `TF_FLASHNEXT_DEPTH=15`, which our tree does
not read; the panel row below measures the depth-15 setting separately in our engine's names.

### chat

| streams | P (P1 / P2 / P3) | D (D1a / D1b / D2a / D2b) | dev mean / P mean | verdict |
|---:|---|---|---:|---|
| 1 | 86.6;86.6 / 85.8;85.8 / 86.5;86.5 | 69.0;69.0 / 69.3;69.3 / 69.0;69.0 / 69.1;69.1 | 86.3 / 69.1 | slower -19.9% |
| 2 | 158.9;79.4 / 142.5;72.4 / 158.3;79.1 | 115.9;58.3 / 116.1;58.7 / 115.4;58.1 / 115.6;58.3 | 153.2 / 115.8 | slower -24.5% |
| 4 | 243.7;62.8 / 241.1;62.1 / 242.3;62.4 | 203.6;52.0 / 203.6;52.0 / 202.4;51.8 / 202.5;51.8 | 242.4 / 203.0 | slower -16.2% |
| 6 | 331.6;57.2 / 330.6;56.8 / 331.0;57.0 | 269.8;46.5 / 269.1;46.4 / 267.8;46.2 / 268.3;46.2 | 331.1 / 268.8 | slower -18.8% |
| 8 | 406.8;52.7 / 407.0;52.5 / 407.6;52.7 | 323.1;42.2 / 322.1;42.1 / 321.4;42.0 / 321.5;42.0 | 407.1 / 322.0 | slower -20.9% |

### code

| streams | P (P1 / P2 / P3) | D (D1a / D1b / D2a / D2b) | dev mean / P mean | verdict |
|---:|---|---|---:|---|
| 1 | 92.9;92.9 / 92.1;92.1 / 92.7;92.7 | 96.2;96.2 / 95.9;95.9 / 96.0;96.0 / 95.8;95.8 | 92.6 / 96.0 | faster +3.7% |
| 2 | 163.6;82.9 / 142.5;73.0 / 142.4;72.3 | 156.7;78.8 / 156.5;78.8 / 155.2;78.2 / 155.9;78.6 | 149.5 / 156.1 | level +4.4% |
| 4 | 263.6;67.5 / 291.0;74.0 / 262.3;67.2 | 273.4;69.8 / 273.4;69.8 / 272.4;69.6 / 271.7;69.5 | 272.3 / 272.7 | level +0.2% |
| 6 | 360.7;61.7 / 358.3;61.2 / 358.9;61.4 | 353.0;60.6 / 351.3;60.4 / 351.2;60.4 / 352.3;60.5 | 359.3 / 351.9 | slower -2.0% |
| 8 | 442.0;56.7 / 439.0;56.3 / 439.3;56.4 | 420.3;54.6 / 419.4;54.5 / 420.3;54.7 / 418.3;54.4 | 440.1 / 419.6 | slower -4.7% |

Noise rule over the ten cells (dev against production): faster 1, slower 7, level 2, indicative 0, not-taken 0.

Cell source: each figure is that arm's own `out/<arm>/conc_t0.json` field `aggregate_tps` (and
`per_stream_tps` after the semicolon), and the solo row is `out/<arm>/openai_t0.json`'s `decode_tps_median`.

1-stream solo (bench_openai decode_tps_median, one request at a time):

| arm | chat | code |
|---|---:|---:|
| P1 | 85.9 | 93.3 |
| P2 | 85.2 | 92.2 |
| P3 | 85.6 | 92.8 |
| D1a | 69.2 | 96.3 |
| D1b | 69.2 | 96.5 |
| D2a | 68.7 | 96.0 |
| D2b | 69.0 | 96.1 |

The engines' own draft counters, from `/metrics` before and after each probe:

| arm | 1-stream cell drafted / accepted | the ten decode cells drafted / accepted | acceptance |
|---|---:|---:|---:|
| P1, P3 | 1,964 / 1,460 | 31,085 / 23,356 and 31,039 / 23,310 | 75.1% |
| P2 | 2,531 / 1,662 | 31,106 / 23,348 | 75.1% |
| D1a, D1b, D2a, D2b | 2,080 / 1,488 | 25,186 / 21,506, identical on all four boots | 85.4% |

Our arm is counter-identical across its four boots, which is why its cells repeat to 0.6 percent; it drafts 19 percent
fewer tokens than production over the ten cells, accepts a ten-point higher fraction, and pays for it in the rounds.
The server's own `done` lines for our 1-stream replies say where the split is: the chat reply (`sha e4cb0b3b74d7`)
runs 85 rounds verifying 261 drafts (3.07 a round) and accepting 171, which is 3.01 tokens a round at 43.2 to 45.9 ms
a round, while the code reply (`sha d6382fff1e9f`) runs 54 rounds verifying 259 drafts (4.80 a round) and accepting
201, which is 4.72 tokens a round at 48.9 to 52.6 ms a round. A prose token therefore buys fewer tokens a round and
its rounds are cheaper, so the cell lands at 69 against the code's 96. Production logs no per-request round line on
this image, so the same split on its side is unmeasured rather than absent.

### The drafts depth production runs, in our engine's names

Production's launcher sets `TF_FLASHNEXT_DEPTH=15`; our tree does not read that name. Its lever is
`TF_FLASHNEXT_DRAFTS` (sampled, recipe default 6) and `TF_FLASHNEXT_DRAFTS_GREEDY` (greedy, engine default 8), and the
recipe honours an outer value for either. The pair below boots the same image and the same environment with both at
15, which is the closest our engine can come to production's block, and measures the same ten cells against the same
production shots.

The depth-15 pair is **not-taken in this run**. Its driver (`work/DevVsProd/depth.sh`, staged and verified on the box)
was queued for `~/work/gpu.lock` at 21:17 and waited behind the `KvTierW2` lane's second window for the rest of this
session; it was cancelled before it took the lock (queued `flock` pid 499437 killed at 2026-11-22T21:45:48+00:00, its
`out/depth.log` one line long), so nothing of that lane's work was disturbed. The cells above are therefore at our
recipe's own depth (`TF_FLASHNEXT_DRAFTS=6`, greedy 8), which is the one production drafter setting this table does
not honour; `TF_FLASHNEXT_DEPTH=15` is production's name for the lever and our tree has no reader for that name.



## 4. Frame 1: cold TTFT (thinking off, idle) and the warm turn on a kept 100k conversation

Median seconds from each run's own ttft summary line; the arm value is the mean of its runs' medians. The cold cells
are the four D boots at the 4096-page pool, which leaves no prompt cache on this budget ("no prompt cache" in the
plan line), so every cold prefill is genuinely cold. The warm cell needs the cache, so it comes from the separate
`DW` boot (192 pages, 786,432 positions) against production's three shots.

| case | P medians (P1 / P2 / P3) | P mean | dev medians | dev mean | dev/P | verdict |
|---|---|---:|---|---:|---:|---|
| cold1k-off | 0.419 / 0.415 / 0.500 | 0.445 | 0.473 / 0.480 / 0.462 / 0.477 | 0.473 | 1.06 | level +6.4% |
| cold8k-off | 2.680 / 2.705 / 2.641 | 2.675 | 3.175 / 3.160 / 3.204 / 3.171 | 3.178 | 1.19 | slower +18.8% |
| cold32k-off | 10.700 / 10.711 / 10.610 | 10.674 | 13.046 / 13.074 / 13.065 / 13.066 | 13.063 | 1.22 | slower +22.4% |
| warm2k | 1.254 / 1.074 / 1.041 | 1.123 | - | - | - | not-taken |

Cell source: each figure is that arm's own `out/<arm>/ttft.out` `summary <case> idle ... ttft med` line.

Excluded samples (a cell whose every sample was flagged is unmeasured):

- P1: none
- P2: none
- P3: none
- D1a: warm2k: n 0 excluded 3
- D1b: warm2k: n 0 excluded 3
- D2a: warm2k: n 0 excluded 3
- D2b: warm2k: n 0 excluded 3
- DC: none
- DW: none

Production's own warm turn is 1.254, 1.074 and 1.041 s (mean 1.123 s) on its 6.2 GiB prompt cache; the `DW` boot for
ours is **not-taken in this run**: the `DW` boot (192 pages, 786,432 positions, which leaves room for the prompt cache) was
part of the same queued driver and was cancelled with it, so the warm turn is unmeasured for our arm. The cold cells
above do not depend on it.


## 5. Frame 2, the campaign-shape frame our other tables quote (cross-shape, cross-day, cross-harness)

Ours: `work/QInt4/box/speed.json` arm B, the same INT4 image, 4 slots at 131,072 with bf16 KV for 1 and 4 streams and
8 slots at 32,768 with bf16 KV for 8, 512-token greedy replies. Production: `work/SyncBench/box/out/window/P1` and
`P9` `conc_t0.json`, its own serve, 256-token greedy replies.

| streams | kind | ours per-stream / aggregate | production per-stream / aggregate | ours / production |
|---:|---|---:|---:|---:|
| 1 | prose | 70.71 / 70.7 | 87.55 / 87.5 | 0.81 |
| 1 | code | 114.97 / 115.0 | 94.05 / 94.0 | 1.22 |
| 4 | prose | 39.17 / 155.2 | 62.20 / 245.8 | 0.63 |
| 4 | code | 61.57 / 241.2 | 72.35 / 281.9 | 0.86 |
| 8 | prose | 26.63 / 216.9 | 53.25 / 412.5 | 0.53 |
| 8 | code | 41.87 / 329.7 | 57.35 / 447.0 | 0.74 |

Cell source: an ours figure is `work/QInt4/box/speed.json`'s entry at that stream count and kind, field
`B.per_stream_mean` and `B.aggregate_mean` (the mean of that arm's two boots); a production figure is the mean of the
`P1` and `P9` `conc_t0.json` cells at that stream count, prompt `chat` for prose and `code` for code, fields
`per_stream_tps` and `aggregate_tps`. The summary table's ours column is the mean of the prose and code
`aggregate_mean`s; its production column is the mean of the four cells (two shots, two kinds) at that stream count.

The summary those tables quote (ours is the mean of the prose and code aggregates, production the mean of its four
shots at that stream count):

| streams | ours | production | ratio |
|---:|---:|---:|---:|
| 1 | 92.8 | 90.8 | 1.02 |
| 4 | 198.2 | 263.9 | 0.75 |
| 8 | 273.3 | 429.7 | 0.64 |

(`work/QInt4`'s and the brief's 264.0 and 429.8 are the same quantities to their rounding; these are computed from
the same files by this window's script.)

This frame is cross-shape (4 x 131,072 bf16 and 8 x 32,768 bf16 against 8 x 262,144 fp8), cross-day (both sides are
2026-11-21 and 11-22 recordings, not this window) and cross-harness (512-token cells against 256-token cells). It is
here for continuity with `work/QInt4/RESULT.md` and `work/SyncBench/SUMMARY.md`, not as the answer.

Its production side is not fully repeatable: across its own two shots (P1 and P9) every chat cell and code at 1, 6 and
8 streams agree within 0.5 percent, but code at 2 streams reads 175.7 against 144.9 (21.3 percent) and code at 4 reads
267.4 against 296.3 (10.8 percent). The 0.64 at 8 streams and 1.02 at 1 stream are stable numbers; the 0.75 at 4
streams rides a production cell whose two shots differ by 10.8 percent.

## 6. Production restored, and the lock

- Before `P2`: `[2026-11-22T20:41:39+00:00] RESTORE prod_rc 0 /health 200 image
  tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 sha256:235211ea77ee4ed0e61c4c2e73746ed17eccfb6b9e7571eb0787802440f8a33f`
  and `PROD-IMAGE ok` on the same line's image.
- Before `P3` (the restore boot): `[2026-11-22T21:12:19+00:00] RESTORE prod_rc 0 /health 200 image
  tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 sha256:235211ea77ee...` and `PROD-IMAGE ok`.
- Window end: `[2026-11-22T21:16:28+00:00] RUN-DONE ... elapsed 63 min` and `EXIT-DONE ... health 200 image
  tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 sha256:235211ea77ee...`; the fetched `health-restored.json` and
  `restored-container.txt` are from that state.
- The lock was released at that point and the queued `KvTierW2` lane took it immediately (its own `flock` pid
  4120352). Its window then stopped the serve and put its `kv-w1` image up, so a later read of `:8888` returns 000 by
  that lane's design, not because of this window. The state this window left is the one quoted above.
- `FOREIGN-SUMMARY D1a=0 D1b=0 D2a=0 D2b=0 P1=1961 P2=2359 P3=1916`: our arms are loopback-bound and logged no
  external request. The production figures are cumulative counts of non-loopback request lines across the window and
  comprise sparkDash's `GET` polls from `192.168.99.111` and two `POST /v1/chat/completions` from `192.168.1.242`
  that arrived before P2's probes started (see `NOTES.md` section 6). They are not a count of requests inside a
  measured cell.


## 7. What this window does not measure

- Our dev arm's drafted-equals-plain exactness under **production's** drafter block (`TF_FLASHNEXT_DRAFT_INT4=1` with
  the `mtp-fp8` overlay): the QInt4 window proved that on the campaign block (`MTP_WEIGHTS=mxfp8`, 20 of 20 prompts)
  and its decode cells, not on this block. A speed cell does not depend on it (the verifier decides every token), so
  the cells stand; the exactness of this block is a further capture.
- One prompt pair a kind (the harness's own prose and code prompts), 256-token greedy replies, 1,000- to 32,000-token
  prompts: not the owner's 100k-to-650k agent traffic, and not a long-context decode sweep.
- Image and video inputs: our image's vision helper does not come up (section 1), so no cell exercised them on either
  arm; the tower's 0.84 GiB and its 2 GiB workspace are in production's memory only.
- Thinking off is *requested* on both sides and *verified* on ours only: `bench_openai`'s chat row reads
  `off requested (unverified)` on production and `off` on our arm because the harness could not discover the switch
  on production's build, while both requests carried `chat_template_kwargs {"enable_thinking": false}`. Production's
  own boot line documents that kwarg, so the request is honoured by design; it is the harness's label that differs.
- The warm turn is one kept 100k conversation with a 2k addition, idle; the loaded variant of that cell is not taken.
- Production's 1- and 2-stream cells run on its 8-slot serve (its serving shape) on both arms; the 2026-11-19 window
  instead booted production with `PARALLEL` equal to the cell's stream count.

## 8. What this window's own instruments did

Four defects of the harness, recorded because the next window will hit them:

- **A production shot dumps its log before its probes.** `prod_shot` reads `docker logs` in its plan step, so the
  fetched `server.log` for P1, P2 and P3 holds the boot and the traffic before the probes, not the probe window. The
  dev arms re-dump after their probes. Capturing a production arm's probe-window log needs a second dump at the end
  of the shot, and the container name is shared with the next lane, so it must be fetched before the window's close
  (this window's P3 container was replaced by the queued lane's serve within a minute of the lock handover).
- **The `foreign` counter sums cumulative counts.** `gets()` reports the server's running total of non-loopback
  request lines, and `FOREIGN-SUMMARY` adds those totals across probes, so the production figures (1961, 2359, 1916)
  are not counts of requests. The honest statement is per arm and needs the distinct request lines: our arms 0,
  production's a mix of sparkDash's GET polls and two external chat completions before P2's probes.
- **The 4096-page pool leaves no prompt cache**, by design of the budget order: 5.07 GiB own stream plus 23.55 GiB of
  pages against 29.2 GiB leaves nothing for the whole-prompt cache, so the warm cell of the main arms is
  `n 0 excluded 3`. The warm cell therefore needs its own boot with a smaller pool (`DW`, 192 pages), which is what
  the follow-up runs.
- **The environment audit's `extra` count is our recipe, not drift**: every dev boot reports sixteen lever defaults of
  our own engine that production's build cannot set (listed in section 1), and the same 54 production names match on
  every dev boot.

## 9. Where every number comes from

| claim | source |
|---|---|
| arm identity, image ids, manifests | `out/<arm>/image-id.txt`, `out/<arm>/model.txt`, the preflight lines in `out/run.log`, `work/DevVsProd/in/prod.env` |
| environment readback | `out/<arm>/env.txt` against `out/<arm>/env-expected.txt`, judged by `in/envaudit.py` into `out/<arm>/env-diff.txt` |
| boot shape, pool, prompt cache, vision | `out/<arm>/banner.txt`, `out/<arm>/plan.txt`, `out/<arm>/pool.txt`, `out/<arm>/server.log` |
| decode cells | `out/<arm>/conc_t0.json`, `out/<arm>/openai_t0.json`; means and verdicts by `analyze_devvsprod.py` |
| cold TTFT and the warm turn | `out/<arm>/ttft.out` summary lines (median seconds, n and excluded samples) |
| draft counters and request counts | `out/<arm>/metrics.txt`, `out/<arm>/gets.txt` |
| foreign traffic | `out/<arm>/gets.txt` `nonlocal=` summed per arm (`FOREIGN-SUMMARY` in `out/run.log`) |
| production's own plan and shape | `out/P*/server.log`, production's launcher `~/qwen6-start-prod.sh`, its recipe `~/qwen-zig-prod/scripts/config.sh` |
| frame 2 cells | `work/QInt4/box/speed.json`, `work/SyncBench/box/out/window/P{1,9}/conc_t0.json` |
| restore | `out/run.log` (`RESTORE`, `PROD-IMAGE`), `out/health-restored.json`, `out/restored-container.txt` |
