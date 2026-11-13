# Serving production's INT4-AutoRound checkpoint on our v1.2.7 engine (experimental, 2026-11-13)

Owner directive: our engine (TensorFold v1.2.7 `93a2e93ec` plus `patches/1.2.7`, 0001 to 0015) serves the checkpoint
production serves, `azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound` (spark6 HF cache, revision
`1464274120d36a4d8fcaa934552334a7d83ce0fd`), so the 18 to 39% gap in `docs/CATCHUP-1.2.6.md` ("The production target is
a different model configuration") can be split into engine and checkpoint. Not for upstream. The work is a separate
package, `patches/1.2.7-int4/`, applied on top of the accepted series, which stays untouched.

Production's tree is the `production` branch at `5c3e3e29` (worktree `work/prod`); every production anchor below is
a file under `work/prod/zig/src/families/flashnext/` unless it names another directory. Every "ours" anchor is a
line of the accepted tree (v1.2.7 plus 0001 to 0015, `work/i4` here), under `zig/src/families/flashnext/` unless
it names `zig/src/cuda/` (the engine's shared CUDA library) or `zig/kernels/cuda/`.

## Phase 0: what production does for this checkpoint that ours refuses or fixes at compile time

The checkpoint (its `config.json`): 48 layers, 512 experts of width 640, hidden 2560, `num_experts_per_tok` 5,
`shared_expert_intermediate_size` 1280, `quantization_config` GPTQ (`bits` 4, `group_size` 128, `sym`, `desc_act`
false, `lm_head` true) with `dynamic` rules that leave the mixers, the hyper-connections, the router, the shared
expert, the embeddings and the MTP layer out. Those are stored as block FP8 (e4m3 `weight` with fp32
`weight_scale_inv` per 128x128 block: DeltaNet and attention projections and the shared expert) and BF16 (the
rest, including every MTP-layer tensor).

| # | item | production: file and symbol | ours: where it lands | size | phase |
|---|---|---|---|---|---|
| 1 | GPTQ layout accepted beside ModelOpt | `cuda_config.zig`: `Quant.gptq` (l.17), `Rule` (l.131), `Gptq.bitsOf` / `quantized` (l.134-163), `regexMatch` / `reAt` (l.167-200, the `dynamic` rules' re.match subset), `gptqOf` (l.586), the `quant_method` branch (l.807-809), `checkGptqImpl` (l.408-452) | `cuda_config.zig`: `Mode` (l.114) gains `.gptq`; `mode` (l.206-224) reads `quant_method`; a `gptqMismatch` beside `modeloptMismatch` (l.121-144); `shapes` (l.11-34) take `num_experts_per_tok` and `shared_expert_intermediate_size` from the geometry of item 2 | ~170 lines (rule matcher and its tests lifted) | 1 |
| 2 | routing width and shared-expert width | runtime fields: `Config.top_k`, `shared_width` (`cuda_config.zig` l.223-225), `state.Geometry.shared_width` / `mtp_top_k` (`cuda_state.zig` l.63-68), filled by `cuda_engine.geometry` (l.213, l.241-243) | comptime `slots = 11` and `moe_w = 640` (`cuda_prompt_wt.zig` l.20-21): `slots` is on 161 lines in 48 non-test files, 12 of them comptime array sizes, and it fixes the router's write (`cuda_glue.zig` l.595-597, `topkMany`), the slot sum (`cuda_batch_moe.zig` l.21), the shared slot's place (`cuda_shared_split.zig` l.26, `cuda_batch_side.zig` l.52); `moe_w` is on 67 lines and also sizes the shared expert (`cuda_mixed_experts.zig` l.30-33, `cuda_shared_split.zig` l.15, `cuda_batch_state.zig` l.468) | see the decision below: one constant changed and one added (`shared_w`), plus the ~8 shared-expert sites | 1 |
| 3 | block-FP8 mixers and shared expert | `cuda_weights.zig`: `isFp8` (l.848), the block-FP8 face (l.842-924), `gdn8` (l.925), `attention8` (l.963), `moe8` (l.994-1019, the healed 1280-wide shared expert on block FP8); `cuda_fp8.zig` (1,090 lines: the FP8G lane matmul host, `columnScales` l.341, `fragmentOrder` l.355, `tileScales` l.367, the fused split-K levers `FP8_FUSED_SPLIT` and `FP8_PROMPT_TILES`); device code `zig/kernels/cuda/fn_qmmf.cu` mode FP8G | no new kernel: our `zig/kernels/cuda/qmmf.cu` carries the same upstream FP8G mode (l.16, instantiated l.107-113, l.163-169), `zig/src/cuda/fp8.zig` l.52 builds an FP8G `qmmf.Weight` and `zig/src/cuda/qlinear.zig` runs it (l.65, l.126-182); the loader refuses it because `readMicro` (`cuda_projection_load.zig` l.23-37) knows only MXFP8's `weight_scale`; lands as an FP8G arm in `cuda_projection.zig` (beside `mxfp8`, l.52-78) and in `cuda_projection_load.zig` `load` / `loadStitched` (l.73-123), keyed on `weight_scale_inv` | ~120 lines | 1 |
| 4 | GPTQ int4 routed experts | `cuda_int4.zig` (556 lines: `Experts`, `Mat`, `shuffle`, `packWords`, `packScales`, `zerosAreSymmetric`, `Kernels`, `gateUp`, `down`, `gateUpPrompt`, `downPrompt`, `dense`); device code `zig/kernels/cuda/fn_int4.cu` (499 lines, namespace `tf_fn_int4`: `int4_kernel`, `int4_prompt_kernel`); `cuda_weights.int4Experts` (l.1022-1060); `cuda_forward.moeRowsInt4` (l.2053+); the host check `cuda_int4_check.zig` (763 lines) | a third arm in `cuda_moe_native.run` (l.23-33, today `.nvfp4` and `.fp8g`); the load in `cuda_modelopt_experts.zig` (`formatOf` l.142, `load` l.79-88) via `cuda_mixed_experts.load` (l.21-37), called from `cuda_prompt_load.zig` l.431-432; the kernel module registered in `zig/build/cuda_kernels.zig` and loaded beside `Kernels` (`cuda_batch_kernels.zig` l.98) | ~560 lifted host lines, the 499-line kernel as is, ~150 lines of glue | 2 (load in 1) |
| 5 | GPTQ int4 LM head | `cuda_weights.int4Head` (l.482-500), `Weights.head4` (l.240), `cuda_forward.headMm` (l.943-946: `int4.dense`), the int4 draft head `TF_FLASHNEXT_DRAFT_INT4` (`cuda_weights.zig` l.1601-1610, gathered from the head's own columns) and `HEAD_ROW_TILES` (`cuda_int4.headRowTiles` l.315) | head load `cuda_prompt.zig` l.185-192 (BF16 `lm_head.weight`), head matmuls `cuda_head.zig`, `cuda_heads.zig`, `cuda_batch_head.zig`; the draft head `cuda_mtp_load.zig` l.20-30 and `cuda_mtp.zig` l.265 (our 0007 re-quantizes BF16 head rows to 4-bit, so it needs a source) | ~150 lines | 2 |
| 6 | the MTP layer as stored (BF16 throughout) | BF16 MTP experts (`cuda_weights.zig` l.1147-1157), the MTP shared expert at its own width (l.792), MTP top-k `mtpTopK` (`cuda_engine.zig` l.201-210, `TF_FLASHNEXT_MTP_TOPK`, only 10 accepted), the overlay `TF_FLASHNEXT_MTP_FP8` (`cuda_engine.zig` l.588-590) built by `production/mtp_fp8.py` (q/k/v/o, both blocks' hyper-connection down/up and the mixer on block FP8) | `cuda_mtp.zig` l.257 loads the layer through `loadLayerAt`, whose experts go to `cuda_modelopt_experts.formatOf` (BF16 experts refused; ours expects FP8_PB_WO, `cuda_fp8_experts_load.zig`); the drafter's BF16 linears already have our 0014 (`TF_FLASHNEXT_MTP_WEIGHTS=mxfp8`) | ~60 lines | 1 |
| 7 | the prompt (prefill) side of items 3 to 5 | `cuda_int4.gateUpPrompt` / `downPrompt` (l.399-472, `TF_FLASHNEXT_INT4_PROMPT_GATE_UP`), `cuda_moe_prompt.zig` | the same dispatch at the prompt tile (`cuda_moe_native.zig` l.26-29: `nvfp4_tile.size`) | in item 4 | 2 |
| 8 | production-only settings these paths read | launcher `production/qwen6-start-prod.sh` l.43-62: `DRAFT_INT4`, `HEAD_ROW_TILES=2`, `INT4_PROMPT_GATE_UP=1`, `FP8_FUSED_SPLIT=4`, `FP8_PROMPT_TILES=1`, `SHARED_SLOT_LD=1`, `SHARED_EARLY_ROWS=6`, `MTP_FP8` | none have a counterpart; each is a speed setting on an exact path (production's own checks compare bytes), so the same-checkpoint measurement is ours as ported against production with them, and the table says so | - | 3 |

Port order, smallest first, each step compiled on the laptop before the next: 1 (config), 2 (geometry), 3 (FP8G
faces), 6 (MTP as stored), 4 (int4 experts: loader, then kernel and launch), 5 (int4 head), 7 (prompt tiles).
Items 1, 2, 3 and 6 and the loader half of 4 are what the engine needs to reach a first forward; 4 and 5 make the
forward production's arithmetic.

### Decision: the routing and shared widths as build-time constants, not load-time values

A load-time `slots` means threading one value through 161 lines in 48 files, 12 of which size arrays at compile
time, and through every captured graph's recorded shapes. The measurement needs one image that serves this
checkpoint and nothing else, so the experimental series sets the constants at build time instead: `slots = 6` (top-5
plus the shared slot) and a new `shared_w = 1280` beside `moe_w = 640`. That is a second compile-time instantiation of
the same engine. The config check (item 1) then refuses the FP4 checkpoint by name (`num_experts_per_tok`), so an
image of this series cannot silently serve the wrong model. What it costs: the MTP layer routes at the same width as
the main layers unless it gets its own constant (see item 6 and the measured production setting below).

### Exactness, by item

- Items 4 and 5 are production's own kernels, lifted with their provenance, so a reply can match production's
  token for token where the rest of the forward agrees.
- Item 3 runs our FP8G lane matmul; production's is the same upstream `qmmf.cu` mode (its `fn_qmmf.cu` header:
  copied, SASS-equal to the Python extension), so the arithmetic is expected equal and is compared by replies.
- Item 6 never changes a reply: the MTP layer only proposes and the verify keeps or rejects every token.
- The rest of the forward (read-outs, attention and DeltaNet, glue) is v1.2.7's, not production's. Where those
  differ in arithmetic the replies can diverge after some tokens; the oracle reports the first divergence.

## Phase 1: load and boot (done 2026-11-13)

`patches/1.2.7-int4/0016-int4-autoround.patch` (26 files, +1,482 / -38 against the 15-patch tree, cut by
`scripts/qwen38/zig/target/int4/mkpatch.sh` from the series' own files) carries items 1 to 6 of the table, and these
found on the way:

- The n-gram table is not in this checkpoint's index: it is the FP8 table of `Qwen/Qwen3.8-Flash-Next-FP8` in
  `ple-table/*.safetensors` (shards e4m3 `[2500012, 160]`, no table scale). `cuda_ple.Ngram.open` maps that
  directory's n-gram tensors beside the index (production's loader does the same, `openExtra` in its
  `cuda_weights.zig`).
- The rank memory estimate (`cuda_rank_memory.tensorBytes`) priced the GPTQ experts at zero bytes (it counts
  `.weight` only); `qweight` and `scales` are now counted.
- The layer loader chose the native MoE only when the experts store a `.weight` (`cuda_prompt_load.zig` l.431), so
  GPTQ experts fell to the legacy MLX branch, which refused the 1280-wide shared expert (`UnexpectedTensor` within
  nine seconds of boot, image `int4b`).
- Five hyper-connection write-back calls passed a fixed top-10 and 11 slots (`cuda_batch.zig` l.203,
  `cuda_batch_hc.zig` l.62, l.92, l.94, `cuda_prompt_step.zig` l.198). With 6 slots the MoE sum read the wrong rows:
  image `int4c` booted and answered garbage from the first token (golden 0 of 6, "window self-check: 1 of 2080").
  They now pass `slots - 1, slots`.

Image `int4d` (this text) boots in 148 to 151 s: "model 70.69 GiB; 1 stream at once, 5.14 GiB each at a
262144-token window (fp8 caches)", "window self-check: 1176 of 2080 rows byte-equal to their one-token steps",
48-row copy windows, as the accepted series on its own checkpoint. The tree passes
`zig build compile-config-server -Dtarget=aarch64-linux-gnu` on the laptop at every step.

## Phase 2: replies against production's own serve (2026-11-13)

Golden (`~/work/qf_harness.py golden`, six greedy prompts) of image `int4d` at one stream against production's
golden captured in the same evening (`~/work/int4/bench-int4b/p-c1/zgold.json`, its own launcher), compared by
`scripts/qwen38/zig/target/int4/gcmp.py`: **6 of 6 identical**, content and token hash, including the two long
replies (215 and 256 tokens):

| prompt | tokens | token hash, both serves |
|---|---:|---|
| golden-0 | 2 | `7d3144d36034` |
| golden-1 | 215 | `24916427be0a` |
| golden-2 | 13 | `a82a61d48299` |
| golden-3 | 7 | `43c6b9cfeecb` |
| golden-4 | 256 | `fd67ce6f9784` |
| golden-5 | 4 | `559657976e04` |

So on these prompts our forward (v1.2.7's attention, DeltaNet, read-outs and glue, production's int4 kernels, the
FP8G lane matmul on the block-FP8 mixers) gives production's tokens. Six prompts are not a proof that every reply
is identical; they are the bar this campaign uses.

The three fixed chat prompts (`chat_prompts.txt`, temperature 0, thinking off, 160 tokens) read as coherent, correct
answers: "The capital of Australia is **Canberra** ... selected as the capital in **1908** as a political compromise
between Australia's two largest cities"; a typed iterative `fibonacci(n: int) -> int` with a docstring and doctest
examples; and "A refrigerator uses a circulating refrigerant that absorbs heat from the interior air as it
evaporates ... compressed by a motor ... releases this heat into the surrounding room air as it condenses".

## Phase 3: the speed answer (2026-11-13)

One GPU window each, spark6, one fresh boot a cell, the same harness (`tfm_decode.py`, one pass of 512-token prose
and code replies), fp8 KV at a 262,144-token window. Ours: image `int4d`, `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8` (our
8-bit drafter, the counterpart of production's FP8 overlay), 6 and 8 streams on `TF_FLASHNEXT_KV_PAGES=4096`
(window 22:57 to 23:20 UTC, `~/work/int4/bench-int4d/`). Production: its own launcher and image (window 21:47 to
21:58 UTC, `bench-int4b/p-c*`, repeats in brackets: `bench-int4b/pr-c1` and, at the end of our window,
`bench-int4d/pr-c1`, `pr-c4`). Aggregate tok/s prose / code, per-stream median after the semicolon:

| streams | ours (INT4 checkpoint) | production (INT4 checkpoint) | ours / production |
|---:|---|---|---|
| 1 | 61.3 / 105.8 (65.8 / 110.5) | 71.6 / 128.4 (75.0 / 130.7, 71.9 / 129.4) | 0.86 / 0.82 |
| 2 | 93.9 / 156.9; 47.0 / 78.5 a stream | 119.8 / 180.8; 59.9 / 90.4 | 0.78 / 0.87 |
| 4 | 134.8 / 218.5; 34.4 / 56.0 | 165.1 / 259.4 (166.0 / 261.9); 41.3 / 65.3 | 0.82 / 0.84 |
| 6 | 166.2 / 267.7; 27.7 / 45.7 | 210.3 / 328.2; 35.7 / 55.0 | 0.79 / 0.82 |
| 8 | 184.7 / 308.4; 23.4 / 39.6 | 242.4 / 380.0; 30.7 / 47.5 | 0.76 / 0.81 |

Production's drift across the two windows is small (one stream 71.6 / 128.4, 75.0 / 130.7 and 71.9 / 129.4; four
streams 165.1 / 259.4 and 166.0 / 261.9); our one-stream repeat read 7% / 4% above the first cell, so the ratios
carry a few percent of cell noise.

### What the number means

The earlier table (`docs/CATCHUP-1.2.6.md`, "The production target is a different model configuration") had ours on
the FP4 checkpoint at 61.4 / 81.3, 86.8 / 120.6, 112.9 / 166.4, 146.4 / 204.5 and 162.9 / 234.0 tok/s at 1, 2, 4, 6
and 8 streams. The same engine on production's checkpoint gives +0% / +30% at one stream and +8 to +19% / +30 to +32%
at two to eight. Splitting each total gap to production into the part that moves with the checkpoint and the part
that stays (in logarithms, so the parts add; production from this evening's windows):

| streams | total gap, FP4 checkpoint | gap on the same checkpoint | the checkpoint's share | the engine's share |
|---:|---|---|---|---|
| 1 | -16% / -37% | -13% / -16% (repeats averaged) | 20% / 61% | 80% / 39% |
| 2 | -28% / -33% | -22% / -13% | 24% / 65% | 76% / 35% |
| 4 | -32% / -36% | -19% / -16% | 46% / 61% | 54% / 39% |
| 6 | -30% / -38% | -21% / -18% | 35% / 57% | 65% / 43% |
| 8 | -33% / -38% | -24% / -19% | 32% / 57% | 68% / 43% |

So on code a little over half of the old gap was the checkpoint (production's top-5 routing reads less than half our
expert bytes a round, and its int4 head about a quarter of our BF16 head's), and on prose most of it is the engine.
What remains on the same checkpoint is a 13 to 24% gap that belongs to our engine.

### Where the remaining gap goes at one stream

Factorised from the served one-stream cells (rounds are deterministic: every repeat of a serve gave the same count):

| | ours | production | ours / production |
|---|---|---|---|
| prose: tokens a round (512 tokens in 195 / 186 rounds) | 2.63 | 2.75 | 0.95 |
| prose: ms a round | 42.8 (39.9 repeat) | 38.4 (36.7, 38.3) | about 1.09 |
| code: tokens a round (94 / 81 rounds) | 5.45 | 6.32 | 0.86 |
| code: ms a round | 51.5 (49.3) | 49.2 (48.4, 48.8) | about 1.03 |

So on code the remaining gap is mostly the drafter (14% fewer tokens a round), and on prose mostly the round (about
9% longer). The drafter is engine-side on both counts: production drafts with its int4 head's own columns
(`TF_FLASHNEXT_DRAFT_INT4`), its MTP layer's BF16 experts and its block-FP8 overlay, and its draft policy
(`CONFIDENCE=-0.15`, `DEPTH=15`, `DRAFT_CONTINUE=0.20`, `DRAFT_PROPOSE=0.05`); ours drafts with a 4-bit head
re-quantized from the int4 head's dequantized rows (patch 0007), its MTP experts re-coded to block FP8 at load, the
MXFP8 drafter linears (0014) and our defaults.

The round, from the kernel log (`TF_FLASHNEXT_KERNEL_LOG=1`, graphs off, every launch waited for, one stream, the
decode window closed by a trailing request, aggregated by `expert_ids/ktab3.py`): ours is image `int4x` (0016 plus
the diagnostic patch, `scripts/qwen38/zig/target/int4/0099-diag-int4.patch`, spark6 `~/work/int4/bench-int4x/ep-o1`,
290 rounds); production is `pdiag` on the same checkpoint (`~/work/target/bench/ep-p1`, 268 rounds):

| ms a round | ours (INT4) | production (INT4) | difference |
|---|---|---|---|
| dense projections (ours: the hyper-connection read-outs run here, on the BF16 lane) | 30.10 | 19.91 | +10.19 |
| hyper-connection kernels (production: its 12-bit read-outs `hc_down_q12`, `hc_upmix_q12`) | 2.91 | 8.29 | -5.38 |
| the two above together | 33.01 | 28.20 | **+4.81** |
| experts and the int4 head (every `int4_kernel` launch, our block-FP8 drafter experts) | 11.35 | 14.19 | -2.84 |
| attention and DeltaNet | 2.56 | 2.28 | +0.28 |
| routing | 1.55 | 1.38 | +0.17 |
| rest | 1.75 | 1.92 | -0.17 |
| in kernels | 50.28 | 48.13 | +2.15 |
| window wall | 52.02 | 52.29 | -0.27 |

On equal bytes the engine-owned round cost is where `docs/CATCHUP-1.2.6.md` already placed it: the dense projections
and the read-outs, +4.81 ms a round here against +4.23 there. Our expert and head launches are 2.84 ms cheaper on the
same int4 kernels (production also runs its draft head on `int4_kernel`), and production's window spends 4.16 ms a
round outside its kernels against our 1.74, so the instrumented walls are equal. The served gap at one stream is
therefore the drafter's tokens a round first and the dense projections and read-outs second.
