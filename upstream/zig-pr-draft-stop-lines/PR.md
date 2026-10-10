# Upstream PR (not posted): patches/0020: split draft stop lines, the int4 lm_head as draft head, depth 7 at 2+ streams

Target: MiaAI-Lab/Qwen3.8-Flash-Next-Single-DGX-Spark-TensorFold, base `364f21a` (release 1.0.0).
Evidence: lane w6-opus (`~/work/lanes/w6-opus/`, image `w6-opus-d`, holds h2-h4), stop-rule shootout `merge/mverify5.sh`, merged image `zmerge4` (`merge/mverify6.sh`), host-test mutants `~/work/zpr/mut0020.sh`, `docs/ZIG-SPEED-CAMPAIGN-2026-10.md`. Clean stack: spark6 `~/work/zpr/` (patches/, tf = 0001-0020, image `tensorfold-qwen38:zpr-stack`, host tests `test-stack.log`).

---

**Title:** patches/0020: split draft stop lines, the int4 lm_head as draft head, depth 7 at 2+ streams (decode +1.4 to +7% at 1-2 clients, replies byte-identical)

**Body:**

## Description and Motivation

The running-product stop (`TF_FLASHNEXT_CONFIDENCE < 0`, at up to `TF_FLASHNEXT_PRODUCT_STREAMS` live streams)
uses one line for two decisions: whether the draft just drawn is proposed, and whether the head runs another level.
Proposing a draft is nearly free (a row in the verify window), another head level is not (an MTP step, ~1.3-1.6 ms).

`patches/0020-flash-next-draft-stop-lines.patch`, all of it drafting:

- `TF_FLASHNEXT_DRAFT_PROPOSE` / `TF_FLASHNEXT_DRAFT_CONTINUE` (`cuda_decode.Stop.tp` / `tc`): where the running
  product applies, a draft is proposed while the product is >= the propose line (the first always), and the head
  runs another level only while it is >= the continue line. They replace `-TF_FLASHNEXT_CONFIDENCE`'s one line; unset
  (or a propose line of 0), the one line stands.
- `TF_FLASHNEXT_DRAFT_INT4=1`: the draft head is the int4 lm_head's own GPTQ columns for the draft ids (groups of 128,
  run by `int4.dense`; the id list padded to whole 8-column tiles with its last id), instead of the lm_head's draft
  rows quantized again to 4 bits at load: 105.1 MB read a draft step instead of 127.5 MB, and no second quantization.
- `TF_FLASHNEXT_DRAFT_DEPTH_SHARED=7`: at most 7 drafts a stream while two or more streams draft in one step (a deep
  chain makes every stream of the step wait for it).
- The boot log names all three.

Why the replies do not change: the drafts are verified by the target, which keeps only what it would have produced;
these only change how many drafts are made and which head proposes them.

Measured on one DGX Spark through the recipe's own server: arms interleaved, one boot and one pass an arm per cycle, the order reversed each cycle. Greedy, thinking off, per-request decode tok/s from the client (512-token replies unless a row says otherwise). Every arm ran with `patches/0010` and `0011` and the MTP FP8 overlay (#35, #36) and `TF_FLASHNEXT_CONFIDENCE=-0.15` (#34). Merged build before this patch (`zmerge3`: `0012`-`0014` with the policy off, `0016`-`0018`, the up-mix of
`0019`) against it plus this patch, in a shootout of three stop changes (one hold, a warm-up boot first, two boots an
arm, interleaved), tok/s:

| | before | with `0020` |
| --- | ---: | ---: |
| code, 1 / 2 / 4 clients | 122.2 / 87.9 / 62.0 | 127.7 / 89.1 / 63.5 |
| prose, 1 / 2 / 4 clients | 69.5 / 55.9 / 39.4 | 72.1 / 59.8 / 39.6 |

