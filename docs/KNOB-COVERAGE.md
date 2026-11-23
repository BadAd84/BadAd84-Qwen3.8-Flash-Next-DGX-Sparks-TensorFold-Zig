# Knob coverage: every setting the served tree reads, its verdict, and what still needs an arm

Current state against the served tree `work/Int4Step5/tree` (head `987de0084`), whose
`zig/src/platform/environment.zig` carries 78 rows in the `flashnext`, `cuda` and `common` scopes. The
coverage gate prints `coverage: 78 settings in scope, set 78, missing 0, annotations 2, worklist markers 0`
and `check-dev-env.py` prints `dev-env: 0 setting(s) without a citation` against
`scripts/qwen38/zig/target/env/dev.env` (both run for this document), so this is the complete set, not a
sample. Every row is classified from its read site, not its name.

No measurement was taken for this document. It mines `work/KnobTest`, `work/ProseDraft`, `work/GapArms`,
`work/DevVsProd`, `work/KvTierShip`, `work/KvTierDedup`, the two `patches/main-1ece6e6db-r5*` READMEs,
`work/SpeedAudit`, `docs/INT4-PORT.md` and `scripts/qwen38/zig/target/serve-env126.sh`, then reads each
setting's own read site in the served tree.

## Counts

| verdict | count | meaning |
| --- | ---: | --- |
| MEASURED-KEEP | 4 | a measured positive on this stack, set at the measured value |
| MEASURED-LEVEL | 8 | measured, no gain outside noise, the shipped value stands |
| MEASURED-NEGATIVE | 1 | the only measured alternative was slower, the shipped value stands |
| MEASURED-BY-PATCH | 0 | introduced and measured by a kept patch of ours (no row in this table; our own switches live outside the table) |
| NO-SPEED-EFFECT | 20 | the read site proves a speed arm cannot win: a diagnostic, a path this serve does not run, or a default whose alternative is strictly more work |
| CAPACITY-OR-ADMISSION | 7 | capacity or admission: it decides whether a shape fits or which memory the planner sees, not how fast a round is |
| OTHER-FAMILY-UNREACHED | 18 | the reader is another family's or another backend's; Flash Next never executes it |
| UNMEASURED | 20 | no measurement on this stack, and the read site can move decode or prompt speed: the worklist |
| **total** | **78** | |

`MEASURED-BY-PATCH` is zero for this table because every one of the 78 is an upstream row. Our own switches
(`TF_FLASHNEXT_WINDOW_CHECK`, `TF_FLASHNEXT_KV_PAGES`, `TF_FLASHNEXT_PROMPT_SHARED_DIRECT` and the rest of
the series) are read outside `environment.zig` and are the six exports the coverage gate reports as not in
this serve's table; their verdicts are the measured block and the bottom block of `dev.env` plus each patch
README, and they are not repeated here.

Section of `dev.env`: 4 measured, 4 launcher-carried, 70 explicit defaults (78 rows), out of 85 export
lines. The head has 15 exports, of which 8 are table rows; the other 7 are the series' own names or
production-engine-only names (`TF_FLASHNEXT_DEPTH` and `TF_FLASHNEXT_WINDOW` have no reader in this tree,
and `TENSORFOLD_VISION_PYTHONPATH` is carried for parity with a dev serve that runs `VISION=0`).

## The 78

