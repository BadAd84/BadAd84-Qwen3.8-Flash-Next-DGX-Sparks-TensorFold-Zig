# TensorFold main `964174ea05` patch series (our levers)

The TensorFold tree stays pristine at upstream `main` `964174ea05879e6dde1de1198a3aae3ef8b46a3b`
(`v1.2.9-33-g964174ea05`, 2026-11-15 12:43 UTC) and every change we own is one numbered patch here, one lever a
patch, applied in filename order. Each patch builds on the ones before it and on nothing after it.

    ./apply.sh --check TREE     # the whole series applies, nothing written
    ./apply.sh TREE             # apply it
    build_patches.sh TAG git://192.168.99.16/up-pr/tf 964174ea05879e6dde1de1198a3aae3ef8b46a3b <this directory>

`RECORD.md` has the provenance, the per-patch verdict on this base and the resolutions the re-seat needed. This is
`patches/1.2.7` re-seated: **no patch is retired, because upstream has absorbed none of them** (evidence per patch in
`RECORD.md`). The numbers below are the 1.2.7 series' own, measured as `patches/1.2.7/README.md` records them; the
row for this base is in `docs/RESTACK-main-964174ea05.md`.

## The levers, one a patch

| patch | lever | switch (recipe default) |
|---|---|---|
| 0001 | a lone stream's copy window grows to the boot self-check's largest row-exact width (48 rows on GB10 against the 32-row base); a verify window carrying a pending-row log takes the row-by-row DeltaNet | none (`TF_FLASHNEXT_WINDOW_CHECK=0` skips the boot check) |
| 0002 | copy re-sync past an edit, the copy ramp and the miss rules | lane core config |
| 0003 | `--kv-cache fp8` for Flash Next: e4m3 keys and values with a power-of-two scale a row, 1,056 bytes a position and layer instead of 2,048 | `KV_DTYPE=fp8` |
| 0004 | the n-gram table's rows through a direct-mapped row cache with up to 128 parked readers, a drafted token's rows asked for while the head drafts, a prompt chunk's rows asked for while the chunk before it runs, one gather a shared pass | `GATHER_READ=pread`, `DRAFT_AHEAD=1`, `GATHER_EARLY=1` (all on) |
| 0005 | prompt passes drain less, 3,072-row chunks, the relaxed MX128 prompt tile | `PROMPT_MX128` (0: off) |
| 0006 | the MX128 tile in two stages, two blocks an SM | `PROMPT_GEMM2=1` (on, acts only with MX128) |
| 0007 | the draft head's rows 4-bit by default | `DRAFT_HEAD` (`affine4`; `bf16` restores) |
| 0008 | prompt passes' hyper-connection read-out as fused kernels, the shared expert read in place, wider head pieces | `PROMPT_HC2=1`, `PROMPT_SHARED_DIRECT=1`, `HEAD_PIECE=1536` (all on) |
| 0009 | hyper-connection read-outs from a lossless 12-bit copy | `HC_Q12` (off) |
| 0010 | a shared round priced from the environment | `ROUND_MS`, `DRAFT_ROW_MS` (unset) |
| 0011 | vision tower linears decoded at load, image rows up to 16,384 | none (not a speed lever) |
| 0012 | the row cache can read through the page cache | `GATHER_DIRECT` (1) |
| 0013 | the window self-check can log its first differing row | `CHECK_LOG` (off) |
| 0014 | the drafter's BF16 linears re-coded to MXFP8 at load | `MTP_WEIGHTS` (`bf16`; `mxfp8` on) |
| 0015 | fp8 KV on every served stream and in the shared page pool | `KV_PAGES` with `KV_DTYPE=fp8` |
| 0016 | 0009's 12-bit read-out tile loads its blocks two groups ahead | with `HC_Q12=1` |
| 0017 | lane calls split over K on a cluster run on the fused form | `FUSED_SPLIT=1` (off) |
| 0018 | the read-out's reduce and mix inside its products | `READOUT_FUSE=1` (off) |
| 0019 | the fused split's kernel contract | none (a `tf-cuda-test` contract) |

## Recommended launcher block (FP4) (measured on 1.2.7, 2026-11-14)

    TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_FUSED_SPLIT=1 TF_FLASHNEXT_READOUT_FUSE=1
    TF_FLASHNEXT_SHARED_DRAFTS=0 TF_FLASHNEXT_GREEDY_WIDE=8
    # at 6 and 8 streams with a 262,144 window also TF_FLASHNEXT_KV_PAGES=4096; TF_FLASHNEXT_HC_Q12 stays unset
    # recipe: IMAGE=tensorfold-qwen38:<tag> CHECKPOINT=nvfp4 VISION=0 TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=fp8 \
    #         PARALLEL=<streams> CONTEXT=262144 HOST=127.0.0.1 MEM_CHECK=0 PREPARE=0 ./start.sh restart

`HC_Q12` is the one switch the block leaves out: its 1.02 GiB of 12-bit copies is a capacity cost (14 pool pages,
57,344 positions, fewer at 6 and 8 streams) and it showed no served gain outside the cell noise at 1 to 4 streams.
The rest of the 1.2.7 measurements - the draft settings on the FP4 checkpoint, the one-switch-at-a-time drop table,
and the stack against production at 1, 2, 4, 6 and 8 streams - are in `patches/1.2.7/README.md`; they are not
re-measured here beyond the table this base gets.
