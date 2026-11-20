# Reachability evidence: every non-table, non-test reader of each new setting
From `git grep -n NAME origin/main -- zig`, one entry per setting. `src/platform/environment*.zig`
rows only validate a value; test files prove nothing about the serve. A setting reaches the
Flash Next CUDA serve only when a reader below sits on the `families/flashnext` path, the CUDA
admission, the prompt cache, or the shared lanes engine (all four are reachable; other families
are linked into the same binary but their code runs only for their own model_type).

## `TENSORFOLD_DEVICE_CHECK`
- `src/server/cli.zig` lines 169
- `src/server/device_cli.zig` lines 84, 85

## `TENSORFOLD_HIP_MEMORY_LIMIT_GB`
- `src/families/qwen3_5/backend/hip/engine/native.zig` lines 161, 167
- `src/hip/admission.zig` lines 82, 93, 112, 258

## `TENSORFOLD_LFM2_KV_PAGES`
- `src/core/profile.zig` lines 34, 172
- `src/families/lfm2_moe/cuda_native.zig` lines 57, 59
- `src/native/cuda_kv_pool.zig` lines 589

## `TENSORFOLD_MEMORY_RESERVE_GIB`
- `src/cli/plan.zig` lines 67, 121, 171, 225, 278
- `src/cuda_dense/native.zig` lines 262
- `src/families/dory/cuda_native.zig` lines 215, 217
- `src/families/gemma4/cuda_native.zig` lines 271, 272, 274
- `src/families/kolibri1/native.zig` lines 206, 207
- `src/families/lfm2_moe/cuda_native.zig` lines 204, 205
- `src/families/qwen3_5/backend/hip/engine/native.zig` lines 161
- `src/families/spark25/native.zig` lines 202, 203
- `src/hip/admission.zig` lines 82, 92, 112, 258
- `src/native/cuda.zig` lines 293
- `src/native/cuda_family_memory.zig` lines 39, 40
- `src/native/cuda_kv_pool.zig` lines 472
- `src/native/cuda_memory.zig` lines 169, 384, 387
- `src/server/cli.zig` lines 170

## `TENSORFOLD_UNIFIED_HOST_COUNTS`
- `src/native/cuda_family_memory.zig` lines 21, 23
- `src/native/cuda_memory.zig` lines 222, 224, 231, 233

## `TF_CACHE_EVICT`
- `src/core/profile.zig` lines 8, 144
- `src/core/prompt_cache_decay.zig` lines 13

## `TF_COST_KEY_TRACE`
- `qwen35_cost_process.zig` lines 97
- `src/families/qwen3_5/cuda_cost_adapter.zig` lines 42, 155, 156, 157, 158

## `TF_DSV41_PREFILL_PIECES`
- `src/core/profile.zig` lines 44, 181
- `src/families/deepseek_v41/cuda_model.zig` lines 419, 479, 481
- `src/families/deepseek_v41/metal/entry.zig` lines 34
- `src/families/deepseek_v41/sched_host.zig` lines 1
- `src/families/deepseek_v41/serve_engine.zig` lines 90, 157, 161, 171
- `src/families/deepseek_v41/serve_lanes.zig` lines 50, 91, 93, 182

## `TF_DSV41_ROUND_PROF`
- `src/families/deepseek_v41/metal/round_prof.zig` lines 1, 14

## `TF_FLASHNEXT_CHUNK`
- `src/families/flashnext/cuda_batch_state.zig` lines 57
- `src/families/flashnext/cuda_chunk.zig` lines 1, 6, 8, 12, 18, 20, 24, 30, 45, 54
- `src/families/flashnext/cuda_disk.zig` lines 120
- `src/families/flashnext/cuda_lanes.zig` lines 587, 593
- `src/families/flashnext/cuda_prompt.zig` lines 122, 124, 142

## `TF_FLASHNEXT_CHUNK_SOLO`
- `src/families/flashnext/cuda_chunk.zig` lines 1, 18, 20, 24, 30, 54
- `src/families/flashnext/cuda_disk.zig` lines 120
- `src/families/flashnext/cuda_lanes.zig` lines 593
- `src/families/flashnext/cuda_prompt.zig` lines 122