| setting | scope | dev.env | verdict | class | evidence (record and cell) | read site, and speed effect |
| --- | --- | --- | --- | --- | --- | --- |
| `TF_CACHE_EVICT` | common | explicit default | **MEASURED-LEVEL** | cache/memory plan | `work/KnobTest/VERDICTS.md` (the resumed conversation kept its snapshot under both policies, A3 TTFT level) and `work/KnobTest/RESULT.md` window 3 (EVICT decode level; no victim on our trace) | `zig/src/core/prompt_cache_decay.zig:13` reads the policy; qwen4_exp is in cuda_cache (`core/profile.zig:141`) |
| `TF_STARTUP_RECEIPT` | common | explicit default | **NO-SPEED-EFFECT** | diagnostic | `zig/src/server/main.zig:144` enables a boot receipt only; nothing is read on a request path | `zig/src/server/main.zig:144`, boot once |
| `TF_SHARED_PRICE_LOG` | common | explicit default | **MEASURED-LEVEL** | diagnostic | `work/KnobTest/RESULT.md` window 2 PRICE: every measured decode cell level, tokens equal | `zig/src/core/lanes/price_log.zig:5`, a line a priced shared round |
| `TENSORFOLD_DEVICE_CHECK` | common | explicit default | **MEASURED-LEVEL** | capacity/admission | `work/KnobTest/RESULT.md` window 2 DEVCK: startup only, every measured cell level | `zig/src/server/device_cli.zig:85`, a load-time profile check |
| `TENSORFOLD_VIDEO_TOKENS` | common | launcher | **CAPACITY-OR-ADMISSION** | capacity/admission | production launcher value 16384 (`dev.env` head block); a per-request video token budget, not a speed lever | `zig/src/server/vision_inputs.zig:301-331` caps a request's video tokens, so it changes prompt length |
| `TENSORFOLD_MAX_PDF_PAGES` | common | explicit default | **CAPACITY-OR-ADMISSION** | capacity/admission | `zig/src/server/pdf.zig:18` default 16; a page cap on OCR input | `zig/src/server/pdf.zig:95`, `zig/src/server/ocr/budget.zig:20` |
| `TENSORFOLD_PARALLEL` | common | explicit default | **CAPACITY-OR-ADMISSION** | capacity/admission | `zig/src/server/main.zig:141-142`; the lane count, and the `--parallel` flag wins when present (`cli.zig:251`) | `zig/src/server/main.zig:142`, an admission default only |
| `TENSORFOLD_PRESSURE_CACHE_PERCENT` | common | explicit default | **NO-SPEED-EFFECT** | cache/memory plan | `zig/src/core/memory_pressure.zig:73` and `forOs`: on Linux the governor runs only with `TENSORFOLD_MEMORY_PRESSURE=1` or `on`, which no env sets, so the percent only sizes a watermark nothing reaches | `zig/src/core/memory_pressure.zig:73`, the soft watermark of a governor that is off |
| `TENSORFOLD_PREFIX_WAIT_MS` | common | explicit default | **UNMEASURED** | cache/memory plan | a request whose prompt shares a cut another fill is producing waits for it, and this bounds the wait; it can move TTFT on shared-prefix agent turns | `zig/src/core/lane_host_prefix.zig:19`; arm 0 vs 60000 vs 120000 on a shared-prefix turn, TTFT only |
| `TENSORFOLD_RESTORE_PREFETCH` | common | explicit default | **UNMEASURED** | cache/memory plan | reads held at once for a disk state restored ahead of its request; only reached with a disk state store (the dev KV tier), so it can move resume TTFT there and nothing on the production shape | `zig/src/core/rows_prefetch.zig:23`; arm 1 vs 2 vs 4 under the tier, resume TTFT |
| `TENSORFOLD_RESTORE_PREFETCH_GIB` | common | explicit default | **UNMEASURED** | cache/memory plan | the read-ahead byte cap (16 GiB default), read on the same line as the reads and wait; tier-only | `zig/src/core/rows_prefetch.zig:23`; arm 8 vs 16 vs 32 GiB under the tier |
| `TENSORFOLD_RESTORE_PREFETCH_MS` | common | explicit default | **UNMEASURED** | cache/memory plan | the request's wait bound for its read-ahead (30 s default); tier-only | `zig/src/core/rows_prefetch.zig:23`; arm 5000 vs 30000 vs 0 under the tier |
| `TENSORFOLD_TOOL_ID_KEY_FILE` | common | explicit default | **NO-SPEED-EFFECT** | diagnostic | `zig/src/server/tool_id_key.zig:10-20` and `server.zig:115`: an operator key read once at startup; blank makes a random one | `zig/src/server/tool_id_key.zig:20`, startup only |
| `TF_FLASHNEXT_BATCH_DRAWS` | cuda | launcher | **UNMEASURED** | decode/prefill scheduling | production launcher value 1, never A/B on this stack; batched draws share one completion where per-stream draws keep stream order, so it can move decode | `zig/src/families/flashnext/cuda_draw_batch.zig:15-18`, read by `cuda_mtp.zig:227`; arm 0 vs 1 at 1/4/8 |
| `TENSORFOLD_CUDA_KERNELS` | cuda | explicit default | **UNMEASURED** | decode/prefill scheduling | selects a captured kernel set or the engine's own kernels. The arm's own launcher sets `native` while `dev.env` states the absence (the installed set when present, else native), production boots a captured set, and no A/B on this stack has compared them, so it can move every kernel | `zig/src/cuda/aot.zig:15-23`; one boot each of native and a captured set, decode 1/4/8 and cold 1k/8k/32k |
| `TF_NCCL_LIB` | cuda | explicit default | **NO-SPEED-EFFECT** | transport, path not run | `zig/src/cuda/nccl.zig:81`: the library the tensor-parallel path opens; the serve is one GPU (TP=1), so no NCCL collective runs | `zig/src/cuda/nccl.zig:81`, opened only by the TP path |
| `TF_CUDA_DEVICE` | cuda | explicit default | **NO-SPEED-EFFECT** | diagnostic | `zig/src/native/cuda.zig:222` picks the GPU ordinal; this box has one GB10, so 0 is the only device | `zig/src/native/cuda.zig:222`, a load-time choice with one candidate |
| `TF_CUDA_SEGMENTS` | cuda | explicit default | **NO-SPEED-EFFECT** | decode/prefill scheduling | `zig/src/native/cuda.zig:223` accepts 1 to `F.max_segments`, and Flash Next declares `max_segments = 1` (`cuda_lanes.zig:33`), so 1 is the only value the serve takes | `zig/src/native/cuda.zig:223` with `zig/src/families/flashnext/cuda_lanes.zig:33`; any other value is refused |
| `TF_CUDA_CARVEOUT` | cuda | explicit default | **CAPACITY-OR-ADMISSION** | capacity/admission | `zig/src/cuda/carveout.zig:37-43`: KV planes go to GB10 display memory first; a capacity source, not a kernel | `zig/src/cuda/carveout.zig:37-43` |
| `TF_CUDA_CARVEOUT_MIB` | cuda | explicit default | **CAPACITY-OR-ADMISSION** | capacity/admission | the carveout size (1792 MiB default) on the same reader; capacity only | `zig/src/cuda/carveout.zig:43` |
| `TF_MTP_DRAFTS` | cuda | explicit default | **OTHER-FAMILY-UNREACHED** | other family | `zig/src/families/qwen3_5/cuda_mtp.zig:122`: the qwen3_5 drafter's depth; Flash Next reads `TF_FLASHNEXT_DRAFTS` instead | `zig/src/families/qwen3_5/cuda_mtp.zig:122` |
| `TF_DSPINE_WINDOW` | cuda | explicit default | **OTHER-FAMILY-UNREACHED** | other family | `zig/src/families/qwen3_5/cuda_dspine_config.zig:21`: the DSpine drafter's sliding window, qwen3_5 only | `zig/src/families/qwen3_5/cuda_dspine_config.zig:21` |
| `TF_DRAFT_NODES` | cuda | explicit default | **OTHER-FAMILY-UNREACHED** | other family | `zig/src/core/lanes/draft_tree.zig:86` is the tree walker, and its only family caller is `qwen3_5/cuda_draft_tree.zig:1`; no flashnext file references it | `zig/src/core/lanes/draft_tree.zig:86` with `zig/src/families/qwen3_5/cuda_draft_tree.zig` |
| `TF_QMMF_HALF_BELOW` | cuda | explicit default | **UNMEASURED** | decode/prefill scheduling | a per-call tile choice: MXFP8 and BF16 calls take 32-column half tiles below this many 64-column blocks (default 96, same sums), and the Flash Next lane reads it (`cuda_disk.zig:132`), so it can move decode and prompt passes | `zig/src/cuda/qmmf.zig:124`; sweep 0/32/64/96/128 at 1 and 4 streams |
| `TF_HY4_MEM_FLOOR_GIB` | cuda | explicit default | **OTHER-FAMILY-UNREACHED** | other family | `zig/src/families/hy4_flash/cuda_model.zig:227`: the Hy4-flash loader's memory floor | `zig/src/families/hy4_flash/cuda_model.zig:227` |
| `TENSORFOLD_MEMORY_RESERVE_GIB` | cuda | launcher | **MEASURED-LEVEL** | capacity/admission | `work/KnobTest/RESULT.md` window 2 RESERVE: level in every measured cell; `VERDICTS.md` notes the reserve is what bounds the window on a GB10, so it is an admission number, not a speed lever | `zig/src/native/cuda_memory.zig:390` reads the text, admission at `:167-178` |
| `TENSORFOLD_HIP_MEMORY_LIMIT_GB` | cuda | explicit default | **OTHER-FAMILY-UNREACHED** | other family | `zig/src/hip/admission.zig:89`: the HIP backend's admission; the CUDA build never opens it | `zig/src/hip/admission.zig:89` |
| `TF_QWEN_KEEP_LATE` | cuda | explicit default | **OTHER-FAMILY-UNREACHED** | other family | `zig/src/families/qwen3_5/cuda_cache.zig:25`: qwen3_5's deferred keeps | `zig/src/families/qwen3_5/cuda_cache.zig:25` |
| `TF_QWEN_KV_PAGE_TEST` | cuda | explicit default | **OTHER-FAMILY-UNREACHED** | other family | `zig/src/families/qwen3_5/cuda_cache.zig:75`: a qwen3_5 cache check | `zig/src/families/qwen3_5/cuda_cache.zig:75` |
| `TF_COST_KEY_TRACE` | cuda | explicit default | **OTHER-FAMILY-UNREACHED** | other family | `zig/src/families/qwen3_5/cuda_cost_adapter.zig:42`: qwen3_5's cost-key trace | `zig/src/families/qwen3_5/cuda_cost_adapter.zig:42` |
| `TF_TIMING` | cuda | explicit default | **OTHER-FAMILY-UNREACHED** | other family | `zig/src/families/qwen3_5/cuda_draft.zig:175,553` and `cuda_mtp.zig:163`: qwen3_5's wall-time lines; Flash Next has its own `TF_FLASHNEXT_PROFILE` | `zig/src/families/qwen3_5/cuda_draft.zig:553` |
| `TF_NO_TREES` | cuda | explicit default | **OTHER-FAMILY-UNREACHED** | other family | `zig/src/families/qwen3_5/cuda_draft_tree.zig:14`: chains only for the qwen3_5 drafter | `zig/src/families/qwen3_5/cuda_draft_tree.zig:14` |
| `TF_MTP_TREES` | cuda | explicit default | **OTHER-FAMILY-UNREACHED** | other family | `zig/src/families/qwen3_5/cuda_mtp.zig:121`: planner trees on the qwen3_5 head | `zig/src/families/qwen3_5/cuda_mtp.zig:121` |
| `TF_MTP_BATCH` | cuda | explicit default | **OTHER-FAMILY-UNREACHED** | other family | `zig/src/families/qwen3_5/cuda_mtp.zig:124`: one pass for every stream on the qwen3_5 head | `zig/src/families/qwen3_5/cuda_mtp.zig:124` |
| `TF_QWEN_POOL_LOG` | cuda | explicit default | **OTHER-FAMILY-UNREACHED** | other family | `zig/src/families/qwen3_5/cuda_pages.zig:197`: a qwen3_5 pool census | `zig/src/families/qwen3_5/cuda_pages.zig:197` |
| `TF_Q27_POCKET_OFF` | cuda | explicit default | **OTHER-FAMILY-UNREACHED** | other family | `zig/src/families/qwen3_5/cuda_pocket.zig:121`: a qwen3_5 pocket diagnostic | `zig/src/families/qwen3_5/cuda_pocket.zig:121` |
| `TF_Q27_TAIL` | cuda | explicit default | **OTHER-FAMILY-UNREACHED** | other family | `zig/src/families/qwen3_5/cuda_train.zig:251`: the qwen3_5 training path | `zig/src/families/qwen3_5/cuda_train.zig:251` |
| `TF_Q27_GEMM` | cuda | explicit default | **OTHER-FAMILY-UNREACHED** | other family | `zig/src/families/qwen3_5/cuda_train_ops.zig:55`: qwen3_5 training tiles | `zig/src/families/qwen3_5/cuda_train_ops.zig:55` |
| `TENSORFOLD_PROMPT_CACHE_KEEP_OTHERS` | cuda | explicit default | **UNMEASURED** | cache/memory plan | a new prompt state that fits only by evicting another conversation's is not kept; qwen4_exp is in cuda_cache, so it is reached, and it can move a later turn's TTFT (a refused keep costs a re-prefill) but not a round | `zig/src/core/prompt_cache_others.zig:15` with `core/profile.zig:141`; arm 0 vs 1 on two interleaved conversations |
| `TF_PROMPT_INTERMEDIATE` | cuda | explicit default | **UNMEASURED** | cache/memory plan | a bounded ladder of intermediate prompt checkpoints, kept off until a served A/B shows the marks pay (`cuda_snaps` comment); reached by every CUDA family through `native/cuda.zig:19` | `zig/src/native/cuda_snaps.zig:35`; arm 0 vs 1 on a long agent turn, resume TTFT |
| `TENSORFOLD_LFM2_KV_PAGES` | cuda | explicit default | **OTHER-FAMILY-UNREACHED** | other family | `zig/src/families/lfm2_moe/cuda_native.zig:57-59`: LFM2's page policy | `zig/src/families/lfm2_moe/cuda_native.zig:59` |
| `TENSORFOLD_UNIFIED_HOST_COUNTS` | cuda | explicit default | **CAPACITY-OR-ADMISSION** | capacity/admission | `zig/src/native/cuda_memory.zig:222-233`: which host count admission reads. `work/KnobTest/VERDICTS.md` records the explicit 0 refusing to boot on this GB10 (no stream fits); 1 (procfs) is the only serving value | `zig/src/native/cuda_memory.zig:224`, admission |
| `TF_ROCE_GID_INDEX` | cuda | explicit default | **NO-SPEED-EFFECT** | transport, path not run | `zig/src/cuda/roce.zig:255`: the RoCE GID index for the tensor-parallel verbs path; TP=1 opens no verbs | `zig/src/cuda/roce.zig:255` |
| `TF_QWEN35_CHUNK_SOLO` | cuda | explicit default | **OTHER-FAMILY-UNREACHED** | other family | `zig/src/families/qwen3_5/cuda_solo.zig:47`: qwen3_5's solo prompt pass; Flash Next reads `TF_FLASHNEXT_CHUNK_SOLO` | `zig/src/families/qwen3_5/cuda_solo.zig:47` |
| `TF_FLASHNEXT_PROMPT_BF16` | flashnext | explicit default | **UNMEASURED** | decode/prefill scheduling | on, qmmf's lane loads BF16 prompt tiles from `qmmf.prompt_rows` rows (128-row tile); off takes the other prompt path, so it can move cold prompt speed | `zig/src/families/flashnext/cuda_batch_kernels.zig:122`; arm 0 vs 1, cold 1k/8k/32k |
| `TF_FLASHNEXT_WINDOW_GRAPH` | flashnext | explicit default | **UNMEASURED** | decode/prefill scheduling | drafted windows, head pieces and rollback replays as CUDA graphs (same kernels); capture cost against replay saving, so the default is a hypothesis and it can move decode and prompt passes | `zig/src/families/flashnext/cuda_window_graph.zig:22`; arm 0 vs 1 at 1/4/8 with drafts on |
| `TF_FLASHNEXT_LANE_PARTS` | flashnext | explicit default | **CAPACITY-OR-ADMISSION** | cache/memory plan | `zig/src/families/flashnext/cuda_lanes_load.zig:50` and `cuda_lane_parts.zig:1`: fixed-size lane buffers reused across streams, at most 4 idle blocks each; off allocates each stream. It changes memory held and stream-open allocation, not a decode or prompt pass | `zig/src/families/flashnext/cuda_lanes_load.zig:50`, an allocator policy |
| `TF_FLASHNEXT_KEEP_INPASS` | flashnext | explicit default | **NO-SPEED-EFFECT** | decode/prefill scheduling | `zig/src/families/flashnext/cuda_lanes_snap.zig:7-10`: marks inside a chunk are filled on the way; 0 cuts the pass at each mark, so it runs more passes for the same rows. The default is strictly less work | `zig/src/families/flashnext/cuda_lanes_snap.zig:10`, dominated default |
| `TF_FLASHNEXT_FIRST_EARLY` | flashnext | explicit default | **NO-SPEED-EFFECT** | decode/prefill scheduling | `zig/src/families/flashnext/cuda_mtp.zig:39-41`: a drafted stream's first token is sent before its first drafts are asked; 0 sends it after them, so the first token can only arrive later for the same decode | `zig/src/families/flashnext/cuda_mtp.zig:41`, dominated on TTFT |
| `TF_FLASHNEXT_GPU_TOPK` | flashnext | explicit default | **NO-SPEED-EFFECT** | decode/prefill scheduling | `zig/src/families/flashnext/cuda_mtp_draw.zig:18-21`: a sampled draw reads top_k candidates from the device; 0 downloads whole score rows, strictly more transfer for the same draw | `zig/src/families/flashnext/cuda_mtp_draw.zig:21`, dominated default |
| `TF_FLASHNEXT_GDN_FUSED` | flashnext | explicit default | **NO-SPEED-EFFECT** | decode/prefill scheduling | `zig/src/families/flashnext/cuda_gdn_fused.zig:9-12`: one kernel a value head for a lone stream's pass; 0 is three launches for the same bits | `zig/src/families/flashnext/cuda_gdn_fused.zig:12`, dominated default |
| `TF_FLASHNEXT_GDN_LANES` | flashnext | explicit default | **NO-SPEED-EFFECT** | decode/prefill scheduling | `zig/src/families/flashnext/cuda_batch_gdn_lanes.zig:22-25`: a shared pass's DeltaNet steps over its lanes in one launch each; 0 steps a lane at a time, more launches for the same bits | `zig/src/families/flashnext/cuda_batch_gdn_lanes.zig:25`, dominated default |
| `TF_FLASHNEXT_BATCH_HEADS` | flashnext | explicit default | **NO-SPEED-EFFECT** | decode/prefill scheduling | `zig/src/families/flashnext/cuda_lanes_draft.zig:8-11`: the batched head gives the same drafts; 0 drafts a shared round's streams one at a time, more launches for the same drafts | `zig/src/families/flashnext/cuda_lanes_draft.zig:11`, dominated default |
| `TF_FLASHNEXT_SAMPLED_HEADS` | flashnext | explicit default | **UNMEASURED** | decode/prefill scheduling | keeps sampled streams (temperature above zero) in a shared round's batched head; 0 drafts them separately, so it can move decode on sampled traffic and not on greedy-only cells | `zig/src/families/flashnext/cuda_lanes_draft.zig:16`; arm 0 vs 1 at temperature above zero, 2/4/8 |
| `TF_FLASHNEXT_SHARED_DRAFTS` | flashnext | measured | **MEASURED-KEEP** | decode/prefill scheduling | `work/ProseDraft/RESULT.md` S0 against B0: prose 4 streams 229.0 against 207.8 tok/s (+10.2 percent), code 300.1 against 276.8 (+8.4), 7 to 11 percent at 2 to 8 streams, one stream level to the digit; exactness 8/8 drafts | `zig/src/families/flashnext/cuda_lanes_draft.zig:47` |
| `TF_FLASHNEXT_SHARED_SIDE` | flashnext | explicit default | **UNMEASURED** | decode/prefill scheduling | the shared expert on its own stream beside the routed experts, with a fork and a join a layer; 0 runs it after them on the same stream. The overlap is free work on a bandwidth-bound engine, so only a measurement decides | `zig/src/families/flashnext/cuda_batch_side.zig:11`; arm 0 vs 1 at 1/4/8 |
| `TF_FLASHNEXT_HC_FUSE` | flashnext | explicit default | **NO-SPEED-EFFECT** | decode/prefill scheduling | `zig/src/families/flashnext/cuda_batch_hc.zig:14-17`: one launch does the layer's writeback with the read-out's normalize; 0 splits them into two launches for the same bits | `zig/src/families/flashnext/cuda_batch_hc.zig:17`, dominated default |
| `TF_FLASHNEXT_READOUT_FUSED` | flashnext | measured | **MEASURED-KEEP** | decode/prefill scheduling | `work/KnobTest/RESULT.md` window 1 F1: cold TTFT faster by 3.19 percent at 64k, 3.86 at 32k, 4.11 at 8k and 6.47 at 2k, decode level, tokens equal; `work/RoGpu/receipt/cold.md` 7 of 8 cold cells faster | `zig/src/families/flashnext/readout_fused.zig:4` with `cuda_tiles.zig:94` (fused rows 768) |
| `TF_FLASHNEXT_KEEP_LATE` | flashnext | explicit default | **UNMEASURED** | decode/prefill scheduling | drafting streams keep a partly kept window's DeltaNet rows pending in a log instead of re-running them, one GPU only (TP refuses it); it can move decode at one stream and does nothing unset | `zig/src/families/flashnext/cuda_mtp_draft.zig:141`; arm unset vs 1 at 1 stream, rounds and TTFT |
| `TF_FLASHNEXT_DECODE_GRAPH` | flashnext | explicit default | **UNMEASURED** | decode/prefill scheduling | one bounded decode round captured as a graph, recaptured when owners, scratch or geometry move; capture cost against replay saving, and the 1.2.6 stack measured 0 to 2 percent alone (3.1 percent stacked with ATTN_LANES and CHUNK 1024), so it can move decode | `zig/src/families/flashnext/cuda_round_graph.zig:8`; arm 0 vs 1 at 1/4/8 (SPLIT_DENSE=0 only at TP=2) |
| `TF_FLASHNEXT_SPLIT_DENSE` | flashnext | explicit default | **NO-SPEED-EFFECT** | decode/prefill scheduling | `zig/src/families/flashnext/cuda_dense_split.zig:35-36`: `applies()` returns false at world != 2, so a TP=1 serve never reads it (it is the TP=2 set) | `zig/src/families/flashnext/cuda_dense_split.zig:36`, TP=2 only |
| `TF_FLASHNEXT_SHARD_HEAD` | flashnext | explicit default | **NO-SPEED-EFFECT** | decode/prefill scheduling | `zig/src/families/flashnext/cuda_head.zig:14-15`: `shard()` returns BadHeadSharding at world != 2, so TP=1 keeps the whole head and never reads a different value | `zig/src/families/flashnext/cuda_head.zig:15`, TP=2 only |
| `TF_FLASHNEXT_ATTN_LANES` | flashnext | explicit default | **UNMEASURED** | decode/prefill scheduling | a shared round's attention in one launch a kernel for every lane against a lane at a time; the 1.2.6 stack measured 0 to 2 percent alone and 3.1 percent stacked with DECODE_GRAPH and CHUNK 1024, and the current stack has it off, so it is the cheapest decode lead | `zig/src/families/flashnext/cuda_batch_lanes.zig:44`; arm 0 vs 1 at 2/4/6/8 |
| `TF_FLASHNEXT_WARM_AHEAD` | flashnext | explicit default | **UNMEASURED** | cache/memory plan | warm-ahead hints on the PLE reader (the n-gram table read before a pass needs it); it can move cold prompt speed | `zig/src/families/flashnext/cuda_ple.zig:383`; arm 0 vs 1, cold 8k/32k |
| `TF_FLASHNEXT_TABLE_WARM` | flashnext | explicit default | **UNMEASURED** | cache/memory plan | after load, the table is read ahead into the page cache so a cold prompt reads RAM; a boot-side decision that can move the first prompt's TTFT (boot wall recorded too) | `zig/src/families/flashnext/cuda_ple.zig:447`; arm 0 vs 1, cold 8k/32k |
| `TF_FLASHNEXT_PROFILE` | flashnext | explicit default | **NO-SPEED-EFFECT** | diagnostic | `zig/src/families/flashnext/cuda_batch_kernels.zig:160-163`: each chunk's synchronized wall time and its host n-gram gather on stderr; off in every measured arm | `zig/src/families/flashnext/cuda_batch_kernels.zig:163`, a diagnostic |
| `TF_FLASHNEXT_VERIFY_HOST_LOGITS` | flashnext | explicit default | **NO-SPEED-EFFECT** | decode/prefill scheduling | `zig/src/families/flashnext/cuda_batch_state.zig:176-179`: drafted windows also copy their last row's scores to the host; 0 is strictly less transfer for the same replies | `zig/src/families/flashnext/cuda_batch_state.zig:179`, dominated default |
| `TF_FLASHNEXT_DRAFTS` | flashnext | explicit default | **MEASURED-LEVEL** | decode/prefill scheduling | `work/GapArms/RESULT.md` D15 against C3a: 15/15 gives counters identical to the shipped 6/8 and every cell is level, so the numeric depth is not a lever | `zig/src/families/flashnext/cuda_lanes_load.zig:93` |
| `TF_FLASHNEXT_DRAFTS_GREEDY` | flashnext | explicit default | **MEASURED-LEVEL** | decode/prefill scheduling | the same D15 pair (`work/GapArms/RESULT.md`): greedy 15 against 8 is digit-identical to the shipped value | `zig/src/families/flashnext/cuda_lanes_load.zig:95` |
| `TF_FLASHNEXT_GREEDY_WIDE` | flashnext | explicit default | **MEASURED-LEVEL** | decode/prefill scheduling | `work/ProseDraft/RESULT.md` G8 (8): level at every cell; the source already keeps greedy depth at width 4 | `zig/src/families/flashnext/cuda_lanes_draft.zig:42` |
| `TF_FLASHNEXT_WINDOW_ROWS` | flashnext | explicit default | **MEASURED-NEGATIVE** | decode/prefill scheduling | `scripts/qwen38/zig/target/serve-env126.sh`: `Do not set TF_FLASHNEXT_WINDOW_ROWS: 32 costs 5% at four streams`; the table also caps a value above the shared round's rows, so only a lower value acts and it loses | `zig/src/families/flashnext/cuda_lanes.zig:495` with `cuda_mtp.zig:86` |
| `TF_FLASHNEXT_READOUT_ROWS` | flashnext | explicit default | **UNMEASURED** | decode/prefill scheduling | rows from which a prompt pass's read-out takes the fused tiles (default 64, 0 never), read once at load; a threshold that can move prompt speed | `zig/src/families/flashnext/cuda_chunk.zig:41`; sweep 0/32/64/128/256, cold 1k/8k/32k |
| `TF_FLASHNEXT_CHUNK` | flashnext | measured | **MEASURED-KEEP** | decode/prefill scheduling | `work/GapArms/RESULT.md` C4 against C3: cold TTFT 0.959 at 1k, 0.964 at 8k, 0.975 at 32k; `work/KnobTest/RESULT.md` window 2 C4096 faster by 3.74 to 4.06 percent at 8k/32k and level at 2k | `zig/src/families/flashnext/cuda_chunk.zig:8` |
| `TF_FLASHNEXT_CHUNK_SOLO` | flashnext | measured | **MEASURED-KEEP** | decode/prefill scheduling | `work/KnobTest/RESULT.md` window 3 P_16384: 13.867 against 14.062 s at 32k and 28.577 against 28.901 at 64k, 2k and 8k level, tokens equal | `zig/src/families/flashnext/cuda_chunk.zig:30` |
| `TF_FLASHNEXT_FACT_ROWS` | flashnext | explicit default | **UNMEASURED** | decode/prefill scheduling | rows from which NVFP4 experts take the prompt tiles (default 64, 0 never), read once at load; a threshold that can move prompt speed | `zig/src/families/flashnext/cuda_nvfp4_tile.zig:8`; sweep 0/32/64/128/256, cold 1k/8k/32k |
| `TF_FLASHNEXT_KV_PAGE_TEST` | flashnext | explicit default | **NO-SPEED-EFFECT** | diagnostic | `zig/src/families/flashnext/cuda_pages.zig:58-60`: each stream's caches read through reversed n-position pages; a check, off in every measured arm | `zig/src/families/flashnext/cuda_pages.zig:60` |
| `TF_FLASHNEXT_CONFIDENCE` | flashnext | launcher | **MEASURED-LEVEL** | decode/prefill scheduling | `work/ProseDraft/RESULT.md`: 0 is 2.6 percent slower at one stream (7.9 drafts at 0.363 acceptance) and -0.20 is level against the shipped -0.15, so the launcher value stands | `zig/src/families/flashnext/cuda_lanes_load.zig:97` |
| `TF_FLASHNEXT_PROMPT` | flashnext | explicit default | **NO-SPEED-EFFECT** | diagnostic | `zig/src/families/flashnext/cuda_rows.zig:192-197`: the rows path belongs to the flashnext-prompt tool (`cuda_prompt_main.zig:42`); `cuda_launch.zig:489` only references the module | `zig/src/families/flashnext/cuda_rows.zig:197`, tool only |

