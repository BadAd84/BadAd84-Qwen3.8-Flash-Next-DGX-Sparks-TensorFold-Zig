# CHANGES: the bf16 draft head keeps its stored rows

## 1. The defect (r5 series: base `1ece6e6db` + 0001-0020)

`TF_FLASHNEXT_MTP_WEIGHTS=mxfp8` (patch 0014) re-codes the drafter's BF16 linears to MXFP8 at load through one module
global, `cuda_projection.recode`, and restores it with a `defer` in `Head.init`'s **function** scope:

- `zig/src/families/flashnext/cuda_mtp.zig:288` `@import("cuda_projection.zig").recode = weights;`
- `:289` `defer @import("cuda_projection.zig").recode = .bf16;`
- `:314` `h.draft = try head_load.draft(gpa, driver, &store, &h.artifact, role);` loads the MTP draft head inside
  that scope, though the comment above the window says it covers "the drafter's own weights only".
- `zig/src/families/flashnext/cuda_mtp_load.zig:27` (the `bf16` role) `return projection.dense(...)`, and
  `zig/src/families/flashnext/cuda_projection.zig:37-39` `switch (recode) { .mxfp8 => return
  @import("cuda_mtp_mxfp8.zig").project(...) }`: the head's stored rows come back as an MXFP8 projection
  (`native.mode == .mxfp8`).
- `zig/src/families/flashnext/cuda_mtp.zig:349-351` `Head.project` wraps whatever `h.draft.native` holds as
  `.{ .bf16 = weight }` for the BF16 proposal lane, and `zig/src/cuda/qlinear.zig:224`
  `if (q.mode != mode) return error.FormatMismatch;` answers on the first drafted request.

So `TF_FLASHNEXT_DRAFT_HEAD=bf16` (keep the checkpoint's rows) was overwritten by `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8`
(a setting for the drafter's own linears), and every request failed `reason=error (FormatMismatch)` with HTTP 500.
The checkpoint is not at fault and there is no geometry mismatch: its `lm_head.weight` is BF16, and the same arm
serves when the recode is off (`TF_FLASHNEXT_MTP_WEIGHTS=bf16`).

## 2. The fix

- `cuda_mtp.zig` `Head.init`: the recode window is now a block that ends after the drafter's own linears (fc_embedding,
  fc_hidden, the hyper-connection mixer and the MTP layer) and before the draft head loads; its `defer` restores
  `.bf16` at that block's exit, an error included.
- One predicate, `storedRows` (`cuda_mtp.zig:250`), names the invariant: a draft head's native projection is the
  stored BF16 coding. It is checked where the head loads (the boot stops with `error.DraftHeadFormat` by name,
  `:323`) and where it projects (`:359`), so neither this path nor a future caller can hand the BF16 lane another
  coding.
- The default path is untouched: `TF_FLASHNEXT_DRAFT_HEAD` unset still selects `affine4` (0007), whose head has
  `native == null` (the predicate passes) and whose Q4 path is unchanged.

## 3. The host test, both ways

`zig/src/families/flashnext/cuda_mtp_head_format_test.zig`, reached by
`zig build -Dfixed-cpu test-flashnext-draft-head-host`: it builds a `Head` whose draft projection is a native MXFP8
one and drives `Head.project`, requiring `error.DraftHeadFormat`; the format check answers before any kernel lookup,
so the test needs no device. A second test pins the predicate over the three codings (MXFP8 refused, BF16 and the
affine4 head passed).

Both ways, measured: on the series tree with the two guard lines removed (the mutant `M1`) the same test fails with
qlinear's `error.FormatMismatch` at `qlinear.zig:224`. With the recode window restored to the function scope (the
mutant `M2`) the host tests pass, because `Head.init` needs a CUDA device and the test builds its own `Head`: on host
the window is not observable, and the device arms are its test (section 5).

## 4. Gates

Real lines, not summaries. The host gates ran on Paperclip (x86-64, 16 threads, Zig 0.17.0), under
`flock ~/work/host.lock`, on freshly extracted staged trees: the pristine base, the r5 series, and this package's
tree. The log is tracked as `receipt/gates.out`.

