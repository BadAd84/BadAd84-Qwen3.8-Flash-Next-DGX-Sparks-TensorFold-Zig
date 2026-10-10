# Upstream PR (not posted): patches/0018: fused split-K block-FP8 projections and 32-row lm_head items

Target: MiaAI-Lab/Qwen3.8-Flash-Next-Single-DGX-Spark-TensorFold, base `364f21a` (release 1.0.0).
Evidence: lane w8-opus (`~/work/lanes/w8-opus/`, images `w8-opus-v2`/`v4`, holds s3-s6), W8Fable's cross-check, merged image `zmerge3` (`merge/mverify4.sh`), `docs/ZIG-SPEED-CAMPAIGN-2026-10.md`. Clean stack: spark6 `~/work/zpr/` (patches/, tf = 0001-0020, image `tensorfold-qwen38:zpr-stack`, host tests `test-stack.log`).

---

**Title:** patches/0018: fused split-K block-FP8 projections and 32-row lm_head items (copy windows +7%, code at 4 clients +8% on the merged build; replies byte-identical)

**Body:**

## Description and Motivation

Two bandwidth-bound decode kernels left the GPU partly idle:

- The block-FP8 projections that split K (`out_proj`, 2560 x 6144 and the like) run on the cluster kernel below 256
  rows: one block a K slice, the slices added in the cluster. On GB10 a cluster launch fits two blocks per SM, so
  `out_proj`'s 320 cluster blocks run in about 3.3 waves.
- The int4 lm_head's dense calls ran in 16-row items whatever the rows, so a 17-64-row call (a copy window of `0013`)
  read the 0.33 GB head once for every 16 rows.

`patches/0018-flash-next-fp8-fused-split-head-rows.patch`:

- `TF_FLASHNEXT_FP8_FUSED_SPLIT=4` (`cuda_fp8.zig` `Mode`): split shapes of at least `TF_FLASHNEXT_FP8_FUSED_SPLIT_N`
  (2048) columns below 256 rows run on the stock kernel's fused form, one block a 64-column tile walking its K slices
  and adding them in slice order, the cluster's own sum. Row tiles 16 and 32 use new instantiations of the same
  kernel at pipeline depth 4 (or 8), row tile 64 the prompt's fused kernel. The column gate keeps narrow shapes (the
  MTP layer's hyper-connection down: a few column tiles over K 10240) on the cluster kernel: fused, that one took
  0.51 -> 1.16 ms a round.
- `TF_FLASHNEXT_HEAD_ROW_TILES=2` (`cuda_int4.zig`): the head's calls of 17+ rows take 32-row items (the kernel's
  dense items are now 16 x MT rows; MT 2 was already instantiated for prompt items), so the weights are read once for
  32 rows. 16 rows and fewer are unchanged.
- `tensorfold fp8-fused-check MODEL` and `tensorfold int4-head-check MODEL` (no weights): the two against the stock
  paths, bytes compared, then timed. The boot log names both settings.

Why the replies do not change: the fused form adds the same K slices in the same order as the cluster, and the head's
32-row item is two 16-row tiles under one weight read: every output's MMA chain and `fmaf` order are the same.

Measured on one DGX Spark through the recipe's own server: arms interleaved, one boot and one pass an arm per cycle, the order reversed each cycle. Greedy, thinking off, per-request decode tok/s from the client (512-token replies unless a row says otherwise). Every arm ran with `patches/0010` and `0011` and the MTP FP8 overlay (#35, #36) and `TF_FLASHNEXT_CONFIDENCE=-0.15` (#34). Kernel times (weights rotated so they cannot stay in the 24 MB L2, median of 5, us a call):

| shape | rows | cluster | fused |
| --- | --- | ---: | ---: |
| 2560 x 6144 | 1-16 | 81.3 | 70.5 |
| 2560 x 6144 | 17-32 | 93-96 | 72 |
| 2560 x 3072 | 1-16 | 41.4 | 36.9 |
| 2560 x 2560 | 1-16 | 35.8 | 30.4 |

| lm_head 248,320 x 2560, us | 17 rows | 32 rows | 33 rows | 64 rows |
| --- | ---: | ---: | ---: | ---: |
| 16-row items | 2,853 | 2,972 | 4,328 | 5,882 |
| 32-row items | 1,486 | 1,541 | 2,943 | 3,087 |