## The worklist, ranked

20 settings are UNMEASURED and can move decode or prompt speed. They are ranked by how directly the read
site sits in a round: a per-round decision first, then a per-pass kernel choice, then a one-off boot policy,
then cache and resume tuning.

| rank | class | setting | what the arm changes | exact arm |
| --- | --- | --- | --- | --- |
| 1 | A1 | `TF_FLASHNEXT_ATTN_LANES` | shared-round attention in one launch a kernel | 0 (now) against 1, decode 2/4/6/8, drafts on |
| 2 | A1 | `TF_FLASHNEXT_DECODE_GRAPH` | one bounded decode round as a CUDA graph | 0 (now) against 1, decode 1/4/8, same prompts |
| 3 | A1 | `TF_FLASHNEXT_WINDOW_GRAPH` | drafted windows and head pieces as graphs | 0 against 1 (now), decode 1/4/8 with drafts |
| 4 | A1 | `TF_QMMF_HALF_BELOW` | 32-column half tiles below N 64-column blocks | 0, 32, 64, 96 (now), 128 at 1 and 4 streams, decode |
| 5 | A1 | `TF_FLASHNEXT_BATCH_DRAWS` | batched draws against per-stream draws | 0 against 1 (now), decode 1/4/8 |
| 6 | A1 | `TF_FLASHNEXT_SHARED_SIDE` | shared expert on its own stream against inline | 0 against 1 (now), decode 1/4/8 |
| 7 | A1 | `TF_FLASHNEXT_SAMPLED_HEADS` | sampled streams in the batched head | 0 against 1 (now) at temperature above zero, 2/4/8 |
| 8 | A1 | `TF_FLASHNEXT_KEEP_LATE` | pending DeltaNet rows against a re-run | unset (now) against 1, decode at 1 stream |
| 9 | A2 | `TF_FLASHNEXT_PROMPT_BF16` | BF16 prompt tiles against the other prompt path | 0 against 1 (now), cold TTFT 1k/8k/32k |
| 10 | A2 | `TF_FLASHNEXT_READOUT_ROWS` | tile threshold for the read-out | 0, 32, 64 (now), 128, 256 cold 1k/8k/32k |
| 11 | A2 | `TF_FLASHNEXT_FACT_ROWS` | tile threshold for NVFP4 experts | 0, 32, 64 (now), 128, 256 cold 1k/8k/32k |
| 12 | A2 | `TF_FLASHNEXT_WARM_AHEAD` | PLE warm-ahead hints | 0 (now) against 1, cold 8k/32k |
| 13 | A3 | `TF_FLASHNEXT_TABLE_WARM` | PLE table read ahead after load | 0 (now) against 1, cold 8k/32k, boot wall recorded |
| 14 | A3 | `TENSORFOLD_CUDA_KERNELS` | captured kernel set against native | the arm launcher's native against the image's installed captured set (share/tensorfold/cuda/sm<cap>) where the image ships one, decode 1/4/8 and cold 1k/8k/32k; if it does not, the arm is a build first |
| 15 | A4 | `TENSORFOLD_PREFIX_WAIT_MS` | bound on waiting for another fill's cut | 0, 60000 (now), 120000, TTFT on a shared-prefix turn |
| 16 | A4 | `TENSORFOLD_PROMPT_CACHE_KEEP_OTHERS` | refuse a keep that would evict another conversation | 0 (now) against 1, two interleaved conversations, later-turn TTFT |
| 17 | A4 | `TF_PROMPT_INTERMEDIATE` | intermediate prompt checkpoint ladder | 0 (now) against 1, long agent turn, resume TTFT |
| 18 | A4 | `TENSORFOLD_RESTORE_PREFETCH` | reads held for a disk state | 1, 2 (now), 4 under the dev tier, resume TTFT |
| 19 | A4 | `TENSORFOLD_RESTORE_PREFETCH_GIB` | read-ahead byte cap | 8, 16 (now), 32 GiB under the dev tier |
| 20 | A4 | `TENSORFOLD_RESTORE_PREFETCH_MS` | read-ahead wait bound | 5000, 30000 (now), 0 under the dev tier |

