# Build receipt: a clean upstream-main image for issue #4803

This receipt covers the build half of the request only. The measurement half (fresh servers, arms, hashes,
counters, cached control) is in this folder's `RESULT.md` and `tables.md` once the GPU window has run.

## What was built

| | |
| --- | --- |
| upstream repository | `https://github.com/ashhart/TensorFold` |
| commit | `9a38b1f7b33863507cdea47e88207d8b3bea3f22` (main's tip, fetched 2026-11-24) |
| tree | `6e00d270fec84cb6decb784e148712d4d27b5f03` |
| source form | `git archive --format=tar.gz --prefix=src/ 9a38b1f7b`, 44,952,663 bytes, sha256 `7b91b872d4d0e78d4ecc27be8b5c947477225da607cece56a8e911e9abad5297` |
| patch stack applied | NONE. The Dockerfile copies the archive and runs Zig; no `git apply`, no `patches/`, no OTS environment |
| Dockerfile | `work/SharedDraftsMain/Dockerfile`, build context `~/work/SharedDraftsMain/build/` on spark6 |
| build host | spark6 (DGX Spark, GB10, driver 580.178.04), docker build is CPU only |
| Zig | 0.17.0 (`.zig-version`), archive sha256 `9e8d11661d4ae3bd57702a3832781e23ad151dde5798e16a5ccd503f65234ff8`, checked with `sha256sum -c` inside the build |
| nvcc | CUDA 13.3, V13.3.73, `Build cuda_13.3.r13.3/compiler.38244171_0`, from `nvcr.io/nvidia/pytorch:26.07-py3` |
| build command | `zig build -Dnvcc=/usr/local/cuda/bin/nvcc -Doptimize=fast --prefix /opt/tensorfold -j20 fatbins install native` (main's own receipt command, `docs/receipts/flashnext-prompt-chunk3072/README.md:9`) |
| image | `tensorfold-qwen38:main-9a38b1f7b` = `sha256:2533c8a882610a69e376d1ea3d89d4ac03add9b1e8b642de6e770fc0ea1cc7e6`, 24,965,638,043 bytes, created 2026-11-24T18:57:08Z |
| binary | `/opt/tensorfold/native/bin/tensorfold-native`, sha256 `8e04b448aac1bccba6452088278d71328aae8b2813eb1e45fe3228c4ec10e933`, `tensorfold-native 1.3.4` |
| build log | spark6 `~/work/SharedDraftsMain/build/build.log` (wall 636 s in the build step), copied by the window to `out/phase0/build.log` |

## Exact build-log lines (spark6 `~/work/SharedDraftsMain/build/build.log`)

```text
#10 0.131 SOURCE_SHA 9a38b1f7b33863507cdea47e88207d8b3bea3f22
#10 0.133 TREE c462d5da8cfc31bd7d39f3f34de008a73059595e01c35cba04ce129ec78f7753 changelog-sha
#10 0.151 ZIG 0.17.0
#10 0.151 ZIG_ARCHIVE_SHA256 9e8d11661d4ae3bd57702a3832781e23ad151dde5798e16a5ccd503f65234ff8
#10 0.154 NVCC Cuda compilation tools, release 13.3, V13.3.73 Build cuda_13.3.r13.3/compiler.38244171_0
#11 636.0 BUILD OK 8e04b448aac1bccba6452088278d71328aae8b2813eb1e45fe3228c4ec10e933  /opt/tensorfold/native/bin/tensorfold-native
BUILD_RC=0
IMAGE_ID sha256:2533c8a882610a69e376d1ea3d89d4ac03add9b1e8b642de6e770fc0ea1cc7e6 CREATED 2026-11-24T18:57:08.56690285Z SIZE 24965638043
tensorfold-native 1.3.4
BUILD_DONE 2026-11-24T18:57:09+00:00
```

`SOURCE_TARBALL_SHA256 7b91b872d4d0e78d4ecc27be8b5c947477225da607cece56a8e911e9abad5297` is recorded on the
same log's fifth line (line 4 of the header block printed by `build.sh`).

## The lever is in the served binary, and only the one

The image's binary carries `TF_FLASHNEXT_SHARED_DRAFTS` among its setting names (probe on the image, read-only:
`grep -a -o -E '(TF|TENSORFOLD)_[A-Z0-9_]+' /opt/tensorfold/native/bin/tensorfold-native | sort -u`, 415 names,
`TF_FLASHNEXT_SHARED_DRAFTS` exact-line present; also `TF_FLASHNEXT_CONFIDENCE` and `TF_FLASHNEXT_GREEDY_WIDE`,
which are left at their defaults on both arms).

The serve argument list was parsed by the built binary on the host before the window (no GPU needed):
`serve /nonexistent-model --name Qwen3.8-Flash-Next --host 0.0.0.0 --port 8888 --context 32768 --parallel 8
--prompt-cache-gib 3 --temperature 0` returned `tensorfold: /nonexistent-model is neither a directory nor a Hugging
Face repo id (owner/name)` and not an unknown-argument error, so every flag is accepted by this build.

## Checkpoint identity (main's own ModelOpt checkpoint for one GB10)

`nvidia/Qwen3.8-Flash-Next-FP4-Local` at revision `b9ce18a6887e18c089fdea8509a33e63429a3300`:

- HF cache ref on spark6: `~/.cache/huggingface/hub/models--nvidia--Qwen3.8-Flash-Next-FP4-Local/refs/main` =
  `b9ce18a6887e18c089fdea8509a33e63429a3300`.
- `config.json` sha256 `b50dbc52a0c83b0cd2a44a372c1fb6b5e0e6827d22f2611c97d4d030f92f6b28`,
  `model_type` `qwen4_exp`, `quantization_config.quant_method` `modelopt`, `quant_algo` `MIXED_PRECISION`,
  routed experts `NVFP4` group 16 with `weight_scale_encoding: csf`.
- `model.safetensors.index.json` sha256 `5fa166bbb1cf25adda455117563efa72a2072272001f459eedece131ffc913e1`;
  375,487 tensors in 21 files.
- 96 GiB on disk. Served from the snapshot path with the whole HF model directory mounted read-only at
  `/models/qwen38` (the shard symlinks resolve inside it).

Why this checkpoint and not the dev stack's: main's docs serve it on one GB10
(`docs/recipes/flash-next-cuda.md:236-241`, `docs/hermes-agent.md:51`), and main's own receipts pin exactly this
revision (`docs/receipts/flashnext-draft-head/README.md:19`). The dev stack's
`azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound` is not used: main's loader does not serve it, and the
request says not to use it. The other checkpoint main documents for CUDA, `TensorFold/Qwen3.8-Flash-Next-MLX-4bit-MTP`
(`docs/recipes/flash-next-cuda.md:86-87`), is a 105.5 GiB download (`docs/supported-models.md:36`) and spark6 had
116 GiB free before the build, so it cannot be fetched without deleting another lane's checkpoint.
