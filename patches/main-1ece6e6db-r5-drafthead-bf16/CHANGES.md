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

Both ways: on the series tree the same test fails with qlinear's `error.FormatMismatch` (the mutant `M1`, the two
guard lines removed). The window mutant `M2` (the recode restored to the function scope) passes the host test,
because the refusals still stand: on host the window is not observable, and the device smoke is its test.

## 4. Gates

- Package: `apply.sh --check` on a pristine `1ece6e6db`: the series and both patches apply, nothing written. On
  spark6 the package applied to a pristine extraction reproduced the shipped tree file for file (manifest
  `dbcebcc68930542595a3c545a71290083bc22819a86998e9314b2774694f6582`, 12,623 files).
- Lean pair, the trees the gate ships: `lean: 230 problems, 230 on the base, 0 new` (pre 230 problems over 7,014
  files, fix 230 over 7,015). The pristine base reads 168; its delta is r5's own and already accepted, so the judged
  comparator is the series tree this package stacks on.
- Paperclip, fixed tree: `zig fmt --check build.zig zig` rc=0, `cuda_common_check.py` rc=0,
  `cuda_fragment_check.py` rc=0, and `zig build -Dfixed-cpu test-flashnext-draft-head-host` rc=0 with
  `Build Summary: 4/4 steps succeeded; 24/24 tests passed`.
- Repo gates: `scripts/check-patch-packages.sh` CLEAN, `scripts/check-python.sh` CLEAN.
- Queued behind another lane's `~/work/host.lock` when this package was written, and not yet reported: `test-cuda-host`,
  `test-gradient-serving`, `test-kernel-contract`, both `compile-config-server` targets, `compile-cuda-tests`
  (aarch64), and the two mutants. Their exit statuses are the ones to read before believing more than the line above.

## 5. Device receipt

The window's four arms (one boot each: `def` the default affine4 head, `bf16`, `bf16n` with the recode off, and
`pre` the series image without this fix) send three short prompts and one ~1,200-token prompt drafted and with
`"draft": false`; `compare.py` requires the `bf16` and `bf16n` replies to equal the `def` arm's on every prompt, the
`bf16` arm to have drafted, and `pre` to refuse by name. Built for it: `tensorfold-qwen38:dhbf16-pre`
(`sha256:826d2c3be1...`) and `tensorfold-qwen38:dhbf16-fix`; the receipt is `~/work/DraftHeadBf16/receipt.tgz` on
spark6 (`out/compare.out`, `out/<arm>/probe.json`, `out/RESTORED`). The arms were still running when this package's
text was written; the mechanism above is source-derived and does not depend on them.

## 6. Revert

`git apply -R` the two patches in reverse order on the series tree, or drop the package. Nothing outside the two
patched files and the pinned fixture row changes.
