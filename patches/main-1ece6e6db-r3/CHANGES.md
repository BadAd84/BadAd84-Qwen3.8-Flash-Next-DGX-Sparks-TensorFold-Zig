# `main-1ece6e6db-r3`: what differs from `main-1ece6e6db-r2`

One behaviour changes: **the copy window fails closed.** r2's 0001 raised a verify window to 64 rows and, when the
boot self-check could not run, served those 64 rows with nothing proved; an unprobed width past the proved one can
change tokens, because a wider window's rows are only byte-equal to their one-token steps where the check proved it.
r3 carries the lever in the shape we submitted upstream (PR #4075, branch head `be2dc1a57`, cut from upstream
`3661a4281`): a verify window's rows are the pending-row log's, `batch.late_rows` (48), the shipped width is 32, and a
check that does not run, fails, or proves nothing past 32 leaves the window at 32.

Seventeen of the twenty patches are byte-identical to r2's. `0001` carries the shape, `0007` moves three context lines
because 0001 rewrites the test tail it quoted, and `0020` re-pins the eight rows 0001 moves. `apply.sh` and
`RETIRED.md` are unchanged copies; `SHA256SUMS` is regenerated over all 20 patches.

## The policy, as 0001 now writes it

    pub const max_rows: usize = batch.late_rows;   // 48: the pending-row log's own rows
    pub const base_rows: usize = 32;               // the width the engine ships
    pub var buffer_rows: usize = base_rows;        // the rows a load's buffers hold
    pub var served_rows: usize = base_rows;        // the width a load serves

    bufferWidth(check_runs) -> max_rows only when the boot check runs, else base_rows
    sizeWindow(check_runs)  writes buffer_rows before any window buffer is made
    servedWidth(check_on, proved) -> base_rows unless the check ran and proved a width, clamped to
                                     base_rows .. buffer_rows (so never past the buffers)
    serveWindow(check_on, proved) writes served_rows; window()/bufferRows() read them
    rowsOk(n)               -> 1 <= n <= served_rows, the one verify bound
    probeWidths(rows)       -> serves the buffers' width for the sweep, then every width it holds

The load reads `TF_FLASHNEXT_WINDOW_CHECK` with `try` (default `false`, malformed text refused by name), runs the
probe only for drafts on, a head loaded and `--tp 1`, sizes the buffers before the probe's own draft, and serves the
proved width or 32. `verify` and `verifyMany` refuse through `rowsOk`; a stream's window and its cache rows past the
reply take `bufferRows()`; a draft's layout, its scores, best values and saved rows are sized at `bufferRows()`, and
the draw offsets, the recording device's addresses and the lane's admission assertion follow that layout; the boot
check's own draft is bounded by its layout's rows; the late-log kernels' contract serves the log's 48 rows.

The log lines say what the code does: on a probe that did not run, `the window self-check did not run (...); copy
windows stay at 32 rows`; on a probe that ran, `serving N-row copy windows after the self-check` (only above 32) and
`window self-check: P of Q rows byte-equal to their one-token steps (widths 1-R)`, with `widths 1-R are row-equal at
every row` when some width past the run differs. r2's line `serving 64-row copy windows unprobed` is gone with the
64.

## Exactly what differs, file by file

| file | change |
|---|---|
| `0001-rows.patch` | **the shape**: 15 files, 835 lines. `cuda_mtp.zig` (the five widths, the policy and its two host tests), `cuda_mtp_check.zig` (the sweep at `bufferRows()`, the PR's `windowCheck` guard and `probeServed`), `cuda_lanes_load.zig` (the switch, `sizeWindow`, the probe, `serveWindow`, the log lines), `cuda_lanes.zig` (the served width as `exact_width`, `bufferRows()` for a stream's cache rows, `window()` for the verify guard), `cuda_mtp_ops.zig` (both verifies through `rowsOk`), `cuda_mtp_draft.zig` (layout, scores, best values and saved rows at `bufferRows()`; both byte pins at each width), `cuda_draft_draw.zig` and `cuda_mtp_draw.zig` (candidates and columns at the draft's layout rows), `cuda_mtp_nonfinite_fixture.zig` (the recording device's addresses and its draft's layout), `cuda_lanes_admission_test.zig` (its cache-row assertion follows `bufferRows()`), `zig/tests/cuda/contract_flashnext_late.zig` (the late-log kernels serve the log's 48 rows), `environment.zig` and `environment_test.zig` (the switch's rule and its two valid readings), `build/cuda_fault_host.zig` (`test-flashnext-window-host`), `CHANGELOG.md` (r2's bullet, unchanged). `cuda_batch.zig` is no longer touched: r2's `keep.log == 0` gate on the fused kernel existed because a 64-row window can reach `n >= 64`; at 48 rows a verify window never does, and the PR does not touch that file. |
| `0007-draft-head-4bit.patch` | **context only**: its `cuda_mtp_draft.zig` hunk quoted r2's two `max_rows` pin lines as context; 0001 rewrites that test. The added lines (the appended 4-bit test) and the removed line are byte-identical to r2's, measured. |
| `0020-serving-pins.patch` | **eight rows re-pinned** for the files 0001 moves (table below); the other nineteen rows and the whole row set are unchanged. |
| `apply.sh`, `RETIRED.md` | unchanged copies (the base and the retirement record are the same). |
| `SHA256SUMS` | regenerated over all 20 patches of this package. |

