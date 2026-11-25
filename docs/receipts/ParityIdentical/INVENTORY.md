# Why two engines on one checkpoint return different greedy replies: the numeric-path inventory

P is production, image `tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7` (`sha256:235211ea77ee`), source tree
`production` (`5c3e3e29`). D is the dev composition, image `tensorfold-qwen38:r5dev40` (`sha256:adc40fe3ea7b`),
upstream `1ece6e6d` plus the 40 patches of `patches/main-1ece6e6db-r5-dev`. One checkpoint on both:
`azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound`, revision `1464274120d36a4d8fcaa934552334a7d83ce0fd`.

Sources, all read for this table:

- P's engine sources: `git archive production` extracted to `work/ParityIdentical/Ptree` (this session), plus
  `work/ParityIdentical/Ptree/py/src/tensorfold/families/qwen4_exp/cuda/` - the Python engine the Zig engine replays.
- D's engine sources: `work/ParityGap/DevTree` (upstream `1ece6e6d` + the 40 patches, staged by the ParityGap lane).
- The two container environments at the recorded boots: `work/ParityIdentical/ev/{P,D}/c8/run1/env.txt` (from
  `docs/receipts/ParityAB/ev.tgz`, `docker inspect .Config.Env`), and each boot's log
  `work/ParityIdentical/ev/{P,D}/c8/run1/boot.log`.
- The recipes: `work/ParityGap/box-start-prod.sh` / `box-start-dev.sh` (box copies, 2026-11-24) and
  `work/ParityGap/box-config-prod.sh` / `box-config-dev.sh`.

Line numbers below are of those trees as staged; `P:` prefixes a file in `work/ParityIdentical/Ptree`, `D:` one in
`work/ParityGap/DevTree`.

## What is already fixed and equal

| input | both arms | evidence |
|---|---|---|
| checkpoint | `snapshots/1464274120d36a4d8fcaa934552334a7d83ce0fd` | `ev/{P,D}/c8/run1/meta.txt`; both argv |
| prompt tokens | equal on every recorded row | `docs/receipts/ParityAB/ev.tgz` `dec.jsonl`: 12 of 12 rows equal at C=1, 48 of 48 at C=8 (`prompt_tokens` per (`kind`,`pass`,`j`)); the window re-checks by `/tokenize` ids |
| greedy request | `temperature 0`, `seed 1234`, `chat_template_kwargs.enable_thinking=false`, 512 tokens | `docs/receipts/ParityAB/in/qf_harness.py:72-76` (`body_of`) |
| KV dtype | fp8 on both (`--kv-dtype fp8` / `--kv-cache fp8`) | each boot's argv and its own `fp8 KV cache, 1056 bytes a position a layer` line |
| run-to-run determinism | each arm reproduces itself across two fresh boots at C=1, 2 and 4 (6/6, 12/12, 24/24 reply shas and token shas); P at C=6 36/36 | `ev/{P,D}/c{1,2,4}/run{1,2}/dec.jsonl`, `ev/P/c6/run{1,2}` |
| golden set | the same 6 golden replies on both arms, including 215- and 256-token replies | `ev/{P,D}/c1/run2/gold.txt`: same six `sha=` values, both `6/6 identical` to the one base record |

The determinism and golden rows are why this is an engine difference and not noise: the same binary on two boots
answers byte for byte, and on six short factual prompts the two engines agree for 200+ tokens.

## 1. The weight path

Both engines serve the INT4-AutoRound checkpoint through the same kernel module source line, and the four settings
that steer it are at the same values on both arms.

