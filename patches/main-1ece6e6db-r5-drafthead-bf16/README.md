# TensorFold main `1ece6e6db` + r5 + the bf16 draft head's stored rows

Applied on top of `patches/main-1ece6e6db-r5` (0001 to 0020) on a pristine checkout of upstream main at
`1ece6e6dbbc073582d50738ce8e73e3c3261a73b`. It fixes one defect the r5 series carries on the FP4 checkpoint: with
`TF_FLASHNEXT_MTP_WEIGHTS=mxfp8` set and `TF_FLASHNEXT_DRAFT_HEAD=bf16` selected, every request failed with
`error (FormatMismatch)` and HTTP 500.

    ./apply.sh --check TREE     # the series and both patches apply, nothing written
    ./apply.sh TREE             # apply them

| patch | what it carries |
|---|---|
| `0021-draft-head-format.patch` | the fix: the drafter's `TF_FLASHNEXT_MTP_WEIGHTS` recode window closes before the MTP draft head loads, and a draft-head projection in another coding is refused by name (`DraftHeadFormat`) at load and at the projection, with the host test `test-flashnext-draft-head-host` and its build step |
| `0022-draft-head-format-pins.patch` | `zig/tests/fixtures/gradient-serving.tsv`: the hash column of 0021's `cuda_mtp.zig` row, as r5's 0020 does |

## The defect

Patch 0014 (the drafter's BF16 linears re-coded to MXFP8) sets `cuda_projection.recode` and restores it with a
`defer` at the *function's* scope, so the window covered every load after the drafter's linears, the draft head's
included (`cuda_mtp.zig`, `Head.init`). With `TF_FLASHNEXT_DRAFT_HEAD=bf16` the head then asked
`projection.dense` for its stored rows and got an MXFP8 projection back (`cuda_mtp_load.zig`), which
`Head.project` handed to the BF16 proposal lane as if it were BF16; `qlinear`'s own check answered
`error.FormatMismatch` on the first drafted request.

The fix closes the window where the comment always said it ended (the drafter's own linears), and names the
invariant: the draft head's native rows are the stored BF16 ones, checked by one predicate at load and at the
projection.

## Checks

`RECORD.md` has the provenance, the gate table with the exact line each gate is judged on, the mutant runs and the
device receipt (the same prompts on the unfixed and the fixed image, drafted and `"draft": false`).
