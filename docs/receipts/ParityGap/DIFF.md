# Parity diff, evidence annex

Companion to `PLAN.md` (same directory): the full lists and the quoted read sites behind its tables.
Sources: `docs/receipts/ParityAB/ev.tgz` (extracted under `work/ParityGap/ev/`), the production branch
(`git show production:...`, tree `5c3e3e29`), the dev tree `work/ParityGap/DevTree` (upstream `1ece6e6d` +
the 40 patches of `patches/main-1ece6e6db-r5-dev/`), and the box's own files (`ev/box-*.sh`, copied
2026-11-24).

## 1. Effective launcher environment

`ev/env-P-container.txt` (54 names, from `docker inspect ... .Config.Env` at the P boot) against
`ev/env-D-container.txt` (150 names, same capture at the D boot). Classification: `ev/envdiff.txt`.

```
P names 54 D names 150 both 53 onlyP 1 onlyD 97 both-different 1
only-P:
  TF_FLASHNEXT_MTP_FP8 = /root/.cache/huggingface/tensorfold-mtp-fp8/azampatti--Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound/1464274120d36a4d8fcaa934552334a7d83ce0fd
both but different:
  TENSORFOLD_CUDA_KERNELS P= /opt/tensorfold/share/tensorfold/cuda/sm121 D= native
```

The one value that differs is the kernel set. P's recipe injects it and refuses the env's own value
(`ev/box-start-prod.sh:169` `ENV_ARGS=(-e HF_HUB_OFFLINE=... -e TENSORFOLD_CUDA_KERNELS="$KERNELS_PATH")`,
`:171` `[[ "$name" == TENSORFOLD_API_KEY || "$name" == TENSORFOLD_CUDA_KERNELS ]] && continue`); the dev
recipe forwards `^(TENSORFOLD|TF_)_[A-Z0-9_]+=` (`ev/box-start-dev.sh:168-172`), so `dev.env`'s
`TENSORFOLD_CUDA_KERNELS=native` reaches the container.

### Names both arms set that D's tree does not read (43)

From `ev/namecheck.txt` (`DEAD-ON-D` intersect the shared names). These are production-engine levers carried
into `dev.env` at production values:

```
TENSORFOLD_IMAGE_TOKENS TENSORFOLD_MAX_IMAGES TENSORFOLD_PROMPT_CACHE_WHOLE TENSORFOLD_PROMPT_CACHE_WHOLE_MIN
TENSORFOLD_VISION_PYTHONPATH TENSORFOLD_VISION_WORKSPACE_MIB TENSORFOLD_WARM_TURNS
TF_FLASHNEXT_BATCH_WINDOWS TF_FLASHNEXT_COPY_MISS TF_FLASHNEXT_COPY_RAMP TF_FLASHNEXT_COPY_RESYNC
TF_FLASHNEXT_COPY_SHARED TF_FLASHNEXT_COST_RETIME TF_FLASHNEXT_DEPTH TF_FLASHNEXT_DRAFT_CONTINUE
TF_FLASHNEXT_DRAFT_DEPTH_SHARED TF_FLASHNEXT_DRAFT_INT4 TF_FLASHNEXT_DRAFT_PROPOSE TF_FLASHNEXT_EARLY_DRAW
TF_FLASHNEXT_FP8_FUSED_SPLIT TF_FLASHNEXT_FP8_PROMPT_TILES TF_FLASHNEXT_MULTI_LRU TF_FLASHNEXT_MULTI_MAX
TF_FLASHNEXT_MULTI_VERIFY TF_FLASHNEXT_NGRAM_LATE TF_FLASHNEXT_NGRAM_PREFETCH TF_FLASHNEXT_NGRAM_RANDOM
TF_FLASHNEXT_NGRAM_THREADS TF_FLASHNEXT_PREFILL_ROWS TF_FLASHNEXT_PRODUCT_STREAMS TF_FLASHNEXT_PROMPT_HEAD_SKIP
TF_FLASHNEXT_QSA_SELECT TF_FLASHNEXT_QSA_TILE TF_FLASHNEXT_REDUCE_ACT TF_FLASHNEXT_SEQ_POOL
TF_FLASHNEXT_SHARED_COST_LEVELS TF_FLASHNEXT_SHARED_EARLY_ROWS TF_FLASHNEXT_SHARED_SLOT_LD
TF_FLASHNEXT_SOLO_MAX TF_FLASHNEXT_UPMIX_DECODE TF_FLASHNEXT_WARM_POOL TF_FLASHNEXT_WINDOW TF_FLASHNEXT_YARN
```

