# Deliverable A: the parity diff (condensed answer)

Evidence: `docs/receipts/ParityAB/ev.tgz` (extracted `work/ParityGap/ev/`), the P container env
`ev/env-P-container.txt` (54 names) and D `ev/env-D-container.txt` (150), the box's launchers and recipes
`ev/box-*.sh`, the two trees (`production` branch, `work/ParityGap/DevTree` = upstream `1ece6e6d` + the 40
dev patches), and the boot logs `ev/bootlines-{P,D}.txt`.

## 1. Launcher environment (effective, from each container's own env)

P 54 names, D 150; 53 shared; 1 shared with a different value; 1 P-only; 97 D-only. Of the 53 shared, 43 are
names D's tree does not read (production-engine levers carried in `dev.env` at production values)
(`ev/namecheck.txt`, `ev/envdiff.txt`).

- The one shared name with a different value: `TENSORFOLD_CUDA_KERNELS` = `/opt/tensorfold/share/
  tensorfold/cuda/sm121` on P (the recipe injects it, `ev/box-start-prod.sh:169,171`), `native` on D
  (`dev.env`'s enabler because the dev engine refuses a captured set at fp8 KV,
  `DevTree/zig/src/families/flashnext/cuda_lanes_load.zig:33`). P cannot run native: its engine loads the
  set unconditionally (`production:zig/src/families/flashnext/cuda_engine.zig:582`) and `aot.Set.load`
  reads `<dir>/aot.json` (`production:zig/src/cuda/aot.zig:66`).
- The one P-only name: `TF_FLASHNEXT_MTP_FP8` (the precomputed FP8 drafter overlay); D recodes the drafter
  at load with `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8`.
- The 43 shared-but-dead names include four copy-policy levers whose dev-engine readers live under another
  namespace and are unset, so D runs the dev defaults where P runs production's values:
  `TF_FLASHNEXT_COPY_MISS/RAMP/SHARED/RESYNC` (read at `production:zig/src/native/cuda.zig:289-298`) against
  `TENSORFOLD_COPY_MISS/RAMP/SHARED/RESYNC/_RESYNC_PROMPT_ONLY` (read at
  `DevTree/zig/src/native/cuda_startup_phase.zig:23-33`; defaults `.first`/`.double`/false/false,
  `core/lanes/config.zig:120-128`). Boot lines prove it: P `copy policy: after a missed copy round keep,
  after a clean one jump, resync on (copies out of the prompt), shared rounds ramp copies out of the prompt`;
  D `copy policy: miss first, ramp double, shared rounds first width, resync off`.

## 2. Recipe settings (box copies, `ev/cfgdiff.txt`)

Differing: `TF_REF` (`db281878` vs `eab85828` v1.1.4), `TF_TAG`, `PARALLEL` (8 vs 5), 
`TENSORFOLD_MEMORY_RESERVE_GIB` (10 vs 9), `TF_FLASHNEXT_PRODUCT_STREAMS` (2 vs 5),
`KERNELS_PATH` (prod only, `/opt/.../sm121`), `KERNEL_SOURCE_MTIME` (prod only), `TF_FLASHNEXT_DEPTH` (prod
15 only), `TF_FLASHNEXT_YARN` (prod only), `TF_FLASHNEXT_CONFIDENCE` (dev default -0.4 only),
`TF_FLASHNEXT_DRAFTS` (dev 6 only), checkpoint/quant presets, and the dev-supplied group
(`SAMPLED_HEADS`, `SAMPLE_CAND`, `GATHER_EARLY`, `GATHER_READ=pread`, `HOST_DRAW_THREADS=7`, `KEEP_LATE`,
`DRAFT_AHEAD`, `WARM_AHEAD`, `PROMPT_HC2`, `PROMPT_GEMM2`, `PROMPT_SHARED_DIRECT`, `HEAD_PIECE=1536`,
`PROMPT_EXPERT_TILE_ROWS=256`, `SHARED_SIDE`, `GDN_LANES`, plus the image decoders). Both launchers pass
`PARALLEL=8`, `CONTEXT=262144`, `MEMORY_RESERVE_GIB=10`, `CONFIDENCE=-0.15`, `PRODUCT_STREAMS=8`, so those
recipe defaults are inert at the boot. The KV flag differs in spelling only (`--kv-dtype` vs `--kv-cache`),
both fp8; the production banner's `bf16 KV` is hard-coded text (`ev/box-start-prod.sh:255`) and
`PRODUCTION.md` repeats it.

