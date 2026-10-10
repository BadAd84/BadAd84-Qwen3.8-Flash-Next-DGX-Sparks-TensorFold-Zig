# Upstream PR (not posted): patches/0017: one launch and one read for a draft level's greedy draws

Target: MiaAI-Lab/Qwen3.8-Flash-Next-Single-DGX-Spark-TensorFold, base `364f21a` (release 1.0.0).
Evidence: lane w4-fable (`~/work/lanes/w4-fable/FINDINGS.md`, image `w4-fable-batch2`, mutant image from `batch-draws-v2-mutant.patch`), merged image `zmerge1`, `docs/ZIG-SPEED-CAMPAIGN-2026-10.md`. Clean stack: spark6 `~/work/zpr/` (patches/, tf = 0001-0020, image `tensorfold-qwen38:zpr-stack`, host tests `test-stack.log`).

---

**Title:** patches/0017: one launch and one read for a draft level's greedy draws (+1 to +2.7% at 4-8 clients, replies byte-identical)

**Body:**

## Description and Motivation

In a shared draft step each stream drew its draft on its own: per stream a `toF32`, three logsumexp kernels, an
argmax, `draft_pick`, a synchronize and a 12-byte read, about 38 us of GPU (with #35) plus a wait, per stream per level.
At four streams `mtp.draft_sample` took 0.56-0.70 ms a round (`TF_FLASHNEXT_PROFILE=1`, eager).

`patches/0017-flash-next-batched-draws.patch` (one rank, greedy streams):

- `tf_fn_draft_greedy_rows_kernel` (`fn_logsumexp.cu`), one block a row over the step's rows: the first maximum by
  `argmax_order.h`'s total order (NaN first, then the largest value at the lowest column, so any block shape finds the
  same column), then the sum of `exp(x - m)` in ATen's single-row reduce order (`tf_fn_logsumexp_config(1, n)`: the
  `ctas` CTAs walked one after another by the same block), writing `draft_pick`'s [max, lse, column]. Each row's
  bytes are its own per-row draw's.
- `draftMany` draws a level's greedy streams with that one launch and one read (`Draws.sampleDraftRows`); sampled
  streams keep their own draws. `TF_FLASHNEXT_BATCH_DRAWS=0` is the old path.
- `sampleWindow`: a shared round's greedy windows take one argmax over the round's rows and one read
  (`TF_FLASHNEXT_BATCH_WINDOWS=0`: one a window).
- `tensorfold draft-check MODEL [--rows ...]` (no weights): the batched draw against the per-row draw, bytes compared
  on adversarial rows at the draft vocabulary's width (79,591), the main head's (248,320) and three more, then both
  timed.

Measured on one DGX Spark through the recipe's own server: arms interleaved, one boot and one pass an arm per cycle, the order reversed each cycle. Greedy, thinking off, per-request decode tok/s from the client (512-token replies unless a row says otherwise). Every arm ran with `patches/0010` and `0011` and the MTP FP8 overlay (#35, #36) and `TF_FLASHNEXT_CONFIDENCE=-0.15` (#34). Lane image (this patch on the stock engine), aggregate tok/s (completion tokens over the batch's wall time,
the stable measure at 4+ clients), two or three runs an arm:

| aggregate tok/s | stock | 0017 | same binary, `=0` |
| --- | ---: | ---: | ---: |
| code, 4 clients | 198.5 / 198.5 / 199.0 | 205.5 / 202.1 | 199.0 / 200.8 |
| prose, 4 clients | 138.1 / 138.2 / 137.6 | 139.6 / 139.2 | 138.4 / 137.9 |
| code, 8 clients | 286.5 / 292.9 | 294.7 / 294.4 | 288.1 / 292.0 |
| prose, 8 clients | 193.7 / 194.5 | 197.3 / 196.5 | 194.6 / 194.4 |

Every run with the patch beat every stock run and every knobs-off run at 4 and 8 clients. At 1-2 clients the per-level
saving (~16 us at one stream) is below the harness's noise (code 117.5 -> 118.5, 84.6 -> 85.6). In the same binary,
four streams: `mtp.draft_sample` 0.556 -> 0.167 ms a round (prose), 0.700 -> 0.214 (code); `sample` 0.148 -> 0.057.
The kernel draws 1 to 16 rows in 21-22 us (the rows run on separate SMs). In the merged builds the gain at four clients
was inside the hold's noise.

## Related Issues

None.

---

## Testing

- Golden replies (six greedy prompts, `temperature: 0`, fixed seed) byte-identical to the stock image on every boot of every hold quoted here. Round, draft and acceptance counts equal across arms (e.g. 4,837 / 12,769 / 10,105 against
  4,846 / 12,744 / 10,097).
- `tensorfold draft-check`: 360/360 cases byte-equal (widths 79,591, 248,320, 4,096, 1,000, 131; 1-64 rows; normal,
  wide exponents, ties, NaN, +inf, all -inf, signed zeros, subnormals, mixed). A mutant (the four partial sums folded
  into one accumulator in the aligned branch) gives 23/360 different (1-ulp logsumexp drifts) and FAIL.
- The patch here is the measured code with the campaign's experiment-only switches taken out (named above). The whole stack, `patches/0001`-`0020`, applies with `git apply` in order on TensorFold `db281878`, builds the image's engine (`zig build -Doptimize=fast fatbins install native` with nvcc in the build image), and passes `zig build test` (21/21 steps, 189/189 tests).
- `bash -n start.sh stop.sh scripts/*.sh`; `python3 -m py_compile tools/*.py`; shellcheck adds no finding.
- Memory: 768 bytes of device scratch and a few KB of host arrays.

Other PRs from me in this batch: #34 (the one-Spark draft stop default), #35 (`patches/0010`), #36 (`patches/0011` + `MTP_FP8`), and #[0012's PR] (n-gram host gather), #[0013's PR] (copy windows), #[0014's PR] (copy re-sync and ramp), #[0015's PR] (copies in shared rounds), #[0016's PR] (sequence pool and graphs), #[0018's PR] (fused FP8 split-K and lm_head row tiles), #[0019's PR] (decode read-out fusion), #[0020's PR] (draft stop lines). `patches/0012`-`0020` are one stack written in that order on top of `0001`-`0011`: each applies with `git apply` after the ones before it (several edit the same lines of `cuda_engine.zig`), so this PR's patch needs #35, #36 and #[0012's PR], #[0013's PR], #[0014's PR], #[0015's PR], #[0016's PR] merged first (logically it extends #35's `fn_logsumexp.cu`). All twelve add CHANGELOG/README/CREDITS lines in the same places, the patch PRs each add a row to the same new patch table (as #35 and #36 do), and the setting PRs add `scripts/config.sh` lines after `TF_FLASHNEXT_PREFILL_TAIL`; whichever merges second, I rebase.

---

## Checklist:

- [x] I have read the README and `scripts/config.sh` and kept my changes consistent with them.
- [x] My pull request has a sound title and description (not something vague like `Update README.md`).
- [x] My change is reproducible and verified (script syntax check, `scripts/prepare.sh`, a launch, or a re-measurement).
- [x] A patch change keeps every reply byte-identical, and I said how I checked it.
- [x] I updated the README and/or `scripts/config.sh` if a setting, default, or measured number changed.
- [x] If my change affects memory, I checked the startup estimate still fits the budget at the default 5 x 262,144 int8 setting.
- [x] Defaults in `scripts/config.sh` still work out of the box; a new setting has a sane fallback like the existing ones.