Four of them have a live dev counterpart under another namespace, and D's boot proves the production
values are not in force (`ev/bootlines-D.txt` `copy policy: miss first, ramp double, shared rounds first
width, resync off`):

| P name and read site | D's reader | D's default |
|---|---|---|
| `TF_FLASHNEXT_COPY_MISS` production `zig/src/native/cuda.zig:289` | `TENSORFOLD_COPY_MISS` `DevTree/zig/src/native/cuda_startup_phase.zig:23` | `.first` (`core/lanes/config.zig:120,127`) |
| `TF_FLASHNEXT_COPY_RAMP` `cuda.zig:290` | `TENSORFOLD_COPY_RAMP` `cuda_startup_phase.zig:27` | `.double` (`config.zig:122,128`) |
| `TF_FLASHNEXT_COPY_SHARED` `cuda.zig:292` | `TENSORFOLD_COPY_SHARED` `cuda_startup_phase.zig:31` | false |
| `TF_FLASHNEXT_COPY_RESYNC` `cuda.zig:297` | `TENSORFOLD_COPY_RESYNC` `cuda_startup_phase.zig:32` | false |
| `TF_FLASHNEXT_COPY_RESYNC_PROMPT_ONLY` `cuda.zig:298` | `TENSORFOLD_COPY_RESYNC_PROMPT_ONLY` `cuda_startup_phase.zig:33` | true (inert while resync is off) |

The print that states each side's values: production `zig/src/native/cuda.zig:299`; dev
`native/cuda_startup_phase.zig:34`. The captured boots print them (P: `keep ... jump ... resync on
(copies out of the prompt), shared rounds ramp copies out of the prompt`; D: `miss first, ramp double,
shared rounds first width, resync off`).

### Names only D sets that its own tree reads (91 of 97)

D's own levers and explicit defaults, from `ev/envdiff.txt`. The serve-shaping ones:
`TF_FLASHNEXT_CHUNK=4096`, `CHUNK_SOLO=16384`, `DRAFTS=6`, `DRAFTS_GREEDY=8`, `GREEDY_WIDE=4`,
`SHARED_DRAFTS=0`, `DECODE_GRAPH=0`, `WINDOW_CHECK=1`, `KV_PAGES=4096`, `GATHER_*` (7 names),
`READOUT_FUSED=1`, `READOUT_FUSE=0`, `PROMPT_SHARED_DIRECT=1`, `PROMPT_GEMM2=1`, `PROMPT_HC2=1`,
`HEAD_PIECE=1536`, `PROMPT_EXPERT_TILE_ROWS=256`, `HOST_DRAW_THREADS=7`, `SAMPLE_CAND=1`,
`KEEP_LATE=1`, `WARM_AHEAD=1`, `DRAFT_AHEAD=1`, `SPLIT_DENSE=1`, plus the fused/lane/attention switches
at their engine defaults. The six only-D names dead even in D's tree: `TENSORFOLD_IMAGE_TOKENS`,
`TENSORFOLD_MAX_IMAGES`, `TENSORFOLD_PARALLEL`, `TENSORFOLD_PROMPT_CACHE_WHOLE`,
`TENSORFOLD_PROMPT_CACHE_WHOLE_MIN`, `TENSORFOLD_VISION_PYTHONPATH`, `TENSORFOLD_VISION_WORKSPACE_MIB`
(vision off, recipe-owned names).

