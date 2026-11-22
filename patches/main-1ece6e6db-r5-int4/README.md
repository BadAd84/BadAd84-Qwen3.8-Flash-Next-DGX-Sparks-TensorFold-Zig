# TensorFold main `1ece6e6db` + r5 + INT4-AutoRound (experimental, not the accepted series)

Applied on top of `patches/main-1ece6e6db-r5` (0001 to 0020) on a pristine checkout of upstream main at
`1ece6e6dbbc073582d50738ce8e73e3c3261a73b`, so the engine serves production's checkpoint,
`azampatti/Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound` (5 routed experts a token, GPTQ int4 in groups of 128 with zero
point 8, a 1,280-wide shared expert). An image of this series serves that checkpoint only: the routing width is a
build-time constant (`slots = 6`, `shared_w = 1280` in `cuda_prompt_wt.zig`) and the config check refuses the FP4
checkpoint by name (`num_experts_per_tok`).

    ./apply.sh --check TREE     # the series and both INT4 patches apply, nothing written
    ./apply.sh TREE             # apply them

| patch | what it carries |
|---|---|
| `0021-int4-autoround.patch` | the INT4 port re-seated onto r5 (31 paths, +1,488 / -44): its GPTQ admission reads through main's `core.quant.gptq` (#3611), its own tests are collected, `zig build -Dfixed-cpu test-flashnext-int4-host` runs them, and its four settings read through `platform/environment.zig` |
| `0022-int4-serving-pins.patch` | 17 rows of `zig/tests/fixtures/gradient-serving.tsv` re-hashed for the pinned files 0021 changes (hash column only, as r5's 0020) |

The numbers sort after r5's 0020, so one directory holding r5's twenty patches and these two applies in glob order,
which is how `scripts/qwen38/zig/target/build_patches.sh` applies a directory.

This package exists because the r5 series fixes 0008's shared-direct write-back (r4) and splits the
writeback-with-normalize family into `zig/kernels/cuda/flashnext_hc_norm.cuh` (r5); the r2-int4 package cannot be
stacked on r5 as it stands, because its `cuda_batch_hc.zig` hunk rewrites the line r4 fixed. `RECORD.md` has the
per-file disposition and the one resolution; `CHANGES.md` names every difference from the r2-int4 package.

**STATUS: host gates only, and every one of them green on the re-cut patches.** `RECORD.md` ("Checks") has the table,
each gate with the exact line it is judged on, and `work/R5Int4Fix/RESULT.md` holds that run and its log. Two numbers
are worth stating here because they were the first cut's failures: `cuda_common_check` reads `55 local copies, 0
violations` (was `61 local copies, 6 violations`) and the lean pair reads `230 problems, 230 on the base, 0 new` (was
60 new). The old and the new `fn_int4.cu` compile to one fatbin (`8080835b`, 1,132,920 bytes), the same image the first
cut's own `fatbins install native` produced. Not built into an image or served on this base. The last served receipt of
this port is the previous re-seat (`patches/main-964174ea05-int4`, image `pvz-int4`, window of 2026-11-19,
`docs/PROD-VS-ZIG-2026-11-18.md`): golden 6/6 identical to production's own serve at 1, 2, 4, 6 and 8 streams, decode
0.94 / 0.97 of production at one stream and 0.82 / 0.87 at eight (prose / code). Those numbers are not this package's
until a window repeats them on this base.

## Serve settings for this checkpoint (measured 2026-11-14 on 1.2.7, image `int4d`; not yet measured on this base)

The recipe's own environment (`CHECKPOINT=int4 VISION=0 KV_DTYPE=fp8`) plus:

    TF_FLASHNEXT_MTP_WEIGHTS=mxfp8      # the drafter's BF16 linears on MXFP8 (r5 0014)
    TF_FLASHNEXT_CONFIDENCE=-0.15       # draft while the drafts' probability product stays at 0.15 or more
    TF_FLASHNEXT_DRAFTS_GREEDY=15       # a greedy chain's depth at most
    TF_FLASHNEXT_SHARED_DRAFTS=0        # shared rounds keep that rule instead of 0.6 a draft
    TF_FLASHNEXT_GREEDY_WIDE=8          # 6 and 8 streams keep the depth
    TF_FLASHNEXT_KV_PAGES=4096          # 6 and 8 streams at a 262,144-token window with fp8 KV (r5 0015)

Production's drafter overlay, `TF_FLASHNEXT_MTP_FP8` (its launcher passes
`/root/.cache/huggingface/tensorfold-mtp-fp8/azampatti--Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound/1464274120d36a4d8fcaa934552334a7d83ce0fd`),
has no reader in this engine (no `MTP_FP8` anywhere in the applied tree), so setting it changes nothing here; the
drafter's 8-bit form in this engine is `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8`. The block belongs in
`scripts/qwen38/zig/target/env/dev.env` only after it is measured on this engine; `prod.env` stays production's.

## What this package does not do (the gap between "dev serves INT4" and "upstream serves INT4")

The maintainer's approved order on issue #3368 has six steps; this package is a dev route, not those steps. This table
is the r2-int4 package's record of the upstream state at 2026-11-21, carried unchanged; re-read it before quoting it
as current:

| step | upstream state (2026-11-21) | in this package |
|---|---|---|
| 1. routing and shared widths | PR #3523 open | **only as build-time constants** (`slots = 6`, `shared_w = 1280`, the five write-backs on `slots - 1, slots`): one image serves INT4 and refuses FP4; no runtime widths |
| 2. block-FP8 projections and the shared expert | unsubmitted branch `work/PrBlockFp8` (head `126b95f6`) | the port's own loader arm (`cuda_projection.zig`, `cuda_projection_load.zig`), with no loader host test and no device check against a float64 reference |
| 3. the core GPTQ reader | **merged** (#3611: `51a108030` the reader, `fe3622b72`, `08540d797`; changelog `0f8e35a1a`) | used for admission; the loader still reads the tensors through the port's own `cuda_int4.Source`, not `gptq.read` |
| 4. the int4 kernel | PR #4183 open, not called by any family | production's lifted `fn_int4.cu` and `cuda_int4.zig` (not #4183's `zig/src/cuda/int4.zig`), with #4183's common helpers and its four settings read through `platform/environment.zig`; no contract records, no planted controls, no float64 device test |
| 5. admission and loading as stored | not started | admits and loads the checkpoint, but: no lane name, `--tp 2` refused only by a bare `error.UnsupportedQuantization` (`cuda_mixed_experts.zig`) and drafts not refused, the int4 module loads at every boot (`cuda_batch_kernels.zig`), `cuda_ple.zig` at 636 lines over 600 (a base finding, present on r5's own tree), no fidelity cells against a float64 reference |
| 6. the MTP layer as stored | not started | **not as stored**: the MTP layer's BF16 experts are re-coded to block FP8 at load (e4m3, lossy; drafts only, so replies stay exact) |
