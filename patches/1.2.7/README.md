# TensorFold 1.2.7 patch series (our levers)

The TensorFold tree stays pristine at upstream v1.2.7 (`93a2e93ecebff8aa52b88e58c5dd222516e69c5f`) and every change
we own is one numbered patch here, one lever a patch, applied in filename order. Each patch builds on the ones
before it and on nothing after it: the tree compiles after every one of the 13.

    ./apply.sh --check TREE     # the whole series applies, nothing written
    ./apply.sh TREE             # apply it
    build_patches.sh TAG git://192.168.99.16/up-pr/tf 93a2e93ecebff8aa52b88e58c5dd222516e69c5f <this directory>

`RECORD.md` says where the text comes from and which repairs it carries; `docs/CATCHUP-1.2.6.md` has every
measurement behind the table below. RETIRED: the 32-patch series and its integration tail (campaign repo history up
to `6b4cb3b`); it compiled at four points only and served with a stale chunk position.

The same 13 levers as `patches/1.2.6`, re-seated on v1.2.7 (see `RECORD.md`), each re-tested one rung at a time
(`scripts/qwen38/zig/target/v127.sh`, spark6, 2026-11-12: NVFP4 checkpoint, bf16 KV, 131,072-token window, one fresh
boot a cell, one decode pass of 512-token prose and code replies). Images: `up127` is v1.2.7 alone, `v<N>` the first N
patches. Aggregate tok/s, prose / code; every cell's golden is 6/6 identical to v1.2.6 stock's:

| arm | 1 stream | 4 streams | cold 8k / 32k prompt (s) |
|---|---|---|---|
| v1.2.6 stock | 54.5 / 74.5 | 105.4 / 153.7 | 3.49 / 14.30 |
| v1.2.7 stock (two runs) | 54.2 / 74.0, 53.4 / 73.4 | 105.9 / 154.0, 105.2 / 152.5 | 3.51 / 14.29, 3.49 / 14.31 |
| v1.2.6 + 0001-0007 (`g21`) | 60.9 / 80.4 | 111.4 / 164.6 | 3.52 / 14.28 |
| v1.2.7 + 0001 | 53.7 / 73.2 | 105.2 / 153.6 | 3.51 / 14.33 |
| v1.2.7 + 0001-0003 | 53.9 / 74.1 | 105.3 / 153.3 | 3.53 / 14.31 |
| v1.2.7 + 0001-0004 | 53.6 / 73.3 | 104.8 / 153.0 | 3.52 / 14.24 |
| v1.2.7 + 0001-0005 | 53.4 / 73.5 | 105.3 / 152.9 | 3.51 / 14.28 |
| v1.2.7 + 0001-0006 | 53.5 / 73.1 | 105.4 / 153.3 | 3.51 / 14.24 |
| **v1.2.7 + 0001-0007** | **60.5 / 80.0** | **111.4 / 164.7** | 3.51 / 14.24 |
| v1.2.7 + 0001-0008 | 60.7 / 80.5 | 111.5 / 163.6 | 3.40 / 13.74 |
| v1.2.7 + 0001-0009 | 60.3 / 80.1 | 111.4 / 163.9 | 3.35 / 13.79 |
| v1.2.7 + 0001-0010 | 60.6 / 79.8 | 111.2 / 164.2 | 3.35 / 13.74 |
| v1.2.7 + 0001-0011 | 60.7 / 80.0 | 111.3 / 164.0 | 3.46 / 13.82 |
| v1.2.7 + all 13 | 60.4 / 80.2 | 111.5 / 163.6 | 3.39 / 13.78 |

- v1.2.7 gives the same speed as v1.2.6 on this workload, and the series behaves the same on it: the 4-bit draft head
  (0007) is the whole decode gain (+11.6% prose, +8.1% code at one stream, +5.2% / +7.0% at four, against v1.2.7
  stock), the read-out fusion (0008) is the whole prompt gain (14.24 to 13.74 s at 32k, -3.5%), and every other patch
  is flat.
- No patch is retired: v1.2.7 absorbed none of them (each lever's gain survives without a counterpart in the base).
- Not yet run on v1.2.7: the copy workload, fp8 KV at 262,144, the stock `DRAFT_HEAD` arm, the 2, 6 and 8 stream cells.
- Cell-to-cell noise is about 1% (the stock arm run twice: 54.2 and 53.4 at one stream).