## 3. Patch sets and the lever map

P: upstream `db281878d` + the recipe's nine Python patches (squashed as `3289c9eb recipe-patched`: fp8 KV
Python path, `prompt_mm.py`'s Triton prompt matmuls, `yarn.py`, the vision helper, `tools/zig/aot_pack.py`
which packs the captured set, `check_flashnext_lse.py`) + our `0010`-`0028` (23 engine commits,
`git log --oneline 3289c9eb..production -- zig`) + `tfm-fixes`, `tfm-warm-t`, the zmerge8 keep set
(`27b6700cb`) + `kindling 0002` (`5c3e3e29`). D: upstream `1ece6e6d` + the 40 patches of
`patches/main-1ece6e6db-r5-dev`.

Carried under another name or mechanism: 0011 (mtp-fp8 overlay vs 0014 mxfp8 recode), 0012 (ngram host
gather vs 0004/0012), 0013 (copy window vs 0001 + `WINDOW_CHECK`), 0017 (batched draws), 0018/0019 (fused
split, read-out fusion), 0020 (draft stop lines vs `CONFIDENCE`+`SHARED_DRAFTS`), 0022 (12-bit read-outs),
0024 (prompt FP8 tiles/int4 gate-up vs 0005/0006/0021), 0025 (retime vs 0010 round-cost), 0028 (shared
expert). Carried as a namespace change D's env never states: **0014 copy-resync and 0015 copy-shared-rounds**
(+ the miss/ramp names). Not carried by D at all: 0010 (argmax-LSE rows), 0016 (sequence pool), 0021
(sliced fill, P's default off), 0023 (indexer select tile; D has `qsa` only in contract records), 0026
(first token), 0027 (whole-prompt cache). D-only: 0003/0015 (fp8 KV and the page pool), 0007 (draft head
4-bit default), 0011 (vision decode), 0023-0026 (the persistent KV tier and its budget refusals),
0027/0028 (draft-head format), 0029-0032 (int4 contract suite), 0034-0040 (fixture/pin corrections).

## 4. Engine-level defaults visible in the boot logs

| row | P | D |
|---|---|---|
| kernels | `/opt/.../sm121`; `kernels=present`; `matmul K slices in one program (_b16mm_ks/_fp4mm_ks), experts on 128-pair items (fn_experts_prompt)` | `native`; `kernels=embedded`; `own glue kernels`; `prompt passes of 16384 rows, 4096 while another stream decodes`; `int4 kernels: prompt gate/up int4_prompt_kernel, lm_head 32-row items past 16 rows` |
| KV | `fp8` (`--kv-dtype fp8`); `fp8 KV cache, 1056 bytes a position a layer`; banner `bf16 KV` (hard-coded bug) | `fp8` (`--kv-cache fp8`); `full: ... 18.44 KiB a token, 4096 rows a page`; `state run ... 673.39 MiB on 10 pages`; `snapshot ... 110.29 MiB on 2 pages` |
| cache/plan | `sequence memory: 28.57 GiB`; `prompt cache: whole-prompt states from 1024 tokens`; `prompt chunks of up to 2,048 tokens` | `7 more taking 220 pages of 4096 rows (15.84 GiB) ... of 27.2 GiB left after a 10.0 GiB reserve; prompts in passes of up to 16384 rows, a 6.0 GiB prompt cache`; `prompt cache: ... disk tier at /cache/kv` |
| tier | none | `conversation states on disk in /cache/kv/... (0 states, 0 MiB of 61440 MiB)` |
| drafter | overlay `mtp-fp8.safetensors`; `draft head: the int4 lm_head's own columns (DRAFT_INT4), 79592 ids, 105.1 MB`; `drafts: at most 7 a stream while two or more draft together`; `draft stop: ... >= 0.050 ... >= 0.200` | `the drafter's BF16 linears kept as mxfp8 (MTP_WEIGHTS)`; `window self-check: 1176 of 1176 rows byte-equal ... (widths 1-48)`; `serving 48-row copy windows after the self-check` |
| graphs | `shared verify rounds of up to 1 streams captured, MTP steps of up to 4; 192 shared graphs kept ...; sequence pool 8`; `graph warm-up: 384 graphs on 8 pooled sequences` | no graph line; `DECODE_GRAPH=0` (default false, `cuda_round_graph.zig:8`) and refused with the dense split (`cuda_lanes_explain.zig:25`) |
| vision | on: `a 0.84 GiB tower`; `2.00 GiB kept free` | off |
| boot | `loaded in 84.8s`, answered 88s; `15s 12.6 GiB ... 60s 72.3 GiB` | `loaded in 148.3s`, answered 151s; `15s 8.4 GiB ... 121s 65.4 GiB` |

What D loads that P does not: the persistent KV tier (states on disk; 0 states at boot after the store is
cleared) and a 6.0 GiB prompt-cache ask (its plan line). What D does not load: the 2.00 GiB vision
workspace, the 0.84 GiB tower, the FP8 drafter overlay (it recodes at load). The 60 s boot delta itself is
the weight stream (P ~1.2 GiB/s, D ~0.54 GiB/s), not the tier or the cache. KV geometry: 48 layers,
`full_attention_interval 4` (12 full layers), 2 KV heads of 256, so fp8 KV is 1,024 B a position a full
layer and P's 1056 includes 32 B of scales; D's 18.44 KiB a token is its full page group's row, and the 6.06 KiB
beyond P's figure is consistent with the group also carrying the indexer's keys (12 x 512 B = 6.0 KiB) that
P keeps in a separate ring (an inference from the arithmetic, not a read site). Both fp8; no width lever.

## 5. Ranked candidates, the arm that isolates each, and its confound

| # | candidate | points | isolating arm | confound |
|---|---|---|---|---|
| C1 | captured Triton kernel set (P mandatory, D refused at fp8) | prefill 11-13% + part of decode | A2 = P + `TF_FLASHNEXT_PROMPT_MM=0` (prices the prompt-matmul half) | prices the prompt-matmul half only; P cannot run fully native, so the decode-glue half is not isolatable |
| C2 | four copy-policy levers dead on D by namespace | 0-5% decode, most at concurrency | A1 = D + the five `TENSORFOLD_COPY_*` values | one group of four; dev defaults may be deliberate |
| C3 | decode-round graphs (P on, D off) | 0-8% decode | A3 = P + `TF_FLASHNEXT_GRAPH_FAIL=1` (eager, same bits) | test hook; captures pause after a failure; measures P, not a D path |
| C4 | persistent KV tier + 6 GiB ask (D only) | 0-2% decode | A4 = D + `LEARN=0` | drops the disk tier and the device cache ask together |

Refuted before the window: draft depth (POLICY.md's digit-identical round counters at 6/8 and 15/15; and D
drafts deeper than P at C=1 anyway), vision (a P cost, not a D cost), KV format (both fp8), copy-window
width (its own receipt measured the checked width faster on copy turns).
Not isolatable by the diff: the captured set's decode glue - P cannot boot without the set, D cannot boot
with it at fp8. The needed measurement is either D at bf16 KV with/without the captured set (confounded by
the KV format and the 8-stream memory plan) or a build of P's tree with native glue. A2 prices the prompt
half; the decode half needs a kernel-level profile of one decode round on each engine.
