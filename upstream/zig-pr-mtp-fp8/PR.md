# Upstream PR #36: patches/0011 + MTP_FP8 (posted 2026-10-09)

Target: MiaAI-Lab/Qwen3.8-Flash-Next-Single-DGX-Spark-TensorFold, base `364f21a` (release 1.0.0).
Evidence: `scripts/qwen38/zig/` A/B rows on spark6 (2026-10-08), `docs/ZIG-SPEED-CAMPAIGN-2026-10.md`.

---

**Title:** patches/0011 + MTP_FP8: the MTP draft layer on block FP8 (code decode +4 to +5%, replies unchanged)

**Body:**

## Description and Motivation

INT4-AutoRound keeps the MTP layer (`mtp.layers.0`, the mixer) in bf16. Every draft step reads its attention
q/k/v/o and its three hyper-connection down/up pairs, ~139 MB, at the bf16 roofline: in `TF_FLASHNEXT_PROFILE=1` the
MTP head was ~12% of a one-stream round and ~15% at four streams, and its attention projection alone ran at ~213 GB/s
(nsys). This PR drafts from a block-FP8 copy of those linears, ~70 MB a step.

- `patches/0011-flash-next-mtp-fp8-overlay.patch`: `TF_FLASHNEXT_MTP_FP8=DIR` opens a second overlay directory, read
  before the checkpoint's `fast-fp8/` (that one repeats the MTP layer's bf16 tensors, so the first overlay holding a
  name wins). The MTP layer takes `attention8` when its `q_proj` is FP8 there; its hyper-connections already take the
  FP8 path when `input_mix_weight_down` is. The forward code is unchanged: the main layers' FP8 paths run.
- `tools/mtp_fp8.py`: writes the overlay. Each linear becomes e4m3 codes plus fp32 `weight_scale_inv` per 128x128
  block (scale = block amax / 448), the checkpoint's own block-FP8 format. Relative error ~2.6% a matrix.
- `scripts/prepare.sh` runs it once in the image into `$HF_CACHE/tensorfold-mtp-fp8/<model>/<revision>/` (as the
  user, no network), `start.sh` passes `TF_FLASHNEXT_MTP_FP8` when `MTP_FP8=1` and `DRAFTS=1`, and `prepared_state`
  includes the overlay, so a missing one re-runs `prepare.sh`. `MTP_FP8=0` drafts from the bf16 layer as before.

Why replies do not change: the MTP head only proposes drafts; the target model verifies every one and keeps only
what it would have produced. Only acceptance could move, and it did not measurably (decode rounds a pass within boot
noise of the bf16 arm).

Measured on one DGX Spark through the recipe's own server, defaults otherwise. Per-request decode tok/s, greedy,
thinking off, 512-token replies, medians of two boots an arm; the control is the same source rebuilt without the
patch, so the build adds nothing:

| | control | 0011 + overlay | change |
| --- | ---: | ---: | ---: |
| code, 1 / 2 / 4 clients | 104.8 / 75.9 / 54.9 | 109.5 / 79.0 / 57.6 | +4.5 / +4.1 / +4.9% |
| prose, 1 / 2 / 4 clients | 62.0 / 50.7 / 37.3 | 63.3 / 51.5 / 38.0 | +2.1 / +1.6 / +1.9% |

Code gains more because its chains run deeper (more draft steps a round, each reading the MTP layer).

## Related Issues

None.

---

## Testing

- Golden replies (six greedy prompts, `temperature: 0`, fixed seed) byte-identical to the stock image in every boot.
- `tools/exact.py`: PASS (6 drafted replies equal the `"draft": false` ones, 522 drafts accepted; 6 concurrent replies equal the one-at-a-time ones), on the server built with 0010 and 0011.
- `scripts/prepare.sh` from a clean state: a clean clone of `main` with 0010 and 0011 in `patches/` built its image locally with `PULL=0 scripts/prepare.sh` (both patches applied by the Dockerfile's `git apply`; the kernel set step: 320 kernels, 101 cubins equal to the capture's), then `start.sh` served it; `tools/toolcheck.py` 3/3 and `tools/needle.py` (199,730-token prompt) passed too. `prepare.sh` wrote the overlay (`10 MTP linears on block FP8 in ...`) and the engine log names it (`overlay .../tensorfold-mtp-fp8/.../mtp-fp8.safetensors`); `docker logs qwen38-flash-next-tf 2>&1 | grep overlay`
  names the file.
- With `TF_FLASHNEXT_INT4AR_FAST=1` as well (both overlays): boots and serves (before the read order was fixed, the
  `fast-fp8/` bf16 copy won and the load stopped on a dtype mismatch).
- `bash -n start.sh stop.sh scripts/*.sh`; `python3 -m py_compile tools/*.py`; shellcheck adds no finding.
- Memory: the MTP layer's device buffers shrink by ~70 MB; with the defaults (8 streams, 262,144, FP8 KV, vision) the engine sized sequence memory at 33.83 GiB with 10 GiB kept free.

Other PRs from me in this batch: #34 (the one-Spark draft stop default) and #35
(`patches/0010`). All three add CHANGELOG/README/CREDITS lines in the same places, and this PR and #35 each
add a row to the same new patch table; whichever merges second, I rebase.

---

## Checklist:

- [x] I have read the README and `scripts/config.sh` and kept my changes consistent with them.
- [x] My pull request has a sound title and description (not something vague like `Update README.md`).
- [x] My change is reproducible and verified (script syntax check, `scripts/prepare.sh`, a launch, or a re-measurement).
- [x] A patch change keeps every reply byte-identical, and I said how I checked it.
- [x] I updated the README and/or `scripts/config.sh` if a setting, default, or measured number changed.
- [x] If my change affects memory, I checked the startup estimate still fits the budget at the default 5 x 262,144 int8 setting.
- [x] Defaults in `scripts/config.sh` still work out of the box; a new setting has a sane fallback like the existing ones.
