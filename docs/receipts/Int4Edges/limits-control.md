# The limits audit's 550 stale records: base 7bd7081e0 against the int4 head 984556bf

The device window on the rebased head reported `FAIL kernel-contract-limits: 550 problems`, all `(record stale)`
lines in other families. The review asked for a control: the same audit on upstream main `7bd7081e0`, so that
"pre-existing" is measured. This is that control.

## Result

| tree | box, compiler | audit |
|---|---|---|
| base `7bd7081e061ca22e3431d2342cd66104dd5fe320` | Paperclip (x86_64), nvcc 13.3 build 13.3.73 | 5836 `PASS`, **550 `(record stale)`**, 0 `FAIL limits`, 1718 `RECORD`, 10 `RED`, 0 `MISSED`, 2751 `N/A`; `FAIL kernel-contract-limits: 550 problems` |
| head `984556bf50ac4e603695596444772f27bd93bd01` | spark6 (GB10, aarch64), the CUDA 13.3 container, 2026-11-23 device window (`work/Int4Device/out2/05-limits-fixed.log`) | 5941 `PASS`, **550 `(record stale)`**, 0 `FAIL limits`, 1739 `RECORD`, 10 `RED`, 0 `MISSED`, 2751 `N/A`; `FAIL kernel-contract-limits: 550 problems` |

Both logs print `INFO limits fatbins: images built by nvcc 13.3, checked against nvcc 13.3's records`.

The stale records are the same records. The two logs' `(record stale)` lines, reduced to their launch and SM
(`sm_<n> <launch>`), are 550 lines each and `diff -u` between them is empty (`stale-diff.txt`, 0 lines, with both
sides sorted under `LC_ALL=C`). So every stale record on the head exists on the base, launch for launch and SM for
SM, and the int4 branch adds none.

The counts move by exactly the int4 launches and records:

| count | base | head | difference | what the difference is |
|---|---:|---:|---:|---|
| `PASS limits` lines | 5836 | 5941 | 105 | the 21 int4 launches on five SMs, all current |
| `RECORD` lines | 1718 | 1739 | 21 | one record a launch for the 21 int4 launches |
| `(record stale)` lines | 550 | 550 | 0 | the same set |
| `FAIL limits` / `MISSED` | 0 / 0 | 0 / 0 | 0 | no launch past a limit on either tree |
| `RED` limiter controls | 10 | 10 | 0 | both controls red on every SM on both trees |

The device window's own int4 subset: 105 `PASS` over 21 launches at sm_80/86/89/120/121, 21 `RECORD`, 0 stale,
0 failing.

## Why the trees can only differ by int4

`diff -u` of the audit source `zig/tests/cuda/contract_limits.zig` between the base archive and the head has
exactly one added line, `if (std.mem.eql(u8, name, "fn_int4")) return kk.fn_int4;`, and `zig/build/cuda_kernels.zig`
adds exactly the `fn_int4` kernel entry. `zig/build/options.zig`, `zig/tests/cuda/check.zig` and the target table
`zig/src/core/contract/limits.zig` are byte-identical. Of the 216 files in `zig/src/core/contract/`, 214 are
byte-identical; only `int4_records.zig` and `registry_joins.zig` differ. So the only records the branch can add
are the 21 int4 ones, and the device window reads those as current.

## How the base measurement was made

Trees: `in/base.tar.gz` and `in/head.tar.gz`, each `git archive`d from the repo and each verified blob by blob
against its `git ls-tree -r` manifest before any build (`MANIFEST base files 13481 mismatches 0 extras 0`,
`MANIFEST head files 13489 mismatches 0 extras 0`).

Base images, under `flock ~/work/host.lock`:

```
zig build --summary all -Dnvcc=<CUDA 13.3> -Dsm=80,86,89,120,121 -j8 fatbins kernel-contract-fatbins
Build Summary: 356/356 steps succeeded        wall 1292 s, 173 images in zig-out/fatbin, 376 MiB
```

Base runner, same tree, under the same lock:

```
zig build --summary all -Dfatbins=/home/adam/work/Int4Edges/base/zig-out/fatbin -j8 compile-cuda-tests
Build Summary: 9/9 steps succeeded            wall 303 s
```

`kernel-contract-limits` reads register usage out of the fatbins and launches no kernel, but `tf-cuda-test` opens a
CUDA context before dispatch and refuses a GPU whose SM the build's embedded images do not cover. Paperclip's
Quadro P4000 is sm_61, below every recorded target. A runner built with `-Dfatbins` embeds prebuilt images and
declares no target list, so `zig/src/cuda/context.zig` skips that refusal for it, and the audit still reads the
five recorded SMs' images from its directory argument. The images themselves are the five-SM build above, the same
flags the device windows used.

The build lock was then held by other lanes for over an hour, so the audit itself (a read-only 58 s pass, one core,
`nice -n 19 ionice -c 3`) was run directly rather than waiting; it reads the fatbins the locked build produced and
touches no build state:

```
cd base && nice -n 19 ionice -c 3 tf-cuda-test-base kernel-contract-limits base/zig-out/fatbin
FAIL kernel-contract-limits: 550 problems
```

The head's number is the device window's own run, not a Paperclip build; the identical stale set across the two
hosts also shows the records are compiler-version behaviour, not host-architecture behaviour.