Rank classes: A1 per-round, A2 per-pass prompt, A3 boot policy, A4 cache and resume. The top of the list is
where the existing evidence points: `ATTN_LANES` and `DECODE_GRAPH` carried 0 to 2 percent alone
and 3.1 percent stacked on the 1.2.6 stack (`scripts/qwen38/zig/target/serve-env126.sh`) and both are off
here; `QMMF_HALF_BELOW` and the two tile thresholds are geometric decisions with the same sums and no A/B
at all.

## Boots the worklist implies

At the repo's five-level rule (1, 2, 4, 6 and 8 concurrent streams, `AGENTS.md`): 20 arms x 5 levels = **100 boots** if every level gets its own fresh boot, which is how `docs/SPEED-TARGET-1.2.6.md` states the method (`a fresh boot for every concurrency level`); **20 boots** if one fresh boot per setting carries all five client levels, which is `AGENTS.md`'s `one fresh boot per setting`. The two records differ, so plan the queue on 100 and keep the cheaper reading only if the concurrency sweep can run inside one boot without reloading the model. Each arm also needs a control at the other value; the control is the same image, not a second setting.

## Settled by reading the code, no arm needed

These are decided, not deferred. Each line names the read site that decides it.

- `TF_FLASHNEXT_KEEP_INPASS`: 0 cuts the prompt pass at each mark, so it runs more passes for the same rows (`cuda_lanes_snap.zig:7-10`).
- `TF_FLASHNEXT_VERIFY_HOST_LOGITS`: 1 copies a row's scores to the host; 0 is the same replies with less transfer (`cuda_batch_state.zig:176-179`).
- `TF_FLASHNEXT_GDN_FUSED`: 0 is three launches for the same bits (`cuda_gdn_fused.zig:9-12`).
- `TF_FLASHNEXT_GDN_LANES`: 0 steps a lane at a time for the same bits (`cuda_batch_gdn_lanes.zig:22-25`).
- `TF_FLASHNEXT_HC_FUSE`: 0 splits the writeback and normalize into two launches (`cuda_batch_hc.zig:14-17`).
- `TF_FLASHNEXT_BATCH_HEADS`: 0 drafts a shared round's streams one at a time and the batched head gives the same drafts (`cuda_lanes_draft.zig:8-11`).
- `TF_FLASHNEXT_GPU_TOPK`: 0 downloads whole score rows instead of top_k candidates (`cuda_mtp_draw.zig:18-21`).
- `TF_FLASHNEXT_FIRST_EARLY`: 0 sends the first token only after the first drafts are asked (`cuda_mtp.zig:39-41`).
- `TF_CUDA_SEGMENTS`: Flash Next declares max_segments = 1, so 1 is the only accepted value (`cuda_lanes.zig:33` with `native/cuda.zig:223`).
- `TF_FLASHNEXT_SPLIT_DENSE`: applies() returns false at world != 2 (`cuda_dense_split.zig:35-36`).
- `TF_FLASHNEXT_SHARD_HEAD`: shard() returns BadHeadSharding at world != 2 (`cuda_head.zig:14-15`).
- `TF_NCCL_LIB`: the TP path opens NCCL; the serve is TP=1 (`cuda/nccl.zig:81`).
- `TF_ROCE_GID_INDEX`: the TP verbs path reads it; the serve is TP=1 (`cuda/roce.zig:255`).
- `TF_CUDA_DEVICE`: one GB10, so the ordinal is 0 (`native/cuda.zig:222`).
- `TENSORFOLD_PRESSURE_CACHE_PERCENT`: the Linux governor runs only with TENSORFOLD_MEMORY_PRESSURE=1, which nothing sets (`core/memory_pressure.zig:73`).
- `TF_STARTUP_RECEIPT`: a boot receipt (`server/main.zig:144`).
- `TF_FLASHNEXT_PROFILE`: synchronized per-chunk timing on stderr (`cuda_batch_kernels.zig:160-163`).
- `TF_FLASHNEXT_KV_PAGE_TEST`: reversed page reads, a check (`cuda_pages.zig:58-60`).
- `TF_FLASHNEXT_PROMPT`: the flashnext-prompt tool's rows path (`cuda_rows.zig:197`, `cuda_prompt_main.zig:42`).
- `TENSORFOLD_TOOL_ID_KEY_FILE`: a startup key (`server/tool_id_key.zig:20`).

