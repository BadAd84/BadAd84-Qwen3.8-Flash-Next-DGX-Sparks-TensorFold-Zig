# Knob receipt: every upstream setting that reaches the Flash Next CUDA serve

Status of this document, stated before any number: **the classification (step 1), the image, the harness and the
first measured boots are complete; the timing windows are IN FLIGHT on spark6 and their tables are not in this
document yet.** Nothing below is extrapolated: every figure is copied from a file under `box/`, and every section
that is not yet measured says so and names the marker to watch.

- Upstream main: `1ece6e6dbbc073582d50738ce8e73e3c3261a73b` (fetched from `ashhart/TensorFold`).
- Our campaign base: `964174ea05`. Set difference of `docs/environment.md`: **44 settings added** (the brief listed
  39; the difference also carries five `TENSORFOLD_*` names), 0 removed, 2 whose text changed.
- Image: one image from a verified `git archive` of that commit, every arm the same image and the same environment
  except one setting.

## The image

```
IMAGE [tensorfold-qwen38:knob-m-1ece6e6d] id=sha256:323872ff61fea2623dbf0580705c1f7e1e3a3f0b3130f22fc6c5700974328c1e created=2026-11-20T14:08:38.967368393Z kernels=embedded size=25174908060
  #10 0.120 SOURCE 1ece6e6dbbc073582d50738ce8e73e3c3261a73b
  #10 0.122 NVCC Cuda compilation tools, release 13.3, V13.3.73 Build cuda_13.3.r13.3/compiler.38244171_0 
  #10 0.146 ZIG 0.17.0
  #10 463.2 BUILD OK
```

