| setting | verdict |
| --- | --- |
| `TF_FLASHNEXT_CHUNK` | 1536 measured: decode level within 0.72 percent, greedy tokens identical at 1/2/4/6 streams, cold TTFT +4.96 to +7.00 percent (loses on prompt time at equal tokens). The 4096 and 6144 arms, which decide whether to raise our own value, are in window 2 |
| `TF_FLASHNEXT_CHUNK_SOLO` | not yet measured: the `--parallel 8` arm is in window 2, the one-stream arms in window 3 |
| `TF_FLASHNEXT_READOUT_FUSED` | not yet measured: window 1, after the chunk arms |
| `TF_CACHE_EVICT` | not yet measured: window 3 (resume bench) |
| `TF_SHARED_PRICE_LOG` | not yet measured: window 2, one pass A |
| `TENSORFOLD_DEVICE_CHECK` | not yet measured: window 2, one pass A |
| `TENSORFOLD_MEMORY_RESERVE_GIB` | not yet measured: window 2, the unset arm; production's 10 is the baseline (its boot line shows the 10.0 GiB reserve) |
| `TENSORFOLD_UNIFIED_HOST_COUNTS` | not yet measured: window 2, one pass A at 0 |
| `TF_FLASHNEXT_SPLIT_DENSE` | not-run-and-why: TP=2 pair has no Qwen3.8-Flash-Next checkpoint and spark5 has 72 GiB free against a 96 GiB model (NOTRUN.md) |
| `TF_FLASHNEXT_SHARD_HEAD` | not-run-and-why: the same TP=2 blocker |
| `TF_TIMING` | not-reachable: readers only in `src/families/qwen3_5/` (APPENDIX) |
| `TF_COST_KEY_TRACE` | not-reachable: only `families/qwen3_5/cuda_cost_adapter.zig` |
| `TF_NO_TREES` | not-reachable: only `families/qwen3_5/cuda_draft*.zig`, `cuda_sm110_modes.zig` |
| `TF_MTP_TREES` | not-reachable: only `families/qwen3_5/cuda_mtp.zig` |
| `TF_MTP_BATCH` | not-reachable: only `families/qwen3_5/cuda_mtp.zig` |
| `TF_QWEN_KEEP_LATE` | not-reachable: `families/qwen3_5/cuda_cache.zig`, `cuda_sm110_modes.zig` |
| `TF_QWEN_KV_PAGE_TEST` | not-reachable: the same two qwen3_5 files |
| `TF_QWEN_POOL_LOG` | not-reachable: only `families/qwen3_5/cuda_pages.zig` |
| `TF_QWEN35_CHUNK_SOLO` | not-reachable: `families/qwen3_5/cuda_solo.zig`, `cuda_prefill.zig`, `cuda_scratch.zig`, `cuda_engine.zig` |
| `TF_QWEN35_METAL_KV_PAGES` | not-reachable: qwen3_5 Metal (`kernels.zig`, `native/qwen35.zig`) |
| `TF_QWEN27_JOIN` | not-reachable: only `families/qwen27/attention_join.zig` |
| `TF_QWEN27_METAL_KV_PAGES` | not-reachable: qwen27 Metal (`kv_pages.zig`, `attention.zig`) |
| `TF_QWEN27_SHARED_PREFIX` | not-reachable: only `families/qwen27/simd_attention.zig` |
| `TF_QWEN27_SLOT_RESUME` | not-reachable: `native/qwen27_lanes.zig`, `qwen27_slots.zig` |
| `TF_Q27_GEMM` | not-reachable: only `families/qwen3_5/cuda_train_ops.zig` |
| `TF_Q27_POCKET_OFF` | not-reachable: only `families/qwen3_5/cuda_pocket.zig` |
| `TF_Q27_TAIL` | not-reachable: only `families/qwen3_5/cuda_train.zig` |
| `TENSORFOLD_HIP_MEMORY_LIMIT_GB` | not-reachable: `hip/admission.zig`, `families/qwen3_5/backend/hip/...` |
| `TENSORFOLD_LFM2_KV_PAGES` | not-reachable: `families/lfm2_moe/cuda_native.zig`, `native/cuda_kv_pool.zig` (LFM2 only) |
| `TF_GLM_EXPERT_FORM` | not-reachable: glm family (`cuda_lane_costs.zig`) |
| `TF_GLM_INDEX_CUDA` | not-reachable: glm family (`cuda_forward.zig`, `cuda_index.zig`) |
| `TF_GLM_KV_HOST_GIB` | not-reachable: glm family (`cuda_kv_host.zig`, `cuda_ranks.zig`) |
| `TF_GLM_RANK` | not-reachable: glm family (`cuda_native.zig`) and the mesh launcher |
| `TF_GLM_WORLD` | not-reachable: glm family (`cuda_native.zig`, `cuda_ranks.zig`) |
| `TF_GLM_PDL` (text changed) | not-reachable: glm family; the change adds GLM's qmmf linears to dependent launches |
| `TF_METAL4` | not-reachable: Metal backend (`src/metal/*`, `deepseek_v41/metal`) |
| `TF_METAL4_TIMELINE` | not-reachable: Metal 4 only |
| `TF_DSV41_PREFILL_PIECES` | not-reachable: DeepSeek-V4.1 (`serve_engine.zig`, `cuda_model.zig`) |
| `TF_DSV41_ROUND_PROF` | not-reachable: only `families/deepseek_v41/metal/round_prof.zig` |
| `TF_MINIMAX_RANK` | not-reachable: MiniMax-M3.1 (`families/minimax_m3/cuda_native.zig`) |
| `TF_MINIMAX_WORLD` | not-reachable: the same family |
| `TF_NEMOTRON_RANK` | not-reachable: Nemotron (`families/nemotron/cuda_native.zig`) |
| `TF_NEMOTRON_WORLD` | not-reachable: the same family |
| `TF_SLIDE_TAKE_OUT_CHECK` | not-reachable: the `.slide` scope, read only with `--slide` |
| `TF_SLIDE_TAP_CHECK` | not-reachable: the same scope |
| `TF_FLASHNEXT_SCALE_INDEX` (text changed) | not-reachable on CUDA: its one reader is the Metal load (`engine_load.zig:210`); no `cuda_*` file names it |