In the engine (lane image, one stream): `out_proj` 4.09 -> 3.74 ms a round. The lane's own net tok/s hold of the final
version did not report before the merge, so the net numbers are the merged build's (`zmerge3`: this patch and `0019`'s
decode up-mix together, which alone was +0.3 to +0.9%, on `0012`-`0014`, `0016`, `0017`), two boots an arm:

| tok/s | before | with `0018` (+ up-mix) |
| --- | ---: | ---: |
| code, 1 / 2 / 4 clients | 122.0 / 85.7 / 57.3 | 122.9 / 88.1 / 62.1 |
| prose, 1 / 2 / 4 clients | 68.9 / 55.3 / 38.5 | 68.9 / 55.9 / 39.6 |
| verbatim copy / one-word rewrite | 759-769 / 416-420 | 818-821 / 437-438 |

The campaign's other tile variants (pipeline depths 2 and 3 for every tile, 64-row head items) measured no faster or
spilled registers; they and their switches are not in this patch.

## Related Issues

None.

---

## Testing

- Golden replies (six greedy prompts, `temperature: 0`, fixed seed) byte-identical to the stock image on every boot of every hold quoted here.
- Fused split-K: 1,008/1,008 calls byte-equal to the cluster kernel at rows 1-64 (bf16, fp32 and the strided-output
  form, six shapes, the output poisoned before every call; the lane's check also covered the depths the patch
  drops); an independent second check 765/765. A mutant that tells the fused form half the slices differs
  on every tile path (16, 32, 64): `fp8-fused-check` keeps that mutant built in and fails if it survives.
- Head items: 204/204 calls equal to 16-row items and to 1-row calls (rows 1-128, fp32 and bf16, three shapes); the
  item-count mutant is caught; `int4-check` passes.
- The patch here is the measured code with the campaign's experiment-only switches taken out (named above). The whole stack, `patches/0001`-`0020`, applies with `git apply` in order on TensorFold `db281878`, builds the image's engine (`zig build -Doptimize=fast fatbins install native` with nvcc in the build image), and passes `zig build test` (21/21 steps, 189/189 tests).
- `bash -n start.sh stop.sh scripts/*.sh`; `python3 -m py_compile tools/*.py`; shellcheck adds no finding.
- Memory: unchanged (kernel instantiations only).

Other PRs from me in this batch: #34 (the one-Spark draft stop default), #35 (`patches/0010`), #36 (`patches/0011` + `MTP_FP8`), and #[0012's PR] (n-gram host gather), #[0013's PR] (copy windows), #[0014's PR] (copy re-sync and ramp), #[0015's PR] (copies in shared rounds), #[0016's PR] (sequence pool and graphs), #[0017's PR] (batched draft draws), #[0019's PR] (decode read-out fusion), #[0020's PR] (draft stop lines). `patches/0012`-`0020` are one stack written in that order on top of `0001`-`0011`: each applies with `git apply` after the ones before it (several edit the same lines of `cuda_engine.zig`), so this PR's patch needs #35, #36 and #[0012's PR], #[0013's PR], #[0014's PR], #[0015's PR], #[0016's PR], #[0017's PR] merged first (logically it needs none of them). All twelve add CHANGELOG/README/CREDITS lines in the same places, the patch PRs each add a row to the same new patch table (as #35 and #36 do), and the setting PRs add `scripts/config.sh` lines after `TF_FLASHNEXT_PREFILL_TAIL`; whichever merges second, I rebase.

---

## Checklist:

- [x] I have read the README and `scripts/config.sh` and kept my changes consistent with them.
- [x] My pull request has a sound title and description (not something vague like `Update README.md`).
- [x] My change is reproducible and verified (script syntax check, `scripts/prepare.sh`, a launch, or a re-measurement).
- [x] A patch change keeps every reply byte-identical, and I said how I checked it.
- [x] I updated the README and/or `scripts/config.sh` if a setting, default, or measured number changed.
- [x] If my change affects memory, I checked the startup estimate still fits the budget at the default 5 x 262,144 int8 setting.
- [x] Defaults in `scripts/config.sh` still work out of the box; a new setting has a sane fallback like the existing ones.
