# TensorFold main `1ece6e6db` patch series (our levers)

The TensorFold tree stays pristine at upstream `main` `1ece6e6dbbc073582d50738ce8e73e3c3261a73b`
(2026-11-20 13:01 UTC, "changelog: #4202 under Unreleased") and every change we own is one numbered patch here, one
lever a patch, applied in filename order. Each patch builds on the ones before it and on nothing after it.

    ./apply.sh --check TREE     # the whole series applies, nothing written
    ./apply.sh TREE             # apply it

`RECORD.md` has the provenance, the per-patch verdict on this base and every resolution the re-seat needed;
`RETIRED.md` is the hunk-level record of the two levers upstream has absorbed. This is `patches/main-964174ea05`
re-seated: **no patch is wholly retired**, because upstream has absorbed only parts of two of them (0005's 3,072-row
chunk, 0008's fused read-out).

## The levers, one a patch

| patch | lever | switch (recipe default) | upstream path |
|---|---|---|---|
| 0001 | a lone stream's copy window grows to the boot self-check's largest row-exact width (48 rows on GB10 against the 32-row base); a verify window carrying a pending-row log takes the row-by-row DeltaNet | none (`TF_FLASHNEXT_WINDOW_CHECK=0` skips the boot check) | PR #4075 `flashnext-copy-window-up`, open |
| 0002 | copy re-sync past an edit, the copy ramp and the miss rules | lane core config | none |
| 0003 | `--kv-cache fp8` for Flash Next: e4m3 keys and values with a power-of-two scale a row, 1,056 bytes a position and layer instead of 2,048 | `KV_DTYPE=fp8` | none; the ground is upstream issue #4107 (another contributor's fp8 KV), which we do not submit to |
| 0004 | the n-gram table's rows through a direct-mapped row cache with up to 128 parked readers, a drafted token's rows asked for while the head drafts, a prompt chunk's rows asked for while the chunk before it runs, one gather a shared pass | `GATHER_READ=pread`, `DRAFT_AHEAD=1`, `GATHER_EARLY=1` (all on) | PR #4009 `flashnext-gather-early-up` (the gather-early part only), open |
| 0005 | prompt passes drain less on one rank; MXFP8 projections of N columns or more take the relaxed 128 x 128 prompt tile | `PROMPT_SYNC` off (the drain stays off), `PROMPT_MX128` (0: off) | none: the 3,072-row chunk half was absorbed by PR #3726 (merged, `e172bcc29`), the MX128 tile is in no PR |
| 0006 | the MX128 tile in two stages, two blocks an SM | `PROMPT_GEMM2=1` (on, acts only with MX128) | none |
| 0007 | the draft head's rows 4-bit by default | `DRAFT_HEAD` (`affine4`; `bf16` restores) | PR #3477 `flashnext-draft-head-affine4`, open |
| 0008 | a prompt pass's MoE write-back reads the shared expert's fp32 output in place, and a prompt chunk's MTP head pass takes at most `TF_FLASHNEXT_HEAD_PIECE` rows | `PROMPT_SHARED_DIRECT=1`, `HEAD_PIECE` (both on) | none: the fused read-out half was absorbed by PR #3413 (`12233bee5`, branch `flashnext-readout-fuse-up`), the other two halves are in no PR |
| 0009 | hyper-connection read-outs from a lossless 12-bit copy | `HC_Q12` (off) | none |
| 0010 | a shared round priced from the environment | `ROUND_MS`, `DRAFT_ROW_MS` (unset) | none; upstream's own measured pricing is PR #3728 and #3755 (both merged) |
| 0011 | vision tower linears decoded at load, image rows up to 16,384 | none (not a speed lever) | PR #3727 `flashnext-vision-modelopt-up`, open (the decode-at-load part) |
| 0012 | the row cache can read through the page cache | `GATHER_DIRECT` (1) | none |
| 0013 | the window self-check can log its first differing row | `CHECK_LOG` (off) | none |
| 0014 | the drafter's BF16 linears re-coded to MXFP8 at load | `MTP_WEIGHTS` (`bf16`; `mxfp8` on) | PR #3218 `flashnext-mtp-weights`, open |
| 0015 | fp8 KV on every served stream and in the shared page pool | `KV_PAGES` with `KV_DTYPE=fp8` | none (issue #4107's ground, not submitted) |
| 0016 | 0009's 12-bit read-out tile loads its blocks two groups ahead | with `HC_Q12=1` | none |
| 0017 | lane calls split over K on a cluster run on the fused form | `FUSED_SPLIT=1` (off) | PR #3475 `flashnext-fused-split-up`, open |
| 0018 | the read-out's reduce and mix inside its products | `READOUT_FUSE=1` (off) | none |
| 0019 | the fused split's kernel contract | none (a `tf-cuda-test` contract) | PR #3475 carries the contract in its own shape |
| 0020 | the serving pins: every row of `zig/tests/fixtures/gradient-serving.tsv` the series' own edits move (27 rows) | none (package plumbing) | not upstream: the fixture is this package's own contract |

PR #3523 (`flashnext-config-widths`, top-k and shared width) and #4183 (`cuda-int4-kernel-m`) carry levers that are
not patches of this series: #3523 is config widths, #4183 belongs to the experimental INT4 series
(`patches/main-964174ea05-int4`). GPTQ (PR #3611, merged `0f8e35a1a`) touches `core/quant`, which no patch here edits.

## Recommended launcher block (FP4) (measured on 1.2.7, 2026-11-14)

    TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_FUSED_SPLIT=1 TF_FLASHNEXT_READOUT_FUSE=1
    TF_FLASHNEXT_SHARED_DRAFTS=0 TF_FLASHNEXT_GREEDY_WIDE=8
    # at 6 and 8 streams with a 262,144 window also TF_FLASHNEXT_KV_PAGES=4096; TF_FLASHNEXT_HC_Q12 stays unset
    # recipe: IMAGE=tensorfold-qwen38:<tag> CHECKPOINT=nvfp4 VISION=0 TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=fp8 \
    #         PARALLEL=<streams> CONTEXT=262144 HOST=127.0.0.1 MEM_CHECK=0 PREPARE=0 ./start.sh restart

The block is the 1.2.7 measurement's; since then #3413 landed the fused read-out upstream under
`TF_FLASHNEXT_READOUT_FUSED` (off by default), so the same reading is available from main alone with
`TF_FLASHNEXT_READOUT_FUSED=1` added. `HC_Q12` is the one switch the block leaves out: its 1.02 GiB of 12-bit copies
is a capacity cost (14 pool pages, 57,344 positions, fewer at 6 and 8 streams) and it showed no served gain outside
the cell noise at 1 to 4 streams.

## Measured on the old base (`964174ea05`, 2026-11-15, spark6)

The numbers in `patches/main-964174ea05/README.md` are the last full A/B of this series (one decode pass of 512-token
prose and code replies a cell, one fresh boot a cell, golden 6/6 identical in every cell): +24.0%/+21.3% at one
stream, +12.5%/+19.8% at two and +9.8%/+14.4% at four against upstream main alone at bf16 KV, and within 1.3% of the
1.2.7 package at fp8 KV from 1 to 8 streams with identical counters. **They are not re-measured on this base**: this
re-seat is host-only (no GPU window), so the numbers to trust here are the gates below and the doc's per-patch
verdicts, and the first GPU window on this base must reproduce the old table before any cell is quoted.

## Gates on this base (Paperclip, Zig 0.17.0, 2026-11-20)

Host, x86-64, on a `git archive` of `1ece6e6db` with the series applied:

| gate | result |
|---|---|
| `zig fmt --check build.zig zig` | rc 0 on the final series (Zig 0.17.0 formatter) |
| `zig build test-environment-host` | rc 0 on Paperclip for the series before the two compile fixes; the run on the final series was queued on the host lock |
| `zig build -Dfixed-cpu test-gradient-serving test-qwen-serving-host` | rc 0 on the same pre-fix series, and `pincheck.py` reads `files 169 failing 0` on the final tree |
| `zig build -Dfixed-cpu test-kernel-contract` | rc 0 on the final series (259/259 compiled tests pass; the run's `N/A ... not served there` lines are the chip map's own) |
| `zig build compile-config-server -Dtarget=aarch64-linux-gnu` and `compile-cuda-tests -Dtarget=aarch64-linux-gnu` (cross-compiles) | **not observed**: both were re-launched detached behind `~/work/host.lock`, which another lane's `box/runall.sh` held continuously through this session. The one run that did start (on the pre-fix series) failed only on the two defects the doc records, both fixed; the native kernel-contract gate compiles the whole engine here |

Not run here: anything with a GPU (golden replies, decode timing, `tf-cuda-test` execution). The next Spark window
runs those on this base.
