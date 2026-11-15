# Provenance of this package

- **What it is:** an experimental series, not for upstream and not part of the accepted stack: TensorFold `main` at
  `964174ea05879e6dde1de1198a3aae3ef8b46a3b` built to serve production's checkpoint,
  `azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound`, so the speed gap to production can be split into engine and
  checkpoint (`docs/INT4-PORT.md`). It is `patches/1.2.7-int4` re-seated.
- **Base it applies to:** upstream `main` `964174ea05879e6dde1de1198a3aae3ef8b46a3b`, with `patches/main-964174ea05`
  0001 to 0019 applied first. `apply.sh` applies exactly those, checks both `SHA256SUMS`, and refuses any other HEAD.
  The previous package applied to v1.2.7 with `patches/1.2.7` 0001 to 0015.
- **Where the text comes from:** ours, cut by `scripts/qwen38/zig/target/int4/mkpatch.sh` (the series' own files
  against the 15-patch tree on 1.2.7). Two files are lifted from this campaign's own `production` branch (our engine
  fork, the zmerge8 tree at `5c3e3e29`), named in their headers: `zig/kernels/cuda/fn_int4.cu` (unchanged) and
  `zig/src/families/flashnext/cuda_int4.zig` (its packers, launches and host tests). The GPTQ `dynamic` rule matcher
  in `cuda_config.zig` is production's `regexMatch`.
- **Whether we edited it:** two hunks needed a decision on the new base. Every other file applied with `--3way` as
  written; the added and removed lines of all other files are identical to `patches/1.2.7-int4`.
  1. **`cuda_fp8_experts_load.zig`** - the INT4 checkpoint's MTP layer stores BF16 experts, which this port re-codes
     to block FP8 at load. Upstream's v1.2.8 (#2892) replaced the same function's E4M3 branch with the shared
     `core.quant.fp8.read`/`widen` reader, so the re-seat keeps the BF16 recode in front of it and sends stored E4M3
     rows through the shared reader.
  2. **`cuda_batch_state.zig`** - the scratch estimate: the port prices the shared expert at its stored width
     (`wt.shared_w`) plus the BF16 tail it allocates (`tail_n`), which the re-seat keeps; upstream's extra slot row
     (`(pairs + slots)`) stays from the base.

## What 0016 carries

| piece | files |
|---|---|
| routing and shared widths at build time: `slots = 6` (top-5 and the shared slot), `shared_w = 1280` | `cuda_prompt_wt.zig` |
| the MoE sum at that width: five write-back calls that passed a fixed top-10 and 11 slots | `cuda_batch.zig`, `cuda_batch_hc.zig`, `cuda_prompt_step.zig` |
| the GPTQ export accepted beside ModelOpt: bits 4, group 128, sym, no act order, lm_head, its `dynamic` rules | `cuda_config.zig` |
| block-FP8 projections on the lane matmul's FP8G mode; a projection whose trailing parts are BF16 keeps them as a BF16 tail run beside it | `cuda_projection.zig`, `cuda_projection_load.zig`, `cuda_batch.zig`, `cuda_batch_state.zig` |
| the shared expert at its stored width (1280 in the main layers, 640 in the MTP layer) | `cuda_mixed_experts.zig`, `cuda_batch_side.zig`, `cuda_shared_split.zig`, `cuda_batch_state.zig` |
| GPTQ int4 routed experts and lm_head on production's `fn_int4.cu`; GPTQ experts take the native MoE loader | `cuda_int4.zig`, `cuda_int4_load.zig`, `cuda_moe_native.zig`, `cuda_batch_kernels.zig`, `cuda_prompt.zig`, `cuda_prompt_load.zig`, `zig/build/cuda_kernels.zig`, `zig/src/cuda/kernels.zig` |
| the MTP layer as stored: BF16 experts re-coded to block FP8 at load (drafts only), the draft head from the int4 head's rows | `cuda_fp8_experts_load.zig`, `cuda_modelopt_experts.zig`, `cuda_mtp.zig`, `cuda_mtp_load.zig` |
| the n-gram table from `ple-table/` beside the index; the GPTQ experts priced in the memory estimate | `cuda_ple.zig`, `cuda_rank_memory.zig` |

## Checks

- `patches/main-964174ea05-int4/apply.sh --check`: `the series and the INT4 patch apply on
  964174ea05879e6dde1de1198a3aae3ef8b46a3b in order (nothing written)`.
- `zig build compile-config-server` natively on spark6 (aarch64, Zig 0.17.0, the image builds' toolchain) on the
  series plus this patch: rc 0 in 235 s. The first cut of this patch (commit `b20ef9b`) was wrong: it was taken with an
  unrestricted `git diff --cached` against the series stage, so besides the port it reverted every other series path
  and deleted the series' new files, and only `apply.sh --check` passed. It is regenerated restricted to the port's
  26 paths (1,949 lines); their added and removed lines are identical to `patches/1.2.7-int4` except
  `cuda_fp8_experts_load.zig`, the resolution above.
- **NOT built into an image or served on this base.** The receipts in `docs/INT4-PORT.md` (boot, golden 6/6 against
  production's own serve, the speed table at 1, 2, 4, 6 and 8 streams, the kernel-log comparison) are the 1.2.7
  package's, image `int4d`. This re-seat is the text only; a boot and a golden comparison on this base are the next
  step for whoever serves it.
- `scripts/check-patch-packages.sh`: `RECORD.md`, `SHA256SUMS` and the hashes.
