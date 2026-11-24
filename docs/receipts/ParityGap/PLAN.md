# Parity gap attribution: the diff, the ranked candidates, and the window

Window: spark6, one hold of `~/work/gpu.lock`. Every claim below quotes the artefact it came from: the
ParityAB evidence (`docs/receipts/ParityAB/ev.tgz`, extracted to `work/ParityGap/ev/`), the two served
source trees (`docs/receipts/ProdEnvAudit/src` for P's cited files, the production branch at `production`
for the rest of P's tree, `work/ParityGap/DevTree` = upstream `1ece6e6d` + the 40 patches for D's), and
the box's own launchers and recipes (`work/ParityGap/box-*.sh`).

Checkpoint is equal on both arms: `snapshots/1464274120d36a4d8fcaa934552334a7d83ce0fd`
(`ev/P/c8/run1/meta.txt` `model_dir=`, `ev/D/c8/run1/meta.txt` `model_dir=`, equal strings). Everything
below is engine plus environment.

## 1. Launcher environment: the effective container env

Effective means the container's own `Config.Env` captured at the boot, not the launcher text:
`ev/P/c8/run1/env.txt` (54 names) against `ev/D/c8/run1/env.txt` (150 names).

| set | count | evidence |
|---|---:|---|
| P names | 54 | `wc -l ev/P/c8/run1/env.txt` = 54 |
| D names | 150 | `wc -l ev/D/c8/run1/env.txt` = 150 |
| both | 53 | `work/ParityGap/envdiff.txt` |
| both, different value | 1 | `TENSORFOLD_CUDA_KERNELS` P=`/opt/tensorfold/share/tensorfold/cuda/sm121` D=`native` |
| only P | 1 | `TF_FLASHNEXT_MTP_FP8=/root/.cache/huggingface/tensorfold-mtp-fp8/.../1464274120d36a4d8fcaa934552334a7d83ce0fd` |
| only D | 97 | 91 read by the dev tree, 6 dead even there (`work/ParityGap/envdiff.txt`) |
| in both, read by nothing in D's tree | 43 | `work/ParityGap/namecheck.txt` `DEAD-ON-D` intersection |

The one differing shared name is the kernel set, and it is the largest single structural difference:

- P passes `TENSORFOLD_CUDA_KERNELS=/opt/tensorfold/share/tensorfold/cuda/sm121`; the production recipe
  injects it itself and skips the env's own value (`box-start-prod.sh:169,171`:
  `ENV_ARGS=(-e HF_HUB_OFFLINE=... -e TENSORFOLD_CUDA_KERNELS="$KERNELS_PATH")`, then
  `[[ "$name" == TENSORFOLD_API_KEY || "$name" == TENSORFOLD_CUDA_KERNELS ]] && continue`).
- D passes `TENSORFOLD_CUDA_KERNELS=native` (`dev.env`, in the enabler block), because the dev engine
  refuses a captured set at fp8 KV: `work/ParityGap/DevTree/zig/src/families/flashnext/cuda_lanes_load.zig:33`
  `if (o.kv8 and (o.tp != 1 or captured != null or o.slide)) return error.Fp8KvUnsupported;`.
- P cannot run native at all: production's engine loads the set unconditionally,
  `production:zig/src/families/flashnext/cuda_engine.zig:582` `e.set = try cuda.aot.Set.load(gpa, io, d, ctx.device, kernels_dir);`,
  and `aot.Set.load` reads `<dir>/aot.json` (`production:zig/src/cuda/aot.zig:66`).

The 43 shared names D's tree does not read are production-engine levers carried into `dev.env` at
production values. Four of them are not merely inert: the dev engine has the same levers under a different
namespace, and D's boot line proves the production values are NOT in force:

