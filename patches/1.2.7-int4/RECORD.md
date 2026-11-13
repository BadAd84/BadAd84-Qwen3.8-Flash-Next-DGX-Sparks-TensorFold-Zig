# Provenance of this package

- **What it is:** an experimental series, not for upstream and not part of the accepted stack: TensorFold v1.2.7
  built to serve production's checkpoint, `azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound`, so the speed gap
  to production can be split into engine and checkpoint (`docs/INT4-PORT.md`).
- **Base it applies to:** `ashhart/TensorFold` v1.2.7, `93a2e93ecebff8aa52b88e58c5dd222516e69c5f`, with
  `patches/1.2.7` (0001 to 0015) applied first. `apply.sh` applies both, checks both `SHA256SUMS`, and refuses any
  other HEAD.
- **Where the text comes from:** ours, written with `git diff` against the 15-patch tree. Two files are lifted from
  this campaign's own `production` branch (our engine fork, the zmerge8 tree at `5c3e3e29`), named in their headers:
  `zig/kernels/cuda/fn_int4.cu` (unchanged, 499 lines) and `zig/src/families/flashnext/cuda_int4.zig` (its packers,
  launches and host tests; the plan types taken from `cuda.grouped`, the kernels loaded from a driver, the check-only
  helpers left out). The GPTQ `dynamic` rule matcher in `cuda_config.zig` is production's `regexMatch`.
- **Whether we edited it:** the lifted files as above; the rest is new.

## What 0016 carries

| piece | files |
|---|---|
| routing and shared widths at build time: `slots = 6` (top-5 and the shared slot), `shared_w = 1280` | `cuda_prompt_wt.zig` |
| the GPTQ export accepted beside ModelOpt: bits 4, group 128, sym, no act order, lm_head, its `dynamic` rules | `cuda_config.zig` |
| block-FP8 projections (fp32 `weight_scale_inv` per 128x128 block) on the lane matmul's FP8G mode; a projection whose trailing parts are BF16 (DeltaNet's `in_proj_b`/`a`, the indexer's `index_qk_proj`) keeps them as a BF16 tail run beside it and copied into place | `cuda_projection.zig`, `cuda_projection_load.zig`, `cuda_batch.zig`, `cuda_batch_state.zig` |
| the shared expert at its stored width (1280 in the main layers, 640 in the MTP layer) | `cuda_mixed_experts.zig`, `cuda_batch_side.zig`, `cuda_shared_split.zig`, `cuda_batch_state.zig` |
| GPTQ int4 routed experts and lm_head on production's `fn_int4.cu` | `cuda_int4.zig`, `cuda_int4_load.zig`, `cuda_moe_native.zig`, `cuda_batch_kernels.zig`, `cuda_prompt.zig`, `zig/build/cuda_kernels.zig`, `zig/src/cuda/kernels.zig` |
| the MTP layer as stored: BF16 experts re-coded to block FP8 at load (drafts only), the draft head from the int4 head's rows | `cuda_fp8_experts_load.zig`, `cuda_modelopt_experts.zig`, `cuda_mtp.zig`, `cuda_mtp_load.zig` |

## Checks

- `zig build compile-config-server -Dtarget=aarch64-linux-gnu` on the laptop (Zig 0.17.0) passes on the 16-patch
  tree.
- Box builds, boots and measurements are in `docs/INT4-PORT.md`.