| item | P | D | equal? |
|---|---|---|---|
| checkpoint coding | GPTQ int4, symmetric (zero point 8), fp16 scale a 128 inputs, `qweight [K/8, N]` | same | yes |
| int4 kernels | `fn_int4.cu` compiled into the served binary (`P:zig/src/cuda/kernels.zig:43` `fn_int4` blob), loaded as `cuda.kernels.fn_int4` (`P:zig/src/families/flashnext/cuda_int4.zig:276`) | same structure: `D:zig/src/families/flashnext/cuda_int4.zig:251` `cuda.Module.load(d, cuda.kernels.fn_int4)` | source differs (153 changed lines in `fn_int4.cu`: `common/` headers, comments, `qmm_frag::mma`; the arithmetic paragraph and every template instantiation are the same) |
| per-output arithmetic | `total` per group = one fp32 MMA chain over k32 blocks in order, both k16 steps in order, then `acc = fmaf(group sum, scale, acc)` in group order; a row depends on its own inputs only | identical contract, `D:zig/kernels/cuda/fn_int4.cu:1-25` | yes by construction |
| kernel set (captured Triton AOT set) | `TENSORFOLD_CUDA_KERNELS=/opt/tensorfold/share/tensorfold/cuda/sm121`, loaded unconditionally (`P:zig/src/families/flashnext/cuda_engine.zig:582`); image label `kernels=present` | `TENSORFOLD_CUDA_KERNELS=native`, image label `kernels=embedded`; a captured set is *refused* at fp8 KV (`D:zig/src/families/flashnext/cuda_lanes_load.zig:33`) | **no** - see item 4 |
| `TF_FLASHNEXT_INT4_PROMPT_GATE_UP` | `1` (read at `P:.../cuda_int4.zig:299`) | `1` (read at `D:.../cuda_int4.zig:272`) | yes |
| `TF_FLASHNEXT_HEAD_ROW_TILES` | `2` (`P:.../cuda_int4.zig:303`) | `2` (`D:.../cuda_int4.zig:274`) | yes |
| `TF_FLASHNEXT_INT4_TILE` | unset -> `kern.plan_tile` = 16 (`P:.../cuda_int4.zig:148`) | `16` (`D:.../cuda_int4.zig:151`) | yes |
| `TF_FLASHNEXT_INT4_PROMPT_DOWN` | unset -> on (`P:.../cuda_int4.zig:434`) | `1` (`D:.../cuda_int4.zig:386`) | yes |
| llm_head | int4 GPTQ head through `fn_int4` (`P:.../cuda_weights.zig:482`) | same (`D:.../cuda_weights.zig`, int4 head) | yes |
| read-out matrices | 12-bit lossless copies, `HC_Q12=1`: 192 matrices, 1266.2 -> 970.8 MB, 95876 escapes | 12-bit lossless copies, `HC_Q12=1`: 194 matrices, 1.07 GB, 97079 escapes | yes on the values (lossless both: `P:.../cuda_hc_q12.zig:1-12`, `D:.../cuda_hc_q12.zig:1-8`); the 2 extra matrices are coverage, not rounding |

Verdict for this section: **the INT4 weight path is not a source of difference.** Same coding, same kernel module,
same four settings, same per-output arithmetic contract. The arm that perturbs it (D with `HEAD_ROW_TILES=1`, which
both engines claim is bit-equal) is carried in phase 3 as a sensitivity control, not as a candidate.

The observable difference in this section is the *kernel set*, not the weights: P runs prompt matmuls from a
captured Triton set, D runs native kernels. That is item 4.

## 2. The drafter

| item | P | D | effect |
|---|---|---|---|
| drafter weights | `TF_FLASHNEXT_MTP_FP8=<dir>`: a pre-computed block-FP8 overlay of the MTP layer's bf16 linears, loaded from disk (`P:.../cuda_engine.zig:588-591`, built by `production/mtp_fp8.py`) | `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8`: bf16 linears re-coded to MXFP8 **at load** (`D:.../cuda_mtp_mxfp8.zig:1-19`, set by the dev launcher line 37) | different 8-bit quantisation of the draft head -> different drafts |
| chain depth | `TF_FLASHNEXT_DEPTH=15` (`P:.../cuda_native.zig:87-88`), shared rounds capped by `TF_FLASHNEXT_DRAFT_DEPTH_SHARED=7` (`P:.../cuda_lanes.zig:195`) | `TF_FLASHNEXT_DRAFTS=6`, `DRAFTS_GREEDY=8` (`D:.../cuda_lanes_load.zig:90-92`) | different draft volume |
| stop rule | two lines: propose >= 0.05, continue >= 0.20 (`P:.../cuda_engine.zig:60-90`, `TF_FLASHNEXT_DRAFT_PROPOSE`/`_CONTINUE`) | one line: the product stop `CONFIDENCE=-0.15`, and beside another stream `shared_stop=0.6` unless `SHARED_DRAFTS=0` (`D:.../cuda_lanes_draft.zig:38,42,57-59`); D sets `SHARED_DRAFTS=0` | different draft volume |
| `CONFIDENCE` | `-0.15` | `-0.15` | equal |
| `GREEDY_WIDE` | unset (engine default) | `4` | different draw path when sampling |
| what a draft can change | the acceptor is exact-match on the target's pick, and the emitted token is the **target's** pick: `acceptPath` follows the child whose token equals `picks[row]` (`D:.../core/lanes/accept.zig:40-58`), `targetPick` returns `picks[parent]` (`:60-62`), and a rejected draft is replaced by the target row's own draw | same rule on P (`P:.../cuda_decode.zig`, `cuda_lanes` keep/rollback over the accepted prefix) | **a draft can never be emitted unless the target's own argmax at that row is the same token** |

