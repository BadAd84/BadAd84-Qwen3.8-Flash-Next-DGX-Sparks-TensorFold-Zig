# `main-1ece6e6db-r2`: what differs from `main-1ece6e6db`

This package is `patches/main-1ece6e6db` with one defect fixed. Nineteen of its twenty patches are
byte-identical to the first package's; `0008` carries the fix, `0010` carries a one-line context refresh that the fix
forces, and `0020` carries the two pins the fix moves.

## The defect, as measured

`0008-shared-direct-head-piece.patch` adds `forwardHeadPieces`, which takes `TF_FLASHNEXT_HEAD_PIECE` rows a pass and
bounds the piece by half the pass's scratch cap (`piece = min(piece_max, s.cap / 2)`). The head's `fc_h` lane then
calls `cuda_tiles.matmul` for `streams * piece` rows at `sk = 4`; with a native weight and `sk > 1` that call writes
one fp32 slice into `part` and **clears the slice beside it**, so it needs `2 * streams * piece` rows of `part`. The
first package sized `part` as `partRows(cap) = max(2 * cap, out_sk * min(cap, 63))`, which holds only `2 * cap` rows
for caps of 63 and up, so the piece had to be at most `cap / 4` and ran `cap / 2`.

Measured on the s-series tree (main `1ece6e6db` + the first package's 0001-0020) on spark6, with the labelled memset
check naming the site:

```
error: cuMemsetD8Async@tiles.matmul part=0xef20dae00000 bytes=62914560 m=6144 sk=4 n=2560 prompt=false:
CUDA_ERROR_INVALID_VALUE (1) invalid argument
```

`bytes` = 6144 x 2560 x 4 = 62,914,560, exactly the size of `part` at cap 3,072 (6,144 rows of 2,560 fp32), and the
call clears at `part + bytes`, i.e. starting at the end of the allocation. The prompt is the resume probe's 8,607
tokens, which reserves a 3,072-row scratch; the recipe's `scripts/config.sh:133` exports
`TF_FLASHNEXT_HEAD_PIECE=1536`, so the piece was 1,536 rows and `streams * piece` = 6,144. The failure is dtype
independent (bf16 KV fails too), is not `PROMPT_SYNC`, and is not the prompt cache.

Main itself has the same overrun in the same line at its own 256-row bound, for a pass whose cap lands in **128 to
1,023** rows (a prompt of roughly 128 to 1,023 tokens with drafts on): `2 * 4 * 256 = 2,048 > partRows(cap)` below cap
1,024. The first package's `cap / 2` bound makes that fire at every prompt above about 126 tokens instead.

## The fix

**`partRows` is sized for its widest consumer** (FIX-NOTES option 1), and the requirement is asserted where it is
used (option 3's guard):

    partRows(cap) = max(2 * cap, out_sk * min(cap, 63), 2 * streams * (cap / 2))

The third term is exactly the `fc_h` lane's need at a piece of `cap / 2`: `2 x 4 x (cap / 2)` rows. It leaves the
out projection's two cap slices and the legacy tile's floor untouched, and it fixes main's own 128..1,023 hole as
well. `cuda_mtp_pieces.zig` returns `error.UnexpectedTensor` before the lane call when `2 * streams * m` exceeds
`partRows(s.cap)`, in both the single-piece (`Piece.run`) and grouped (`Group.run`) passes, so a future piece change
fails by name instead of as a CUDA invalid value.

**Memory cost, measured at cap 3,072:** `part` grows from 6,144 rows to 12,288 rows of 2,560 fp32, i.e. from
62,914,560 bytes to 125,829,120 bytes: **+62,914,560 bytes (60 MiB)** on the one pass scratch, and the same delta in
`Scratch.bytes`, which the engine's memory accounting reads. At the decode caps (48-64 rows) the term is
`2 x 4 x 24..32`, under the legacy tile's 8 x cap floor, so nothing grows there.

**Why not the alternatives.** Bounding the piece by `cap / 4` (option 2) makes `TF_FLASHNEXT_HEAD_PIECE=1536` a no-op
at cap 3,072 (the piece becomes 768), which replaces the measured lever with an unmeasured one and still leaves main's
own hole. Giving `fc_h` its own part (option 3) costs a second buffer of the same 120 MiB beside the existing 60 MiB
and new allocation/copy plumbing; its guard is kept here without the buffer.

## Exactly what differs, file by file

| file | change |
|---|---|
| `0008-shared-direct-head-piece.patch` | **the fix**: `cuda_scratch_sizes.zig`'s `partRows` third term; `cuda_mtp_pieces.zig`'s two guards; the `part` docblock and the `piece` bound's comment; a new host test `cuda_part_rows_test.zig` (imported from `cuda_batch.zig`'s test block, runnable as `zig build test-flashnext-part-rows-host`, and part of `zig build test` through the module's own suite); the build step `zig/build/cuda.zig`; the CHANGELOG bullet's part-sizing clause |
| `0010-round-cost.patch` | one context line in its `CHANGELOG.md` hunk, because 0008's bullet grew: its own added lines are unchanged |
| `0020-serving-pins.patch` | two re-pinned rows for the two pinned files 0008 changes: `cuda_batch_state.zig` `f94fe83b1646...` -> `b0475f008783...`, `cuda_mtp_ops.zig` `641407742f68...` -> `058f3ffdd366...` |
| `apply.sh`, `RETIRED.md` | unchanged copies (the base and the retirement record are the same) |
| `SHA256SUMS` | regenerated over all 20 patches of this package |

Everything else, including the other seventeen patches and their pins, is byte-identical to
`patches/main-1ece6e6db`.

## Proof that the series still is the same series

- The package applies in order on a pristine `1ece6e6dbbc073582d50738ce8e73e3c3261a73b`: `apply.sh --check` writes
  nothing and reports 20 patches; a full `apply.sh` on a fresh clone applies 20/20.
- The applied tree's manifest against the bisect window's verified `s-series` manifest (12,620 entries): **7 entries
  changed and 1 added** (12,621 total) - exactly the files in the table above plus the new test file. No other blob
  moved, so the image built from this package differs from the measured s-series image only in the fix.
- `pincheck.py` over the applied tree reads `files 169 failing 0`.

## The host test, and what it holds

`zig/src/families/flashnext/cuda_part_rows_test.zig` computes, not fits:

- the measured failure's arithmetic: cap 3,072, piece 1,536, `need = 2 x 4 x 1,536 = 12,288` rows, the old
  `partRows` 6,144 (strictly less: it fails), the new `partRows` 12,288 (it holds);
- main's own 256-row bound over every cap 1..4,096: the first cap the old buffer overruns is **128** and the last is
  **1,023**; cap 127 fits the old buffer exactly and cap 1,024 fills it exactly;
- the recipe's piece on the caps a serve meets (32, 48, 126, 512, 1,024, 2,048, 3,071, 3,072, 4,096), and that the
  legacy floor at cap 63 is still 504 rows.

**Where the test hangs, and why.** It is imported from `cuda_batch.zig`'s test block, not from `cuda_batch_state.zig`'s.
The flashnext module's root (`cuda_launch.zig`) collects tests from files it names in its own test blocks
(`_ = prompt.batch`, `_ = @import("cuda_batch_kernels.zig")`, ...), and `cuda_batch_state.zig` is not among them: an
import placed in its test block compiles and runs nothing (measured: the step's log was empty and the pre-fix mutant
survived). `cuda_batch.zig` is collected (`_ = prompt.batch`), so the test runs there.

Run on the first package's 0008 code it fails on `need > partRows(cap)`; on this package it passes. The gate table
below records both runs.

## Gates

Measured on this package (2026-11-21):

| gate | result |
|---|---|
| `apply.sh --check` on a clone at `1ece6e6dbb...` | `apply.sh: 20 patches apply on 1ece6e6dbbc073582d50738ce8e73e3c3261a73b in order (nothing written)`, rc 0, `git status` clean |
| full apply, then `pincheck.py` | 20/20 applied; `files 169 failing 0` |
| applied-tree manifest against the verified r1 `s-series` manifest | 7 changed + 1 added (12,620 -> 12,621), the files in the table above; no other blob moved |
| `zig build test-flashnext-part-rows-host` (the new step; also runs upstream's default-chunk scratch ceiling) | the mutant of `partRows` (pre-fix formula) must fail on `need > partRows(cap)` and the fixed tree must pass; the lane's gate log and the exact rcs are recorded in `work/SeriesFix/RESULT.md` section 4 |

The Paperclip host and nvcc gates for this exact package (fmt, `test-environment-host`,
`test-gradient-serving test-qwen-serving-host`, `test-kernel-contract`, `compile-config-server` and
`compile-cuda-tests` for aarch64, `compile-cuda-tests` with nvcc, and `fatbins install native`) were queued behind
another lane's build lock when this package was written; their lines are appended to `work/SeriesFix/RESULT.md`
section 4 as they land, and none is claimed here before it exists.