| P name (read at) | P value | D's namespace (read at) | D's value in force |
|---|---|---|---|
| `TF_FLASHNEXT_COPY_MISS` `production:zig/src/native/cuda.zig:289` | `keep` | `TENSORFOLD_COPY_MISS` `DevTree/zig/src/native/cuda_startup_phase.zig:23` | unset: default `first` (`core/lanes/config.zig:120,127`) |
| `TF_FLASHNEXT_COPY_RAMP` `cuda.zig:290` | `jump` | `TENSORFOLD_COPY_RAMP` `cuda_startup_phase.zig:27` | unset: default `double` (`config.zig:122,128`) |
| `TF_FLASHNEXT_COPY_SHARED` `cuda.zig:292` | `1` | `TENSORFOLD_COPY_SHARED` `cuda_startup_phase.zig:31` | unset: default false |
| `TF_FLASHNEXT_COPY_RESYNC` `cuda.zig:297` | `1` | `TENSORFOLD_COPY_RESYNC` `cuda_startup_phase.zig:32` | unset: default false |
| `TF_FLASHNEXT_COPY_RESYNC_PROMPT_ONLY` `cuda.zig:298` | absent (default true) | `TENSORFOLD_COPY_RESYNC_PROMPT_ONLY` `cuda_startup_phase.zig:33` | unset: default true (inert while resync is off) |

