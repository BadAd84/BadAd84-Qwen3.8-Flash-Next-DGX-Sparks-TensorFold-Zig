# `main-1ece6e6db-r5-dev`: provenance, per-patch benefit, the collisions and the tolerance port

## What this is

Upstream TensorFold `main` at `1ece6e6dbbc073582d50738ce8e73e3c3261a73b`, then 36 patches in filename order: the r5
core levers (0001-0020), the INT4 and KV-tier six (0021-0026), the bf16 draft-head pair (0027-0028), the int4
contract suite with the tolerance branch's three commits (0029-0032), the merged serving pins (0033), and the three
composed-gate corrections (0034-0036). It is the dev
engine: the one directory a device build applies, and the one stack whose gates decide whether the dev arm is good.

Every row of the table below names the source, whether this package edited the text, the measured benefit and the
evidence file. The source packages and branches are **not deleted**; they stay as provenance and alternatives. Once
this package is accepted, deleting any of them loses nothing that is not here: the text is carried (0001-0026 byte for
byte, 0027-0032 with the edits `CHANGES.md` names), and the benefit/evidence record is this file.

## Per-patch record

| # | source | text edited here | measured benefit | evidence |
|---|---|---|---|---|
| 0001 | `patches/main-1ece6e6db-r5/0001-rows.patch` | no, byte-identical | a lone stream's copy window is the boot check's largest row-exact width (48 rows on GB10 against the 32-row base); a failed or unrun check stays at 32 | `patches/main-1ece6e6db-r5/README.md` (lever table), `work/SeriesR3/REPORT.md` |
| 0002 | `patches/main-1ece6e6db-r5/0002-copy-resync.patch` | no | copy re-sync past an edit; proposals only, replies identical | `work/upsubmit/Triage/rest.md` (0002 items) |
| 0003 | `patches/main-1ece6e6db-r5/0003-kv8.patch` | no | fp8 KV: 1,056 bytes a position and layer against 2,048 | `patches/main-1ece6e6db-r5/README.md`, `patches/1.2.7/README.md:246` |
| 0004 | `patches/main-1ece6e6db-r5/0004-ngram-row-cache.patch` | no | with 0012, its absence costs about 7.8 GiB of 4-stream headroom (20.15 GiB needed against 17.79 left, 25.6 left with it); `GATHER_EARLY=0` costs 4.5 percent on code and 4.3 on prose at four streams | `work/upsubmit/Triage/ngram.md:17,229-243,252` |
| 0005 | `patches/main-1ece6e6db-r5/0005-prompt-sync-mx128.patch` | no | the drain alone is -7.8 percent cold 64k at C>=2 in one receipt and flat in two; the MX128 tile is the kept half | `work/upsubmit/Triage/prompt.md:14-15` |
| 0006 | `patches/main-1ece6e6db-r5/0006-prompt-gemm2.patch` | no | the MX128 tile in two stages, two blocks an SM; acts only with 0005 | `patches/1.2.7/README.md` (0001-0007 arms, lines 24-35) |
| 0007 | `patches/main-1ece6e6db-r5/0007-draft-head-4bit.patch` | no | the draft head's 4-bit rows are the group's last lever: the 0001-0007 bundle reads 60.5/80.0 prose/code at one stream against stock 54.2/74.0 | `patches/1.2.7/README.md:24,30` |
| 0008 | `patches/main-1ece6e6db-r5/0008-shared-direct-head-piece.patch` | no | the head-piece bound fixes the 8,607-token resume (`cuMemsetD8Async ... bytes=62914560` on the pre-fix series); cold prompts read 3.40/13.74 s at 8k/32k against 3.51/14.24 | `patches/main-1ece6e6db-r2/CHANGES.md:5-40`, `work/SeriesFix/RESULT.md`, `patches/1.2.7/README.md:31` |
| 0009 | `patches/main-1ece6e6db-r5/0009-readout-q12.patch` | no | read-out down 43.6 to 40.2 ms, up 36.5 to 34.2 ms, kernels a round 69.92 to 69.45 ms | `patches/1.2.7/README.md:324-328` |
| 0010 | `patches/main-1ece6e6db-r5/0010-round-cost.patch` | no | a shared round priced from the environment; no isolated cell in the records | `work/SpeedAudit/REPORT-verify.md` (A-row on the pricing campaign) |
| 0011 | `patches/main-1ece6e6db-r5/0011-vision.patch` | no | vision linears decoded at load, image rows to 16,384; not a speed lever (vision off in the speed arms) | `work/SpeedAudit/REPORT-verify.md:141`, `docs/PROD-VS-ZIG-2026-11-18.md:13-20` |
| 0012 | `patches/main-1ece6e6db-r5/0012-gather-direct.patch` | no | the row cache's page-cache path; the 0004/0012 bundle's capacity term is the measured one | `work/upsubmit/Triage/ngram.md:229-268` |
| 0013 | `patches/main-1ece6e6db-r5/0013-check-log.patch` | no | the self-check logs its first differing row; a diagnostic | `work/SeriesR3/REPORT.md` |
| 0014 | `patches/main-1ece6e6db-r5/0014-mtp-mxfp8.patch` | no | the drafter's BF16 linears re-coded to MXFP8 at load; the arm is the INT4 package's `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8` | `patches/main-1ece6e6db-r5-int4/README.md` (serve settings), `patches/1.2.7/README.md` (MTP section) |
| 0015 | `patches/main-1ece6e6db-r5/0015-kv8-pages.patch` | no | pages admit 6 and 8 streams at 262,144: 144.2/204.8 and 160.5/234.3 against refused (30.23 GiB against 27.26, and 40.31 GiB); 18,880 against 30,784 bytes a token | `patches/1.2.7/README.md:246,270-276,288-300` |
| 0016 | `patches/main-1ece6e6db-r5/0016-readout-q12-ahead.patch` | no | 0009's tile loads two groups ahead; the Q12 pair is the 0.47 ms row, the fused form 0.45 ms more | `patches/1.2.7/README.md:317,349-352` |
| 0017 | `patches/main-1ece6e6db-r5/0017-fused-split.patch` | no | split over K at 2,048 columns or more below 256 rows; 0.45 ms a round, +0.4 to +1.3 percent at eight | `patches/1.2.7/README.md:317,349-352` (`work/SpeedAudit/REPORT-verify.md` A29) |
| 0018 | `patches/main-1ece6e6db-r5/0018-readout-fuse.patch` | no | launches 1,649.5 to 1,420.0 a round, read-out kernels 9.938 to 9.130 ms, +1.8 percent at eight | `patches/1.2.7/README.md:374-402`, `work/Fuse0018Fix/RESULT.md:356` |
| 0019 | `patches/main-1ece6e6db-r5/0019-fused-split-contract.patch` | no | the fused split's kernel contract (gates 1-4) | `patches/1.2.7/README.md` (contract section) |
| 0020 | `patches/main-1ece6e6db-r5/0020-serving-pins.patch` | no | the r5 series' 28 serving-pin rows; `pincheck` failing 0 | `patches/main-1ece6e6db-r5/RECORD.md` |
| 0021 | `patches/main-1ece6e6db-r5-int4/0021-int4-autoround.patch` | no, byte-identical | the INT4 checkpoint served: decode 0.79 of production on prose and 0.95 on code at eight streams, level on code at one, two and four; internal exactness 20 of 20 | `work/DevVsProd/RESULT.md`, `work/QInt4/RESULT.md`, `work/R5Int4Fix/RESULT.md`; quality not measured: `work/Int4Window/QUALITY-DEFECT.md` |
| 0022 | `patches/main-1ece6e6db-r5-int4/0022-int4-serving-pins.patch` | no | the INT4 port's 17 serving-pin rows | `patches/main-1ece6e6db-r5-int4/RECORD.md` |
| 0023 | `patches/main-1ece6e6db-r5-kvtier/0021-kv-tier-fp8.patch` | no | the fp8 state image, on the NVFP4 arm: first state 6,813 tokens, 232 MiB, 294 ms write, 76 ms read; a resumed prefill 0.113 s against 2.947 s cold | `patches/main-1ece6e6db-r5-kvtier/README.md`, `work/KvTierShip/RESULT.md` |
| 0024 | `patches/main-1ece6e6db-r5-kvtier/0022-kv-tier-dedup.patch` | no | on the same arm: an append turn 115.1 MiB against 228.1; a 60 GiB budget 508 append turns against 257 | `patches/main-1ece6e6db-r5-kvtier/README.md`, `work/KvTierDedup/` |
| 0025 | `patches/main-1ece6e6db-r5-kvtier-pool/0023-kv-tier-pool.patch` | no | a plan that leaves the prompt cache no bytes refuses by name (at the INT4 shape: `no prompt cache` beside `389 pages of 4096 rows`) | `patches/main-1ece6e6db-r5-kvtier-pool/README.md`, `work/KvTierShip/STATUS.md` |
| 0026 | `patches/main-1ece6e6db-r5-kvtier-pool/0024-kv-tier-full-ask.patch` | no | the store's budget at the served shape: 6,442,450,944 B with the whole ask against 3,320,107,008 B on the five-patch head | `docs/receipts/FullAsk/RESULT.md`, `work/TierFollowup/RESULT.md` |
| 0027 | `patches/main-1ece6e6db-r5-drafthead-bf16/0026-draft-head-format.patch` | yes: one hunk's context line, to sit after the INT4 test step (`CHANGES.md` section 2) | `TF_FLASHNEXT_DRAFT_HEAD=bf16` with `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8` serves; the unfixed image refuses every request (`FormatMismatch`, HTTP 500); 28 comparison lines all `EQ`, 12 of 12 drafted replies equal to their plain twins | `patches/main-1ece6e6db-r5-drafthead-bf16/RECORD.md`, `receipt/device.tgz` |
| 0028 | `patches/main-1ece6e6db-r5-drafthead-bf16/0027-draft-head-format-pins.patch` | yes: the row value, regenerated from the merged bytes (`CHANGES.md` section 3) | the `cuda_mtp.zig` pin row: `304a8cfc153fb4cd30743d1c996e8f54501f219a0718bcf9b896ca4c5916bf2a` | `zig/tests/fixtures/gradient-serving.tsv:145`, `test-gradient-serving` |
| 0029 | PR #4183 contract slice at `d1d763ca0c13413f96aad99f9570f9c5ea983ba3` (carrier for 0030-0032) | yes: three context adaptations and one notice sentence, listed in `CHANGES.md` section 4 | the int4 experts and head through gates 1-4 and float64 at the checkpoint's widths, with two planted controls; the branch's device receipt reads 8 kernels, 8 pass, 5 controls 5 red | `work/Int4Tolerance/RESULT.md` (device summary at `3afd83b555`); host suite here: `test-kernel-contract` |
| 0030 | branch `int4-tolerance` commit `34274bd49225904960d7a4c5de92b17e83f927c1` | no (hunks apply as written; offsets only) | the `int4-contract` verb runs the suite on a built runner; the usage lists it (`USAGE 145: int4-contract`) | `work/Int4Tolerance/RESULT.md` |
| 0031 | commit `33f6110dc5494f82c6e6293d6de9adf7434ab1c6` | no | the sums' second count removed: the allowance is a median 11 percent tighter at the served width, 2 percent at k 640, under 1 percent at k 256; a stated gate lands at 2.15 times the generic bound and 0.66 of the derived allowance | `work/Int4Tolerance/DERIVATION.md`, `work/Int4Tolerance/RESULT.md` |
| 0032 | commit `3afd83b5558e57bc341eb069c4bf1af041662d48` | no | the epilogue's scalar model passes gates 1-4; three planted controls on the gate/up form are red at gate 3 (two) and gate 4 (one); gate 4's bf16 ceiling is `1 / (4.039307 u) = 63.38`, so the registration states 60 | `docs/int4-contract-allowances.md`, `work/Int4Tolerance/RESULT.md`, `work/Int4Tolerance/DERIVATION.md` |
| 0033 | this package (the INT4 package's pin convention, regenerated) | yes: generated from the merged bytes | the `root.zig` pin row after the contract export: `167d76c511f03e5ce78747066a1243dd187ecd6c6731fdd62f406f0f60c4d93b` | `zig/tests/fixtures/gradient-serving.tsv:109`, `test-gradient-serving` |
| 0034 | this package (the composed gate's finding) | yes: the test's last arm | the pool's `named8` arm now pins the #2987 behaviour: an asked cache beside TF_KV_SHARE keeps the remainder as pages (`kept = 6 GiB - 8 slots`), copied 0; before, the test expected the remainder as copies and failed (`21 pass, 1 fail (22 total)`); after, `22/22 tests passed` | `zig/src/native/cuda_cache_capacity_test.zig:79-84`, `cuda_cache_capacity_test`, gate log |
| 0035 | this package (the composed gate's finding) | yes: the test's fixture value | the int4 port splits the shared expert's width from the routed experts' (1,280 against 640); the wider-shared fixture now starts from `wt.shared_w + 64`, the value `mismatch` compares, instead of `wt.moe_w + 64` | `zig/src/families/flashnext/cuda_config.zig:349`, gate log |
| 0036 | this package (the composed gate's finding) | yes: one dispatch guard and one fixture field | the int4 dense dispatch now applies only to the 64/128 groups `fn_int4.cu` builds, so a fixture with no group keeps the normal lane (the paged-prompt test); the split-lane fixture sets `shared_width = wt.moe_w`, the field the port reads (before, `Owned` was `undefined` there and the run overflowed at `cuda_split_lane_test.zig:289`) | `zig/src/families/flashnext/cuda_batch.zig:135`, `zig/src/families/flashnext/cuda_split_lane_test.zig:284`, gate log |

## The tolerance port's outcome

Ported in full: all three commits, every hunk, no piece stopped. The branch is `int4-tolerance` in the fork clone
`work/upmain`, head `3afd83b5558e57bc341eb069c4bf1af041662d48`, cut on the PR's live head
`d1d763ca0c13413f96aad99f9570f9c5ea983ba3`; the three shas are in the table above (0030-0032). Nothing was pushed and
nothing was posted.

The one thing the branch could not supply itself is its carrier: those commits edit a suite this composition did not
carry (`contract_int4.zig`, `int4_ref.zig`, the controls image and the verb's wiring), because our INT4 route is
production's lifted `fn_int4.cu` and `cuda/int4.zig` is not part of it. So 0029 imports PR #4183's contract slice at
the branch's parent `d1d763ca`, and the three commits apply on top as their own patches. The kernel the suite tests is
the one here: the same groups-of-128 mangled symbols, with the composition's extra groups-of-64 instantiations and one
local load the only differences in `fn_int4.cu` (`CHANGES.md` section 4).

The three commits' text was not edited. The context offsets (`zig/build/kernel_contract.zig` hunk at 206, `main.zig`
at 337, `main_usage.zig` at 141) are this base's line numbers; the hunks' content is the branch's.

## The two collisions, resolved

1. **`zig/build/cuda.zig`**: the draft-head package's step and the INT4 step share one block. One block, both
   registrations, at lines 277-280 (`part-rows`, `int4`, `draft-head`, `living`). 0027's hunk context is re-cut for
   it; its inserted line is byte-identical to the source.
2. **`zig/tests/fixtures/gradient-serving.tsv`**: both pin patches re-pin `cuda_mtp.zig` from different trees. The
   merged rows were regenerated once from the merged bytes with `work/DevComposition/repin.py` (every row is mode
   `raw`: sha256 of the file's bytes, the pin test's own rule), never hand-edited. 0028 carries the `cuda_mtp.zig`
   row (`304a8cfc...`, line 145), 0033 the `root.zig` row (`167d76c5...`, line 109); the INT4 package's 17 rows at
   0022 stand unchanged.

## Source branches and packages, and deletion

| source | what it supplied here | safe to delete once this package is accepted? |
|---|---|---|
| `patches/main-1ece6e6db-r5` | 0001-0020 | yes: byte-identical copies; its RECORD/README are also summarised in this file |
| `patches/main-1ece6e6db-r5-int4` | 0021-0022 | yes: byte-identical copies |
| `patches/main-1ece6e6db-r5-kvtier` | 0023-0024 | yes: byte-identical copies |
| `patches/main-1ece6e6db-r5-kvtier-pool` | 0025-0026 | yes: byte-identical copies |
| `patches/main-1ece6e6db-r5-int4-kvtier` | nothing unique (its six are 0021-0026 here) | yes: composed wholly into this package |
| `patches/main-1ece6e6db-r5-drafthead-bf16` | 0027-0028 | yes: text carried with the two edits above; its `receipt/device.tgz` is the evidence and stays with the package |
| branch `int4-tolerance` (`work/upmain`) | 0030-0032 | yes: every hunk is carried; the three shas above are the record |
| PR #4183 head `d1d763ca` (`BadAd84/TensorFold` `cuda-int4-kernel-m`, also `refs/int4tolerance/prhead`) | 0029 (the contract suite) | not ours to delete; the suite text is carried in 0029 |

No branch or package was deleted by this work.

## Checks

Paperclip (x86-64, 16 threads, Zig 0.17.0, nvcc 13.3.73), 2026-11-24, under `flock ~/work/host.lock`, on a pristine
`git archive` of the base in `~/work/DevComp/pristine` and a fresh worktree in `~/work/DevComp/gated`. The gate script
is `~/work/DevComp/gate2.sh`; every line below is the run's own (`~/work/DevComp/gate2.log`).

| step | rc | line |
|---|---|---|
| the staged archive against `git ls-tree` (`verify_lstree.py`) | 0 | `LSTREE .../pristine entries 12601 blobs 12601 others 0 missing 0 mismatch 0 extra 0 mode_bad 0` |
| `apply.sh --check .` | 0 | `apply.sh: 34 patches apply on 1ece6e6dbbc073582d50738ce8e73e3c3261a73b in order (nothing written)` |
| `apply.sh .` | 0 | `apply.sh: 34 patches applied on 1ece6e6dbbc073582d50738ce8e73e3c3261a73b` |
| `git diff --check` | 0 | no output |
| the applied tree's manifest | 0 | 12,635 files (base 12,601 + 34); `LC_ALL=C` recomputation `31ce29368af1ae9ffef4304bc4c789e60a2ea1602aec3c4a883542aaf3ef4c7b`, equal to the local replay's manifest, so the box tree is the composition's tree file for file |
| `zig fmt --check build.zig zig` | 0 | no output |
| `tools/zig/cuda_common_check.py` | 0 | `cuda common: 55 local copies, 0 violations` |
| `tools/zig/cuda_fragment_check.py` | 0 | `cuda fragments: 2 fragments, 16 includes, 0 misses` |
| `pincheck.py` | 0 | `files 170 failing 0` |
| lean, pristine base (its own checker) | 1 (its own findings) | `6993 files, 168 problems` |
| lean, composition (its own checker) | 1 (its own findings) | `7026 files, 230 problems` |
| `lean_new.py`, pristine base against head | 1 | `lean: 230 problems, 168 on the base, 62 new`; every one is the r5 series' own file (see the next two rows) |
| lean, series tree (0001-0028) | 1 (its own findings) | `7018 files, 230 problems` |
| `lean_new.py`, series against head | 0 | `lean: 230 problems, 230 on the base, 0 new`; the draft-head and contract layers add no finding |
| `test-environment-host` | 0 | |
| `test-gradient-serving` | 0 | |
| `test-qwen-serving-host` | 0 | |
| `test-flashnext-int4-host` | 0 | |
| `test-int4-host` | 0 | |
| `test-flashnext-draft-head-host` | 0 | |
| `test-cuda-cache-budget-host` | 0 | before 0034: `21 pass, 1 fail (22 total)` at `cuda_cache_capacity_test.zig:82` (`expected 5517312000, found 0`); after: the step passes |
| `test-prompt-cache-host` | 0 | |
| `test-cache-store-host` | 0 | |
| `test-learn-recovery` | 0 | |
| `test-cuda-kept-host test-disk-identity-host test-cuda-disk-open-host` | 0 | |
| `test-kernel-contract` | 0 | |
| `compile-config-server -Dtarget=aarch64-linux-gnu` | 0 | 315 s |
| `compile-cuda-tests` | 0 | 262 s |
| `compile-cuda-tests -Dtarget=aarch64-linux-gnu` | 0 | 294 s |
| `compile-cuda-tests -Dnvcc=<13.3>` | 0 | 969 s |
| `compile-cuda-tests -Dnvcc=<13.3> -Dtarget=aarch64-linux-gnu` | 0 | 945 s |
| `test-cuda-host` | 1 | `7666/7715 tests passed (44 skipped, 4 failed, 1 crashed)` on the 35-patch tree. This run found 0034, 0035 and 0036; after 0034 the cache-budget step reads `22/22 tests passed`. 0035 fixes the config fixture; 0036 fixes the paged-prompt failure (`cuda_paging_batch_test.zig:176`, `cuda_int4.dense` refusing a fixture with no group) and the split-lane panic (`cuda_split_lane_test.zig:289`, `shared_width` read from `undefined`). A run with all three applied was in flight at hand-off; the log is `~/work/DevComp/gate2.log` |

The package's own gates: `scripts/check-patch-packages.sh` reads `check-patch-packages: CLEAN (19 package dirs
checked, 1 grandfathered)`; `scripts/check-patch-reverts.py` reads `34 patches, 124 findings, 124 allowed, 0 open,
0 stale`; `scripts/check-python.sh` reads `check-python: CLEAN`.

The env coverage gate against the applied tree is red on four of 0021's rows and is reported in `README.md`: `coverage:
99 settings in scope, set 95, missing 4, absent 2, annotations 2, worklist markers 0, passage-lost off`, the missing
names `TF_FLASHNEXT_HEAD_ROW_TILES`, `TF_FLASHNEXT_INT4_PROMPT_DOWN`, `TF_FLASHNEXT_INT4_PROMPT_GATE_UP`,
`TF_FLASHNEXT_INT4_TILE`. `check-dev-env.py` reads `dev-env: 0 setting(s) without a citation`.

What the gate does not prove: no device run of this composition, and `test-cuda-host` is not yet observed green. The
contract suite's device receipt is the tolerance branch's head (`work/Int4Tolerance/RESULT.md`); here the suite is
exercised on the host and by the nvcc compile legs. The four full-suite findings are addressed by 0034-0036; 0034 is
observed at `22/22`, and the run that observes 0035 and 0036 was in flight at hand-off.