The 7 capacity and admission settings (`TENSORFOLD_VIDEO_TOKENS`, `TENSORFOLD_MAX_PDF_PAGES`, `TENSORFOLD_PARALLEL`, `TF_CUDA_CARVEOUT`, `TF_CUDA_CARVEOUT_MIB`, `TENSORFOLD_UNIFIED_HOST_COUNTS`, `TF_FLASHNEXT_LANE_PARTS`) change what fits, not how fast a pass runs; `UNIFIED_HOST_COUNTS=0` refuses to boot on this GB10. The 18 other-family readers cannot execute on a Flash Next serve at all.

## Never sweep these again

The measured levels and the negative, with the losing values named:

- `TF_FLASHNEXT_DRAFTS=15` and `TF_FLASHNEXT_DRAFTS_GREEDY=15`: digit-identical counters to the shipped 6/8
  (`work/GapArms/RESULT.md`). The depth number is not the prose gap.
- `TF_FLASHNEXT_GREEDY_WIDE=8`: level at every cell (`work/ProseDraft/RESULT.md`); greedy depth is already
  kept at width 4.
- `TF_FLASHNEXT_CONFIDENCE=0`: 2.6 percent slower at one stream; `-0.20`: level against the shipped -0.15
  (`work/ProseDraft/RESULT.md`, window 4 for the combination).