P's boot prints the values in force (`ev/P/c8/run1/boot.log`): `copy policy: after a missed copy round keep,
after a clean one jump, resync on (copies out of the prompt), shared rounds ramp copies out of the prompt`.
D's prints its own (`ev/D/c8/run1/boot.log`): `copy policy: miss first, ramp double, shared rounds first
width, resync off`. That line is the proof, not the env file.

## 2. Recipe settings: the production recipe against the dev recipe (box copies)

`work/ParityGap/box-config-prod.sh` (`~/qwen-zig-prod/scripts/config.sh`, recipe 1.0.0 @ `364f21a`) against
`work/ParityGap/box-config-dev.sh` (`~/qwen-zig/scripts/config.sh`, recipe v1.1.4 @ `eab85828`). Values that
differ, from `work/ParityGap/cfgdiff.py`:

| setting | production | dev | effect on the two arms |
|---|---|---|---|
| `TF_REF` | `db281878` (zig-flashnext) | `eab85828` (v1.1.4) | different engine releases |
| `TF_TAG` | `zig-<sha7>` | `v1.1.4-<sha7>` | image naming |
| `PARALLEL` | 8 | 5 | both launchers pass 8; inert here |
| `TENSORFOLD_MEMORY_RESERVE_GIB` | 10 | 9 | both launchers pass 10; inert here |
| `TF_FLASHNEXT_PRODUCT_STREAMS` | 2 | 5 | D's engine does not read it (dead on D); P's launcher passes 8 |
| `MODEL_ID` / `MODEL_REVISION` / `CKPT_GIB` / `QUANT_LABEL` | one checkpoint, 122 GiB | checkpoint presets | `CHECKPOINT=int4` selects the same checkpoint |
| `KERNELS_PATH` | `/opt/tensorfold/share/tensorfold/cuda/sm121` | absent | P's recipe injects it; D takes `native` from `dev.env` |
| `KERNEL_SOURCE_MTIME` | pinned `1791318675` | absent | Triton source mtime pin for the captured set |
| `TF_FLASHNEXT_DEPTH` | 15 | absent (engine default 6 via `DRAFTS`) | P's solo chain depth 15; D's `DRAFTS=6`/`DRAFTS_GREEDY=8` (`DRAFT` stop binds first, see below) |
| `TF_FLASHNEXT_YARN` | computed, 0 at 262,144 | absent (1.1.4 has no YaRN) | dead on D |
| `TF_FLASHNEXT_CONFIDENCE` | absent (engine `-0.4`) | `-0.4` default | both launchers pass `-0.15`; equal |
| `TF_FLASHNEXT_DRAFTS` | absent | 6 | D's `most_drafts` seed |
| `TF_FLASHNEXT_{SAMPLED_HEADS,SAMPLE_CAND,GATHER_EARLY,GATHER_READ,HOST_DRAW_THREADS,KEEP_LATE,DRAFT_AHEAD,WARM_AHEAD,PROMPT_HC2,PROMPT_GEMM2,PROMPT_SHARED_DIRECT,HEAD_PIECE,PROMPT_EXPERT_TILE_ROWS,SHARED_SIDE,GDN_LANES}` | absent | supplied (1 except `HOST_DRAW_THREADS=7`, `HEAD_PIECE=1536`, `PROMPT_EXPERT_TILE_ROWS=256`) | D's recipe supplies these; they are in D's container env and read by the dev tree |
| KV flag | `SERVE_ARGS+=(--kv-dtype "$KV_DTYPE")` (`box-start-prod.sh:47`) | `SERVE_ARGS+=(--kv-cache "$KV_DTYPE")` (`box-start-dev.sh:46`) | same fp8 KV, two engine spellings (P argv `--kv-dtype fp8`, D argv `--kv-cache fp8`) |
| banner | `... · bf16 KV · ...` hard-coded (`box-start-prod.sh:255`) | `... · $KV_DTYPE KV · ...` (`box-start-dev.sh:254`) | P's banner mislabels the served fp8 KV; `PRODUCTION.md` repeats it |
| `TF_RELEASE*`, `LIBJPEG*`, `LIBWEBP*` | absent | present | 1.1.4 image decoders, no serve effect |

## 3. Patch sets: what each arm carries, and the map

P's engine (`production`): upstream `db281878d` + the MiaAI recipe's patches 0001-0009 + our
`0010`-`0028` + `tfm-fixes` + `tfm-warm-t` + the zmerge8 keep set (`27b6700cb` "c68-shared-cost-levels") +
`kindling 0002` (`5c3e3e29`); `git log --oneline 3289c9eb..production -- zig` lists 23 engine commits, from
`0010-flash-next-argmax-lse-rows` to `kindling 0002: native upload mmap staging` (PRODUCTION.md).

D's engine (`patches/main-1ece6e6db-r5-dev/README.md`, 40 patches, applied to upstream `1ece6e6d` in
`work/ParityGap/DevTree`).

| P lever (commit) | P read site / boot evidence | D carrier | verdict |
|---|---|---|---|
| 0010 argmax-lse-rows | `TF_FLASHNEXT_*` none; decode argmax path | `0009-readout-q12`, `0018-readout-fuse` cover the read-out family | mapped by family |
| 0011 mtp-fp8-overlay | `TF_FLASHNEXT_MTP_FP8`, `cuda_engine.zig:589` overlay2; boot `overlay .../mtp-fp8.safetensors` | `0014-mtp-mxfp8` recodes at load (`cuda_mtp_mxfp8.zig:23`) | same 8-bit drafter intent, different mechanism; not isolatable by env |
| 0012 ngram-host-gather | 32 gather threads, prefetch 2 chunks (`TF_FLASHNEXT_NGRAM_*`, dead on D) | `0004-ngram-row-cache`, `0012-gather-direct` (`TF_FLASHNEXT_GATHER_*`) | carried |
| 0013 copy-window | `TF_FLASHNEXT_WINDOW=64`; boot `copy windows: a lone stream verifies up to 64 rows` | `0001-rows` + `TF_FLASHNEXT_WINDOW_CHECK=1` -> boot `serving 48-row copy windows after the self-check` | carried, D narrower by design |
| 0014 copy-resync | `TF_FLASHNEXT_COPY_RESYNC=1` -> boot `resync on (copies out of the prompt)` | intended by `0002-copy-resync` but the name is `TENSORFOLD_COPY_RESYNC`, unset -> boot `resync off` | **GAP (candidate C2)** |
| 0015 copy-shared-rounds | `TF_FLASHNEXT_COPY_SHARED=1` -> boot `shared rounds ramp copies out of the prompt` | same gap (`TENSORFOLD_COPY_SHARED`, unset) -> boot `shared rounds first width` | **GAP (candidate C2)** |
| 0016 sequence-pool | `TF_FLASHNEXT_SEQ_POOL=8` (dead on D), boot `sequence pool 8` | none (dev engine releases sequences) | P-only |
| 0017 batched-draws | `TF_FLASHNEXT_BATCH_DRAWS=1` (read on D) | dev tree reads `BATCH_DRAWS` | carried |
| 0018 fp8-fused-split-head-rows | `FP8_FUSED_SPLIT=4`, `HEAD_ROW_TILES=2` (dead on D) | `0017-fused-split`, `0018-readout-fuse`; `TF_FLASHNEXT_FUSED_SPLIT`/`READOUT_FUSE` are D's spellings | carried under D names |
| 0019 decode-readout-fusion | `TF_FLASHNEXT_UPMIX_DECODE`, `REDUCE_ACT` (dead on D) | `0018-readout-fuse`, `TF_FLASHNEXT_READOUT_FUSED` | carried under D names |
| 0020 draft-stop-lines | `TF_FLASHNEXT_DRAFT_PROPOSE=0.05`, `DRAFT_CONTINUE=0.20` (`cuda_engine.zig:60-90`), `CONFIDENCE=-0.15` | no reader for PROPOSE/CONTINUE (`docs/receipts/ProseDraft/POLICY.md` section 5); D's equivalent is the product stop `CONFIDENCE=-0.15` plus `SHARED_DRAFTS=0` | behaviour carried by other names |
| 0021 sliced-fill-one-at-a-time | `TF_FLASHNEXT_FILL`/`FILL_LAYERS` (dead on D; P default off) | none | P-only, off |
| 0022 readout-12bit-weights | boot `hc q12: decode read-outs from 12-bit copies: 192 matrices, 1266.2 -> 970.8 MB, 95876 escapes` | `0009-readout-q12`, `0016-readout-q12-ahead`; boot `read-outs in 12 bits: 194 matrices, 1.07 GB beside their rows (76.2% of them), 97079 escapes` | carried |
| 0023 indexer-select-scores-tile | `TF_FLASHNEXT_QSA_SELECT`/`QSA_TILE` (dead on D) | dev tree has `TF_FLASHNEXT_QSA_SELECT`? `namecheck` says dead on D; dev `QSA_*` names are absent | P-only at the env level |
| 0024 prompt-fp8-tiles-int4-gate-up | `FP8_PROMPT_TILES=1` (dead on D), `INT4_PROMPT_GATE_UP=1` (read on D) | `0005-prompt-sync-mx128`, `0006-prompt-gemm2`, `0021-int4-autoround` | carried |
| 0025 retime | `TF_FLASHNEXT_COST_RETIME=4` (dead on D) | `0010-round-cost` | carried by patch |
| 0026 first-token | `EARLY_DRAW=1` (dead on D) | `TF_FLASHNEXT_FIRST_EARLY` default true | carried |
| 0027 whole-prompt-cache | `TF_FLASHNEXT_PROMPT_CACHE_WHOLE*` (dead on D); boot `prompt cache: whole-prompt states from 1024 tokens` | D's prompt cache is the tier + device cache; boot `prompt cache: device budget not reported, disk tier at /cache/kv` | different mechanism |
| 0028 shared-expert | `TF_FLASHNEXT_SHARED_EARLY_ROWS=6`, `SHARED_SLOT_LD=1` (dead on D) | `0008-shared-direct-head-piece` | carried |
| tfm-fixes / tfm-warm-t | warm turns off (`TENSORFOLD_WARM_TURNS=0`, dead on D) | D's `dev.env` `WARM_TURNS=0` via the launcher/recipe | equal |
| c68-shared-cost-levels | `TF_FLASHNEXT_SHARED_COST_LEVELS=0` (dead on D) | `0010-round-cost` | carried |
| kindling 0002 | native weight upload staging | D boots on the same 64k-page kernel, so the fix is in its image/upstream | equal |

D-only levers with no production counterpart: `0003-kv8`/`0015-kv8-pages` (fp8 KV and the page pool),
`0007-draft-head-4bit` (`DRAFT_HEAD=affine4` default), `0011-vision` (D runs vision off), `0023`-`0026`
(the persistent KV tier, its dedup, pool refusal and whole-ask budget), `0027`/`0028` (the draft-head format
pair), `0029`-`0032` (the int4 contract suite and its allowance work), `0034`-`0040` (test-fixture and pin
corrections).

`TF_FLASHNEXT_DRAFT_INT4=1` is set on both arms and is dead on both trees' name lists (`namecheck.txt`
shows it in neither tree's `flashnext` rows); the draft head's 4-bit form on D comes from
`TF_FLASHNEXT_DRAFT_HEAD`'s `affine4` default (0007's README), and on P from
`info: draft head: the int4 lm_head's own columns (TF_FLASHNEXT_DRAFT_INT4), 79592 ids, 105.1 MB`
(boot log; the name is read by P's binary even though the tree shows it only in the log text - the
production tree is the 20 cited files plus the branch, and `DRAFT_INT4` appears there).

