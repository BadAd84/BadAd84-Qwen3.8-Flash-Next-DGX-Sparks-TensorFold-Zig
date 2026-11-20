# KnobTest: classification of every setting upstream main gained since 964174ea05

Source of the set: `git show 964174ea05:docs/environment.md` against `git show origin/main:docs/environment.md`, a
name-by-name set difference, 44 added and 0 removed, plus 2 whose text changed. The brief listed 39; the
difference also carries five `TENSORFOLD_*` names the brief's list omitted, so all 44 are classified here.

Readers: `git grep -n NAME origin/main -- zig` for each name, read in full; the rules are the rows of
`zig/src/platform/environment.zig`. Effects are from the reader bodies and the setting's own doc table row.
Authors and pull requests: `gh search prs --repo ashhart/TensorFold NAME`, the lowest-numbered PR that
names the setting (read-only; `prs.json` holds every hit). The clone is shallow at `abc43804e` (2026-11-10),
so `git log -S` cannot see before it; a name that first appears there is reported by its PR, not the commit.

## The serve under test

Qwen3.8 Flash Next NVFP4, family `flashnext` (model_type `qwen4_exp`), CUDA backend, ONE GB10, TP=1,
drafts on, through the production recipe copy on spark6 (`~/work/lanes/rpr/recipe`) with the env that
`~/qwen6-start-prod.sh` exports. A setting "reaches us" only if code on THAT path reads it: every family is
linked into `tensorfold-native`, so linking is not reach: the family dispatch and the reader's own file are.

## Table

