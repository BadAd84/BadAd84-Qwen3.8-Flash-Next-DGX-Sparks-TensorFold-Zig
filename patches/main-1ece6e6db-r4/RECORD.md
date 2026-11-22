# Provenance of this package

**Revision r4.** r4 is r3 with one behaviour fixed in 0008, plus the two `0020` rows that fix moves: the
shared-direct write-back now writes the normalized rows in mode 3 of `hc_writeback_norm` (its own kernel
`fn_hc_writeback_norm_moe_sh`, its own glue case `3 =>` in `hcWritebackNorm`, and the branch in
`cuda_batch_hc.zig`'s `writebackNorm` calls it), so the fused read-out reads a NORM the launch wrote. The mechanism and
its measurement are in `CHANGES.md`; r3's own 0008 is byte-identical to r2's, so this is 0008's first change since r2.
Eighteen patches are byte-identical to r3's (0008 and 0020 differ), and the same base, provenance and resolution rules
below apply unchanged. The two files the fix edits that `zig/tests/fixtures/gradient-serving.tsv` pins are re-hashed in
0020; `cuda_batch_hc.zig` and the two contract test files carry no row there.

**Revision r3.** 0001 is replaced by the shape of the lever we submitted upstream (PR #4075, branch head
`be2dc1a57` against upstream `3661a4281`): `max_rows = batch.late_rows` (48), `base_rows = 32`, `buffer_rows` and
`served_rows` defaulting to 32, buffers and served widths written by one policy per load, and a boot check that did not
run or failed leaving the window at 32 (r2 served 64 unprobed). Eight of the files whose base blobs are identical in
`1ece6e6db` and `3661a4281` were taken from the PR head byte for byte (`cuda_mtp.zig`, `cuda_mtp_check.zig`,
`cuda_lanes_load.zig`, `cuda_mtp_draft.zig`, `cuda_draft_draw.zig`, `cuda_mtp_draw.zig`,
`cuda_mtp_nonfinite_fixture.zig` and `zig/tests/cuda/contract_flashnext_late.zig`); `cuda_mtp_ops.zig` is that file
with `const max_rows = mtp.max_rows;` restored for 0008's context; `cuda_lanes_admission_test.zig` and
`zig/build/cuda_fault_host.zig` take the branch's own line; and the rest were edited by the PR's hunks only, so the
copy-window code is the PR's own bytes. Seventeen patches are byte-identical to r2 (0001, 0007 and 0020 differ;
`CHANGES.md` names every difference, including the items 0001 does not take from the PR and why). The switch stays in
the `.cuda` scope r2 gave it because 0004's and 0010's environment hunks quote that line.

**Revision r2.** This package is `patches/main-1ece6e6db` with one defect fixed. Patch 0008's
`TF_FLASHNEXT_HEAD_PIECE` bound let the MTP head's `fc_h` lane write `2 x streams x piece` rows into the pass
scratch's `part`, which held only `2 x cap`; on the 8,607-token resume prompt (cap 3,072, recipe piece 1,536) the
labelled build measured `cuMemsetD8Async@tiles.matmul ... bytes=62914560 m=6144 sk=4 n=2560 ...
CUDA_ERROR_INVALID_VALUE`. r2 sizes `partRows` for that lane (`2 x streams x (cap / 2)`), returns
`error.UnexpectedTensor` from both head passes when the requirement is not met, and holds the arithmetic in a host
test (`cuda_part_rows_test.zig`, `zig build test-flashnext-part-rows-host`). It also fixes main's own overrun for
prompt caps 128..1,023. Seventeen patches are byte-identical to r1 (0008, 0010 and 0020 differ); `CHANGES.md` names
every difference. Recipe
speed: `TF_FLASHNEXT_HEAD_PIECE=1536` stays the measured setting (option 1 of the bisect's `FIX-NOTES.md`), at a
measured cost of 62,914,560 bytes more scratch at cap 3,072.

- **What it is:** our own levers on upstream TensorFold `main` at
  `1ece6e6dbbc073582d50738ce8e73e3c3261a73b` (2026-11-20 13:01 UTC, "changelog: #4202 under Unreleased"), as 20
  numbered patches: 0001 to 0019 are the previous package's levers (one a patch, the series' own order), and 0020
  re-pins the serving fixture's rows for the files those levers edit. Nothing here is another project's commit; the
  base tree is never edited in place.
- **Base it applies to:** `ashhart/TensorFold` `1ece6e6dbbc073582d50738ce8e73e3c3261a73b`. `apply.sh` refuses any
  other HEAD. The previous package, `patches/main-964174ea05`, applies to
  `964174ea05879e6dde1de1198a3aae3ef8b46a3b`.
- **Where the text comes from:** `patches/main-964174ea05`, re-seated one patch at a time in filename order on a
  worktree of the new base (`git apply --3way`, then the hand-written resolutions below, then the new patch is the
  exact difference between the staged trees). The CHANGELOG is rebuilt from each patch's own added bullets, so no
  patch conflicts there; `scripts/qwen38/zig/target/reseat.py`'s procedure with the old base and the series as
  arguments.
