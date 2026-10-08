# Upstream PR #35: patches/0010 argmax and logsumexp rows on 1024 threads (posted 2026-10-09)

Target: MiaAI-Lab/Qwen3.8-Flash-Next-Single-DGX-Spark-TensorFold, base `364f21a` (release 1.0.0).
Evidence: `scripts/qwen38/zig/` A/B rows on spark6 (2026-10-08: arms `ctl` and `o1`), `docs/ZIG-SPEED-CAMPAIGN-2026-10.md`.

---

**Title:** patches/0010: argmax and logsumexp row maxima on 1024 threads (replies byte-identical)

**Body:**

## Description and Motivation

`patches/0010-flash-next-argmax-lse-rows.patch` changes two launches in the Zig engine:

- `Torch.argmax` (the greedy pick over a vocabulary row, `tf_argmax_rows_i32_kernel`) launches 1024 threads a row
  instead of 256. The kernel is already `__launch_bounds__(1024)` and reduces through a 32-warp shared table.
- `tf_fn_lse_max_kernel` (the row maxima before logsumexp) takes up to 1024 threads (its shared table grows from 256 to
  1024 floats) with four loads in flight a thread, and launches with 1024.

Each launch is one block a row. With 256 threads a block reads a 248,320-column bf16 row at about 8 GB/s: the profile
(nsys, one stream) showed `tf_argmax_rows_i32_kernel` at ~60 us a call and `tf_fn_lse_max_kernel` at ~49 us. At four
streams the draft sampling (`mtp.draft_sample` in `TF_FLASHNEXT_PROFILE=1`) took ~1.5 ms a round.

Why the results do not change: the argmax pick is a total order (the first maximum, a NaN first, `argmax_order.h`), and
a maximum does not depend on which thread reads which column. The sums after the maxima (`tf_fn_lse_sum_kernel`) are
not touched, so logsumexp keeps ATen's reduction order.

Measured on one DGX Spark through the recipe's own server, defaults otherwise. Per-request decode tok/s, greedy,
thinking off, 512-token replies; the control is the same source rebuilt without the patch, so the build adds nothing:

| | control | 0010 |
| --- | ---: | ---: |
| code, 1 / 2 / 4 clients | 104.7 / 76.1 / 52.2 | 105.3 / 76.8 / 54.1 |
| prose, 1 / 2 / 4 clients | 62.2 / 50.8 / 37.2 | 62.4 / 51.1 / 37.4 |

Small (+0.3 to +1% where the arms are steady; code at four clients varies between boots), but every cell moves the same
way and it costs two constants.

## Related Issues

None.

---

## Testing

- Golden replies (six greedy prompts, `temperature: 0`, fixed seed) byte-identical to the stock image in both boots.
- A standalone CUDA check built from the engine's kernel sources (nvcc in the image): the argmax at 256 and 1024
  threads, and the shipped `tf_fn_lse_max_kernel` at 256 against the patched one at 1024, on 120 rows (ties at the
  first and last column, a maximum in the unrolled loop's tail, NaN, +-inf, +-0, widths 1, 7, 4,097, 79,591 and
  248,320): 0 differences (a NaN row gives NaN in both; every other maximum equal bit for bit). Three mutants of the new loop (no tail loop, three of four loads, a wrong loop bound) each
  make it fail.
- `tools/exact.py`: PASS (6 drafted replies equal the `"draft": false` ones, 522 drafts accepted; 6 concurrent replies equal the one-at-a-time ones), on the server built with 0010 and 0011.
- The image built by `scripts/prepare.sh` with the patch: a clean clone of `main` with 0010 and 0011 in `patches/` built its image locally with `PULL=0 scripts/prepare.sh` (both patches applied by the Dockerfile's `git apply`; the kernel set step: 320 kernels, 101 cubins equal to the capture's), then `start.sh` served it; `tools/toolcheck.py` 3/3 and `tools/needle.py` (199,730-token prompt) passed too.
- The A/B: two fresh boots an arm, one pass of the decode matrix a boot, arms alternating, the order reversed the
  second cycle.
- Memory: unchanged (launch widths only).

Other PRs from me in this batch: #34 (the one-Spark draft stop default) and #36 (the MTP
layer on block FP8, `patches/0011`). All three add CHANGELOG/README/CREDITS lines in the same places, and this PR and
#36 each add a row to the same new patch table; whichever merges second, I rebase.

---

## Checklist:

- [x] I have read the README and `scripts/config.sh` and kept my changes consistent with them.
- [x] My pull request has a sound title and description (not something vague like `Update README.md`).
- [x] My change is reproducible and verified (script syntax check, `scripts/prepare.sh`, a launch, or a re-measurement).
- [x] A patch change keeps every reply byte-identical, and I said how I checked it.
- [x] I updated the README and/or `scripts/config.sh` if a setting, default, or measured number changed.
- [x] If my change affects memory, I checked the startup estimate still fits the budget at the default 5 x 262,144 int8 setting.
- [x] Defaults in `scripts/config.sh` still work out of the box; a new setting has a sane fallback like the existing ones.