The eight re-pinned rows (`old -> new`):

| row | r2 | r3 |
|---|---|---|
| `cuda_batch.zig` | `8c80e0beb405d477820c04dc400b78237f62678ddeb270e061c35f9754fbe3b3` | `c4e3f9ac9f1292450999560d0f5ce4957cdf9a6baa4cf87e044377aa59e1379b` |
| `cuda_lanes.zig` | `f779ac96814333a6192e1d815d09adec9c4bc5ce14a43c3d93bf07d5f0aa03e1` | `e5d3185d73bb4b68ee76caa236a72a047d736c00f54deb51a53a73d0cccc7a50` |
| `cuda_lanes_admission_test.zig` | `e14f1dd7f236c2ee7be76a1066487c280017af339525ebf94b90067f5efb65d4` | `3f34c402c7f231d088f6b1c876b48265e128b70d4202c8644fbee455f7c5df97` |
| `cuda_lanes_load.zig` | `8c1376018c2a83facd3c7c847d35fa62f097d14bb7f7cb8dfd699818235da1b5` | `18b19ecce27f3e8701caee5ba531ac79ed24399b5e0d870328c5a29d9e417e5a` |
| `cuda_mtp.zig` | `eb23bff52cfd9a7252a8e47e80665820a321af3f84715aa57c0636f96224a267` | `9ba55a30ecefc06a9c8459b87baac78ac2c5d148595e1c15a46e441be79e7a23` |
| `cuda_mtp_check.zig` | `b355dd144302a8cf510059207aacaaf443ec9830ba4baf1cc9a8c87a56a8ccfe` | `fb426202a42133aacb5ae6bd192cf2e3917025eecf2c58634129096326bcbe84` |
| `cuda_mtp_draft.zig` | `e3634cbaae1dac94ddfd9bd3809e38f66e26e0efbccba182048f16f61e6df923` | `ad32587c056ff0a723ad440f08ff6dd33c20811fe8e655d6c5ea1657e789af3c` |
| `cuda_mtp_ops.zig` | `058f3ffdd366bde5edc2744961a17213ba0f3b6e62f9cd94eb00727ccb3495d4` | `c28c14f1ce8d63532bcf70e2aa6ba1951f0e178e33f0930ec888cc8b86947e9b` |

## What 0001 does not take from the PR, and why

| item | r3 | why |
|---|---|---|
| the switch's row scope | `.cuda`, after `TF_QMMF_HALF_BELOW`, as r2 has it (the PR files it in `.flashnext`) | 0004's and 0010's own `environment.zig` hunks quote this line as context; moving it would rewrite three patches for a registration grouping. `read` and `parse` validate the value by the same rule and the same `forms` whichever scope holds it, so a malformed value is refused by name in both. |
| `cuda_batch.zig`'s fused gate | not touched (r2 gated fused on `keep.log == 0`) | a verify window of at most 48 rows never reaches the fused path's `n >= 64`; the PR leaves the file alone, and main's own `if (fused and keep.log != 0) return error.UnexpectedTensor;` is never reached by a window. |
| `cuda_kv_lanes.zig`'s rows past a request | `window_rows = mtp.max_rows` (48) unconditionally | the PR narrows these to `bufferRows()` through one helper in `native/cuda_memory.zig`; the KV pages are patch 0015's lever, and the helper's four call sites are its files. The effect is a pool line that over-grants 16 rows a stream when the check is off: memory, not tokens. |
| `environment_flashnext_test.zig`'s count | unchanged (34 settings, 23 switches) | the row stays in the `.cuda` scope, so the Flash Next family's count does not move. |
| `cuda_mtp_ops.zig`'s `const max_rows` | kept (unused) | 0008's own hunk quotes it as context. |

## Proof that the series still is the same series

- The package applies in order on a pristine `1ece6e6dbbc073582d50738ce8e73e3c3261a73b`: `apply.sh --check` writes
  nothing and reports 20 patches; a full `apply.sh` applies 20/20, and the tree has 92 modified files and 20 new ones.
- `pincheck.py` over the applied tree reads `files 169 failing 0`.
- Against r2's applied tree the package moves **fourteen files**: the twelve sources and build files 0001 edits
  (`cuda_mtp.zig`, `cuda_mtp_check.zig`, `cuda_mtp_draft.zig`, `cuda_mtp_draw.zig`, `cuda_mtp_ops.zig`,
  `cuda_mtp_nonfinite_fixture.zig`, `cuda_lanes.zig`, `cuda_lanes_load.zig`, `cuda_lanes_admission_test.zig`,
  `cuda_draft_draw.zig`, `zig/tests/cuda/contract_flashnext_late.zig`, `build/cuda_fault_host.zig`), `cuda_batch.zig`,
  which r2 edited and r3 leaves at the later patches' bytes, and the serving fixture 0020 re-pins. `CHANGELOG.md`,
  `environment.zig` and `environment_test.zig` are byte-identical to r2's.
- The fail-closed test is in `cuda_mtp.zig` and runs as `zig build test-flashnext-window-host`: it fails on an r2
  tree and passes on this one (`work/SeriesR3/REPORT.md` quotes both), and four mutants of the policy each fail it.

The gate lines for this exact package are in `work/SeriesR3/REPORT.md`; none is claimed here before it exists.
