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

The same 13 levers as `patches/1.2.6`, re-seated on v1.2.7 (see `RECORD.md`). **Nothing on this base has been measured
yet**: the numbers for each lever are in `patches/1.2.6/README.md`, and each one is re-tested here, one rung at a
time, with `scripts/qwen38/zig/target/v127.sh` (images `up127` for v1.2.7 alone, `v1` to `v13` for the prefixes);
a patch that v1.2.7 made redundant is retired by name when that test shows it.
