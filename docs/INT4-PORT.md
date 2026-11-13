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