The volume those settings produce, from the recorded window's own counters (median over the passes of each
cell, `ev/{P,D}/c*/run*/dec.log`): the two policies land in the same place, so the drafter is not a large shape
difference in practice.

| level | P drafted/round prose | D drafted/round prose | P code | D code | P tokens/round prose | D prose |
|---|---:|---:|---:|---:|---:|---:|
| C=1 | 2.18 | 2.19 | 5.92 | 6.13 | 2.64 | 2.70 |
| C=2 | 2.05 | 1.91 | 5.14 | 5.26 | 2.39 | 2.41 |
| C=4 | 2.38 | 2.21 | 5.20 | 5.55 | 2.62 | 2.58 |
| C=6 | 2.28 | 2.11 | 5.02 | 4.84 | 2.55 | 2.51 |
| C=8 | 2.38 | 2.15 | 5.15 | 4.86 | 2.59 | 2.56 |

Verdict: the drafter changes *draft volume* and can change the *shape* of a verify pass (row counts in the head and
the attention kernel), never the identity of a verified token by the acceptor rule. So it is a candidate only
through a batch-shape channel, and that channel is testable with `DRAFTS=0` on both arms (recipe switch
`DRAFTS=0` -> `--no-drafts`, `work/ParityGap/box-start-prod.sh:45` and `box-start-dev.sh:44`).

## 3. Attention and KV

| item | P | D | equal? |
|---|---|---|---|
| KV format | fp8 e4m3, one power-of-two scale a (position, KV head) row: `s = 2^(ceil(log2 amax) - 8)`, codes land in (128, 256]; key row = D codes + `s_k` + `s_v` + 8 zero bytes; value row = D codes (`P:py/.../kv8.py:26-34,44-45,72-93`) | same: `scale_shift = 8` (`D:.../cuda_kv.zig:48-49`), `scaleExponent` (`:69-83`), `key_trailer = 16` (`:42`), `dequantizeRow` rounds to bf16 exactly (`:146`) | **yes, byte for byte in the rule** |
| KV bytes/position/layer | 1,056 (`2 x 2 x 256` codes + 32 B trailer) | 1,056 (`D:.../cuda_kv.zig:29-38`) | yes |
| KV store | contiguous sequence cache; 28.57 GiB plan; indexer keys in a ring | 4,096-row page pool (`TF_FLASHNEXT_KV_PAGES=4096`), 73.75 MiB a page; the page group also holds the indexer's keys | different addressing, same values |
| attention kernel | decode: captured Triton `_chunks` at `CHUNK = 512` keys a chunk, partials merged in chunk order by `_merge` (`P:py/.../attention.py:13,100-123,178-187`); prompt: the 64-key fold of `tf_prefill_attention` (`P:zig/kernels/cuda/prefill_attention.cu:1-20`) | one-pass `prefill_attention_rows.cuh` (online softmax over key tiles, paged keys, no cross-pass partials) and `block_attention.cu` (`D:zig/kernels/cuda/`), driven from `D:.../cuda_batch.zig:404-450` | **no: different reduction structures** (R3) |
| split-K on block-FP8 projections | `TF_FLASHNEXT_FP8_FUSED_SPLIT=4` (shapes of 2,048+ columns below 256 rows: one block a column tile, K slices summed in slice order) and `FP8_PROMPT_TILES=1` (`P:.../cuda_fp8.zig:66-91`; both set by the production launcher) | the names have no reader in D's tree; D's own split lever `TF_FLASHNEXT_FUSED_SPLIT=0` (`D:.../cuda_fused_split.zig`) | **different mechanisms, same slice boundaries claimed** |
| prompt pass rows | 2,048: the server's chunk hint is the constant `prefill_step = 2048` (`P:.../cuda_native.zig:29`; boot line `prompt chunks of up to 2,048 tokens, cut at replies 256+ tokens apart`, printed by `P:.../server/server.zig:89`), and the engine's own cap is `TF_FLASHNEXT_PREFILL_ROWS=4096` (`P:.../cuda_engine.zig:416-423`, pinned by the production launcher; its comment claims "any chunking gives the same bits") | `TF_FLASHNEXT_CHUNK=4096` beside a decoding stream, `TF_FLASHNEXT_CHUNK_SOLO=16384` alone (`D:.../cuda_chunk.zig:1-31`; boot line `prompt passes of 16384 rows, 4096 while another stream decodes`) | **no** |
| sparse indexer | `QSA_SELECT=1`: block lists from `fn_qsa_stream`, `cs4` from 32,768 blocks in decode, `s5` for prompt blocks (`P:.../cuda_engine.zig:755`; boot line `qsa select: ...`) | its own select kernel `fn_qsa_select` with `index_top=512`, `index_ratio=4` (`D:.../cuda_prompt_wt.zig:41-46`, `D:.../cuda_batch.zig:437-450`) | both sparse; dense below `dense_keys = (512+1)*4-1 = 2051` keys (`D:.../cuda_prompt_wt.zig:46`) so a 1k prompt is dense on both and an 8k prompt is pruned on both |
| decode graphs | on by default (`P:.../cuda_engine.zig:112-113`), 192 shared graphs kept, 384 warmed | `TF_FLASHNEXT_DECODE_GRAPH=0` (`D:.../cuda_round_graph.zig:8`), refused with the dense split (`D:.../cuda_lanes_explain.zig:25`) | different execution, same claimed bits |
| vision | on: 0.84 GiB tower, 2.00 GiB workspace | off (`VISION=0`) | text path unaffected; carried as a control arm |

