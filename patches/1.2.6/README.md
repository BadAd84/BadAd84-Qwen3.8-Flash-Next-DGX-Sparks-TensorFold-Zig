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
| 0001 | copy windows up to 64 rows, with the boot self-check that serves the largest row-exact window (48) | none | exact; decode flat (-0.3%); copy workload not yet run |
| 0002 | copy re-sync past an edit, copy ramp and miss rules | lane core config | exact; decode flat; copy workload not yet run |
| 0003 | `--kv-cache fp8` for Flash Next | `KV_DTYPE` | exact at bf16; decode flat at bf16; fp8 capacity not yet run on this series |
| 0004 | n-gram row cache, draft-ahead, one gather a shared pass | `GATHER_READ=pread`, `DRAFT_AHEAD=1`, `GATHER_EARLY=1` (all on) | exact; decode level with the base's own readers (61.6 / 81.3 against 62.1 / 81.9); cold 32k prompt 14.1 s against 14.3 |
| 0005 | prompt passes drain less, 3072-row chunks, the relaxed MX128 prompt tile | `PROMPT_MX128` (0: off) | exact with the tile off; cold prompt unchanged with it off; 32k 13.4 s against 14.1 with `=1024`, replies not yet compared |
| 0006 | the MX128 tile in two stages, two blocks an SM | `PROMPT_GEMM2=1` (on, acts only with MX128) | 32k 13.4 s against 13.8 without it, under MX128 |
| 0007 | the draft head's rows 4-bit by default | `DRAFT_HEAD` (`affine4`; `bf16` restores) | **exact; +14.0% prose, +9.9% code at one stream, +6.1% / +7.5% at four** (same binary, switch on and off, repeated) |
| 0008 | prompt passes' hyper-connection read-out as fused kernels, the shared expert read in place, wider head pieces | `PROMPT_HC2=1`, `PROMPT_SHARED_DIRECT=1`, `HEAD_PIECE=1536` (all on) | repaired (see `RECORD.md`), builds; arms queued |
| 0009 | hyper-connection read-outs from a lossless 12-bit copy | `HC_Q12` (off) | exact off; never run switched on with 1.2.6; flat on 1.2.4 |
| 0010 | a shared round priced from the environment | `ROUND_MS`, `DRAFT_ROW_MS` (unset) | exact unset; never run priced |
| 0011 | vision tower linears decoded at load, image rows up to 16,384 | none | exact on text; not a speed lever |
| 0012 | the row cache can read through the page cache | `GATHER_DIRECT` (1) | switch only |
| 0013 | the window self-check can log its first differing row | `CHECK_LOG` (off) | log only |

The accepted stack for speed today is 0001 to 0007: 61.6 / 81.3 tok/s at one stream and 112.8 / 167.4 at four,
against stock's 54.4 / 74.3 and 106.8 / 155.9. Patch 0007 is a default flip of a knob the base already has, so the
same gain is expected from `TF_FLASHNEXT_DRAFT_HEAD=affine4` on an unpatched binary; that arm is queued.

Not in this series: `TF_FLASHNEXT_HC_MXFP8` (the hyper-connection matrices re-coded to MXFP8 at load,
`work/ladder/rungs/gm21.patch`, measured by `mx.sh`). It is not exact, so it goes in only on the owner's word. The
diagnostic logs are `scripts/qwen38/zig/target/diag/`.
