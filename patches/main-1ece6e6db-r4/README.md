# TensorFold main `1ece6e6db` patch series (our levers), revision r4

The TensorFold tree stays pristine at upstream `main` `1ece6e6dbbc073582d50738ce8e73e3c3261a73b`
(2026-11-20 13:01 UTC, "changelog: #4202 under Unreleased") and every change we own is one numbered patch here, one
lever a patch, applied in filename order. Each patch builds on the ones before it and on nothing after it.

**r4 fixes 0008's shared-direct write-back.** With `TF_FLASHNEXT_PROMPT_SHARED_DIRECT=1` and the fused read-out on,
the write-back wrote the written-back rows and their sums but no NORM, while the read-out reads NORM: the lever broke
the 20-item answer set (0/20) and `TF_FLASHNEXT_HC_FUSE=0` restored it. 0008 now carries a mode-3 form of
`hc_writeback_norm` (its own kernel, its own glue case) and the shared-direct branch calls it, so NORM, HOUT and PSS
come from one launch on both routes; the contract compares the two modes byte for byte. 0020 re-pins the two serving
rows the fix moves; the other eighteen patches are byte-identical to r3's. `CHANGES.md` names every difference, the
mechanism's line numbers and the measurement.

**r3 makes 0001 the lever we submitted upstream.** r2's 0001 raised a verify window to 64 rows and, when its boot
self-check could not run, served the 64 unprobed; an unprobed width past the proved one can change tokens. 0001 now
carries PR #4075's own shape: a window's rows are the pending-row log's, `batch.late_rows` (48), the shipped width is
32, and a check that does not run, fails, or proves nothing past 32 leaves the window at 32. Seventeen patches are
byte-identical to r2's; 0007 moves three context lines and 0020 re-pins eight rows. `CHANGES.md` names every
difference. The switch is off unless set: `TF_FLASHNEXT_WINDOW_CHECK=1` runs the boot self-check.

**r2 fixes one defect in 0008.** The first package's `TF_FLASHNEXT_HEAD_PIECE` bound let the MTP head's `fc_h` lane
overrun the pass scratch's `part` on a long prompt (the 8,607-token resume prompt failed with
`cuMemsetD8Async ... CUDA_ERROR_INVALID_VALUE`; the bisect's evidence is in `work/SeriesBisect/`). `CHANGES.md` names
exactly what differs from `patches/main-1ece6e6db`; the fix is `partRows` sized for that lane plus a guard and a host
test.

    ./apply.sh --check TREE     # the whole series applies, nothing written
    ./apply.sh TREE             # apply it

`RECORD.md` has the provenance, the per-patch verdict on this base and every resolution the re-seat needed;
`RETIRED.md` is the hunk-level record of the two levers upstream has absorbed; `docs/RESEAT-1ece6e6db.md` is the
study with the evidence and the gate outputs. This is `patches/main-964174ea05` re-seated: **no patch is wholly
retired**, because upstream has absorbed only parts of two of them (0005's 3,072-row chunk, 0008's fused read-out).

## The levers, one a patch