- `TF_CACHE_EVICT=decayed_resume`: level on our resume workload, no victim for the policy
  (`work/KnobTest/VERDICTS.md`).
- `TENSORFOLD_MEMORY_RESERVE_GIB`: level in every cell; it is an admission bound, not a speed arm.
- `TF_FLASHNEXT_WINDOW_ROWS=32`: 5 percent slower at four streams (`serve-env126.sh`); the default 64 stands.
- Values that lost inside a setting we otherwise keep: `TF_FLASHNEXT_CHUNK=1536` (6.75 to 8.15 percent slower
  cold), `TF_FLASHNEXT_CHUNK_SOLO=3072` (6.3 to 7.3 percent slower) and unset/8192 (1.1 to 1.4 percent behind
  16384 at 32k/64k), `TF_FLASHNEXT_SHARED_DRAFTS=1` (the 0.6 gate, 7 to 11 percent slower),
  `TF_FLASHNEXT_READOUT_FUSED=0` (3.19 to 6.47 percent slower cold).
- `TENSORFOLD_UNIFIED_HOST_COUNTS=0`: refuses to boot on this GB10 (no stream fits, `work/KnobTest/VERDICTS.md`).
- `TF_FLASHNEXT_SPLIT_DENSE` and `TF_FLASHNEXT_SHARD_HEAD` are the TP=2 set: do not open them until a TP=2
  serve of this checkpoint exists; at TP=1 they are unread.