## 2. Recipe settings (box copies, `ev/cfgdiff.txt`)

`ev/box-config-prod.sh` against `ev/box-config-dev.sh`. Differing settings:

```
TF_REF            prod db281878ddb836fd0df510d8771ecb7e0fe47d26   dev eab8582819688325e371907e4706e1c602b8a273 (v1.1.4)
TF_TAG            prod zig-${TF_REF:0:7}                            dev v1.1.4-${TF_REF:0:7}
PARALLEL          prod 8                                            dev 5
TENSORFOLD_MEMORY_RESERVE_GIB prod 10                               dev 9
TF_FLASHNEXT_PRODUCT_STREAMS  prod 2                                dev 5
KERNELS_PATH      prod /opt/tensorfold/share/tensorfold/cuda/sm121  dev absent
KERNEL_SOURCE_MTIME prod 1791318675                                 dev absent
TF_FLASHNEXT_DEPTH prod 15                                          dev absent
TF_FLASHNEXT_YARN  prod computed (0 at 262144)                      dev absent
TF_FLASHNEXT_CONFIDENCE prod absent (engine -0.4)                   dev -0.4
TF_FLASHNEXT_DRAFTS prod absent                                     dev 6
CHECKPOINT / MODEL_ID / CKPT_GIB / QUANT_LABEL / WEIGHTS_GIB / MIN_FREE_GB  presets vs one checkpoint
supplied by dev: SAMPLED_HEADS=1 SAMPLE_CAND=1 GATHER_EARLY=1 GATHER_READ=pread HOST_DRAW_THREADS=7
  KEEP_LATE=1 DRAFT_AHEAD=1 WARM_AHEAD=1 PROMPT_HC2=1 PROMPT_GEMM2=1 PROMPT_SHARED_DIRECT=1
  HEAD_PIECE=1536 PROMPT_EXPERT_TILE_ROWS=256 SHARED_SIDE=1 GDN_LANES=1
supplied by dev image block: LIBJPEG_TURBO_VERSION/SHA256, LIBWEBP_VERSION/SHA256, TF_RELEASE_VERSION,
  TF_RELEASE_AARCH64_SHA256
```

Both launchers pass `PARALLEL=8`, `CONTEXT=262144`, `TENSORFOLD_MEMORY_RESERVE_GIB=10`,
`TF_FLASHNEXT_CONFIDENCE=-0.15`, `TF_FLASHNEXT_PRODUCT_STREAMS=8`, so those recipe defaults are inert at
the boot. The KV flag differs by engine spelling only: `--kv-dtype` (prod `ev/box-start-prod.sh:47`)
against `--kv-cache` (dev `ev/box-start-dev.sh:46`), both `fp8`.

The production banner is hard-coded `bf16 KV` (`ev/box-start-prod.sh:255`), and `PRODUCTION.md` repeats
that; the argv and the engine's own line say fp8 (`ev/env` meta `kv_dtype=fp8`;
`info: sequence memory: ... fp8 KV cache, 1056 bytes a position a layer`). The banner is a misprint, not
the served format.

## 3. Patch sets and the lever map

P (`PRODUCTION.md`, production branch): upstream `db281878d`, the MiaAI recipe's patches 0001-0009, our
`0010`-`0028`, `tfm-fixes`, `tfm-warm-t`, the zmerge8 keep set `27b6700cb` (`c68-shared-cost-levels`),
and `kindling 0002` (`5c3e3e29`); `git log --oneline 3289c9eb..production -- zig` names all 23 engine
commits. D: upstream `1ece6e6d` + the 40 patches (`patches/main-1ece6e6db-r5-dev/README.md`).