- **Whether we edited it:** yes, by these resolutions and the two hunk-level retirements (see `RETIRED.md`):
  - **0001:** `cuda_lanes_load.zig` keeps main's `dropPageCache(gpa, io, dir, ...)` call and puts the boot self-check
    before it; the rule goes in after `TF_QMMF_HALF_BELOW`, where main now starts its Qwen 3.5 block. r3 carries the
    submitted PR #4075 shape of this lever and keeps that placement (see the r3 revision above and `CHANGES.md`).
  - **0003:** `#840` (`917f2070d`) moved the kept-state copy out of the family's `View` into `native/cuda_kept.zig`,
    so the fp8 refusal is re-homed as an optional `View.copyable` declaration called by the shared copy (two lines in
    `cuda_kept.zig`, no effect on Gemma 4). The test command's usage line moved to main's `tests/cuda/main_usage.zig`.
  - **0004, 0005, 0006, 0008, 0017:** the environment rules go in after the series' own previous rule, because main
    restructured the `.cuda` rule region; 0017's and 0018's hunks were re-cut against the new neighbours.
  - **0005:** the 3,072-row chunk half stays main's (`e172bcc29`, PR #3726); the patch keeps `PROMPT_SYNC` and the
    MX128 tile, and its CHANGELOG bullet no longer claims the chunk.
  - **0008:** reduced to `PROMPT_SHARED_DIRECT` and `HEAD_PIECE` because the fused read-out is main's from #3413
    (`12233bee5`); `cuda_batch_hc.zig` keeps main's `cuda_tiles.zig` import (main's own `promptFused` reads
    `tiles.fused_rows`) beside the patch's knobs import.
  - **0010:** main's pricing campaign (#3728, #3755) rewrote both `rate()` call sites in `allocate.zig` and added the
    verify-price branch in `windows.zig`. The resolution keeps main's overhead expressions and routes them through
    `rateRows` with `base` and `head.draft_row_ms` (a no-op when `draft_row_ms` is 0), sets the two fields in both
    `allocateDrafts` literals, and keeps main's moved depth tests (the two inline tests the old patch deleted are no
    longer inline).
  - **0015:** main renamed the pool's arena field (`p.arena.ptr` -> `p.arena.buf.ptr`); the `kv` field is added to
    main's expression.
  - **0016:** main added a `TF_QMMF_WFIRST` preload with its own `#ifdef/#else/#endif`; the two-groups-ahead block
    goes after `#endif`, common to both branches.
  - **0002, 0007, 0009, 0011 to 0014, 0018, 0019:** three-way apply only; their added lines are the old package's.
  - **Two defects of the previous package fixed here:** `flashnext_kv8_tests.zig` lacked its final newline (the file
    `zig fmt --check` refused) and is now created with one; the series now carries the pins patch the serving gate
    needs.

## Per-patch verdicts on `1ece6e6db`

| patch | verdict | evidence |
|---|---|---|
| 0001 | re-seated | 0 added lines lost; one context change (`dropPageCache`) and one rule placement |
| 0002 | re-seated | applies by three-way, 0 added lines lost |
| 0003 | re-seated | the fp8 refusal re-homed on the shared copy (2 new lines), usage line moved; 0 lever lines lost |
| 0004 | re-seated | 0 added lines lost; eight rules placed after 0001's |
| 0005 | re-seated, chunk half retired | `e172bcc29` (#3726); 4 hunk lines dropped, `PROMPT_SYNC` and MX128 kept |
| 0006 | re-seated | 0 lost; rule placed after 0005's |
| 0007 | re-seated | 0 lost |
| 0008 | re-seated, read-out half retired, fixed in r2 | `12233bee5` (#3413); 935 lines dropped, `SHARED_DIRECT` and `HEAD_PIECE` kept; r2 adds the `partRows` term, the two guards and the host test (see the r2 note) |
| 0009 | re-seated | 0 lost |
| 0010 | re-seated | call sites re-expressed on main's overhead; 0 lever lines lost |
| 0011 | re-seated | 0 lost |
| 0012 | re-seated | 0 lost |
| 0013 | re-seated | 0 lost |
| 0014 | re-seated | 0 lost |
| 0015 | re-seated | the arena field follows main; 0 lever lines lost |
| 0016 | re-seated | block placed after main's WFIRST `#endif` |
| 0017 | re-seated | cluster narrowed beside main's `pdl` line; rule and case seated |
| 0018 | re-seated | 0 lost |
| 0019 | re-seated | 0 lost |
| 0020 | new (package plumbing) | 27 serving-pin rows re-hashed for the files the series edits; r2 re-pins `cuda_batch.zig` and `cuda_mtp_ops.zig` again for its own edits; `pincheck` failing 0 |

## Checks this package has passed

- `patches/main-1ece6e6db/apply.sh --check` on a pristine worktree at the base: `20 patches apply on
  1ece6e6dbbc073582d50738ce8e73e3c3261a73b in order (nothing written)`.
- The applied result is blob-identical to the re-seat tree `f7ef089eb72c22cffc5d5ba4c125aa397e60e333` (12,620 files,
  `git ls-tree -r` against a per-file git blob hash on the build host).
- `scripts/qwen38/zig/target/reseat` chain: every patch is the exact diff between consecutive staged trees; the
  added-line comparison against `patches/main-964174ea05` loses exactly the retired hunks (0005: 4 lines, 0008: 935)
  and the two re-seats' own lines (0003: 2, 0010: 4, 0015: 1 swap), and nothing else.
- `work/upsubmit/MergeMain2/box/pincheck.py`: base `files 169 failing 0`, series `files 169 failing 0`.
- Host gates on Paperclip (x86-64, Zig 0.17.0): see `docs/RESEAT-1ece6e6db.md`, "Gates".
- `scripts/check-patch-packages.sh` (RECORD.md + SHA256SUMS with every patch listed).