The do-not-chase register (`work/SpeedAudit/REPORT-kimi.md` section D, `CORRECTIONS.md`) names no setting
in this table: its entries (relaxed MX128 and GEMM2, HC_Q12, Q12 prefetch, round-cost pricing, the prefill
tail, the gather log, `MTP_WEIGHTS`) are our series' names outside the 78. Their verdicts are already in
`dev.env`'s bottom block and the patch READMEs; this document does not reopen them.

## What this document does not cover

- The seven exports in `dev.env` that this serve's table does not have (`TENSORFOLD_NO_UPDATE_CHECK`,
  `TENSORFOLD_VISION_PYTHONPATH`, `TF_FLASHNEXT_DEPTH`, `TF_FLASHNEXT_KV_PAGES`,
  `TF_FLASHNEXT_PROMPT_SHARED_DIRECT`, `TF_FLASHNEXT_WINDOW`, `TF_FLASHNEXT_WINDOW_CHECK`): three are
  measured levers carried at the top of `dev.env`, three serve the production engine or its vision helper,
  and `NO_UPDATE_CHECK` is a launcher name.
- The 150 upstream settings outside these three scopes (Metal, GLM, DeepSeek-V4.1, MiniMax, the slide scope and
  the rest): other backends and other families, classified in `work/KnobTest/CLASSIFY.md` and not this serve's.
- Any measurement. This is the map of what is known and what is not; the arms in the worklist are the next
  windows.