Verdict: the KV *format* is refuted as a source - both serialise the same codes from the same rule. What differs is
how the same dequantised rows are summed: P splits the key range into 512-key chunks and merges the partials in chunk
order, D's kernels use their own tile/stage structure, and P partitions prompts into 2,048-row passes where D takes
4,096 or 16,384 rows a pass.

## 4. Reduction structure: the places a sum order changes

| # | place | P | D |
|---|---|---|---|
| R1 | prompt dense matmul | captured `_b16mm_ks` / `_fp4mm_ks`: every K slice of a tile in one program, slice totals added in slice order, "`_b16mm` + `_reduce`'s bits" (`P:.../cuda_prompt.zig:1-8`, `e.f.prompt_mm` on at `cuda_engine.zig:649`) | native `_b16mm`/`qmm` split-K with an fp32 partial buffer and a `_reduce` launch (`D:zig/kernels/cuda/qmm.cu:18-30`, `qmm_prefill.cu`, `cuda_batch_ops.zig`) |
| R2 | block-FP8 dense projections (o_proj and the rest) | captured block-FP8 kernels with `TF_FLASHNEXT_FP8_FUSED_SPLIT=4`: one block a column tile, its 4 K slices summed in slice order in one program (`P:.../cuda_fp8.zig:66-91`; the `fp8-fused-check` compares that against the cluster kernel, bytes) | native `tf_qmmf` FP8G kernel, one block's own K chain, no 4-slice split (`D:zig/kernels/cuda/qmmf.cu:1-40`, called from `D:.../cuda_projection.zig:33-40`); the P name has no reader in D's tree |
| R3 | attention over KV | decode: 512-key chunks, one `(po, pm, pl)` partial a chunk, `_merge` walks them in ascending chunk order (`P:py/.../attention.py:13,100-123,178-187`, replayed by `P:.../cuda_forward.zig:1727-1729` "the chunked attention and merge"); prompt: the `tf_prefill_attention` kernel's 64-key fold (`P:zig/kernels/cuda/prefill_attention.cu:1-20`) | one kernel an attention: `prefill_attention_rows.cuh` walks the keys in 32-row (and D/8-chunk) tiles in one pass with an online softmax, no cross-pass partials (`D:zig/kernels/cuda/prefill_attention_rows.cuh:1-20,84-140`), and `block_attention.cu` is the same shape for every family |
| R4 | int4 matmuls | fp32 group chain, group order, `fmaf(sum, scale, acc)` | identical contract |
| R5 | read-outs | 12-bit copy, lossless; fused up/mix (`UPMIX_DECODE=1`) and `REDUCE_ACT=1` | 12-bit copy, lossless; `READOUT_FUSED=1`, `READOUT_FUSE=0` |
| R6 | prompt partitioning | 2,048-row passes | 4,096 / 16,384-row passes |
| R7 | verify-pass row counts (drafter-driven) | up to 15+1 rows a chain, shared cap 7, shape-keyed CUDA graphs | up to 6+1 rows, `GREEDY_WIDE=4`, eager |

