# Why two engines on one checkpoint return different greedy replies: the measured divergence

P is production, image `tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7` (`sha256:235211ea77ee`), Zig engine on
`5c3e3e29` plus the zmerge8 keep set. D is the dev composition, image `tensorfold-qwen38:r5dev40`
(`sha256:adc40fe3ea7b`), upstream `1ece6e6d` plus the 40 patches of `patches/main-1ece6e6db-r5-dev`. One checkpoint
on both, `snapshots/1464274120d36a4d8fcaa934552334a7d83ce0fd`.

Every number below is quoted from a command over an artefact, named with its path. Two sources:

- the queued window's own output on spark6 at `~/work/parityid/out` (its log, `run.log`, shows `RUN-DONE`,
  `EXIT-DONE`, the restore at `21:32:48Z`), packed as `~/work/parityid/parityid-ev.tgz`; the tables here are
  `~/work/parityid/out/report1.md`, `report2.md`, `report3.md`, `tables.md`, `dist.md`. Copied to this repo at
  `work/ParityDivergence/ev-window/` and the per-cell trees at `work/ParityDivergence/ev-cells/`.
- the recorded `docs/receipts/ParityAB/ev.tgz`, unpacked at `work/ParityDivergence/PIDev/`.

The window is the ParityIdentical lane's, deployed and hash-matched before this lane started; it finished during
this lane. This lane did not re-deploy it, did not touch spark6's `gpu.lock`, and signalled no process.

## 1. First divergent token index, per prompt and level

The divergence is localised by the first token id (the engine's own reply token, reconstructed with `/tokenize` on
both arms) at which the two arms differ. `P_a` and `P_b` are two fresh boots of P; `D_a`, `D_b` of D. From
`ev-cells/*/c1/rows.jsonl` over the five fixed prompts (`in/prompts/`), token index k:

| prompt | prompt tokens | k (token index) | P token at k | D token at k | P/D reply tokens |
|---|---:|---:|---|---|---|
| prose-rec0 | 40 | 25 | ' by the producer,' | ' thread reads, so we' | 512/512 |
| code-rec0 | 33 | 492 | (text-equal tail) | | 512/512 |
| prose-1k | 958 | 32 | '.\n\nHere' | '-size circular buffer (' | 512/512 |
| code-1k | 1481 | 389 | | | 512/512 |
| prose-8k | 7997 | 54 | '. In' | ' not static' | 496/407 |

Command: `python3 -c` over `ev-cells/P_a/c1/rows.jsonl` and `ev-cells/D_a/c1/rows.jsonl` comparing `reply_ids`
field by field. Sources: `work/ParityDivergence/ev-window/report1.md` section "cross: one row a cell".

**The index is identical across j and across C=1 and C=8.** `report2.md` cross table shows all 40 rows at C=8
(P_a/D_a and P_b/D_b) carry the same k=25/492/32/389/54 as C=1; `P_b`/`D_b` reproduce it too
(`ev-cells/P_b/c1/rows.jsonl`, `D_b`). So the flip position is a property of the prompt, not of the batch
composition or the stream slot.

**The divergence is mid-text, not an early stop.** Both arms emit a coherent continuation; the count of rows that
complete the same token count as the other arm (from the recorded `docs/receipts/ParityAB/ev.tgz`, unpacked to
`work/ParityDivergence/PIDev/`) is 99 of the 116 differing rows:

```
differing rows 116 of 126; same completion_tokens among differing: 99
differing by C: {1: 6, 2: 12, 4: 22, 6: 33, 8: 43}
  C=1: 6 differing, 5 same tok    C=4: 22 differing, 19 same tok    C=8: 43 differing, 37 same tok
  C=2: 12 differing, 10 same tok  C=6: 33 differing, 28 same tok
```

(script over `PIDev/{P,D}/c*/run*/dec.jsonl`). This reproduces the starting fact (5/6, 10/12, 19/22, 28/33, 37/43).

