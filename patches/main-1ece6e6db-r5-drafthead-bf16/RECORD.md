# RECORD: `main-1ece6e6db-r5-drafthead-bf16`

- **What it is:** two numbered patches on top of `patches/main-1ece6e6db-r5` (0001-0020). They fix one defect the
  series carries on the FP4 checkpoint: with `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8` set, `TF_FLASHNEXT_DRAFT_HEAD=bf16`
  failed every request with `error (FormatMismatch)` and HTTP 500.
- **Where the text comes from:** ours. The patches are `git diff` between two commits of a scratch clone of upstream
  (`series-ref` = base `1ece6e6db` + r5's twenty patches; `fix-ref` = that tree plus this package's files). No
  external commit, contributor branch or third-party text is carried.
- **Base it applies to:** `ashhart/TensorFold` `1ece6e6dbbc073582d50738ce8e73e3c3261a73b` with
  `patches/main-1ece6e6db-r5` applied. `apply.sh` refuses any other HEAD.
- **The applied-result identity:** on spark6, the package applied to a pristine extraction of the base reproduced the
  shipped tree file for file (`APPLY base + 22 patches reproduces the shipped tree, file for file`; the tree's
  manifest sha256 is `dbcebcc68930542595a3c545a71290083bc22819a86998e9314b2774694f6582`, 12,623 files).

| patch | what it carries |
|---|---|
| `0021-draft-head-format.patch` | `cuda_mtp.zig`: the recode window is a block that closes before the draft head loads, one predicate `storedRows`, and its two refusals by name; `cuda_mtp_head_format_test.zig` (new); the `test-flashnext-draft-head-host` step in `zig/build/cuda.zig`; a `CHANGELOG.md` bullet |
| `0022-draft-head-format-pins.patch` | `zig/tests/fixtures/gradient-serving.tsv`: the hash column of 0021's `cuda_mtp.zig` row, as r5's 0020 does |

## Checks

<<GATES>>

## Retirements

None. No patch of r5 is superseded, no hunk of this package replaces an r5 line except the recode window's own
braces and the pin row it moves.

## Scratch

- Laptop: `work/DraftHeadBf16/` (this lane's trees, tars, gate and box scripts), removed when the lane closed.
- spark6: `~/work/DraftHeadBf16/` (pkg, in, box, out), recorded in `~/INVENTORY.md`; remove with
  `rm -rf ~/work/DraftHeadBf16`.
- Paperclip: `~/work/DraftHeadBf16/gate/`, recorded in `~/INVENTORY.md`; remove with `rm -rf ~/work/DraftHeadBf16`.
