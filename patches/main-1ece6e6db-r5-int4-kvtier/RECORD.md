# `main-1ece6e6db-r5-int4-kvtier`: provenance, base and the gates it passed

## What this is

The combined directory: upstream TensorFold `main` at `1ece6e6dbbc073582d50738ce8e73e3c3261a73b`, then
`patches/main-1ece6e6db-r5` 0001 to 0020, then five patches in filename order. It is the tree the gate run and the
device window used, built as one directory because `scripts/qwen38/zig/target/build_patches.sh` applies a directory in
glob order and a device build reads one tarball of the result.

- **Base it applies to**: upstream `1ece6e6dbbc073582d50738ce8e73e3c3261a73b` with `patches/main-1ece6e6db-r5`
  0001 to 0020 first. `apply.sh` checks this package's `SHA256SUMS`, the series' own `--check`, and refuses any other
  HEAD.
- **Where the text comes from**: `patches/main-1ece6e6db-r5-int4` for 0021 and 0022 and `patches/main-1ece6e6db-r5-kvtier`
  for 0023 and 0024 and `patches/main-1ece6e6db-r5-kvtier-pool` for 0025, each byte for byte. Those packages record
  their own provenance: the INT4 port re-seated from the r2 series with one hand-resolved conflict
  (`main-1ece6e6db-r5-int4/RECORD.md`), the fp8 image and the append dedup attributed to the two tier windows
  (`main-1ece6e6db-r5-kvtier/RECORD.md`), and the pool refusal attributed to the measured plan at production's shape
  (`main-1ece6e6db-r5-kvtier-pool/RECORD.md`).
- **Whether we edited it**: the composition adds no line of its own. The only change is the renumbering of the tier's
  and the pool's patches so they sort after the INT4 pair; `sha256sum` proves each patch is the source package's file
  (`CHANGES.md` has the table).
- **Base for a rebuild**: apply the five to a pristine checkout at the base above, or extract the gated tree the host
  proved (`head.tgz`, sha256 `dba3520a2f12f7c86141660f61eac120b096aa848a5ccfb13422c8c917bcc46e`, 13,319 files).

## Checks

Paperclip (x86-64, 16 threads, Zig 0.17.0, nvcc 13.3), under `flock ~/work/host.lock`, on freshly extracted staged
trees. Every number below is the gate run's own line, `~/work/KvTierShip2/gate-run.log`.

| step | verdict |
|---|---|
| the staged tree against the base's listing (`verify_lstree.py`) | `entries 12601 blobs 12601 others 0 missing 0 mismatch 0 extra 0 mode_bad 0`, `STAGE tree 3a37e287...`, `STAGE HEAD 1ece6e6dbb... status 0` |
| `main-1ece6e6db-r5/apply.sh --check` | rc 0 |
| `main-1ece6e6db-r5-int4/apply.sh --check` | rc 0, `status after int4 --check: 0 paths` |
| `main-1ece6e6db-r5-int4/apply.sh` (the lean base) | rc 0 |
| this package's `apply.sh --check` | rc 0, `status after --check: 0 paths, scratch index 0` |
| this package's `apply.sh` | rc 0 |
| the applied tree's change counts | `head modified 114 new 24; base modified 109 new 24` |
| the gated tree the device builds from | `HEAD-TREE dba3520a2f12f7c86141660f61eac120b096aa848a5ccfb13422c8c917bcc46e  head.tgz files 13319` |
| the lean pair, each side's own `lean_check.py` | base `7017 files, 230 problems`; head `7017 files, 230 problems` |
| `lean_new.py` on (file, message) | `lean: 230 problems, 230 on the base, 0 new`, rc 0 |
| `git diff --check` | rc 0 |
| `zig fmt --check build.zig zig` | rc 0 |
| `tools/zig/cuda_common_check.py` | `cuda common: 55 local copies, 0 violations` |
| `tools/zig/cuda_fragment_check.py` | `cuda fragments: 2 fragments, 16 includes, 0 misses` |
| `pincheck.py` over `zig/tests/fixtures/gradient-serving.tsv` | `files 170 failing 0` |
| `zig build -Dfixed-cpu test-environment-host` | `3/3 steps succeeded; 29/29 tests passed` |
| `zig build -Dfixed-cpu test-gradient-serving test-qwen-serving-host` | `7/7 steps succeeded; 3/3 tests passed` |
| `zig build -Dfixed-cpu test-flashnext-int4-host` | `4/4 steps succeeded; 26/26 tests passed` |
| `zig build -Dfixed-cpu test-prompt-cache-host` | `3/3 steps succeeded; 707/707 tests passed` |
| `zig build -Dfixed-cpu test-cache-store-host` | `3/3 steps succeeded; 154/154 tests passed` |
| `zig build -Dfixed-cpu test-learn-recovery` | `3/3 steps succeeded; 719/719 tests passed` |
| `zig build -Dfixed-cpu test-cuda-kept-host test-disk-identity-host test-cuda-disk-open-host` | `12/12 steps succeeded; 68/68 tests passed` |
| `zig build -Dfixed-cpu test-kernel-contract` | `36/36 steps succeeded; 260/260 tests passed` |
| `zig build compile-config-server -Dtarget=aarch64-linux-gnu` | `8/8 steps succeeded` |
| `zig build compile-cuda-tests -Dtarget=aarch64-linux-gnu` | `10/10 steps succeeded` |
| `zig build -Dnvcc=... compile-cuda-tests` (the runner) | rc 0, 645 s; `Build Summary: 169/169 steps succeeded` |
| `zig build -Dnvcc=... -Dtarget=aarch64-linux-gnu compile-cuda-tests` (cross) | rc 0, 712 s; `Build Summary: 169/169 steps succeeded` |
| `zig build -Dnvcc=... -Doptimize=fast --prefix ... fatbins install native` | rc 0, 711 s; `FATBIN fn_int4: 1132920 bytes sha256 8080835ba1bccf4595f6ee21181e87fe8ed96f6d3d1da128bdfff8f81fa6beba`; `FATBIN images 125` |
| `zig build -Dfixed-cpu test-cuda-cache-budget-host` (the pool's witness step) | `6/6 steps succeeded; 21/21 tests passed` |
| the gate's `new_test_ran` check | fired `the pool guard's test ran in no host step`, so the run closed `GATES-DONE bad=1`; the check greps for a phrase Zig's runner prints only on failure, and the test is proved collected by the counts (19 before the pool patch, 21 after) and by a planted failure that names it (`20 pass, 1 fail (21 total)`), both recorded in `main-1ece6e6db-r5-kvtier-pool/RECORD.md` |

Every other line of the run is rc 0, and `GATES end ... bad=1` is that single check.

## The lean finding and its resolution

The first gated tree read `2 new`: two `multi-line comment` findings from the pool patch's three-line doc comment,
fixed by collapsing it to one 111-column line and renaming its witness test into the existing
`test-cuda-cache-budget-host` filter. The committed patch's pair reads `lean: 230 problems, 230 on the base, 0 new`.

## What is not proved here

No device result is claimed in this file. The window's report is `work/KvTierShip/RESULT.md`, which is not committed
(the lane's `work/` folder is ignored); the image it built came from the `head.tgz` sha quoted above.