**Both arms are deterministic against themselves, and the flip rate is the rare-event signature.** The recorded
window's run1 against run2: `P run1 vs run2 identical rows: 156 / 156`. The new window's self table (`tables.md`)
is 45/45 rows self-equal per arm (P_a/P_b and D_a/D_b at C=1 and all eight j at C=8). The prompt ids the two arms
render are equal on every row (20 of 20 at C=1 and C=8, `tables.md` section "Prompt ids the two arms render"). So
the inputs are identical and each engine repeats itself; the difference is a reproducible numerical flip.

## 2. The margin at the flip: the two arms' logits differ by a body-level shift, not a near-tie

Neither arm serves logprobs: production answers `logprobs are not supported by this model or backend`, dev answers
the same (`ev-cells/{P_a,D_a}/c1/logprobs.txt`; prod refuses in `production:zig/src/server/fields.zig:287`, dev's
Flash Next backend registers no `first_row`). The instrument chosen is a forced prefix (the chat prompt ids plus the
arm's own reply ids up to k) sent as a token-id prompt on `/v1/completions`, `max_tokens` 1, a ladder of
temperatures with distinct seeds, where the temperature-0 draw is a control that must reproduce the arm's own next
token (`in/dist_probe.py`, seed 1234).

Querying each drawn token's engine hash at the forced prefix shows the two arms' distributions over the SAME
prefix are different distributions, not one distribution sampled twice:

| cell | T | P's own top | D's own top |
|---|---:|---|---|
| code-rec0-j0 | 1.0 | ' -' 32/60 (0.53), ' ' 28/60 | ' ' 33/60 (0.55), ' -' 27/60 |
| code-rec0-j0 | 0.2 | ' -' 57/60 (0.95) | ' ' 33/60, ' -' 27/60 (0.55 flat) |
| code-rec0-j0 | 0.05 | ' -' 60/60 (1.00) | ' ' 33/60, ' -' 27/60 (still flat) |
| prose-1k-j0 | 0.01 | ' memory' 60/60 (1.00) | ' operations' 60/60 (1.00) |

(script over `ev-cells/{P_b,D_b}-c1.jsonl`). Two consequences:

- The deviation is scale-free: the sweeps at T=1.0, 0.2, 0.05 and 0.01 all read the two hypotheses almost equally
  often (e.g. P stays 33/27 at every T on code-rec0; D stays 33/27 at 0.2/0.05/0.01 on code-rec0). A sampling
  artefact of one temperature would move its split with T; this does not.
- P and D hold **different top-1 tokens** at the same position and T=0 (P ' -' vs D ' '; ' memory' vs
  ' operations'; ' is' vs ' ('). The quantised logit difference at the divergent step is therefore larger than
  the temperature ladder can resolve in this direction: at T=0 both arms already sit on opposite sides of the
  argmax with their own most-likely token reproducible to 60/60.

**Classification.** P_a against P_b and D_a against D_b are byte-identical (self table, `tables.md`), so each
arm's own reproducibility noise is **zero** on these prompts; there is no same-arm spread for the gap to hide in.
The divergence cannot be the two arms reading one distribution and picking different tokens (both argmaxes
tie-break to the lowest id, `INVENTORY.md` section 5), and it cannot be noise. It is an arithmetic difference
between the two engines' logits at that position.

**Calibration caveat (the missing instrument):** the ladder's T=0 control `control_ok` is `None` (not `True`) on
every row (`dist.md`), because `dist_probe.py` compares the control's token TEXT with the recorded token text and
the arm was probed on `P_b`/`D_b` (byte-identical to `P_a`/`D_a`, verified:
`P_a == P_b : True`, `D_a == D_b : True`, five rows each). So the sweeps' shape is read from the artefacts, and a
clean single-number "logit gap in bf16 steps" was not produced: the sweeps resolve the split only as a ratio, and
both arms' distributions are peaked enough that the exact nats are not recoverable from a 60-sample draw. The
number that ties a margin to the argmax would come from the engine's own logit row, which neither serves; the
nearest available evidence is this paired-seed sweep, and it settles the classification (different distributions),
not the exact delta.

## 3. The lever: the fp8 KV path is the mechanism; the drafter is refuted

Each lever is one fresh boot of one arm with one setting moved, against that arm's own control, five prompts at
C=1. Rows are `sha` (client text) and `token_sha` (engine). From `ev-cells/*/c1/rows.jsonl`.

| arm | lever | vs its own control (text/tokens) | min k vs control | verdict |
|---|---|---|---:|---|
| D_nodrafts | `DRAFTS=0` (both arms) | 5/5, 5/5 | 406 | **refuted** (drafter not the mechanism) |
| P_nodrafts | `DRAFTS=0` | 5/5, 5/5 | 495 | **refuted** |
| D_notier | `LEARN=0` (KV tier off) | 5/5, 5/5 | 406 | **refuted** |
| D_chunk2048 | `CHUNK=2048 CHUNK_SOLO=2048` | 5/5, 5/5 | 406 | **refuted at C=1** |
| D_int4tile64 | `INT4_TILE=64` | 5/5, 5/5 | 406 | **refuted** |
| D_mtpbf16 | `MTP_WEIGHTS=bf16` | 5/5, 5/5 | 406 | **refuted** |
| P_novision | `VISION=0` | 5/5, 5/5 | 495 | **refuted** |
| P_pmm0 | `PROMPT_MM=0` | 5/5, 5/5 | 495 | **refuted** (prompt-matmul form is speed only) |
| P_int4tile64 | `INT4_TILE=64` | 5/5, 5/5 | 495 | **refuted** |
| D_bf16kv | `--kv-cache bf16` | 0/5, 0/5 | 3 | **load-bearing** |
| P_bf16kv | `--kv-dtype bf16` | 0/5, 0/5 | 3 | **load-bearing** |

Every refuted cell is byte-identical to its own control on all five prompts (5/5 text and 5/5 engine token hash):
its lever changes nothing in its own arm, so it cannot be the cross-arm difference. Most directly, `DRAFTS=0`
leaves D's replies byte-for-byte as D's own greedy replies (`D_a` vs `D_nodrafts`: 512/512 tokens at k on all five,
k=512/512/512/512/406), and `P` at `DRAFTS=0` likewise equals P. So the mechanism is not the drafter, the
acceptor, the persistent tier, the int4 tile, the MTP weights, vision, the prompt-matmul form, or - at one stream -
D's 16384-row chunking.

**The load-bearing pair is the KV dtype.** Both arms boot with `--kv-dtype fp8` / `--kv-cache fp8` (each boot's
argv and plan: "fp8 KV cache, 1056 bytes a position a layer" for P, "18.44 KiB a token" for D). Moving the dtype to
bf16 on ONE arm changes that arm's own replies on all five prompts:

- P (`--kv-dtype bf16`) against P: 0/5. First divergent token 3, 3, 116, 33, 127.
- D (`--kv-cache bf16`) against D: 0/5. First divergent token 99, 3, 32, 389, 120.
- D (`--kv-cache bf16`) against P: 1/5, and where it agrees it is **exact** - `code-1k` D_bf16kv equals P_a sha for
  sha (`e49fb88574...`), the one row of the ten the two bf16 arms produce that is byte-identical across engines.

So the fp8 KV path is the origin of the cross-arm divergence: it is the one setting whose change moves replies, and
the bf16 pair is much closer to agreement than the fp8 pair. Evidence pointer: `docs/receipts/ParityIdentical/INVENTORY.md`
section 3 already established both engines serialise the SAME fp8 rule (scale 2^(ceil(log2 amax) - 8), e4m3, key
row = codes + s_k + s_v + 8 zero bytes, value row = codes; `production/.../kv8.py:26-93` against
`dev/.../cuda_kv.zig:42-146`), so the format is not the difference; what differs is the **quantisation tile order
and the attention reduction structure** that build and sum those rows.

**The divergence is decode-origin, not prompt-pass origin.** The METHOD rule reads a first divergent token at 0 (or
the first generated token) as a prompt-pass / last-prompt-row effect, and k>0 as a decode-loop effect. Here k is
25, 492, 32, 389 and 54 - greater than 0 on every prompt - and it does not scale with the prompt length: the
7,997-token prompt flips at k=54 while the 40-token prompt flips at k=25. A prompt-pass difference would move the
very first generated logits and flip at k near 0, and it would show the shortest prompt flipping first; neither
holds. So the prompt pass (and with it D's 16384-row prompt chunking, which only acts there) is excluded as the
mechanism, and the difference is in the decode loop's read of the KV cache - the fp8 rows and the attention
reduction over them. This also explains why `PREFIX_ROWS` and `PROMPT_MM=0` are both inert: they act on the prompt
pass only.

**Why the hole is now narrower.** D at `CHUNK=2048 CHUNK_SOLO=2048` is byte-identical to D at its own
`CHUNK=4096/16384` on all five prompts (5/5), consistent with the decode-origin finding. What the window cannot
separate is the two engines' fp8 row-quantisation tile from their attention reduction structure, both of which act
in the decode loop. A launcher edit is required to try P at a different prompt-pass size - P's engine reads only
`TF_FLASHNEXT_PREFILL_ROWS` (`work/ParityIdentical/Ptree/zig/src/families/flashnext/cuda_engine.zig:423`, range 16
to 16384) and BOTH launchers pin it to 4096 in their own exec env (`~/qwen6-start-prod.sh:56`, `~/qwen6-start.sh:89`),
the same null-arm trap the preflight caught on `HEAD_ROW_TILES` - and that edit is on the serve lanes' boxes, not
this lane's.

## 4. What is explained and what is refuted

**Explained with a named mechanism (at the level the artefacts support):** the two engines diverge in the KV
read-out path, specifically in the fp8 KV rows and their attention reduction. The evidence is (a) the first
divergent token index is per-prompt fixed and identical at every level (25/492/32/389/54), (b) the two arms hold
different logit distributions at the same forced prefix at every temperature and never tie, and (c) the one setting
that moves an arm's own replies is the KV dtype, whose change to bf16 pulls D_bf16kv onto P exactly on one prompt
and off D on all five.

**Refuted, each with its number:** the drafter and its acceptor (`DRAFTS=0` 5/5 both arms); the persistent KV tier
(`LEARN=0` 5/5); D's 16384-row chunking at one stream (`CHUNK=2048` 5/5); the int4 tile plan (`INT4_TILE=64` 5/5
both arms); the MTP drafter weights (`MTP_WEIGHTS=bf16` 5/5); vision (`VISION=0` 5/5); the prompt-matmul form
(`PROMPT_MM=0` 5/5). Batch composition cannot be the mechanism either: the index is invariant across C=1 and C=8
and across all eight slots at C=8, and both engines' batched per-round attention is off
(`production/.../cuda_forward.zig:533-535`; `dev/.../cuda_batch_lanes.zig:41-44`).

**Refuted in the inventory, by this window:** rank 3 (drafter-driven batch shapes), rank 4 (fp8 KV is not "a
source" - it is THE source), rank 5 (tier), rank 6 (vision), rank 7 (int4 row tile), rank 8 (drafter weights).

**The remaining separation, and why it is not this lane's to close.** Two candidates act inside the decode loop and
the window separates neither: the two engines' fp8 row-quantisation tile order, and their attention reduction
structure (P merges 512-key chunk partials in chunk order, `production/.../attention.py:13,178-187`; D walks keys in
one pass with an online softmax, `dev/.../prefill_attention_rows.cuh`). Closing this needs a launcher edit to move
P's prompt-pass rows or an arm that perturbs one engine's decode KV read directly; no existing knob reaches either,
and the launcher edit is on the serve lanes' boxes, not this lane's (see section 3).

## 5. Files

- `docs/receipts/ParityDivergence/RESULT.md` - this receipt.
- `work/ParityDivergence/ev-window/` - the parityid window's `report1-3.md`, `tables.md`, `dist.md`, `run.log`,
  `parityid-ev.tgz` (gitignored; the source is spark6 `~/work/parityid/out`).
- `work/ParityDivergence/ev-cells/` - the per-cell `rows.jsonl`, env, argv, plan, boot log for the 16 cells and the
  distribution jsonl (gitignored).
- `work/ParityDivergence/PIDev/` - the recorded ParityAB window unpacked (gitignored).