## 4. Engine-level defaults visible in the boot logs (`ev/{P,D}/c8/run1/boot.log`)

| row | P | D |
|---|---|---|
| kernels | `TENSORFOLD_CUDA_KERNELS=/opt/.../sm121`; label `kernels=present`; `prompt path: 4096-row chunks ..., matmul K slices in one program (_b16mm_ks/_fp4mm_ks), experts on 128-pair items (fn_experts_prompt)` | `native`; label `kernels=embedded`; `[tensorfold] ... own glue kernels`; `prompt passes of 16384 rows, 4096 while another stream decodes`; `int4 kernels: prompt gate/up int4_prompt_kernel, lm_head 32-row items past 16 rows` |
| KV | `--kv-dtype fp8` (argv); `fp8 KV cache, 1056 bytes a position a layer`; banner `bf16 KV` (hard-coded bug) | `--kv-cache fp8` (argv); `KV page groups ... full: layers not named, 18.44 KiB a token, 4096 rows a page, 0 B padding (0.0 %)`, `state run, in the pool: 673.39 MiB on 10 pages`, `snapshot, outside the pool: 110.29 MiB on 2 pages` |
| cache / plan | `sequence memory: 28.57 GiB (40.57 GiB free, 10.0 GiB kept free)`; `prompt cache: whole-prompt states from 1024 tokens`; `prompt chunks of up to 2,048 tokens` | `8 streams ..., 7 more taking 220 pages of 4096 rows (15.84 GiB) ..., of 27.2 GiB left after a 10.0 GiB reserve; prompts in passes of up to 16384 rows, a 6.0 GiB prompt cache; own glue kernels`; `prompt cache: device budget not reported, disk tier at /cache/kv` |
| KV tier | none | `conversation states on disk in /cache/kv/fd57234d6ba38d2d (0 states, 0 MiB of 61440 MiB)` |
| drafter | `overlay .../mtp-fp8.safetensors`; `draft head: the int4 lm_head's own columns (TF_FLASHNEXT_DRAFT_INT4), 79592 ids, 105.1 MB`; `drafts: at most 7 a stream while two or more streams draft together (TF_FLASHNEXT_DRAFT_DEPTH_SHARED)`; `draft stop: a draft proposed while the running product is >= 0.050, another head level while it is >= 0.200` | `the drafter's BF16 linears kept as mxfp8 (TF_FLASHNEXT_MTP_WEIGHTS)`; `window self-check: 1176 of 1176 rows byte-equal to their one-token steps (widths 1-48)`; `serving 48-row copy windows after the self-check` |
| graphs | `graphs: shared verify rounds of up to 1 streams captured, MTP steps of up to 4; 192 shared graphs kept ...; sequence pool 8`; `graph warm-up: 384 graphs on 8 pooled sequences` | no graph line; `TF_FLASHNEXT_DECODE_GRAPH=0` (default false, `cuda_round_graph.zig:8`), and the qualification refuses it with the dense split (`cuda_lanes_explain.zig:25`) |
| INT4 path | `int4 prompt gate/up: int4_prompt_kernel on 64-pair items, 2x4 warps, 2x4 tiles, 3 stages (TF_FLASHNEXT_INT4_PROMPT_GATE_UP=1)`; `int4 lm_head: calls of 17 or more rows in 32-row items (TF_FLASHNEXT_HEAD_ROW_TILES=2)` | `int4 kernels: prompt gate/up int4_prompt_kernel, lm_head 32-row items past 16 rows`; `TF_FLASHNEXT_INT4_TILE=16`, `INT4_PROMPT_DOWN=1` (0001-0022 settings) |
| vision | on: `vision: image and video input on this GPU, a 0.84 GiB tower ...`; `vision: 2.00 GiB kept free for the image tower's workspace` | off (`VISION=0`): no vision lines, no 2 GiB set-aside |
| boot | `loaded in 84.8s`; `Server answered after 88s`; load timeline `15s 12.6 GiB, 30s 31.3 GiB, 45s 50.9 GiB, 60s 72.3 GiB` | `loaded in 148.3s`; `Server answered after 151s`; `15s 8.4 GiB, 30s 16.3 GiB, 45s 24.3 GiB, 60s 33.5 GiB, ... 121s 65.4 GiB` |