The tree was verified blob by blob before compiling: `TREE MAIN/src manifest_sha
1ece6e6dbbc073582d50738ce8e73e3c3261a73b entries 12601 mismatches 0 extra_files 0`. The build took 463 s; the
container's binary reports `tensorfold-native 1.3.0` and `docker run --rm --entrypoint
/opt/tensorfold/native/bin/tensorfold-native tensorfold-qwen38:knob-m-1ece6e6d --version` printed it.

## Method

- One image, many boots. Settings vary by environment only, so a difference between arms is the setting.
- The base environment is production's own 52 `TENSORFOLD_*`/`TF_FLASHNEXT_*` lines from
  `~/qwen6-start-prod.sh`, printed per arm from the container's inspect. Checked against M1's `env.txt`: all 52 names
  are present, **no value differs from production's export**, and the recipe's `start.sh` adds its own 18 names
  (`TENSORFOLD_CUDA_KERNELS`, `TF_FLASHNEXT_DRAFTS`, `TF_FLASHNEXT_WARM_AHEAD`, ...), so an arm carries the same 70
  variables production's serve gets, plus the one knob it is testing. Upstream main READS seven of those 52
  (`TENSORFOLD_MEMORY_RESERVE_GIB`, `TENSORFOLD_VIDEO_TOKENS`, `TENSORFOLD_NO_UPDATE_CHECK` (benchmark server only),
  `TF_FLASHNEXT_BATCH_DRAWS`, `TF_FLASHNEXT_CONFIDENCE`, `TF_FLASHNEXT_DEPTH`, `TF_FLASHNEXT_WINDOW`) and ignores the
  other 45, which are this fork's own levers. `prod-readers.tsv` is the per-name evidence. So the baseline is main's
  engine with main's defaults plus those values, and the receipt says that rather than calling it the production serve.
- The checkpoint is `CHECKPOINT=nvfp4` (nvidia/Qwen3.8-Flash-Next-FP4-Local at b9ce18a6) for every arm, as the brief
  and every earlier receipt use. The container that was serving :8888 while these windows were prepared runs
  azampatti's INT4-AutoRound checkpoint, so these arms compare against each other, never against that serve's
  absolute numbers.
- Pass A: fresh boot, `bench_openai` greedy three reps, `bench_concurrent --tokens 256 --reps 3 --levels 1,2,4,6,8
  --alone --serial --temperatures 0` (code and chat), `--tokens 128 --reps 2 --levels 1,2,4,6 --temperatures 1.0,0`
  for the sampled exactness sweep, the golden prompts, `served_exactness drafts` and `turns`. Pass B: a second boot
  with `--prompt-cache-gib 0` at a 131,072-token window for cold TTFT at 2k, 8k, 32k and 64k, `bench_cache
  --require-cold` and `served_exactness fresh`. Pass P: one stream at 131,072 for the solo-chunk arms. Pass D: the
  resume-pressure bench for `TF_CACHE_EVICT`.
- The noise rule: each treatment has two runs and each window is bracketed by two main runs; a cell is slower when
  both treatment runs are under both main runs (for a latency: over) and the mean gap is over 1 percent, faster when
  both are over both and the gap is over 1 percent, level otherwise. A flagged cell gets one rerun in the same
  window; a repeat of slower is a loss.
- Exactness is separate from speed: greedy replies compared across arms by `token_sha256`, concurrent against solo at
  1, 2 and 4, drafted against `"draft": false`, a resumed reply against a fresh one on a cache-off server.
- Every probe records the server's MTP counters and the container log's request lines before and after itself, and
  the GPU temperature at both ends. An arm that saw a request it did not send, or whose boot or a probe failed, is
  rerun once on a fresh boot with its first attempt kept as `.rejected1`.

## Classification: one row per setting

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
| read by main | value | ignored by main (45) |
| --- | --- | --- |
| `TENSORFOLD_MEMORY_RESERVE_GIB` | 10 | every other `TF_FLASHNEXT_*` production name except the three below, plus `TENSORFOLD_IMAGE_TOKENS`, `TENSORFOLD_MAX_IMAGES`, `TENSORFOLD_NO_UPDATE_CHECK` (read only by the benchmark server), `TENSORFOLD_PROMPT_CACHE_WHOLE`, `..._WHOLE_MIN`, `TENSORFOLD_VISION_WORKSPACE_MIB`, `TENSORFOLD_WARM_TURNS` |
| `TENSORFOLD_VIDEO_TOKENS` | 16384 | |
| `TF_FLASHNEXT_BATCH_DRAWS` | 1 | |
| `TF_FLASHNEXT_CONFIDENCE` | -0.15 | |
| `TF_FLASHNEXT_DEPTH` | 15 | |
| `TF_FLASHNEXT_WINDOW` | 64 | |

The raw readers behind every "reaches" and "not reachable" cell are in `APPENDIX-reachability.md` (file and line per
setting, tests and the value table excluded), and the pull requests are in `prs.json`.

### First knob cells: `TF_FLASHNEXT_CHUNK=1536` against the base arm

Parsed from `out/w1/C1536/a/conc_t0.json` and `openai_t0.json` against M1's, one run a side so these are not yet
noise-ruled:

| prompt | streams | main tok/s | chunk1536 tok/s | gap |
| --- | --- | --- | --- | --- |
| chat | 1 | 41.7 | 41.6 | -0.24% |
| chat | 2 | 86.4 | 86.0 | -0.46% |
| chat | 4 | 155.8 | 155.7 | -0.06% |
| chat | 6 | 210.3 | 209.1 | -0.57% |
| chat | 8 | 256.5 | 256.6 | +0.04% |
| code | 1 | 72.9 | 72.6 | -0.41% |
| code | 2 | 137.1 | 137.3 | +0.15% |
| code | 4 | 242.9 | 242.2 | -0.29% |
| code | 6 | 307.8 | 306.0 | -0.58% |
| code | 8 | 372.7 | 370.0 | -0.72% |

Its greedy replies are identical to main's: `token_sha256` equal 1 of 1 at one stream, 2 of 2 at two, 4 of 4 at
four and 6 of 6 at six (the `chat` prompt; `code` the same), so the setting is token-neutral on the decode path, as
the family's own rule says.

Every decode cell is level within 0.72 percent, which is what the setting should do: the chunk sizes a prompt pass,
not a decode round, so the cell that can move is the cold TTFT one, which was still running. The receipt keeps the two
apart rather than calling a prompt knob a decode knob.

Its cold TTFT, which is the cell this setting can move (cache off, `--parallel 4`, medians of three):

| prompt | main (3072 rows) | chunk 1536 | gap |
| --- | --- | --- | --- |
| 2k | 1.009 s | 1.059 s | +4.96% |
| 8k | 3.732 s | 3.993 s | +7.00% |
| 32k | 15.049 s | 16.008 s | +6.37% |

So the smaller chunk costs 5 to 7 percent of cold prompt time at equal tokens, the direction our own #3726
receipt found when 3,072 replaced 1,536. One run a side so far (the second run and the 4096 and 6144 arms are
queued), so this is a measured gap and not yet a noise-ruled loss.

### An instrument defect found before it could lie

The first version of the cross-level comparison paired every evidence row of a one-stream cell with every row of an
N-stream cell, and reported 1 of 2 equal at temperature 1.0 on M1. The tool gives request i seed + i when sampled
(`tools/bench_concurrent.py`), so only request 0 of each rep is comparable across levels and the rest are different
draws by design. Comparing request 0 per rep, M1's contract is 2 of 2 at 2, 4 and 6 streams for both prompts and both
temperatures. Recorded because a wrong instrument here would have reported a knob as changing tokens.

## Measured so far: the base arm of window 1

The first boot of the base arm (`M1`, production's environment, main's own defaults) is complete and its decode
numbers are parsed from `out/w1/M1/a/openai_t0.json` and `out/w1/M1/a/conc_t0.json`:

| cell | aggregate tok/s | per stream | tokens a round |
| --- | --- | --- | --- |
| code, 1 stream (greedy) | 72.9 | 72.9 | 5.689 |
| code, 2 streams | 137.1 | 69.5 | 4.83 |
| code, 4 streams | 242.9 | 62.5 | 4.83 |
| code, 6 streams | 307.8 | 53.3 | 4.491 |
| code, 8 streams | 372.7 | 49.0 | 4.491 |
| chat, 1 stream (greedy) | 41.7 | 41.7 | 3.012 |
| chat, 8 streams | 256.5 | 33.1 | 2.51 |

Its cold TTFT (pass B, cache off, `--parallel 4`, 131,072-token window), medians of three from `ttft.out` and
`ttft64.out`: 2k **1.009 s**, 8k **3.732 s**, 32k **15.049 s**, 64k **30.606 s**. Its cache-off checks: `fresh` **7 of
7** clean (each resumed reply equal to the fresh plain and drafted ones by `token_ids`), and `bench_cache`
`qualified: true` with every request cold (0 cached tokens). Pass A's boot-to-boot wall time was 13 minutes, pass B
about 4, and the boot itself 37.1 s. **The base arm is therefore measured end to end**, so the baseline exists even if
a later window slips.

Its exactness contracts, parsed from `out/w1/M1/a/drafts.json` and `out/w1/M1/a/turns.json`: drafted equals
`"draft": false` **8 of 8** (basis `token_ids`), and **7 of 7** turns resumed from cached prompt tokens
`[13, 16, 16, 13, 24, 18, 3406]`. All six of pass A's probes returned rc 0 (`openai_t0`, `conc_t0`, `conc_t1`,
`golden`, `drafts`, `turns`), and the GPU temperature at their ends was 52 to 64 C.

Its boot line, from the container's own startup log: `model 73.50 GiB; 8 streams at once, 1.32 GiB each at a
32768-token window, of 26.0 GiB left after a 10.0 GiB reserve; prompts in passes of up to 3072 rows, a 15.4 GiB
prompt cache; own glue kernels`. The 3,072 rows is main's new default (our #3726, previously 1,536), and the 10.0
GiB reserve is production's `TENSORFOLD_MEMORY_RESERVE_GIB=10` reaching main.

## Windows: state and how they finish

Three windows are queued FIFO on `~/work/gpu.lock`, each from its own detached driver; window 1 holds the lock and is
running its arms.

| window | arms | state |
| --- | --- | --- |
| w1 | base pair M1/M2 around `TF_FLASHNEXT_CHUNK=1536` (twice) and `TF_FLASHNEXT_READOUT_FUSED=1` (twice) | running: M1 complete (all 11 probes rc 0, exactness clean), C1536 next |
| w2 | base pair around `CHUNK=4096`, `CHUNK=6144`, `CHUNK_SOLO=3072` (each twice), plus `TF_SHARED_PRICE_LOG=1`, `TENSORFOLD_DEVICE_CHECK=0`, `TENSORFOLD_UNIFIED_HOST_COUNTS=0`, `TENSORFOLD_MEMORY_RESERVE_GIB` unset (each twice, pass A only) | queued |
| w3 | base pair around `TF_CACHE_EVICT=decayed_resume` (resume bench plus decode 1/2) and the one-stream solo arms: `CHUNK_SOLO` unset (8,192 rows), 3,072, 16,384 | queued |

Finish and analyse, on spark6 (`HANDOFF.md` has the same text plus the recovery path):

```
tail -5 ~/work/KnobTest/out/w{1,2,3}/run.log            # ARM-OK / ARM-FAILED / RESTORE / DONE
cat  ~/work/KnobTest/out/w{1,2,3}/production.txt        # the restored serve's /health code
python3 ~/work/KnobTest/scripts/analyze_knobs.py ~/work/KnobTest/out/w1 --base M1,M2 --write
```

then `bash fetch.sh` from the laptop, `bash finalstate.sh` on the box, and `make_result.py` here. Production is
restored by each window's own EXIT trap (`./stop.sh` then `LOCK_HOLDER=0 ~/qwen6-start-prod.sh`, `/health` polled to
200 and written to `production.txt`), so a driver that ends for any reason leaves :8888 up.

## Not run, and why

# Cells and knobs not taken, with the reason

## The two-rank knobs: `TF_FLASHNEXT_SPLIT_DENSE`, `TF_FLASHNEXT_SHARD_HEAD` are NOT RUN

They are layout knobs of the Flash Next two-rank path. `cuda_dense_split.zig`'s `applies()` returns false when
`world != 2` and `cuda_head.zig`'s `shard()` refuses `world != 2`, so at TP=1 they are read only for their value and
change nothing. The TP=2 pair boxes were idle and permitted (checked 2026-11-20 13:52 UTC: no `flock` holder, no
container, GPU 0 percent at 41 and 38 C on spark4 and spark5), so idleness was not the obstacle:

- neither spark4 nor spark5 holds the checkpoint the family serves: `~/.cache/huggingface/hub` has
  `models--deepseek-ai--DeepSeek-V4.1-Flash-1017` and the Mia-AI-Lab EXL3 of it, and NO
  `models--nvidia--Qwen3.8-Flash-Next-FP4-Local`;
- the checkpoint is 96 GiB (`scripts/config.sh`: `CKPT_GIB=96`) and spark5 had 72 GiB free on `/home` (92 percent
  used), so it does not fit even before the ~25 GiB runtime image; spark4 had 116 GiB;
- spark6 does not export its cache over NFS (`/etc/exports` holds only the commented example) and no pair box has an
  NFS or 9p mount of it, so a shared read is not available either;
- spark6 cannot ssh to spark4 (`Permission denied (publickey,password)`), so an image transfer needs a key first.

What WOULD take them: a 96 GiB download onto spark4 and spark5 (or an NFS export of spark6's cache and a key), then
the documented two-rank start (`tensorfold-native serve <ckpt> --tp 2 --rank N --master <spark4>` with
`--prompt-cache-gib 0`, `NCCL_SOCKET_IFNAME` and `NCCL_IB_HCA`), one arm at `SPLIT_DENSE=1` (its default) and one at
`0`, one at `SHARD_HEAD=0` (its default) and one at `1`, decode at 1, 2 and 4 streams with token equality against
the default. The pair has never served this family in this repo, so the first boot would also have to prove the
TP=2 path itself.

## Cells not taken inside the windows that DID run

- The cold TTFT cells are `--loads idle` only. `ttft.py`'s `load3` (three other streams decoding) is not run: the
  decode table already gives the beside-decoders picture through `bench_concurrent` at 2, 4, 6 and 8 streams, and a
  `load3` pass would add about 2.5 minutes a boot to every prompt-touching arm.
- The pass A exactness probes use `--tokens 128 --reps 2` for the sampled (temperature 1.0) cells and the greedy
  cells of the decode pass for temperature 0; a longer sampled run is not taken.
- `TF_CACHE_EVICT`'s resume cell is one 9,000-token conversation under 14 fillers then 10 more (`resume_bench.py`),
  not a replay of a real agent trace; the policy's own receipt (#3258) measured agent traces, this receipt measures
  whether the policy changes a resume in OUR budget.

## Gates and cells not taken

- The golden probe's coverage is now established, not assumed. `bench_concurrent --prompts FILE` runs ONE cell where
  request i sends item i modulo the list's length (`tools/bench_concurrent.py`, line 298), so at `--levels 1,2,4,6` it
  sends 1, 2, 4 and then all 6 of `~/work/target/exact15/golden.json`'s prompts. M1's `golden.json` shows exactly that:
  4 cells, and the six-stream cell carries 6 evidence rows with prompt sizes 24, 24, 28, 22, 25, 28. Equality across
  arms is therefore compared position by position in that cell, where position i is prompt i.
- Cold TTFT is `--loads idle` only; `ttft.py`'s `load3` is not run (the decode table gives the beside-decoders
  picture at 2 to 8 streams).
- `TF_CACHE_EVICT`'s cell is one 9,000-token conversation under 14 then 10 filler prompts, not a real agent trace.
- The two-rank knobs are not run (see above).

## Verdict per knob

| setting | verdict |
| --- | --- |
| `TF_FLASHNEXT_CHUNK` | PENDING |
| `TF_FLASHNEXT_CHUNK_SOLO` | PENDING |
| `TF_FLASHNEXT_READOUT_FUSED` | PENDING |
| `TF_CACHE_EVICT` | PENDING |
| `TF_SHARED_PRICE_LOG` | PENDING |
| `TENSORFOLD_DEVICE_CHECK` | PENDING |
| `TENSORFOLD_MEMORY_RESERVE_GIB` | PENDING |
| `TENSORFOLD_UNIFIED_HOST_COUNTS` | PENDING |
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

Not yet measured, and therefore not verdicts: `TF_FLASHNEXT_CHUNK`, `TF_FLASHNEXT_CHUNK_SOLO`,
`TF_FLASHNEXT_READOUT_FUSED`, `TF_CACHE_EVICT`, `TF_SHARED_PRICE_LOG`, `TENSORFOLD_DEVICE_CHECK`,
`TENSORFOLD_MEMORY_RESERVE_GIB`, `TENSORFOLD_UNIFIED_HOST_COUNTS`. Their windows are in flight; the tables that will
carry them are the ones `analyze_knobs.py` writes.

## After the windows (pending, exact commands)

```
# from the laptop
ssh root@proxmox.ots-int.net "pct exec 111 -- systemctl start sparkdash"      # it is inactive now
ssh root@proxmox.ots-int.net "pct exec 111 -- systemctl is-active sparkdash"  # record: must print active
# on spark6, after the last window and after the evidence is fetched
bash ~/work/KnobTest/finalstate.sh
rm -rf ~/work/KnobTest && docker rmi tensorfold-qwen38:knob-m-1ece6e6d    # teardown; recorded in ~/INVENTORY.md
```
