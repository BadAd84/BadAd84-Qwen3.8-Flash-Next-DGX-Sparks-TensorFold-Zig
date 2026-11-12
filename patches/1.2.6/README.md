# TensorFold 1.2.6 patch series (our levers)

The TensorFold tree stays pristine at upstream v1.2.6 (`6e9af930261a88bb28ac0bfb157ce8e57e9eea07`) and every change
we own is one numbered patch here, one lever a patch, applied in filename order. Each patch builds on the ones
before it and on nothing after it: the tree compiles after every one of the 13.

    ./apply.sh --check TREE     # the whole series applies, nothing written
    ./apply.sh TREE             # apply it
    build_patches.sh TAG git://192.168.99.16/up-pr/tf 6e9af930261a88bb28ac0bfb157ce8e57e9eea07 <this directory>

`RECORD.md` says where the text comes from and which repairs it carries; `docs/CATCHUP-1.2.6.md` has every
measurement behind the table below. RETIRED: the 32-patch series and its integration tail (campaign repo history up
to `6b4cb3b`); it compiled at four points only and served with a stale chunk position.

Measured on spark6, NVFP4 checkpoint, bf16 KV, 131,072-token window, one fresh boot a cell, through the upstream
recipe. "Decode" is 512-token prose and code replies at one and four streams. A lever that is exact gives replies
6/6 identical to stock and a window self-check of 1,176 of 2,080.

| patch | lever | switch (recipe default) | measured so far (2026-11-12) |
|---|---|---|---|
| 0001 | copy windows up to 64 rows, with the boot self-check that serves the largest row-exact window (48) | none | exact; decode flat (-0.3%); **copy workload +26% / +12%** (375.0 to 472.7 and 228.6 to 255.9 tok/s on a verbatim copy and a one-word rewrite of a ~1,800-token text, replies identical) |
| 0002 | copy re-sync past an edit, copy ramp and miss rules | lane core config | exact; decode flat; copy workload 472.7 to 470.8 and 255.9 to 255.0 with it (no gain beyond 0001 on these two texts) |
| 0003 | `--kv-cache fp8` for Flash Next | `KV_DTYPE` | exact at bf16; decode flat at bf16; `KV_DTYPE=fp8` on the full series costs no speed (60.7 / 80.4 and 111.3 / 163.9 at 131,072; 60.3 / 80.2 and 111.6 / 163.7 at 262,144, against bf16's 60.5 / 80.1 and 111.3 / 163.9); copy workload flat (471.1) |
| 0004 | n-gram row cache, draft-ahead, one gather a shared pass | `GATHER_READ=pread`, `DRAFT_AHEAD=1`, `GATHER_EARLY=1` (all on) | exact; decode level with the base's own readers (61.6 / 81.3 against 62.1 / 81.9); cold 32k prompt 14.1 s against 14.3. On the full series: with `DRAFT_AHEAD=0` 57.3 / 76.8 against 60.5 / 80.1 at one stream (draft-ahead is worth about 5%); `GATHER_EARLY=0` and all three off are level with on (60.8 / 80.3 and 60.9 / 80.4, noise about 1%); copy workload 462.0 against 472.7 (-2%) with the cache on and 470.1 with it off, 252.1 against 255.9 on the rewrite |
| 0005 | prompt passes drain less, 3072-row chunks, the relaxed MX128 prompt tile | `PROMPT_MX128` (0: off) | exact with the tile off; cold prompt unchanged with it off; 32k 13.42 s against 14.14 (-5.1%) with `=1024`, replies not yet compared |
| 0006 | the MX128 tile in two stages, two blocks an SM | `PROMPT_GEMM2=1` (on, acts only with MX128) | 32k 13.4 s against 13.8 without it, under MX128 |
| 0007 | the draft head's rows 4-bit by default | `DRAFT_HEAD` (`affine4`; `bf16` restores) | **exact; +14.0% prose, +9.9% code at one stream, +6.1% / +7.5% at four** (same binary, switch on and off, repeated) |
| 0008 | prompt passes' hyper-connection read-out as fused kernels, the shared expert read in place, wider head pieces | `PROMPT_HC2=1`, `PROMPT_SHARED_DIRECT=1`, `HEAD_PIECE=1536` (all on) | repaired (see `RECORD.md`); **exact, golden 6/6 and 1,176 of 2,080 at one and four streams; decode flat (61.6 / 81.4 on against 61.5 / 81.3 off); cold 32k prompt 13.58 s against 14.14 (-3.9%)**: fused read-out -2.3%, shared expert in place -3.1%, head piece none |
| 0009 | hyper-connection read-outs from a lossless 12-bit copy | `HC_Q12` (off) | exact; decode flat with the rung (61.7 / 81.9); the switch itself has not been run on |
| 0010 | a shared round priced from the environment | `ROUND_MS`, `DRAFT_ROW_MS` (unset) | exact; decode flat (61.7 / 81.8); never run priced |
| 0011 | vision tower linears decoded at load, image rows up to 16,384 | none | exact; decode flat (61.7 / 82.0); not a speed lever |
| 0012 | the row cache can read through the page cache | `GATHER_DIRECT` (1) | switch only |
| 0013 | the window self-check can log its first differing row | `CHECK_LOG` (off) | log only |

The accepted stack for speed today is 0001 to 0007: 61.9 / 81.7 tok/s at one stream and 113.0 / 166.1 at four,
against stock's 54.4 / 74.3 and 106.8 / 155.9. Patch 0007 is a default flip of a knob the base already has, and the
same gain shows on an unpatched binary with `TF_FLASHNEXT_DRAFT_HEAD=affine4` (stock 54.2 / 74.3, with the switch
61.7 / 82.0 at one stream; replies identical): the 4-bit draft head is an environment setting on stock, and this
series makes it the default. The other stock knobs tried on the unpatched binary (`DRAFTS_GREEDY`, `PLE_IO=mmap`,
`TABLE_WARM`, `SHARED_DRAFTS`, `KEEP_INPASS`, `LANE_PARTS`, `PROMPT_BF16`, `GPU_TOPK`, `READOUT_ROWS`, `FACT_ROWS`)
move nothing or lose; `BATCH_HEADS=0` loses 17 to 28% at four streams, so the default stays.

Not in this series: `TF_FLASHNEXT_HC_MXFP8` (the hyper-connection matrices re-coded to MXFP8 at load,
`work/ladder/rungs/gm21.patch`): +3.5% prose and +6.5% code at one stream, +3.1% / +5.3% at four, golden 6/6, but
the long replies differ (it is not exact), so it goes in only on the owner's word. The
diagnostic logs are `scripts/qwen38/zig/target/diag/`.