What D loads that P does not, proven by those lines: the persistent KV tier (states on disk, 0 states at
boot after the store is cleared) and a 6.0 GiB prompt-cache ask (its plan line). What D does NOT load: the
2.00 GiB vision workspace, the 0.84 GiB tower, and the FP8 drafter overlay (it recodes the drafter at load
instead). The boot-time delta itself is the weight stream: P reaches 72.3 GiB in 60 s, D reaches 65.4 GiB
in 121 s (about 1.2 against 0.54 GiB a second), so the extra 60 s is the loader, not the tier or the cache.

## 5. Ranked candidates

Ranked by the part of the measured gap each could carry, with the mechanism and the read site. Points are
the largest share of the gap the candidate could explain, not a claim it does.

| # | candidate | points | mechanism (evidence) | isolating arm | confound |
|---|---|---|---|---|---|
| C1 | the captured Triton kernel set (P mandatory, D refused at fp8) | prefill 11-18% + part of decode | P's prompt matmuls are the captured `_b16mm_ks/_fp4mm_ks` "one program, all K slices, no [SK,M,N] fp32 buffer" (`production:zig/src/families/flashnext/cuda_prompt.zig:1-8`), and its glue comes from the same set; D runs native glue and `_b16mm` + `_reduce` (two launches, one in-program order) because the set is refused at fp8 (`cuda_lanes_load.zig:33`) | A2 = P + `TF_FLASHNEXT_PROMPT_MM=0` (the captured prompt-matmul path off, same bits by its own header, dev/Python's two-launch form) | prices the prompt-matmul part only; the captured decode glue stays on; P's engine cannot run fully native (`cuda_engine.zig:582` loads the set unconditionally) |
| C2 | the four copy-policy levers dead on D by a namespace change | 0-5% decode, most on code and C>=2 | `TF_FLASHNEXT_COPY_*` on P against `TENSORFOLD_COPY_*` in D's tree; D's boot line shows `miss first, ramp double, shared rounds first width, resync off` where P keeps/jumps/ramps/resyncs | A1 = D + `TENSORFOLD_COPY_MISS=keep COPY_RAMP=jump COPY_SHARED=1 COPY_RESYNC=1 COPY_RESYNC_PROMPT_ONLY=1` | one group of four; the dev defaults may be deliberate; golden 6/6 must hold |
| C3 | decode-round graphs (P on by default, D off and unqualified) | 0-8% decode, likely rising with streams | P's `graphs: shared verify rounds ..., MTP steps ...` plus `graph warm-up: 384 graphs on 8 pooled sequences` (`cuda_engine.zig:686`, `cuda_native.zig:182`); D's round graph default false and refused with the dense split | A3 = P + `TF_FLASHNEXT_GRAPH_FAIL=1` (every instantiate fails, the round runs eagerly, same result; the engine's own fallback) | test hook: captures pause 64->4096 rounds so a few attempts remain; it measures P's graphs, not a D path |
| C4 | the persistent KV tier and the 6 GiB prompt-cache ask (D only) | 0-2% decode | tier argv + boot lines above; the tier's prior receipt is LEVEL on decode with a blind spot at 1-4 streams (`dev.env` citation of `docs/receipts/KvTierShip/RESULT.md`) | A4 = D + `LEARN=0` | drops the disk tier and the device cache ask together |

Refuted by evidence before the window, and not carried as arms:

- **Draft depth** (`DRAFTS_GREEDY` 8 against P's `DEPTH` 15, `GREEDY_WIDE` 4 against P's
  `DRAFT_DEPTH_SHARED` 7). `docs/receipts/ProseDraft/POLICY.md` sections 1-2 measured digit-identical
  round counters at 6/8 and 15/15 because the stop rule ends the chain first, and the observed pattern
  contradicts depth as the cause: at C=2 and C=4 D drafts deeper than P (8 against 7) and is still slower
  (0.947/0.963 and 0.943/0.928). The window still records `rounds`, `drafted`, `accepted` per cell
  (`dec.log`), so tokens a round and acceptance per arm are reported; the residual `GREEDY_WIDE=8` at six
  and eight streams (depth 6 -> 8) stays unmeasured on this composition and is named as such.
- **Vision on (P) against off (D)**: it costs P 2.00 GiB kept free and a 0.84 GiB tower; it cannot make D
  slower.
- **KV format**: both fp8 (argv `--kv-dtype fp8` / `--kv-cache fp8` and each engine's own line). P's
  banner `bf16 KV` is hard-coded text (`box-start-prod.sh:255`) and `PRODUCTION.md` repeats it; the served
  format is fp8. The two width prints are not like for like: the checkpoint is 48 layers with
  `full_attention_interval 4` (12 full-attention layers, 2 KV heads of 256, `config.json` read on the box),
  so fp8 KV is 1,024 B a position a full layer and P's `1056 bytes a position a layer` is that plus 32 B of
  scales (12.38 KiB a token over the 12 full layers). D's `18.44 KiB a token` is its full page group's row,
  and the 6.06 KiB beyond P's KV figure is consistent with the group also carrying the indexer's keys
  (12 x 512 B bf16 = 6.0 KiB), which P keeps in a separate ring (`caches in reserved address space ...,
  indexer keys in a ring`); that part is an inference from the arithmetic, not a read site. No KV-width
  lever exists either way: both engines print fp8, and the two prints measure different sets.
- **Copy window width** (P 64, D 48 under `WINDOW_CHECK=1`): the check's own receipt measured the checked
  width 26% and 12% faster on copy turns (`patches/main-1ece6e6db-r5-dev/README.md` 0001), so it is not a
  cost to remove; it is folded into C2's copy mechanism, not a separate arm.

What the diff cannot rank further: the captured set's **decode glue**. P cannot boot without the set and D
cannot boot with it at fp8, so no single env knob isolates it. The measurement that would settle it is
either D at bf16 KV with the captured set against D at bf16 native (two boots, confounded by the KV format
and by the 8-stream memory plan, which bf16 may not fit) or a build of P's tree with a native glue path.
A2 prices the prompt half; the decode half stays open unless A2 shows the kernel set carries most of the
gap.

One structural difference is also not a knob: D's KV is a page pool (`TF_FLASHNEXT_KV_PAGES=4096`, 73.75
MiB a page, allocated per stream) while P's is a contiguous sequence cache (28.57 GiB planned). The pool is
an enabler, not a tuning choice - without it the same fp8 shape at 8 x 262,144 is refused by name
(`dev.env`'s citation of the pool window) - so no arm turns it off, and any page-table cost in D's
attention is inside every D-family arm alike.

## 6. The window

Six arms, one fresh boot a cell, interleaved so P and D bracket the arms at each level.

| arm | family | lever | expected boot-line proof |
|---|---|---|---|
| P | production | none (control) | `matmul K slices in one program`, `copy policy: ... keep ... jump ... resync on`, kernel dir `/opt/.../sm121` |
| D | dev | none (control) | `own glue kernels`, `copy policy: miss first, ramp double, shared rounds first width, resync off`, tier argv |
| A1 | dev | `TENSORFOLD_COPY_MISS=keep COPY_RAMP=jump COPY_SHARED=1 COPY_RESYNC=1 COPY_RESYNC_PROMPT_ONLY=1` | `copy policy: miss keep, ramp jump, shared rounds ramp prompt copies, resync prompt copies` |
| A2 | production | `TF_FLASHNEXT_PROMPT_MM=0` | `prompt path: ... matmul K slices split with _reduce` |
| A3 | production | `TF_FLASHNEXT_GRAPH_FAIL=1` | `graph instantiate: injected failure` in the server log |
| A4 | dev | `LEARN=0` (no tier, no prompt-cache ask) | argv without `--prompt-cache-gib`; no `conversation states on disk` line |

Screen at C=1 and C=8, orders `c1: P A1 A3 D A2 A4` and `c8: D A2 A4 P A1 A3`. Promotion rule, applied by
`score_arms.py --select` to the screen only: an arm is carried to C=2, C=4 and C=6 when its ratio against
its own family control is outside 0.98-1.02 in either prompt kind's decode aggregate OR in the cold 8k or
32k TTFT at either screen level (the TTFT is included because a prefill-only lever shows nothing in
decode); at most two arms promote (largest deviation first), and each promoted pass re-boots P and D as
controls at that level.

Cells per boot, the ParityAB driver's own: golden 6/6 against the recorded stock reference, decode with
`tfm_decode_ids.py` (3 passes, 512 greedy tokens, prose then code, per-cell token hashes), TTFT with
`ttft.py` (cold 1k/8k/32k, thinking off and on, 2 reps, idle) plus the warm 100k + 2k agent turn (2 reps,
cached tokens recorded). The tier's store is emptied from a throwaway container before every D-family
boot. Thermals at every probe. No rerun pass is declared: repeat counts are the target's own, and any
screen verdict is re-measured at 2/4/6 by a separate boot.

Exact commands (from the workstation, `export SSH_AUTH_SOCK=C:/Users/Adam/AppData/Local/gnupg/agent-gui/S.gpg-agent.ssh.cyg`):

```
ssh adam@192.168.99.16 'mkdir -p ~/work/parity2/out'
scp work/ParityGap/win2/window2.sh work/ParityGap/win2/boot_env2.sh work/ParityGap/win2/score_arms.py \
    adam@192.168.99.16:work/parity2/
ssh adam@192.168.99.16 'cd ~/work/parity2 && setsid nohup env LOG=$HOME/work/parity2/out/run.log \
    bash window2.sh >> window2.log 2>&1 < /dev/null & echo LAUNCHED $!'
ssh adam@192.168.99.16 'tail -5 ~/work/parity2/out/run.log; grep -c "^\[.*CELL-DONE" ~/work/parity2/out/run.log'
```

The driver takes `flock -o -w 43200 ~/work/gpu.lock` itself (the same wrapper as `ParityAB/window.sh`),
stops whatever serves, and restores production from its own launcher in an EXIT trap: `/health` 200, the
pinned image id `sha256:235211ea77ee...`, and `check-prod-env.py --inspect <fresh inspect>` at 0 problems
(117 rows compared). It writes `WINDOW-DONE` to its log as its last line. The outer wrapper re-checks
`/health` after the child exits and restores again under the lock if it is not 200.

Deliverables on disk: `work/ParityGap/out/` (per-cell env, argv, boot log, decode JSONL with token hashes,
TTFT output, golden record, thermals), `score.md` (the per-arm table at every level measured), `restored/`
(the restore proof).