The next step (`zmerge4`: this patch and `0014`'s copy policy together) repeated it: code 122.1 / 87.4 / 61.5 ->
127.3 / 88.5 / 63.1, prose 69.5 / 55.7 / 39.0 -> 71.6 / 59.5 / 39.4. On the lane's own image (hold 4, base x3 against
x2): code +3.6 / +1.3 / +1.4%, prose +3.4 / +5.9% at 1 / 2 clients, every run above every base run at 1 and 2 clients;
3.25-3.26 tokens a round against 3.21, 76.4% of drafts accepted against 78.5%. The int4 head alone was within noise;
the lines carry most of it.

With #34 merged as well, these lines replace its `-0.15` wherever the product rule applies (they were measured on
top of it). Measured and left out: a cost-aware adaptive rule (lines from the round's measured costs), a smaller
draft vocabulary, depth caps at one stream, a calibrated per-draft rule and a propose floor.

## Related Issues

None.

---

## Testing

- Golden replies (six greedy prompts, `temperature: 0`, fixed seed) byte-identical to the stock image on every boot of every hold quoted here. (33 boots on the lane, 9 in the shootout, 4 in the `zmerge4` hold).
- Host test (`cuda_decode.zig`): one line stops the chain at the draft under it; with split lines a draft under the
  continue line is proposed and ends the chain, one under the propose line is not proposed; the first draft always
  goes. Two mutants of `Stop.take` (the propose test against the continue line; the continue test always true) each
  fail it (`zig build test` on the clean stack).
- The patch here is the measured code with the campaign's experiment-only switches taken out (named above). The whole stack, `patches/0001`-`0020`, applies with `git apply` in order on TensorFold `db281878`, builds the image's engine (`zig build -Doptimize=fast fatbins install native` with nvcc in the build image), and passes `zig build test` (21/21 steps, 189/189 tests).
- `bash -n start.sh stop.sh scripts/*.sh`; `python3 -m py_compile tools/*.py`; shellcheck adds no finding.
- Memory: the draft head shrinks from 127.5 MB to 105.1 MB.

Other PRs from me in this batch: #34 (the one-Spark draft stop default), #35 (`patches/0010`), #36 (`patches/0011` + `MTP_FP8`), and #[0012's PR] (n-gram host gather), #[0013's PR] (copy windows), #[0014's PR] (copy re-sync and ramp), #[0015's PR] (copies in shared rounds), #[0016's PR] (sequence pool and graphs), #[0017's PR] (batched draft draws), #[0018's PR] (fused FP8 split-K and lm_head row tiles), #[0019's PR] (decode read-out fusion). `patches/0012`-`0020` are one stack written in that order on top of `0001`-`0011`: each applies with `git apply` after the ones before it (several edit the same lines of `cuda_engine.zig`), so this PR's patch needs #35, #36 and #[0012's PR], #[0013's PR], #[0014's PR], #[0015's PR], #[0016's PR], #[0017's PR], #[0018's PR], #[0019's PR] merged first (logically it builds on #34's running-product rule and #36's MTP layer). All twelve add CHANGELOG/README/CREDITS lines in the same places, the patch PRs each add a row to the same new patch table (as #35 and #36 do), and the setting PRs add `scripts/config.sh` lines after `TF_FLASHNEXT_PREFILL_TAIL`; whichever merges second, I rebase.

---

## Checklist:

- [x] I have read the README and `scripts/config.sh` and kept my changes consistent with them.
- [x] My pull request has a sound title and description (not something vague like `Update README.md`).
- [x] My change is reproducible and verified (script syntax check, `scripts/prepare.sh`, a launch, or a re-measurement).
- [x] A patch change keeps every reply byte-identical, and I said how I checked it.
- [x] I updated the README and/or `scripts/config.sh` if a setting, default, or measured number changed.
- [x] If my change affects memory, I checked the startup estimate still fits the budget at the default 5 x 262,144 int8 setting.
- [x] Defaults in `scripts/config.sh` still work out of the box; a new setting has a sane fallback like the existing ones.