## `TF_FLASHNEXT_READOUT_FUSED`
- `src/families/flashnext/cuda_batch_kernels.zig` lines 44
- `src/families/flashnext/cuda_disk.zig` lines 124
- `src/families/flashnext/cuda_tiles.zig` lines 93
- `src/families/flashnext/readout_fused.zig` lines 1, 4

## `TF_FLASHNEXT_SHARD_HEAD`
- `src/families/flashnext/cuda_head.zig` lines 5, 7, 11, 54, 55, 57, 59, 61, 63, 65

## `TF_FLASHNEXT_SPLIT_DENSE`
- `src/families/flashnext/cuda_dense_split.zig` lines 25, 27, 31, 124, 125, 133, 135, 138, 140, 142, 150, 151, 157
- `src/families/flashnext/cuda_lanes_explain.zig` lines 23, 24

## `TF_GLM_EXPERT_FORM`
- `src/families/glm/cuda_lane_costs.zig` lines 100, 102, 115, 118, 131, 313, 318, 320, 321

## `TF_GLM_INDEX_CUDA`
- `build/glm_family_host.zig` lines 42
- `src/families/glm/cuda_forward.zig` lines 47, 89
- `src/families/glm/cuda_index.zig` lines 20, 27, 37, 101

## `TF_GLM_KV_HOST_GIB`
- `src/families/glm/cuda_kv_host.zig` lines 28, 30, 271
- `src/families/glm/cuda_ranks.zig` lines 30, 163, 166, 239, 476

## `TF_GLM_RANK`
- `src/fabric/mesh/launch.zig` lines 48, 132, 147, 181, 183, 188, 212
- `src/families/glm/cuda_native.zig` lines 1, 133, 138, 513
- `src/server/cli_gpu_flags.zig` lines 88

## `TF_GLM_WORLD`
- `src/fabric/mesh/launch.zig` lines 48, 132, 136, 147, 181, 183, 188, 212
- `src/families/glm/cuda_native.zig` lines 133, 139, 513, 514, 527
- `src/families/glm/cuda_ranks.zig` lines 202, 204
- `src/server/cli_gpu_flags.zig` lines 88
- `src/server/engines.zig` lines 62
- `src/server/idle_unload_policy.zig` lines 10, 20

## `TF_METAL4`
- `src/families/deepseek_v41/metal/boot.zig` lines 40, 42, 46
- `src/metal/command.zig` lines 59
- `src/metal/device.zig` lines 101, 105
- `src/metal/library.zig` lines 15, 19, 138
- `src/metal/metal4.zig` lines 555
- `src/metal/metal4_timeline.zig` lines 1

## `TF_METAL4_TIMELINE`
- `src/metal/command.zig` lines 59
- `src/metal/device.zig` lines 101, 105
- `src/metal/library.zig` lines 15, 19, 138
- `src/metal/metal4.zig` lines 555
- `src/metal/metal4_timeline.zig` lines 1

## `TF_MINIMAX_RANK`
- `src/fabric/mesh/launch.zig` lines 49, 150
- `src/families/minimax_m3/cuda_dump_main.zig` lines 7
- `src/families/minimax_m3/cuda_native.zig` lines 1, 60, 65, 312

## `TF_MINIMAX_WORLD`
- `src/fabric/mesh/launch.zig` lines 49, 150
- `src/families/minimax_m3/cuda_dump_main.zig` lines 7
- `src/families/minimax_m3/cuda_native.zig` lines 1, 60, 66, 312, 315

## `TF_MTP_BATCH`
- `src/families/qwen3_5/cuda_mtp.zig` lines 95, 124

## `TF_MTP_TREES`
- `src/families/qwen3_5/cuda_mtp.zig` lines 66, 121, 566, 567, 568, 569

## `TF_NEMOTRON_RANK`
- `src/cli/cuda_main.zig` lines 234
- `src/fabric/mesh/launch.zig` lines 50, 152
- `src/families/nemotron/cuda_engine.zig` lines 124
- `src/families/nemotron/cuda_latent.zig` lines 88, 91
- `src/families/nemotron/cuda_native.zig` lines 114

## `TF_NEMOTRON_WORLD`
- `src/fabric/mesh/launch.zig` lines 50, 152
- `src/families/nemotron/cuda_engine.zig` lines 124
- `src/families/nemotron/cuda_latent.zig` lines 88, 92
- `src/native/cuda_disk.zig` lines 110