The recipe's nine arrive squashed as `3289c9eb recipe-patched` on `db281878`
(`git show --stat 3289c9eb`): the fp8 KV Python path (`qwen4_exp/cuda/kv8.py` 312 lines, `kv8_multi.py`
84, `kvcache.py`, `weight_types.py`, `weights.py`, `engine.py`, `forward.py`), the prompt-matmul Triton
source `qwen4_exp/cuda/prompt_mm.py` (218 lines - the `_b16mm_ks`/`_fp4mm_ks` kernels P's boot line
names), `yarn.py` (177), the vision helper (`vision/native_helper.py` 243, `qwen_cuda.py`), the captured
set's packer `tools/zig/aot_pack.py` (96 - this is what builds the sm121 kernel set), the LSE oracle
`tools/zig/check_flashnext_lse.py` (68, 0010's check), and CLI/capacity plumbing. So P's captured prompt
matmuls are MiaAI's Triton kernels, packed by `aot_pack.py`, and loaded unconditionally by P's engine;
D's tree contains no `b16mm` of any kind (`grep -rn b16mm work/ParityGap/DevTree/zig` finds nothing).

The map is in `PLAN.md` section 3, one row a lever. Summary of the verdicts:

- carried under a different name or mechanism: 0011 (mtp-fp8 overlay against 0014 mxfp8 recode), 0012
  (ngram host gather against 0004/0012), 0013 (copy window against 0001 + `WINDOW_CHECK`), 0017
  (batched draws), 0018/0019 (fused split and read-out fusion), 0020 (draft stop lines against
  `CONFIDENCE` + `SHARED_DRAFTS`), 0022 (12-bit read-outs), 0024 (prompt FP8 tiles/int4 gate-up against
  0005/0006/0021), 0025 (retime against 0010 round-cost), 0028 (shared expert) - carried;
- **not carried by D at all**, in name or in code: 0010 (argmax-LSE rows; no LSE-row decode in D's tree),
  0016 (sequence pool; no `seq_pool` anywhere in D's tree), 0021 (sliced fill; P's own default off), 0023
  (indexer select scores tile; D's tree has `qsa` only in contract records, no implementation), 0026
  (first token; no `first_early` in D's tree), 0027 (whole-prompt cache; D's cache is the tier/device
  cache);
- carried as a namespace change that D's env never states: **0014 copy-resync and 0015 copy-shared-rounds**
  (the four `TENSORFOLD_COPY_*` names unset), plus `TF_FLASHNEXT_COPY_MISS`/`COPY_RAMP` from the same
  block.

D-only levers with no P counterpart: 0003/0015 (fp8 KV and the page pool), 0007 (draft head 4-bit
default), 0011 (vision decode; D serves vision off), 0023-0026 (the persistent KV tier and its budget
refusals), 0027/0028 (draft-head format pair), 0029-0032 (int4 contract suite), 0034-0040 (test-fixture
and pin corrections).

Read sites behind the two levers this window measures:

```
P: production:zig/src/families/flashnext/cuda_prompt.zig:1-8   prompt matmuls `_b16mm_ks`/`_fp4mm_ks` come
   from the captured set (prompt_mm.py "in the kernel set"); `TF_FLASHNEXT_PROMPT_MM=0` keeps Python's
   two launches ("the A/B and the fallback"), and the print names both
   (production:zig/src/families/flashnext/cuda_engine.zig:649,783)
P: production:zig/src/native/cuda.zig:285-299                   the copy policy TF_FLASHNEXT_COPY_*
D: DevTree/zig/src/native/cuda_startup_phase.zig:21-34          the copy policy TENSORFOLD_COPY_*
D: DevTree/zig/src/core/lanes/config.zig:120-128                CopyMiss.first / CopyRamp.double defaults
D: DevTree/zig/src/families/flashnext/cuda_lanes_load.zig:33    a captured set is refused at fp8 KV
P: production:zig/src/families/flashnext/cuda_engine.zig:582    the captured set is loaded unconditionally
```

## 4. Boot-line evidence (`ev/bootlines-P.txt`, `ev/bootlines-D.txt`)

The P lines (all non-layer lines):

```
[tensorfold] vision: image and video input on this GPU, a 0.84 GiB tower ...
info: copy windows: a lone stream verifies up to 64 rows (TF_FLASHNEXT_WINDOW; the MTP chain 16)
info: cost timing: shared rounds timed with 0 head levels (TF_FLASHNEXT_SHARED_COST_LEVELS)
info: overlay /root/.cache/huggingface/tensorfold-mtp-fp8/.../mtp-fp8.safetensors
info: draft head: the int4 lm_head's own columns (TF_FLASHNEXT_DRAFT_INT4), 79592 ids, 105.1 MB
info: n-gram table on the host: 32 gather threads (blocks from 32 rows), prefetch on (2 chunks ahead), pages read one at a time (MADV_RANDOM)
info: block-FP8 split-K shapes of 2048+ columns below 256 rows: one block a column tile, its K slices in slice order (TF_FLASHNEXT_FP8_FUSED_SPLIT=4)
info: block-FP8 prompt tiles from 256 rows: one-slice shapes of 8192+ columns on 128x128 tiles, the fused form in 2 stages (TF_FLASHNEXT_FP8_PROMPT_TILES=1)
info: int4 prompt gate/up: int4_prompt_kernel on 64-pair items, 2x4 warps, 2x4 tiles, 3 stages (TF_FLASHNEXT_INT4_PROMPT_GATE_UP=1)
info: int4 lm_head: calls of 17 or more rows in 32-row items (TF_FLASHNEXT_HEAD_ROW_TILES=2)
info: greedy draws: a draft level's in one launch, a shared round's windows in one launch
info: draft stop: a draft proposed while the running product is >= 0.050, another head level while it is >= 0.200
info: shared expert: forked before the router in decode windows of at most 6 rows (0: never); down stored straight into its moe_y slot: true
info: graphs: shared verify rounds of up to 1 streams captured, MTP steps of up to 4; 192 shared graphs kept (least recently used out first), solo graphs least recently used out past TF_FLASHNEXT_SOLO_MAX; sequence pool 8
info: first token: drawn before the last chunk's MTP absorb; the MTP head of a one-prompt pass stops after its layer; the host n-gram gather beside the layers before the first n-gram layer
info: decode read-outs: up projection and mix in one pass (_hc_up_mix BM 32)
info: decode read-outs: _reduce and _hc_act in one launch (tf_fn_hc_reduce_act_kernel, checked against the kernel set at load)
info: qsa select: the indexer's block lists from fn_qsa_stream (decode: cs4 from 32768 blocks, s5 below; prompt blocks: s5)
info: hc q12: decode read-outs from 12-bit copies: 192 matrices, 1266.2 -> 970.8 MB, 95876 escapes
info: caches in reserved address space (2048 KiB granularity), indexer keys in a ring
info: vision: 2.00 GiB kept free for the image tower's workspace
info: sequence memory: 28.57 GiB (40.57 GiB free, 10.0 GiB kept free); fp8 KV cache, 1056 bytes a position a layer
info: drafts: at most 7 a stream while two or more streams draft together (TF_FLASHNEXT_DRAFT_DEPTH_SHARED)
info: cost timing: 26 points timed again over 2 more passes (TF_FLASHNEXT_COST_RETIME=4)
info: graph warm-up: 384 graphs on 8 pooled sequences
info: copy policy: after a missed copy round keep, after a clean one jump, resync on (copies out of the prompt), shared rounds ramp copies out of the prompt
info: prompt cache: whole-prompt states from 1024 tokens (that very prompt again resumes with no prompt pass)
[tensorfold] prompt chunks of up to 2,048 tokens, cut at replies 256+ tokens apart
[tensorfold] serving Qwen3.8-Flash-Next at http://127.0.0.1:8888/v1 (...; loaded in 84.8s)
```

The D lines (layer lines removed):

```
info: int4 kernels: prompt gate/up int4_prompt_kernel, lm_head 32-row items past 16 rows
info: flashnext: read-outs in 12 bits: 194 matrices, 1.07 GB beside their rows (76.2% of them), 97079 escapes
info: flashnext: prompt passes of 16384 rows, 4096 while another stream decodes
info: flashnext: the drafter's BF16 linears kept as mxfp8 (TF_FLASHNEXT_MTP_WEIGHTS)
info: flashnext: window self-check: 1176 of 1176 rows byte-equal to their one-token steps (widths 1-48)
info: flashnext: serving 48-row copy windows after the self-check
info: KV page groups: one page 73.75 MiB, 4096 rows of the full group; full: layers not named, 18.44 KiB a token, 4096 rows a page, 0 B padding (0.0 %); state run, in the pool: 673.39 MiB on 10 pages, 64.11 MiB padding (8.7 %); snapshot, outside the pool: 110.29 MiB on 2 pages, 37.21 MiB padding (25.2 %)
info: qwen4_exp: conversation states on disk in /cache/kv/fd57234d6ba38d2d (0 states, 0 MiB of 61440 MiB)
info: copy policy: miss first, ramp double, shared rounds first width, resync off
[tensorfold] chat template: the checkpoint's
[tensorfold] CUDA sm_121 device 0 (NVIDIA GB10, memory shared with the host): model 75.85 GiB; 8 streams at once, the engine's own at a 262144-token window (5.27 GiB, in the model's), 7 more taking 220 pages of 4096 rows (15.84 GiB) as they need them, 0 MiB fixed each, of 27.2 GiB left after a 10.0 GiB reserve; prompts in passes of up to 16384 rows, a 6.0 GiB prompt cache; own glue kernels
[tensorfold] prompt cache: device budget not reported, disk tier at /cache/kv
[tensorfold] profile: stable; registered overrides: TF_FLASHNEXT_KV_PAGES=4096 (experimental, env)
[tensorfold] serving Qwen3.8-Flash-Next at http://127.0.0.1:8888/v1 (...; loaded in 148.3s)
```

Boot timelines (`grep elapsed`): P `15s 12.6 GiB, 30s 31.3 GiB, 45s 50.9 GiB, 60s 72.3 GiB, 75s 74.4
GiB`; D `15s 8.4 GiB, 30s 16.3 GiB, 45s 24.3 GiB, 60s 33.5 GiB, 75s 41.5 GiB, 91s 49.5 GiB, 106s 57.4
GiB, 121s 65.4 GiB, 136s 75.8 GiB`. P streams about 1.2 GiB a second, D about 0.54, which is the 60 s
of the boot delta; the tier's own cost at boot is the state scan (`0 states, 0 MiB of 61440 MiB`) and the
6.0 GiB prompt-cache plan is an allocation, not an IO.

The KV lines are not like for like and must be read with the checkpoint's geometry: 48 layers,
`full_attention_interval 4` -> 12 full-attention layers, `num_key_value_heads 2`, `head_dim 256`
(`config.json` on the box). fp8 K+V is therefore 2 x 2 x 256 = 1,024 B a position a full layer, and P's
`1056 bytes a position a layer` is that plus 32 B of per-row scales over 12 layers = 12.38 KiB a token of
KV. D's `18.44 KiB a token` is its full page group's row (`73.75 MiB / 4096 rows`); the 6.06 KiB beyond P's
12.38 KiB is consistent with the group also holding the indexer's keys (12 layers x 512 B bf16 = 6.0 KiB),
which is an inference from the arithmetic, not a cited read site. P keeps the indexer keys
outside its quoted figure, in a ring ("caches in reserved address space ..., indexer keys in a ring"). So
both arms serve fp8 KV of the same width and the two print sites measure different sets; there is no
KV-width difference to attribute.
