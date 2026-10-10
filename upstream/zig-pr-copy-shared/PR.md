# Upstream PR (not posted): patches/0015: copies out of the prompt ramp in shared rounds too

Target: MiaAI-Lab/Qwen3.8-Flash-Next-Single-DGX-Spark-TensorFold, base `364f21a` (release 1.0.0).
Evidence: lane w2-opus (`~/work/lanes/w2-opus/`, image `w2-opus-cw14`, mutants `sh4mut.sh`), merged image `zmerge5` (`merge/mverify9.sh`), `docs/ZIG-SPEED-CAMPAIGN-2026-10.md`. Clean stack: spark6 `~/work/zpr/` (patches/, tf = 0001-0020, image `tensorfold-qwen38:zpr-stack`, host tests `test-stack.log`).

---

**Title:** patches/0015: copies out of the prompt ramp in shared rounds too (two concurrent file edits +55%, replies byte-identical)

**Body:**

## Description and Motivation

`0013`'s copy ramp applies to a lone stream only: as soon as two clients decode together, every copy window is
15 rows again, so two agents editing files at once copy at a fraction of the lone rate.

`patches/0015-flash-next-copy-shared-rounds.patch`:

- `TF_FLASHNEXT_COPY_SHARED=1` (`core/lanes/config.zig` `copy_shared`): streams in shared rounds take the lone
  stream's ramp too (15 -> 31 -> 63, or `TF_FLASHNEXT_COPY_RAMP`), and follow `TF_FLASHNEXT_COPY_MISS`. The allocator
  still trims each shared round to the decode buffers' rows.
- Only copies out of the prompt ramp in a shared round: the proposer now reports where its last copy came from
  (`Proposer.lastFrom`), and a reply copying its own earlier lines keeps 15 rows (that self-copy is what makes code
  replies pay for wide windows at several clients).
- The boot log line of `0014` adds `shared rounds ramp copies out of the prompt`.

Why the replies do not change: as `0013`: copies are drafts verified row by row; the shared rounds already run up to
128 rows through the same row-invariant kernels.

Measured on one DGX Spark through the recipe's own server: arms interleaved, one boot and one pass an arm per cycle, the order reversed each cycle. Greedy, thinking off, per-request decode tok/s from the client (512-token replies unless a row says otherwise). Every arm ran with `patches/0010` and `0011` and the MTP FP8 overlay (#35, #36) and `TF_FLASHNEXT_CONFIDENCE=-0.15` (#34). Merged build (`zmerge5` = `0012`-`0014`, `0016`-`0020` + this, against the same without this patch and without
`0019`'s reduce + activation, which alone is +0.5 to +1.2% on decode), two boots an arm after a warm-up:

| tok/s | without | with `0015` |
| --- | ---: | ---: |
| two concurrent file edits, each stream | 192-218 | 286-350 |
| a file edit beside a prose reply: edit / prose | 233-236 / 67.0-67.9 | 439-465 / 71.7-72.0 |
| lone copy / one-word rewrite | 817-820 / 584-586 | 819-823 / 585-587 |
| code, 1 / 2 / 4 clients | 127.6 / 88.5 / 63.6 | 128.1 / 88.9 / 63.2 |
| prose, 1 / 2 / 4 clients | 72.3 / 59.8 / 39.6 | 72.6 / 60.1 / 39.9 |

On the lane's own image (the same mechanism, one boot an arm): two concurrent edits 188 / 177 -> 274 / 268 tok/s
(stock ~176 / 176), an edit beside a prose reply 217 -> 312 with the prose stream at 60-66 either way.

## Related Issues

None.

---

## Testing

- Golden replies (six greedy prompts, `temperature: 0`, fixed seed) byte-identical to the stock image on every boot of every hold quoted here.
- Host test (`core/lanes/engine_test.zig`): a shared round copies 15 rows without the knob, 63 with it when the copy
  came from the prompt, and 15 when it came from the reply's own lines; the proposer reports the copy's source index.
  Mutants that ungate the ramp, turn it off, or blank the proposer's source each fail it. The engine line that marks
  whether a copy came from the prompt has no host test: the GPU A/B above is its check.
- The patch here is the measured code with the campaign's experiment-only switches taken out (named above). The whole stack, `patches/0001`-`0020`, applies with `git apply` in order on TensorFold `db281878`, builds the image's engine (`zig build -Doptimize=fast fatbins install native` with nvcc in the build image), and passes `zig build test` (21/21 steps, 189/189 tests).
- `bash -n start.sh stop.sh scripts/*.sh`; `python3 -m py_compile tools/*.py`; shellcheck adds no finding.
- Memory: unchanged (one flag a stream).

Other PRs from me in this batch: #34 (the one-Spark draft stop default), #35 (`patches/0010`), #36 (`patches/0011` + `MTP_FP8`), and #[0012's PR] (n-gram host gather), #[0013's PR] (copy windows), #[0014's PR] (copy re-sync and ramp), #[0016's PR] (sequence pool and graphs), #[0017's PR] (batched draft draws), #[0018's PR] (fused FP8 split-K and lm_head row tiles), #[0019's PR] (decode read-out fusion), #[0020's PR] (draft stop lines). `patches/0012`-`0020` are one stack written in that order on top of `0001`-`0011`: each applies with `git apply` after the ones before it (several edit the same lines of `cuda_engine.zig`), so this PR's patch needs #35, #36 and #[0012's PR], #[0013's PR], #[0014's PR] merged first (logically it builds on #[0013's PR] and #[0014's PR]). All twelve add CHANGELOG/README/CREDITS lines in the same places, the patch PRs each add a row to the same new patch table (as #35 and #36 do), and the setting PRs add `scripts/config.sh` lines after `TF_FLASHNEXT_PREFILL_TAIL`; whichever merges second, I rebase.

---

## Checklist:

- [x] I have read the README and `scripts/config.sh` and kept my changes consistent with them.
- [x] My pull request has a sound title and description (not something vague like `Update README.md`).
- [x] My change is reproducible and verified (script syntax check, `scripts/prepare.sh`, a launch, or a re-measurement).
- [x] A patch change keeps every reply byte-identical, and I said how I checked it.
- [x] I updated the README and/or `scripts/config.sh` if a setting, default, or measured number changed.
- [x] If my change affects memory, I checked the startup estimate still fits the budget at the default 5 x 262,144 int8 setting.
- [x] Defaults in `scripts/config.sh` still work out of the box; a new setting has a sane fallback like the existing ones.