| setting | family / backend | default | effect | reaches our serve | evidence | added by |
| --- | --- | --- | --- | --- | --- | --- |
| `TENSORFOLD_DEVICE_CHECK` | common; serve's device-profile check | 1 | startup only: 0 skips the saved-device-profile refusal | YES | device_cli.zig:85 serveRefusal; cli.zig:169 lists it | #3107 ashhart 2026-11-13 (`tensorfold device` saves the profile; serve refuses on it) |
| `TENSORFOLD_HIP_MEMORY_LIMIT_GB` | HIP admission; qwen3_5 HIP engine | unset | capacity, HIP only | NO | readers: hip/admission.zig, families/qwen3_5/backend/hip/engine/native.zig; no cuda/flashnext reader | #490 BlivionIaG 2026-10-07 (later #812, #3419) |
| `TENSORFOLD_LFM2_KV_PAGES` | lfm2_moe family | unset leases pool pages | capacity/layout, LFM2 only | NO | readers: families/lfm2_moe/cuda_native.zig, native/cuda_kv_pool.zig | #1503 jschmied 2026-10-27 (later #1508, #2107) |
| `TENSORFOLD_MEMORY_RESERVE_GIB` | cuda; native CUDA admission (all CUDA families) | unset = max(4 GiB, total/10) on unified, max(1 GiB, total/32) discrete | capacity: the GiB left free at admission; production exports 10 | YES | cuda_memory.zig:165-178; cli.zig:170 | #133 MiaAI-Lab 2026-09-30 and #165 eleqtrizit 2026-09-30 (the reader is older than the table row; the row came with the strict table) |
| `TENSORFOLD_UNIFIED_HOST_COUNTS` | cuda; native CUDA admission on integrated GPUs | unset = /proc/meminfo on native Linux (/proc/meminfo), CUDA pool under WSL2 | capacity: which host count admission uses; on GB10 the unset default is already procfs | YES | cuda_memory.zig:222-236 (wslPool), cuda_family_memory.zig | #2107 drowzeys 2026-11-04 (the CHANGELOG states 1 keeps /proc/meminfo and 0 reads the pool, native Linux unchanged) |
| `TF_CACHE_EVICT` | common; CUDA cache families incl qwen4_exp (Flash Next) | main | speed: victim choice only, a bounded resume credit for RAM snapshots; same stored state and token arithmetic | YES | profile.zig:144 lists qwen4_exp in cuda_cache; prompt_cache_decay.zig fromEnv() read by core/prompt_cache*.zig | #3258 ashhart 2026-11-13, refs #3241; the CHANGELOG quantifies 24.4-34.5% fewer rebuilt rows on agent traces through the real 16 GiB store |
| `TF_COST_KEY_TRACE` | qwen3_5 CUDA cost adapter | off | diagnostic: each cost key's parts on stderr | NO | only reader: families/qwen3_5/cuda_cost_adapter.zig:42 | none found |
| `TF_DSV41_PREFILL_PIECES` | DeepSeek-V4.1 CUDA and Metal | 0 | speed: prompt pieces between decode rounds | NO | readers: families/deepseek_v41/serve_engine.zig, cuda_model.zig | #2950 gilby 2026-11-11 (later #3566) |
| `TF_DSV41_ROUND_PROF` | DeepSeek-V4.1 Metal | 0 | diagnostic | NO | only reader: families/deepseek_v41/metal/round_prof.zig | #1720 gilby 2026-10-30 (later #2951, #2952) |
| `TF_FLASHNEXT_CHUNK` | flashnext CUDA (prompt passes) | 3072 rows (1..16384) | speed: prompt rows a pass while another stream decodes; row sums keep their order, replies unchanged (#3726 measured 6.4-17.2% faster cold prompts, token-identical) | YES | cuda_chunk.zig:13-25, cuda_batch_state.zig:56; flashnext reads it at load and per pass | #1733 jschmied 2026-10-31 added `TF_FLASHNEXT_CHUNK_SOLO`; #2246 ashhart 2026-11-05 the one-stream default; #3308/#3591 by devopsfortunato the check-by-name; #3726 BadAd84 2026-11-19 set the 3,072-row default (CHANGELOG.md) |
| `TF_FLASHNEXT_CHUNK_SOLO` | flashnext CUDA (one-stream passes) | unset = larger of CHUNK and 8192 on a server of one stream, else CHUNK (off) | speed: prompt rows a pass while no other stream decodes; changes one-stream TTFT only | YES | cuda_chunk.zig:27-45 (lone = --parallel 1 on one rank); the new default is the #2246 rule, the setting itself #1733 | #1733 jschmied 2026-10-31 (option C of #1554); #2246 ashhart 2026-11-05 the unset one-stream default of 8,192 rows (CHANGELOG.md) |
| `TF_FLASHNEXT_READOUT_FUSED` | flashnext CUDA (BF16 read-out) | off | speed: prompt passes of 768 rows or more take two fused tiles instead of five launches, same bits (our #3413) | YES | readout_fused.zig, cuda_batch_hc.zig:29 (n >= 768, BF16 shapes, prompt hook) | #3413 BadAd84 2026-11-15 (ours; merged; default off) |
| `TF_FLASHNEXT_SHARD_HEAD` | flashnext CUDA, TWO RANKS | off | two-rank layout: each rank keeps half the output head; shard() refuses world != 2 | TP=2 only | cuda_head.zig:14-22; only its own test calls shard | #1441 BlivionIaG 2026-10-27 (later #1442, #2982) |
| `TF_FLASHNEXT_SPLIT_DENSE` | flashnext CUDA, TWO RANKS | on | two-rank layout: each of two ranks keeps half the BF16 dense projections; world 1 never reads it | TP=2 only | cuda_dense_split.zig:38-42 applies() returns false at world != 2 | #2980 swbiggart 2026-11-12 (later #2982, #3749) |
| `TF_GLM_EXPERT_FORM` | glm CUDA | unset races the two at each timed width | speed: the expert form of GLM's decode windows, same bits | NO | readers: families/glm/cuda_lane_costs.zig | #3151 Bizuayeu 2026-11-13 (later #3249, #3807) |
| `TF_GLM_INDEX_CUDA` | glm CUDA | both | speed: which DSA indexer kernels run | NO | readers: families/glm/cuda_forward.zig, cuda_index.zig | #1352 Bizuayeu 2026-10-26 (later #1404, #1411) |
| `TF_GLM_KV_HOST_GIB` | glm CUDA | unset = one full window, 16 rows a page | capacity | NO | readers: families/glm/cuda_kv_host.zig, cuda_ranks.zig | #1795 russellmm 2026-11-01 (later #2177, #2578) |
| `TF_GLM_RANK` | glm CUDA, multi-host | unset = 1 rank | layout: rank index | NO | readers: families/glm/cuda_native.zig, fabric/mesh/launch.zig | #804 Bizuayeu 2026-10-13 (later #899, #900) |
| `TF_GLM_WORLD` | glm CUDA, multi-host | unset = 1 rank | layout: rank count | NO | readers: families/glm/cuda_native.zig, fabric/mesh/launch.zig | #804 Bizuayeu 2026-10-13 (later #899, #900) |
| `TF_METAL4` | Metal backend (DeepSeek-V4.1 by default there) | 0 (1 on Metal 4 Macs for DSV4.1) | backend: same kernels and order, Metal 4 queue | NO | readers: src/metal/*.zig, families/deepseek_v41/metal/boot.zig | #3374 ashhart 2026-11-14 |
| `TF_METAL4_TIMELINE` | Metal 4 | 0 | diagnostic: GPU stamps per stage of n rounds | NO | readers: src/metal/metal4_timeline.zig | #3374 ashhart 2026-11-14 |
| `TF_MINIMAX_RANK` | MiniMax-M3.1 CUDA, two hosts | unset = 1 rank | layout | NO | readers: families/minimax_m3/cuda_native.zig, fabric/mesh/launch.zig | none found |
| `TF_MINIMAX_WORLD` | MiniMax-M3.1 CUDA, two hosts | unset = 1 rank | layout | NO | readers: families/minimax_m3/cuda_native.zig, fabric/mesh/launch.zig | #3249 Bizuayeu 2026-11-13 |
| `TF_MTP_BATCH` | qwen3_5 CUDA MTP drafter | on | speed: a shared round drafts every stream in one pass | NO | only reader: families/qwen3_5/cuda_mtp.zig:124 | #1562 laudney 2026-10-28 |
| `TF_MTP_TREES` | qwen3_5 CUDA MTP drafter | off | speed: the planner's trees instead of chains | NO | only reader: families/qwen3_5/cuda_mtp.zig:121 | #856 BobClawblaw 2026-10-14 (later #2951, #2952) |
| `TF_NEMOTRON_RANK` | Nemotron CUDA, multi-host | unset = 1 rank | layout | NO | readers: families/nemotron/cuda_native.zig, fabric/mesh/launch.zig | #1062 Mirrdhyn 2026-10-19 (later #2919, #3558) |
| `TF_NEMOTRON_WORLD` | Nemotron CUDA, multi-host | unset = 1 rank | layout | NO | readers: families/nemotron/cuda_native.zig, fabric/mesh/launch.zig | #980 easthambuilds 2026-10-17 |
| `TF_NO_TREES` | qwen3_5 CUDA drafter | off | speed/layout: chains only, precedence over TF_DRAFT_NODES | NO | readers: families/qwen3_5/cuda_draft.zig:444, cuda_draft_tree.zig:14, cuda_sm110_modes.zig:36 | #978 BobClawblaw 2026-10-17 (later #2705) |
| `TF_Q27_GEMM` | qwen3_5 CUDA training ops | 128x128 tiles | speed/arithmetic of the training path | NO | only reader: families/qwen3_5/cuda_train_ops.zig | none found |
| `TF_Q27_POCKET_OFF` | qwen3_5 CUDA pocket diagnostics | off | diagnostic | NO | only reader: families/qwen3_5/cuda_pocket.zig | rate-limited; commit search only |
| `TF_Q27_TAIL` | qwen3_5 CUDA training | off | arithmetic of the training path | NO | only reader: families/qwen3_5/cuda_train.zig | none found |
| `TF_QWEN27_JOIN` | qwen27 Metal | 1 | speed: a window's rows in pairs in the decode tail before M5 | NO | only reader: families/qwen27/attention_join.zig | #3661 ashhart 2026-11-17 (later #3677) |
| `TF_QWEN27_METAL_KV_PAGES` | qwen27 Metal | 0 | layout, Metal only | NO | readers: families/qwen27/kv_pages.zig, attention.zig | #2283 jschmied 2026-11-05 (later #2436, #2464) |
| `TF_QWEN27_SHARED_PREFIX` | qwen27 Metal before M5 | 1 | speed: cached keys read through the prefix kernels | NO | only reader: families/qwen27/simd_attention.zig | #3677 hobbesd 2026-11-17 |
| `TF_QWEN27_SLOT_RESUME` | qwen27 Metal | on | speed: slot 0 resumes a later prompt | NO | readers: native/qwen27_lanes.zig, qwen27_slots.zig | #1434 akol1 2026-10-27 (later #1437, #1841) |
| `TF_QWEN35_CHUNK_SOLO` | qwen3_5 CUDA prompt passes | 4096 (off) | speed: solo prompt passes take 8192 rows | NO | readers: families/qwen3_5/cuda_solo.zig, cuda_prefill.zig, cuda_scratch.zig, cuda_engine.zig; no flashnext reader | #3060 javierbits 2026-11-12 (later #3294) |
| `TF_QWEN35_METAL_KV_PAGES` | qwen3_5 Metal | off | layout, Metal only | NO | readers: families/qwen3_5/kernels.zig, native/qwen35.zig | #1294 jschmied 2026-10-25 (later #2283) |
| `TF_QWEN_KEEP_LATE` | qwen3_5 CUDA cache | off | speed: defers a keep's rows to the next slot scan | NO | readers: families/qwen3_5/cuda_cache.zig:25, cuda_sm110_modes.zig:35 | #1824 jrb-ai 2026-11-01 (later #1958, #1982) |
| `TF_QWEN_KV_PAGE_TEST` | qwen3_5 CUDA cache | unset (off) | diagnostic/localisation: reads a cache through a page table in reverse | NO | readers: families/qwen3_5/cuda_cache.zig:75, cuda_sm110_modes.zig:34 | none found |
| `TF_QWEN_POOL_LOG` | qwen3_5 CUDA pages | off | diagnostic: the pool's census after a prompt pass | NO | only reader: families/qwen3_5/cuda_pages.zig:197 | none found |
| `TF_SHARED_PRICE_LOG` | common; core/lanes shared rounds (all families) | off | diagnostic only: logs the load-time costs and a line a priced shared round | YES | lanes/price_log.zig; shared_round.zig:105; flashnext imports lanes (cuda_chunk.zig:4, cuda_disk.zig:5) | #2687 ashhart 2026-11-09, refs #2605 (the CHANGELOG names the log as opt-in) |
| `TF_SLIDE_TAKE_OUT_CHECK` | slide scope, only with --slide | off | diagnostic: takes every kept lesson out again | NO | readers: server/slide.zig, server/server.zig (slide path) | #877 ZackSample 2026-10-15 (later #3018) |
| `TF_SLIDE_TAP_CHECK` | slide scope | off | diagnostic | NO | only reader: living/pocket_read.zig | #891 ZackSample 2026-10-15 (later #3018) |
| `TF_TIMING` | qwen3_5 CUDA (draft, MTP, round timing) | off | diagnostic: each call's wall time on stderr | NO | readers: families/qwen3_5/cuda_draft.zig, cuda_mtp.zig, cuda_round_timing.zig (flashnext has no reader) | #836 BobClawblaw 2026-10-14 |
| `TF_GLM_PDL` | glm CUDA | on (text changed: now also GLM's qmmf linears) | speed: dependent launches | NO | readers: families/glm/* (glm scope only) | #2578 Bizuayeu 2026-11-08 (later #3333, #3495) |
| `TF_FLASHNEXT_SCALE_INDEX` | flashnext Metal before tensor units | 1 (text changed from 0) | memory/speed on Metal: the 4-bit expert kernels read scales through a 16-bit index; ignored with --ssd-experts | NO | only reader: families/flashnext/engine_load.zig:210 (the Metal load; no cuda_* file mentions it) | #2760 ashhart 2026-11-10 (later #2784, #2805) |

## The reachable set, and what each needs


Ten names reach a Flash Next CUDA serve at TP=1, eight of them on the decode path:

1. `TF_FLASHNEXT_CHUNK` and `TF_FLASHNEXT_CHUNK_SOLO` (one image, environment only): prompt rows a pass. `CHUNK`
   applies while another stream decodes; `CHUNK_SOLO` applies when none does, and its UNSET default is the larger of
   `CHUNK` and 8,192 on a server of one stream (`--parallel 1` on one rank), the chunk elsewhere. Production runs
   `--parallel 8`, so the unset solo default is OFF there and on in a one-stream boot: the default is stream-count
   dependent and is measured on both.
2. `TF_FLASHNEXT_READOUT_FUSED`: prompt passes of 768 rows or more with the native BF16 read-out shapes; the data for
   making it the default.
3. `TF_CACHE_EVICT`: victim choice for RAM prompt-cache snapshots; measured on a resume workload, where the cell is
   the resumed prompt's TTFT and cached tokens.
4. `TF_SHARED_PRICE_LOG`: diagnostic; a boot, equal tokens and speed within noise is the whole test.
5. `TENSORFOLD_DEVICE_CHECK`, `TENSORFOLD_MEMORY_RESERVE_GIB`, `TENSORFOLD_UNIFIED_HOST_COUNTS`: startup and
   admission; a boot each, tokens equal and speed within noise, plus the memory line each boot prints.
6. `TF_FLASHNEXT_SPLIT_DENSE`, `TF_FLASHNEXT_SHARD_HEAD`: two-rank layout, inert at TP=1 (`applies()` returns false
   at world != 2; `shard()` refuses world != 2). They are the TP=2 set, run on spark4+spark5.

## Why the rest cannot reach us, in one line each

- `TF_TIMING`, `TF_COST_KEY_TRACE`, `TF_QWEN_POOL_LOG`: their only readers are in `src/families/qwen3_5/` and
  `src/families/qwen3_5/cuda_*`. Flash Next has its own `families/flashnext/cuda_mtp.zig`, `cuda_draft_*.zig` and
  cost files; `git grep -n qwen3_5 origin/main -- zig/src/families/flashnext` returns nothing.
- `TF_MTP_TREES`, `TF_MTP_BATCH`, `TF_NO_TREES`, `TF_QWEN_KEEP_LATE`, `TF_QWEN_KV_PAGE_TEST`,
  `TF_QWEN35_CHUNK_SOLO`, `TF_QWEN35_METAL_KV_PAGES`, `TF_QWEN27_*`, `TF_Q27_*`: same family boundary (qwen3_5,
  qwen27), with `TF_QWEN35_METAL_KV_PAGES` and the `TF_QWEN27_*` set also Metal-only.
- `TENSORFOLD_LFM2_KV_PAGES`: lfm2_moe family. `TENSORFOLD_HIP_MEMORY_LIMIT_GB`: HIP admission and the qwen3_5 HIP
  engine; the CUDA build never opens it.
- `TF_GLM_*`, `TF_MINIMAX_*`, `TF_NEMOTRON_*`: those families' own loads. `TF_GLM_PDL`'s text change (dependent
  launches now also on GLM's qmmf linears) is GLM-only.
- `TF_METAL4`, `TF_METAL4_TIMELINE`, `TF_DSV41_ROUND_PROF`, `TF_DSV41_PREFILL_PIECES`: Metal (the last one is
  DeepSeek-V4.1 on CUDA too, but that family is not Flash Next).
- `TF_SLIDE_TAKE_OUT_CHECK`, `TF_SLIDE_TAP_CHECK`: the `.slide` scope, read only when the server starts with
  `--slide`.
- `TF_FLASHNEXT_SCALE_INDEX`'s text change (default 0 -> 1, and the stored scale arrays not kept): its one reader is
  the Metal load (`engine_load.zig:210`, gated on `!device.tensorUnits()`); no `cuda_*` file in the family mentions
  it, so Flash Next on CUDA loads with the index off as before.

## What production's environment is worth on main

`~/qwen6-start-prod.sh` exports 52 settings. Of those, upstream main READS seven and ignores 45 (they are this
fork's own levers, absent from main's source):

| read by main | value | ignored by main (45) |
| --- | --- | --- |
| `TENSORFOLD_MEMORY_RESERVE_GIB` | 10 | every other `TF_FLASHNEXT_*` production name except the three below, plus `TENSORFOLD_IMAGE_TOKENS`, `TENSORFOLD_MAX_IMAGES`, `TENSORFOLD_NO_UPDATE_CHECK` (read only by the benchmark server), `TENSORFOLD_PROMPT_CACHE_WHOLE`, `..._WHOLE_MIN`, `TENSORFOLD_VISION_WORKSPACE_MIB`, `TENSORFOLD_WARM_TURNS` |
| `TENSORFOLD_VIDEO_TOKENS` | 16384 | |
| `TF_FLASHNEXT_BATCH_DRAWS` | 1 | |
| `TF_FLASHNEXT_CONFIDENCE` | -0.15 | |
| `TF_FLASHNEXT_DEPTH` | 15 | |
| `TF_FLASHNEXT_WINDOW` | 64 | |

`prod-readers.tsv` is the per-name count. So every arm boots main's engine with main's own defaults plus those six
values; the arms differ from each other in exactly one setting, and the receipt says so rather than calling the
baseline "the production serve".