R1, R2 and R3 are claimed bit-equal to the *same Python reference* by both sides (each side's own headers say so),
and each side's own checks compare against that reference. What no check compares is P's capture against D's port
directly, and R3's chunk boundaries are structurally different by construction: P has a 512-key chunk merge, D does
not.

## 5. The sampler

| item | P | D | equal? |
|---|---|---|---|
| greedy rule | `temperature <= 0` (or no sampler) -> `firstBest`: value descending, then **lowest id** (`P:.../cuda_sampler.zig:28-34,46-58`) over the GPU's `top_k + 8` f32 candidates | `temperature <= 0` -> `active` returns null (`D:.../host_sample.zig:6-12`) -> `fn_row_best` over the whole bf16 row, tie-break `ov == v && oi < i` = lowest id (`D:zig/kernels/cuda/flashnext_mtp.cu:9-14,19-60`), read by `pickBest` (`D:.../core/proposal_rows.zig`) | **same rule, lowest id on both** |
| `top_k` / `top_p` | inert at T=0 by the same test (`cuda_sampler.zig:49`) | inert at T=0 (`host_sample.zig:8-12`, `batch_sample.zig:11-16`) | yes |
| where a completions request's sampler comes from | a raw prompt skips the template and still resolves the request's sampler: `thinking = false` for `input.prompt != null`, then `resolveSampling` (`P:.../server/chat.zig:155,173`) | same (`D:.../server/chat.zig:158,182`) | yes: a token-id prompt on `/v1/completions` is sampled exactly as the chat path would at that position |
| seed and the keyed draw | `keyBits(seed, position, id) = mix(mix(mix(seed + c) ^ (position * c2)) ^ id)` (`P:.../core/lanes/sampling.zig:43-49`) | the same expression, `keyBase` then `^ id` (`D:.../core/lanes/sampling.zig:72-83`) | **yes, bit-identical**: the same seed at the same position selects the same uniform twice, so a temperature sweep is a paired experiment across the arms |
| logits precision | head writes bf16; the candidates are promoted to f32 | head writes bf16; `fn_row_best` compares bf16 promoted to f32 | yes |
| logprobs | refused by the server: `production:zig/src/server/fields.zig:287` "logprobs are not supported by this model or backend" | the flashnext backend registers no `first_row` (`D:.../families/flashnext/backend.zig:105`) so `core/lanes/backend.zig:208` answers `error.LogprobsUnsupported` | **neither arm can report a distribution through the API** |

Verdict: a sampler difference is refuted by the code - both are argmax with the same tie-break at T=0, and `top_p`
cannot act. Therefore any divergence is in the logits, and the tie/gap question must be measured empirically
(T=1 seed sweep at a forced prefix, phase 2 step 3).

## Ranking

Ranked by (can it flip a greedy token) x (how cheaply one arm isolates it):

| rank | candidate | why it can flip | isolate | cost |
|---:|---|---|---|---|
| 1 | R3/R6 attention partitioning and prompt pass rows (different kernels, different chunk/merge structure) | every token's logits depend on the attention sums; the fp8 cache is the same, the *sums over it* are not | D at `CHUNK=2048 CHUNK_SOLO=2048` (its own claim: chunk-invariant); P's pass size is a compile-time constant, so only D can move | 1 boot |
| 2 | R1 prompt matmul form (captured one-program slices vs native two-launch) | the first generated token's logits come from the prompt pass | P at `TF_FLASHNEXT_PROMPT_MM=0` (its own fallback, claimed bit-equal) | 1 boot |
| 3 | R7 drafter-driven batch shapes (drafts change the rows in every verify pass and the graph shape) | shapes change tile/split plans; the acceptor then emits the target's pick computed under a different shape | `DRAFTS=0` on both arms (recipe switch) | 2 boots |
| 4 | fp8 KV (item 3) | it is lossy, so any difference in its inputs propagates | `KV_DTYPE=bf16` on both arms at C=1 | 2 boots |
| 5 | D's persistent KV tier / 6 GiB prompt cache | could serve a state written under another shape | `LEARN=0` on D | 1 boot |
| 6 | vision on P | text path is separate; almost certainly inert | `VISION=0` on P | 1 boot |
| 7 | int4 row-tile plan (`HEAD_ROW_TILES`) | claimed bit-equal; if it is not, tiles flip tokens | `HEAD_ROW_TILES=1` on D | 1 boot |
| 8 | drafter weights (fp8 overlay vs mxfp8 recode) | drafts only, via the acceptor - refused by the acceptor rule unless shapes matter | `MTP_WEIGHTS=bf16` on D | 1 boot |
| 9 | sparse indexer block selection at 8k | different block sets change attention wholesale | no knob on either arm; measured by the 8k cell only | - |

Prior evidence on the same box from the other lane of this window pair (its `work/` notes, 2026-11-24): P with
`TF_FLASHNEXT_PROMPT_MM=0`, P with its graphs forced eager (`TF_FLASHNEXT_GRAPH_FAIL=1`) and D with production's copy
policy under the dev names were each **byte-identical to their control on the six golden prompts** (6/6 reply
hashes), while the same prompt-matmul arm reproduced D's cold-prefill *speed* gap exactly (8k TTFT 1.121 against P
1.000). So those levers move cost without moving tokens where the top-2 gaps are wide; this window runs them on the
prompts that actually diverge, which is where a bit-level effect would have to show.

