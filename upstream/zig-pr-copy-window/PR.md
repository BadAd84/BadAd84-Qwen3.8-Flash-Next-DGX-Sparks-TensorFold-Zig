# Upstream PR (not posted): patches/0013: 64-row copy windows for a lone stream

Target: MiaAI-Lab/Qwen3.8-Flash-Next-Single-DGX-Spark-TensorFold, base `364f21a` (release 1.0.0).
Evidence: lane w2-fable (`~/work/lanes/w2-fable/README.md`, holds hold1-hold7, images `w2-fable-wide*`), merged image `zmerge1` (`merge/mverify.sh`, `mverify2.sh`), `docs/ZIG-SPEED-CAMPAIGN-2026-10.md`. Clean stack: spark6 `~/work/zpr/` (patches/, tf = 0001-0020, image `tensorfold-qwen38:zpr-stack`, host tests `test-stack.log`).

---

**Title:** patches/0013: 64-row copy windows for a lone stream (file copies 2.3x, one-line edits +84%, replies byte-identical)

**Body:**

## Description and Motivation

A lone stream's verify window held 16 rows: the pending token and 15 drafts, whether the drafts came from
the MTP head or were copied from the context (a file being rewritten, a verbatim repeat). A copy that lands every row
could only grow 15 at a time.

`patches/0013-flash-next-copy-window.patch` separates the window from the MTP chain:

- `cuda_state.max_rows` and `cuda_lanes.max_rows` 16 -> 64, with every host array sized by them following (held
  rows, ids, the sampler's scratch, `Round.held_stride`, the draw tables). A prompt burst stays at `state.ends` (16)
  prompts.
- `Engine.Options.window` / `TF_FLASHNEXT_WINDOW` (depth + 1 .. 64; 64 when unset): the decode buffers hold
  `max(8, streams x (depth + 1), window)` rows (128 at `PARALLEL=8`, as before) and each sequence keeps `window`
  speculative rows past the context.
- The lanes keep `depth` (the head's chain, `TF_FLASHNEXT_DEPTH`) and `window` apart: the round planner's copy ramp
  still starts at 15 rows and now grows 15 -> 31 -> 63, the head still drafts 15 at most, and the planner's cost
  table is still timed for 1..16 rows. Shared rounds (two or more clients) still copy 15 rows (`0015` changes that).
- The server's boot log says `copy windows: a lone stream verifies up to 64 rows ...`; the window is part of the
  two-rank settings agreement.

Why the replies do not change: copies are drafts, verified row by row like the MTP head's, and every row kernel is
row-invariant (shared rounds already run 17..128 rows through the same kernels).

Measured on one DGX Spark through the recipe's own server: arms interleaved, one boot and one pass an arm per cycle, the order reversed each cycle. Greedy, thinking off, per-request decode tok/s from the client (512-token replies unless a row says otherwise). Every arm ran with `patches/0010` and `0011` and the MTP FP8 overlay (#35, #36) and `TF_FLASHNEXT_CONFIDENCE=-0.15` (#34). One client, lane image (the wide window on the stock engine), one hold (hold5: a warm-up boot first, then the
arms interleaved):

| 1 client, tok/s | stock (16 rows) | 64-row windows |
| --- | ---: | ---: |
| verbatim copy of a file | 327 | 763-766 |
| one-word rewrite | 266 | 411-412 |
| four-word rewrite | 151 | 156 |
| a rename to a longer name | 256 | 409-411 |
| a one-line code edit | 275 | 506-510 |

Prose and code decode at one and two clients stayed within 1% (28/28 decode replies identical), with the same round
counts at four clients (engine only, `bench-many --streams 4`: 51.2 vs 51.6 ms a round on prose, 57.0 vs 57.2 on
code). The same binary with `TF_FLASHNEXT_WINDOW=16` measured as stock (copy 330, rewrite 267). Merged build (with
`0012` and `0017`): verbatim copy 325-328 -> 755-765 tok/s, one-word rewrite 265-267 -> 410, prose and code decode at
1-4 clients equal.

Cost: a copy-heavy request captures two more window widths at both parities (32/64-row main graphs, 31/63-row MTP
steps), ~40-60 ms once. The round cost grows with the rows (16 rows ~51 ms, 64 rows ~100 ms a round on one stream), so
the planner only widens a copy that keeps landing. The lane also timed every width past 16 at boot for its log
(+4 s); the patch here drops that diagnostic.

## Related Issues

None.

---

## Testing

- Golden replies (six greedy prompts, `temperature: 0`, fixed seed) byte-identical to the stock image on every boot of every hold quoted here. Every copy, rewrite, rename and edit reply had one sha across every arm and image, and all
  28 decode-matrix replies were identical to the stock image's (34 boots in seven holds).
- Host test (`cuda_lanes.zig`): a window wider than the head's chain prices the chain's rows only; the lanes report
  `exact_width` = the window, `drafts` = the depth, the ramp's first width from the head's window.
- The patch here is the measured code with the campaign's experiment-only switches taken out (named above). The whole stack, `patches/0001`-`0020`, applies with `git apply` in order on TensorFold `db281878`, builds the image's engine (`zig build -Doptimize=fast fatbins install native` with nvcc in the build image), and passes `zig build test` (21/21 steps, 189/189 tests).
- `bash -n start.sh stop.sh scripts/*.sh`; `python3 -m py_compile tools/*.py`; shellcheck adds no finding.
- Memory: each sequence keeps 64 speculative rows past the context instead of 16 (48 rows: under 1 MiB of FP8 cache a
  sequence); the decode buffers stay at 128 rows at `PARALLEL=8`.

Other PRs from me in this batch: #34 (the one-Spark draft stop default), #35 (`patches/0010`), #36 (`patches/0011` + `MTP_FP8`), and #[0012's PR] (n-gram host gather), #[0014's PR] (copy re-sync and ramp), #[0015's PR] (copies in shared rounds), #[0016's PR] (sequence pool and graphs), #[0017's PR] (batched draft draws), #[0018's PR] (fused FP8 split-K and lm_head row tiles), #[0019's PR] (decode read-out fusion), #[0020's PR] (draft stop lines). `patches/0012`-`0020` are one stack written in that order on top of `0001`-`0011`: each applies with `git apply` after the ones before it (several edit the same lines of `cuda_engine.zig`), so this PR's patch needs #35, #36 and #[0012's PR] merged first (logically it needs none of them). All twelve add CHANGELOG/README/CREDITS lines in the same places, the patch PRs each add a row to the same new patch table (as #35 and #36 do), and the setting PRs add `scripts/config.sh` lines after `TF_FLASHNEXT_PREFILL_TAIL`; whichever merges second, I rebase.

---

## Checklist:

- [x] I have read the README and `scripts/config.sh` and kept my changes consistent with them.
- [x] My pull request has a sound title and description (not something vague like `Update README.md`).
- [x] My change is reproducible and verified (script syntax check, `scripts/prepare.sh`, a launch, or a re-measurement).
- [x] A patch change keeps every reply byte-identical, and I said how I checked it.
- [x] I updated the README and/or `scripts/config.sh` if a setting, default, or measured number changed.
- [x] If my change affects memory, I checked the startup estimate still fits the budget at the default 5 x 262,144 int8 setting.
- [x] Defaults in `scripts/config.sh` still work out of the box; a new setting has a sane fallback like the existing ones.