| step | line it is judged on |
|---|---|
| the staged trees | `SETUP archives match SHA256SUMS`; `SETUP base files 12601 pre 12622 head 12623` |
| the fix's own source and pin | `SETUP head cuda_mtp.zig sha256 f4c520b30243387dc0c5765bf65cf2c93132688208f13bff5257f6bb9d92d999`; `SETUP head pin row 1` |
| lean, each side's own `lean_check.py` | base `6993 files, 168 problems`; series `7014 files, 230 problems`; head `7015 files, 230 problems` |
| `lean_new.py`, base against head | `lean: 230 problems, 230 on the base, 0 new`, rc 0 |
| `cuda_common_check.py` | `cuda common: 55 local copies, 0 violations`, rc 0 |
| `cuda_fragment_check.py` | `cuda fragments: 2 fragments, 16 includes, 0 misses`, rc 0 |
| `zig fmt --check build.zig zig` | rc 0, no output |
| `zig build -Dfixed-cpu test-flashnext-draft-head-host` | `Build Summary: 4/4 steps succeeded; 24/24 tests passed`, rc 0 |
| `zig build -Dfixed-cpu test-cuda-host` | `Build Summary: 436/436 steps succeeded; 3551/3581 tests passed (30 skipped)`, rc 0 |
| `zig build -Dfixed-cpu test-gradient-serving` | `Build Summary: 4/4 steps succeeded; 1/1 tests passed`, rc 0 |
| `zig build -Dfixed-cpu test-kernel-contract` | `Build Summary: 36/36 steps succeeded; 260/260 tests passed`, rc 0 |
| `zig build compile-config-server` (x86-64) | `Build Summary: 8/8 steps succeeded`, rc 0 |
| `zig build compile-config-server -Dtarget=aarch64-linux-gnu` | `Build Summary: 8/8 steps succeeded`, rc 0 |
| `zig build compile-cuda-tests -Dtarget=aarch64-linux-gnu` (the nvcc leg: it writes the fatbins) | `Build Summary: 10/10 steps succeeded`, rc 0 |
| the mutants, both legs (spark5, aarch64, Zig 0.17.0) | `M1` rc 1 with `23 pass, 1 fail (24 total)`; `M2` rc 0 at `24/24 tests passed`; `RECORD.md`, The mutants |
| the package | `apply.sh: the series and 2 patches of this package apply on 1ece6e6dbbc073582d50738ce8e73e3c3261a73b in order (nothing written)`, rc 0 |
| `scripts/check-patch-packages.sh` | `check-patch-packages: CLEAN (17 package dirs checked, 1 grandfathered)` |
| `scripts/check-python.sh` | `check-python: CLEAN` |

The CHANGELOG bullet this patch adds carries no reference number. The package is not upstreamed and no issue exists
for the defect, so the placeholder that stood there was removed rather than invented; the reference goes in when a
PR is opened.

## 5. Device receipt

The window's four arms, one boot each, on spark6: `def` (the default affine4 head), `bf16` (the stored BF16 rows, the
arm that failed before the fix), `bf16n` (the stored rows with the drafter's recode off, the pair that always served)
and `pre` (the series image without this fix). Every arm runs `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8`; each sends three short
prompts and one of about 1,200 tokens, drafted and with `"draft": false`.

Images, gated by id before the window: `tensorfold-qwen38:dhbf16-pre`
`sha256:826d2c3be1632ed097c60c4fdc93ca947c7eaa70a456c30d7a3a9de032930990` (the series without the fix) and
`tensorfold-qwen38:dhbf16-fix` `sha256:cccf2c50491848ff97ebd0dc95711c15c6924f92a425efae7e7d49657067c87d`.

The verdict, `compare.out` (tracked in `receipt/device.tgz`):

    CMP bf16 drafter drafted 184 rounds 48
    CMP within eq 12 differ 0
    SUMMARY PASS

28 comparison lines, every one `EQ` (the file's other two `CMP` lines are the drafter count and the within total): 16
required cross comparisons (the `bf16` and `bf16n` replies against the `def` arm's, drafted and plain, on all four
prompts) and 12 within-arm ones (each arm's drafted reply against its own plain reply, reported and not judged). The
`bf16` arm drafted 184 tokens in 48 rounds, so the equality did not hold because the drafter had stopped. The run
log's own lines: `RUN bf16 sum drafted ids 15 sha 7f05426bd7e4822b`, `RUN def sum drafted ids 15 sha 7f05426bd7e4822b`,
and likewise for `code`, `plan` and `medium`.

The unfixed image refused, on its own boot smoke request, before the window's prompts:

    [tensorfold] ended chatcmpl-3ff2806733a36edf154ecc268f82f68c reason=error (FormatMismatch) prompt=16 tokens=1 after=0.12s
    [tensorfold] 127.0.0.1 "POST /v1/chat/completions HTTP/1.1" 500 -
    [start.sh] ERROR: the smoke test request failed; the server is still running
    ARM-FAIL pre (1)

So `compare.py`'s `pre` line is absent: it judges a refusal only from a probe record, and this arm stopped at the
boot smoke test and wrote none. The refusal above is the receipt, and it names the same `FormatMismatch` the defect
was reported with.

Production was stopped for the window and restored:

    RESTORE prod_rc 0 /health 200 2026-11-23T15:43:58+00:00 image tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7
    PROD-IMAGE ok tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7

## 6. Revert

`git apply -R` the two patches in reverse order on the series tree, or drop the package. Nothing outside the two
patched files and the pinned fixture row changes.