| patch | lever | switch (recipe default) | upstream path |
|---|---|---|---|
| 0001 | a lone stream's copy window grows to the boot self-check's largest row-exact width (48 rows on GB10 against the 32-row base); a verify window carrying a pending-row log takes the row-by-row DeltaNet | `TF_FLASHNEXT_WINDOW_CHECK` off (set 1 to run the boot check at load; a failed check stays at 32 rows) | PR #4075 `flashnext-copy-window-up`, open |
| 0002 | copy re-sync past an edit, the copy ramp and the miss rules | lane core config | none |
| 0003 | `--kv-cache fp8` for Flash Next: e4m3 keys and values with a power-of-two scale a row, 1,056 bytes a position and layer instead of 2,048 | `KV_DTYPE=fp8` | none; the ground is upstream issue #4107 (another contributor's fp8 KV), which we do not submit to |
| 0004 | the n-gram table's rows through a direct-mapped row cache with up to 128 parked readers, a drafted token's rows asked for while the head drafts, a prompt chunk's rows asked for while the chunk before it runs, one gather a shared pass (its gather-early half is merged upstream as #4009, `69e4d0f04`) | `GATHER_READ=pread`, `DRAFT_AHEAD=1`, `GATHER_EARLY=1` (all on) | PR #4009 `flashnext-gather-early-up` (the gather-early part only), open |
| 0005 | prompt passes drain less on one rank; MXFP8 projections of N columns or more take the relaxed 128 x 128 prompt tile | `PROMPT_SYNC` off (the drain stays off), `PROMPT_MX128` (0: off) | none: the 3,072-row chunk half was absorbed by PR #3726 (merged, `e172bcc29`), the MX128 tile is in no PR |
| 0006 | the MX128 tile in two stages, two blocks an SM | `PROMPT_GEMM2=1` (on, acts only with MX128) | none |
| 0007 | the draft head's rows 4-bit by default | `DRAFT_HEAD` (`affine4`; `bf16` restores) | PR #3477 `flashnext-draft-head-affine4`, MERGED (2026-11-21, `230837886`). **Superseded on upstream main by `230837886` (2026-11-21 09:32 UTC): do not drop it from this package, whose base `1ece6e6db` predates that merge; drop it at the next re-seat onto a base that contains it, checking that the base reads `TF_FLASHNEXT_DRAFT_HEAD` through `platform/environment.zig` with `affine4` as its default** |
| 0008 | a prompt pass's MoE write-back reads the shared expert's fp32 output in place, and a prompt chunk's MTP head pass takes at most `TF_FLASHNEXT_HEAD_PIECE` rows, with the pass scratch's `part` sized for the head's `fc_h` lane and a host test holding that invariant | `PROMPT_SHARED_DIRECT=1`, `HEAD_PIECE` (both on) | none: the fused read-out half was absorbed by PR #3413 (`12233bee5`, branch `flashnext-readout-fuse-up`), the other two halves are in no PR |
| 0009 | hyper-connection read-outs from a lossless 12-bit copy | `HC_Q12` (off) | none |
| 0010 | a shared round priced from the environment | `ROUND_MS`, `DRAFT_ROW_MS` (unset) | none; upstream's own measured pricing is PR #3728 and #3755 (both merged) |
| 0011 | vision tower linears decoded at load, image rows up to 16,384 | none (not a speed lever) | PR #3727 `flashnext-vision-modelopt-up`, MERGED (2026-11-20, `174cfff34`) (the decode-at-load part) |
| 0012 | the row cache can read through the page cache | `GATHER_DIRECT` (1) | none |
| 0013 | the window self-check can log its first differing row | `CHECK_LOG` (off) | none |
| 0014 | the drafter's BF16 linears re-coded to MXFP8 at load | `MTP_WEIGHTS` (`bf16`; `mxfp8` on) | PR #3218 `flashnext-mtp-weights`, open |
| 0015 | fp8 KV on every served stream and in the shared page pool | `KV_PAGES` with `KV_DTYPE=fp8` | none (issue #4107's ground, not submitted) |
| 0016 | 0009's 12-bit read-out tile loads its blocks two groups ahead | with `HC_Q12=1` | none |
| 0017 | lane calls split over K on a cluster run on the fused form | `FUSED_SPLIT=1` (off) | PR #3475 `flashnext-fused-split-up`, MERGED (2026-11-21, `308d5e1fd`) |
| 0018 | the read-out's reduce and mix inside its products | `READOUT_FUSE=1` (off) | none |
| 0019 | the fused split's kernel contract | none (a `tf-cuda-test` contract) | PR #3475 carries the contract in its own shape |
| 0020 | the serving pins: every row of `zig/tests/fixtures/gradient-serving.tsv` the series' own edits move (27 rows) | none (package plumbing) | not upstream: the fixture is this package's own contract |

PR #3523 (`flashnext-config-widths`, top-k and shared width) and #4183 (`cuda-int4-kernel-m`) carry levers that are
not patches of this series: #3523 is config widths, #4183 belongs to the experimental INT4 series
(`patches/main-964174ea05-int4`). GPTQ (PR #3611, merged `0f8e35a1a`) touches `core/quant`, which no patch here edits.

### What the 0020 pins prove

`0020-serving-pins.patch` re-hashes 27 rows of `zig/tests/fixtures/gradient-serving.tsv`, and the only consumer is
`test-gradient-serving`: `zig/build/gradient_host.zig` copies the fixture in as `manifest.tsv`, and
`zig/tests/gradient_serving_pin.zig` hashes the tree's own files and compares them to those rows. It is a
self-consistency gate: it fails when the tree and the fixture disagree, 0020 exists to make them agree, and it cannot
catch a semantic defect, because a changed file's new hash is exactly what the re-pin blesses. It is also not part of
the Linux host suite: `zig/build/host_tests.zig:16` lists `test-gradient-serving` in the reviewed exclusions ("red on
main, #2031 (Flash Next hyper-connection source pin drifted)"), `zig/build/host_ci.zig:334` carries it only in
`macos_deferred`, and it runs only when a driver names it, which this package's own gate does. The correctness review
the fixture receives is the row-by-row comparison in `CHANGES.md`. `work/SpeedAudit/REPORT-verify.md` B.1 and E.4
record the same finding.

## Recommended launcher block (FP4) (measured on 1.2.7, 2026-11-14)

    TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 TF_FLASHNEXT_FUSED_SPLIT=1 TF_FLASHNEXT_READOUT_FUSE=1
    TF_FLASHNEXT_SHARED_DRAFTS=0 TF_FLASHNEXT_GREEDY_WIDE=8
    # at 6 and 8 streams with a 262,144 window also TF_FLASHNEXT_KV_PAGES=4096; TF_FLASHNEXT_HC_Q12 stays unset
    # recipe: IMAGE=tensorfold-qwen38:<tag> CHECKPOINT=nvfp4 VISION=0 TENSORFOLD_CUDA_KERNELS=native KV_DTYPE=fp8 \
    #         PARALLEL=<streams> CONTEXT=262144 HOST=127.0.0.1 MEM_CHECK=0 PREPARE=0 ./start.sh restart

From r3 on, the copy-window half of these numbers also asks for `TF_FLASHNEXT_WINDOW_CHECK=1`: the switch is
off by default, and with it off the window is main's 32 rows. The block is the 1.2.7 measurement's; since then #3413 landed the fused read-out upstream under
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

## Gates

For revision r2, measured before the Paperclip gate run: `apply.sh --check` rc 0 (20 patches, nothing written), a full
apply 20/20 with `pincheck.py` reading `files 169 failing 0`, and an applied-tree manifest that differs from the
verified r1 tree in 7 changed files and 1 added. The host and nvcc gate lines for this package are appended to
`work/SeriesFix/RESULT.md` section 4. The table below is the r1 re-seat's own record (2026-11-20) and is kept for
the per-gate shape.

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

## 0008's shared-direct write-back was unsafe above 512 prompt rows (fixed in r4, 2026-11-22)

`TF_FLASHNEXT_PROMPT_SHARED_DIRECT=1` makes the prompt-pass MoE write-back read the shared expert's output in place.
Measured on the r2 image with the recipe's own environment: the lever off reproduces the 2026-11-19 reference replies
20 of 20 on 20 items of 1,300 to 1,500 prompt tokens, and the lever on reproduces the wrong answers byte for byte, 0 of
20; the two boots with it off both read 20 of 20, and the environment diff between the arms is empty. The cause was
not the 128-row prompt tile: that tile's fp32 output was measured byte-identical to the strided route's at 400, 513,
600, 1,330 and 3,072 rows (0 differing elements of up to 7,864,320), and a planted 1.5x scale differs everywhere. The
cause was the write-back: the lever's branch called the norm-less mode-3 `hc_writeback`, and the fused read-out then
read a NORM the launch never wrote. r4 instantiates `hc_writeback_norm` in mode 3 and calls it there, so both routes
write HOUT, PSS and NORM in one launch; the contract compares mode 3 with mode 2 byte for byte. `TF_FLASHNEXT_HC_FUSE=0`
also restores the answer set and stays a stop-gap, not the fix. Decode is flat within noise either way; the cost of
turning the lever off is cold first token, about +4.9 percent at 8k and +4.6 percent at 32k - that is the margin the
fixed lever keeps. The dev environment's guard (commit `fb7f905e`) is lifted only if the r4 boot gate passes; the
device result is in `work/SDFix/RESULT.md` of the repo this package lives in.