## `TF_NO_TREES`
- `src/families/qwen3_5/cuda_draft.zig` lines 443, 444
- `src/families/qwen3_5/cuda_draft_tree.zig` lines 12, 14, 22, 23, 24, 25
- `src/families/qwen3_5/cuda_sm110_modes.zig` lines 36, 93

## `TF_Q27_GEMM`
- `src/families/qwen3_5/cuda_train_ops.zig` lines 51, 55, 423, 424, 425, 426, 427, 428

## `TF_Q27_POCKET_OFF`
- `src/families/qwen3_5/cuda_pocket.zig` lines 121, 214, 215, 216, 217, 218

## `TF_Q27_TAIL`
- `src/families/qwen3_5/cuda_train.zig` lines 251, 569, 570, 571, 572

## `TF_QWEN27_JOIN`
- `src/families/qwen27/attention_join.zig` lines 17, 19

## `TF_QWEN27_METAL_KV_PAGES`
- `qwen27_core.zig` lines 29
- `src/core/profile.zig` lines 36, 174
- `src/families/qwen27/attention.zig` lines 15
- `src/families/qwen27/kv_pages.zig` lines 1, 10, 12
- `src/families/qwen27/simd_attention.zig` lines 75
- `src/native/qwen27_served.zig` lines 317, 372
- `src/server/profile_line.zig` lines 169, 284
- `src/tensorfold.zig` lines 144

## `TF_QWEN27_SHARED_PREFIX`
- `src/families/qwen27/simd_attention.zig` lines 65, 67

## `TF_QWEN27_SLOT_RESUME`
- `src/native/qwen27_lanes.zig` lines 94
- `src/native/qwen27_slots.zig` lines 213, 215

## `TF_QWEN35_CHUNK_SOLO`
- `src/families/qwen3_5/cuda_engine.zig` lines 24, 107
- `src/families/qwen3_5/cuda_host_embed.zig` lines 41
- `src/families/qwen3_5/cuda_native_explain.zig` lines 15, 16
- `src/families/qwen3_5/cuda_prefill.zig` lines 72, 137, 294
- `src/families/qwen3_5/cuda_round.zig` lines 7
- `src/families/qwen3_5/cuda_scratch.zig` lines 113
- `src/families/qwen3_5/cuda_solo.zig` lines 1, 6, 47, 53, 57, 65, 84

## `TF_QWEN35_METAL_KV_PAGES`
- `src/core/profile.zig` lines 37, 175
- `src/families/qwen3_5/backend.zig` lines 31
- `src/families/qwen3_5/kernels.zig` lines 8
- `src/families/qwen3_5/state.zig` lines 72
- `src/native/qwen35.zig` lines 45, 47, 59, 60, 97
- `src/server/profile_line.zig` lines 170, 284

## `TF_QWEN_KEEP_LATE`
- `build/cuda_family_host.zig` lines 111
- `src/families/qwen3_5/cuda_cache.zig` lines 19, 25, 421, 422, 423, 424
- `src/families/qwen3_5/cuda_sm110_modes.zig` lines 35, 92

## `TF_QWEN_KV_PAGE_TEST`
- `src/families/qwen3_5/cuda_cache.zig` lines 57, 64, 73, 75, 421, 425, 426
- `src/families/qwen3_5/cuda_sm110_modes.zig` lines 34, 91

## `TF_QWEN_POOL_LOG`
- `src/families/qwen3_5/cuda_pages.zig` lines 195, 197, 281, 282, 283, 284

## `TF_SHARED_PRICE_LOG`
- `src/core/lanes/engine.zig` lines 56
- `src/core/lanes/price_log.zig` lines 1, 5

## `TF_SLIDE_TAKE_OUT_CHECK`
- `src/server/serve.zig` lines 166, 440, 442, 445
- `src/server/server.zig` lines 96
- `src/server/slide.zig` lines 312, 313

## `TF_SLIDE_TAP_CHECK`
- `src/living/pocket_read.zig` lines 134, 143

## `TF_TIMING`
- `src/families/qwen3_5/cuda_draft.zig` lines 175, 551, 553, 596, 597, 598, 599
- `src/families/qwen3_5/cuda_mtp.zig` lines 163, 477
- `src/families/qwen3_5/cuda_round_timing.zig` lines 12
