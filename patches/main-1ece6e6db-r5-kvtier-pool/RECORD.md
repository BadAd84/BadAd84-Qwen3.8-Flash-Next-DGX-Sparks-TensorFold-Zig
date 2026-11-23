# `main-1ece6e6db-r5-kvtier-pool`: provenance, base and the gates it passed

## What this is

Two patches, added on top of `patches/main-1ece6e6db-r5` (0001 to 0020) and `patches/main-1ece6e6db-r5-kvtier`
(0021, 0022):

| patch | sha256 | what |
|---|---|---|
| `0023-kv-tier-pool.patch` | `e6a4872ed53041d3e5e4b850a3733dadba764b15c54941420bd4b480a9032589` | a plan that leaves the prompt cache no bytes refuses by name |
| `0024-kv-tier-full-ask.patch` | `cfec2bb31c847fed1523812639125b6a6267ceee4e85970d1918f513768272db` | a family that declares no `snap_slots` is budgeted its whole ask |

Both are cut against the tier's tree, so those twenty-two patches are byte-identical here and the whole set applies in
filename order.

- **Repository and base**: upstream TensorFold `main`, `1ece6e6dbbc073582d50738ce8e73e3c3261a73b`, plus
  `patches/main-1ece6e6db-r5` 0001 to 0020 and `patches/main-1ece6e6db-r5-kvtier` 0021 and 0022.
- **Source of the change**: our own work, not an upstream import. `0023`'s attribution is the measured plan at
  production's shape (`work/KvTierShip/STATUS.md` records the `int4-c8` line of 2026-11-19 and the three inert sites)
  and the tier design (`work/KvTierRecon/DESIGN.md`). `0024`'s is the same plan's other half, measured in
  `work/TierFollowup/RESULT.md` and `docs/receipts/KvTierShip/SHAPES.md`: a 6 GiB ask at the served shape gave the
  store 3,320,107,008 B, of which the 27 x 115,642,400 B slot half was allocated by nothing, and the review that named
  the consequences is `docs/receipts/Glm54Review/REPORT.md` F2. Both are written by us
  against the tier's tree, with no upstream text.
- **We edited**: yes: `0023`'s three files and `0024`'s four, all by us.
- **Base for a rebuild**: apply r5, then the tier, then these two to a pristine checkout at the base above, or
  extract the gated tree the host proved (`head.tgz`, sha256 in `docs/receipts/FullAsk/RESULT.md`, 13,319 files).

## The patch's shape

| file | + / - |
|---|---:|
| `zig/src/native/cuda_streams.zig` | +45 / -0 |
| `zig/src/native/cuda.zig` | +5 / -0 |
| `docs/recipes/flash-next-cuda.md` | +5 / -0 |

`learningRefusal` is public and returns `!?[]const u8`: the refusal text, or null when there is nothing to refuse. It
reads only what the caller already computed (the open request, the ledger's `Count`, the plan's `Kept`, the room and
the window), so it allocates one message and changes no state.

## The three files' pre-images are the same with and without the INT4 pair

The combined package (`main-1ece6e6db-r5-int4-kvtier`) gates this patch on a tree that also carries the INT4 port, and
this package applies it after the tier alone. The two orders are equivalent for these three files, and the gate run is
the proof:

| file | touched by `main-1ece6e6db-r5-int4`'s 0021 or 0022? | touched by the tier's 0021 or 0022? |
|---|---|---|
| `docs/recipes/flash-next-cuda.md` | no | yes, 0021's fp8 bullet (so both orders see the post-0021 text) |
| `zig/src/native/cuda.zig` | no (the INT4 patch's `cuda.zig` is `zig/build/cuda.zig`) | no |
| `zig/src/native/cuda_streams.zig` | no | no |

`grep '^diff --git'` over the INT4 patches shows `zig/build/cuda.zig` and never `zig/src/native/cuda.zig`, and over the
tier's patches only the recipe doc among these three. Since the combined apply succeeds (below), the same patch applies
on the tier-only tree.

## Checks

Paperclip (x86-64, 16 threads, Zig 0.17.0, nvcc 13.3), under `flock ~/work/host.lock`, on freshly extracted staged
trees. Every number below is the gate run's own line, `~/work/KvTierShip2/gate-run.log`.

| step | verdict |
|---|---|
| the staged tree against the base's listing (`verify_lstree.py`) | `entries 12601 blobs 12601 others 0 missing 0 mismatch 0 extra 0 mode_bad 0`, `STAGE tree 3a37e287...`, `STAGE HEAD 1ece6e6dbb... status 0` |
| `main-1ece6e6db-r5/apply.sh --check` | rc 0 |
| `main-1ece6e6db-r5-int4/apply.sh --check` | rc 0, `status after int4 --check: 0 paths` |
| `main-1ece6e6db-r5-int4/apply.sh` (the lean base) | rc 0 |
| `main-1ece6e6db-r5-int4-kvtier/apply.sh --check` (series, INT4, tier, pool) | rc 0, `status after --check: 0 paths, scratch index 0` |
| `main-1ece6e6db-r5-int4-kvtier/apply.sh` | rc 0 |
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
| `zig build -Dfixed-cpu test-cuda-cache-budget-host` (the witness test's step) | rc 0, 0 s; `6/6 steps succeeded; 21/21 tests passed` |
| the gate's own `new_test_ran` check | `GATE new_test_ran: the pool guard's test ran in no host step`, so the run closed `GATES-DONE bad=1` |

The run's only red is that last line, and it is a defect in the CHECK, not in the test. The check greps the step logs
for the test's phrase, and Zig's test runner prints a test's name only when it FAILS, so no passing run can satisfy it.
What the same command says on three trees:

| tree | `test-cuda-cache-budget-host` |
|---|---|
| the series plus the INT4 pair (`tree5`, this patch absent) | `6/6 steps succeeded; 19/19 tests passed` |
| the series, the INT4 pair and the tier's 0021 and 0022 (`tree6`, this patch absent) | `6/6 steps succeeded; 19/19 tests passed` |
| the gated head (with this patch) | `6/6 steps succeeded; 21/21 tests passed` |

and in a scratch copy of the gated tree with one assertion of the test made false, the step fails and names it:

    +- run test 20 pass, 1 fail (21 total)
    error: 'cuda_streams.test.CUDA cache default: a tier whose plan leaves the cache no bytes is refused by name' failed:
    .../zig/src/native/cuda_streams.zig:201:5 ... 20/21 tests passed (1 failed)

On the unmodified head the same binary prints the witness's own passing line,
`20/21 cuda_streams.test.CUDA cache default: a tier whose plan leaves the cache no bytes is refused by name...OK`,
and `All 21 tests passed.`; both runs are this lane's own (`~/work/KvTierShip2/gate-fix.log` and `gate-planted.log`).
So the witness test is collected by the step and passes on the committed patch, and the gate script's check is
replaced by one that runs the step's own binary and reads that line, with these counts as the attribution.

## The lean finding and its resolution

The first gated tree read `2 new` from `lean_new`: two `multi-line comment` findings on the three-line doc comment
above `learningRefusal`. Collapsed to one 111-column line, and the witness test renamed so the existing
`test-cuda-cache-budget-host` filter collects it. On the committed patch the same pair reads
`lean: 230 problems, 230 on the base, 0 new`.

## What is not proved here

- The package's own `apply.sh --check` was not run on this workstation: a base tree extracted and `git add`ed there
  hashed `d8d3da782170b88576e9dde6dddf90c33e91b969` instead of `3a37e287...`, so `apply.sh`'s HEAD guard refuses it
  and the check belongs on the Linux gate host. The cause of the different tree was not established (the archive's
  executable modes are the likely difference on a Windows filesystem). The same sequence of patches is proved there
  through the combined package, and the pre-image argument above covers the one difference (the INT4 pair).
- No device result is claimed in this file. The window's own report is `work/KvTierShip/RESULT.md` (the lane's `work/`
  folder is not committed), and it is measured on the combined package's image.