## Refuted before any boot, with the evidence

- **Checkpoint**: equal (`meta.txt`, both argvs, the `model_dir` in every cell's `meta.txt`).
- **Prompt rendering**: equal token counts on 60 of 60 recorded rows; the window re-checks the ids by `/tokenize`.
- **fp8 KV format**: same rule, same trailer, same bytes (`kv8.py:26-93` against `cuda_kv.zig:42-146`).
- **KV width**: 1,056 B a position a layer on both; P's `1056` and D's `18.44 KiB a token` measure different sets
  (D's includes the indexer's 6.0 KiB), as `docs/receipts/ParityGap/DIFF.md` established.
- **int4 weight path and its four settings**: same source line, same values (section 1).
- **12-bit read-outs**: lossless on both; the 192/194 matrix difference is coverage.
- **Sampler**: argmax with the same tie-break at T=0; `top_p` inert (`host_sample.zig:6-12`).
- **`SPLIT_DENSE`**: applies only at world 2 (`D:.../cuda_dense_split.zig:25-33`); both arms are single-GPU.
- **Batched (per-round) attention at high concurrency**: off on both arms. P's `attn_multi` is 0 unless set (`P:.../cuda_forward.zig:533-535`) and the production recipe never sets it; D's `TF_FLASHNEXT_ATTN_LANES` defaults false (`D:.../cuda_batch_lanes.zig:41-44`) and D's env sets it to 0. So at C=8 both engines take attention a stream at a time, and no high-concurrency attention-fusion confound exists between them.
- **Drafter identity**: the acceptor emits the target's own pick (`accept.zig:40-62`); a draft token is never the
  reply token when it disagrees with the target's argmax.

## What the window measures, against this table

1. Determinism: P against P and D against D, two fresh boots each, at C=1 and C=8.
2. The first divergent token per prompt per level, and whether it is the first generated token (prefill/attention
   origin) or later (decode origin).
3. The gap at that step. Logprobs are refused on both arms (section 5), so the gap is measured instead by a T=1 seed
   sweep at the same forced prefix (token-id prompt on `/v1/completions`, `top_k=0`, `top_p=1`, one token), with a
   T=0 control that must reproduce each arm's own next token.
4. The ranked arms: `DRAFTS=0` on both, `PROMPT_MM=0` on P, `CHUNK=2048` on D, `KV_DTYPE=bf16` on both, `LEARN=0`
   on D, `VISION=0` on P, `HEAD_ROW_TILES=1` on D, `MTP_WEIGHTS=bf16` on D - each a fresh boot, controls
   interleaved.
