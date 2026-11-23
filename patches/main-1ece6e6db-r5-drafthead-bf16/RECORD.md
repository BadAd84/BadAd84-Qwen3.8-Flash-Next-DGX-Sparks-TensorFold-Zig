# RECORD: `main-1ece6e6db-r5-drafthead-bf16`

- **What it is:** two numbered patches, 0026 and 0027, on top of `patches/main-1ece6e6db-r5` (0001-0020). They fix
  one defect the series carries on the FP4 checkpoint: with `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8` set,
  `TF_FLASHNEXT_DRAFT_HEAD=bf16` failed every request with `error (FormatMismatch)` and HTTP 500.
- **Where the text comes from:** ours. The patches are `git diff` between two commits of a scratch clone of upstream
  (`series-ref` = base `1ece6e6db` + r5's twenty patches; `fix-ref` = that tree plus this package's files). No
  external commit, contributor branch or third-party text is carried.
- **Base it applies to:** `ashhart/TensorFold` `1ece6e6dbbc073582d50738ce8e73e3c3261a73b` with
  `patches/main-1ece6e6db-r5` applied. `apply.sh` refuses any other HEAD.
- **The numbering:** 0026 and 0027 follow `patches/main-1ece6e6db-r5-int4-kvtier`'s last patch (0025), because no
  two directories over the same r5 series may share a patch number. Measured, so that a reader does not infer a
  stack that is not there: this package applies on r5 (0001-0020) and does not apply on r5 plus the INT4 and KV-tier
  directory. It stops at `zig/build/cuda.zig:275`, where both packages add a test step to the same block, and 0027
  re-pins the same `zig/tests/fixtures/gradient-serving.tsv` row as that package's 0022. A combined tree needs a
  composition directory of its own, as that package is.
- **The applied-result identity:** measured, not asserted.
  - The shipped tree the device images were built from reads manifest
    `dbcebcc68930542595a3c545a71290083bc22819a86998e9314b2774694f6582` over 12,623 files. That is the previous
    lane's `APPLY base + 22 patches reproduces the shipped tree, file for file`; this lane reproduced the same
    manifest from base plus the twenty-two patches as they stood before this package's one line of later text, so the
    recipe and the number agree.
  - The committed package applied to a fresh extraction of the base reads manifest
    `d9d341a0cafcd072891a88fe211f3deecd28f384fbd3e0346522d384079ee14e` over 12,623 files; its `git` tree, with the
    index built by `git read-tree HEAD` and `git apply --cached` of 0001-0020 then 0026-0027, is
    `3b26c4ee625e61cb27c22a465da10bf3b9726b6a`.
  - `diff -r -q --exclude=.git` between the shipped tree and the applied tree names one content file, `CHANGELOG.md`,
    and nothing else (`receipt/diff-vs-device.txt`). The difference is this package's own bullet, whose placeholder
    `(#9999)` was removed because the package is not upstreamed and no issue exists for the defect. No build reads a
    markdown file, and both device images were built and gated before that edit.
  - The manifest recipe, run at the tree's root:
    `find . -type f -not -path './.git/*' -print0 | sort -z | xargs -0 sha256sum | sha256sum`.
- **The pin row:** `cuda_mtp.zig` sha256 `f4c520b30243387dc0c5765bf65cf2c93132688208f13bff5257f6bb9d92d999` appears once
  in `zig/tests/fixtures/gradient-serving.tsv`, which is what 0027 pins.

| patch | what it carries |
|---|---|
| `0026-draft-head-format.patch` | `cuda_mtp.zig`: the recode window is a block that closes before the draft head loads, one predicate `storedRows`, and its two refusals by name; `cuda_mtp_head_format_test.zig` (new); the `test-flashnext-draft-head-host` step in `zig/build/cuda.zig`; a `CHANGELOG.md` bullet |
| `0027-draft-head-format-pins.patch` | `zig/tests/fixtures/gradient-serving.tsv`: the hash column of 0026's `cuda_mtp.zig` row, as r5's 0020 does |

## Checks

### The package

| check | line it is judged on |
|---|---|
| `patches/main-1ece6e6db-r5/apply.sh --check` | `apply.sh: 20 patches apply on 1ece6e6dbbc073582d50738ce8e73e3c3261a73b in order (nothing written)`, rc 0 |
| this package's `apply.sh --check` | `apply.sh: the series and 2 patches of this package apply on 1ece6e6dbbc073582d50738ce8e73e3c3261a73b in order (nothing written)`, rc 0 |
| `sha256sum -c SHA256SUMS` | `0026-draft-head-format.patch: OK`, `0027-draft-head-format-pins.patch: OK` (`cf3cf19f5b3fa829d2099325ebca9eb594225d13f5412a401af1d0e1eac8ce6d`, `387f54b6754ef7899ac0125122ef8c922fcf70b0778496e5184b008c7c1db697`) |
| `scripts/check-patch-packages.sh` | `check-patch-packages: CLEAN (17 package dirs checked, 1 grandfathered)` |
| `scripts/check-python.sh` | `check-python: CLEAN` |

### Host gates, Paperclip (x86-64, 16 threads, Zig 0.17.0)

Run 2026-11-23 15:27:48Z to 15:52:51Z, under `flock ~/work/host.lock`, on freshly extracted staged trees: the pristine
base, the r5 series, and this package's tree. Every row is the run's own line; the whole log is `receipt/gates.out`.

| step | line |
|---|---|
| the staged archives | `SETUP archives match SHA256SUMS` |
| the trees | `SETUP base files 12601 pre 12622 head 12623` |
| the fix's source and pin | `SETUP head cuda_mtp.zig sha256 f4c520b30243387dc0c5765bf65cf2c93132688208f13bff5257f6bb9d92d999`, `SETUP head pin row 1` |
| lean, each side's own `lean_check.py` | base `6993 files, 168 problems`; series `7014 files, 230 problems`; head `7015 files, 230 problems` (the tool exits 1 on its own findings, so these three are `rc=1 (recorded)`) |
| `lean_new.py`, series against head | `lean: 230 problems, 230 on the base, 0 new`, rc 0 |
| `cuda_common_check.py` | `cuda common: 55 local copies, 0 violations`, rc 0 (`receipt/cuda_common_check.log`) |
| `cuda_fragment_check.py` | `cuda fragments: 2 fragments, 16 includes, 0 misses`, rc 0 (`receipt/cuda_fragment_check.log`) |
| `zig fmt --check build.zig zig` | rc 0, no output |
| `zig build -Dfixed-cpu test-flashnext-draft-head-host` | `Build Summary: 4/4 steps succeeded; 24/24 tests passed`, rc 0 |
| `zig build -Dfixed-cpu test-cuda-host` | `Build Summary: 436/436 steps succeeded; 3551/3581 tests passed (30 skipped)`, rc 0, 569 s |
| `zig build -Dfixed-cpu test-gradient-serving` | `Build Summary: 4/4 steps succeeded; 1/1 tests passed`, rc 0 |
| `zig build -Dfixed-cpu test-kernel-contract` | `Build Summary: 36/36 steps succeeded; 260/260 tests passed`, rc 0, 289 s |
| `zig build compile-config-server` | `Build Summary: 8/8 steps succeeded`, rc 0 |
| `zig build compile-config-server -Dtarget=aarch64-linux-gnu` | `Build Summary: 8/8 steps succeeded`, rc 0 |
| `zig build compile-cuda-tests -Dtarget=aarch64-linux-gnu` (nvcc writes the fatbins in this step) | `Build Summary: 10/10 steps succeeded`, rc 0 |

### The mutants

Both ran on spark5 (aarch64, idle and not serving: `Linux 7.0.0-1019-nvidia-64k aarch64`, 20 cores, Zig 0.17.0) on a
fresh extraction of the same head tree (12,623 files, `cuda_mtp.zig` sha256 `f4c520b302...`), under `flock
~/work/host.lock`. Paperclip's host lock was held by other lanes' suites for the whole period this package was
finished in, and these are two host-test builds (the cold pair reads 13 s and 14 s). The earlier Paperclip attempt, and
the drifted anchor it caught, is in `receipt/gates.out`.

`mutants.py` in this directory is the script both runs used, byte-identical to the copy on the box
(`sha256 c9176b0a4bafa011df9d8aa5f7a36aa54fea16e949154b28ff112001c35aa973`). Each anchor must match exactly once, and
a drifted anchor is a finding, never a silent no-op: the first attempt at `M2` (Paperclip, 15:52) printed `mutate:
window anchor matched 0 times, expected exactly 1` and the runner closed `bad 1`, which is what sent it back.

- **`M1`, the two refusals removed** (the pre-fix behaviour of `Head.init` and `Head.project`, the rest of the fix
  kept). Control: `Build Summary: 4/4 steps succeeded; 24/24 tests passed`. Mutated: rc 1, `23 pass, 1 fail (24
  total)`:
  `error: 'cuda_mtp_head_format_test.test.draft head format: a native projection the drafter's recode changed is
  refused by name' failed: expected error.DraftHeadFormat, found error.FormatMismatch`, at
  `zig/src/cuda/qlinear.zig:224:29` reached from `cuda_mtp.zig:359:13`. The test names the defect's own error, so the
  new step discriminates the guard. Logs: `receipt/m1-spark5.out` (the run), `receipt/m1_guard_removed2.log` (the
  failure), control `receipt/m1_control2.log`.
- **`M2`, the recode window restored to the function scope** (the series' shape, refusals kept). Control: `Build
  Summary: 4/4 steps succeeded; 24/24 tests passed`. The mutation applied both anchors
  (`mutate: window applied ... (2 anchors)`) and changed the source from `f4c520b3...` to
  `4a595717c8e51209002889b5a5a5fc315b488f49a02f3a9a7b319285703f3e12`. Mutated: rc 0, `Build Summary: 4/4 steps
  succeeded; 24/24 tests passed`. That is the finding, not a clean kill: no host test observes the window, because
  `Head.init` needs a CUDA device and the test builds its own `Head`. Logs: `receipt/m2-spark5.out`,
  `receipt/m2_window_restored2.log`, control `receipt/m2_control2.log`.
  The mutation removes the two braces this patch adds and nothing else, so the `defer` returns to `Head.init`'s own
  scope, the series' line 289. The fix's parent commit would also drop the two refusals (which `M1` covers), so the
  two mutants isolate the fix's two changes instead of reverting it whole. The window's own test is the device window
  below, where the unfixed image refuses by name and the fixed one serves.

### The device window (spark6)

Four arms, one boot each: `def` (the default affine4 head), `bf16` (the stored BF16 rows, the arm that failed before
the fix), `bf16n` (the stored rows with the drafter's recode off, the pair that always served) and `pre` (the series
image without the fix). Every arm runs `TF_FLASHNEXT_MTP_WEIGHTS=mxfp8`. Each sends three short prompts and one of
about 1,200 tokens, drafted and with `"draft": false`, every request up to 64 greedy tokens (`receipt/arms.txt` has
the arms, `receipt/probe.py` the prompt set and `receipt/compare.py` the PASS rule; their sha256s `c49e02aa...` and
`8e2e138f...` are the ones the run log records).

| step | line |
|---|---|
| lock and preflight | `LOCKED 2026-11-23T15:39:19+00:00`, `PREFLIGHT lock free mem 35 GiB home 127 GiB` |
| the images, gated by id | `IMAGE-EXISTS tensorfold-qwen38:dhbf16-pre id sha256:826d2c3be1632ed097c60c4fdc93ca947c7eaa70a456c30d7a3a9de032930990 (not rebuilt)`; `...:dhbf16-fix id sha256:cccf2c50491848ff97ebd0dc95711c15c6924f92a425efae7e7d49657067c87d` |
| the three booting arms | `BOOT def ok ... wall 37s`; `BOOT bf16 ok ... wall 37s`; `BOOT bf16n ok ... wall 40s` |
| every arm's drafted reply against its own plain reply | 12 of 12 `WITHIN ... EQ first_diff None` |
| the compare verdict | 28 comparison lines, all `EQ` (the file's other two `CMP` lines are the drafter count and the within total); `CMP bf16 drafter drafted 184 rounds 48`; `CMP within eq 12 differ 0`; `SUMMARY PASS`; `COMPARE rc 0` |
| the unfixed arm | `reason=error (FormatMismatch)`, `"POST /v1/chat/completions HTTP/1.1" 500`, `ARM-FAIL pre (1)` |
| production restored | `RESTORE prod_rc 0 /health 200 2026-11-23T15:43:58+00:00 image tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7`; `PROD-IMAGE ok` |

The receipt is tracked as `receipt/device.tgz`, fetched with
`ssh adam@192.168.99.16 'tar -czf - -C ~/work/DraftHeadBf16 out' > receipt/device.tgz` after the window closed
(`RESTORED 2026-11-23T15:43:58+00:00`, `QUEUE-EXIT driver exit 0`); it holds `compare.out`, `run.log`, and every arm's
`probe.json`, `probe.out`, `server.log` and boot record. `receipt/compare.py`, `receipt/probe.py` and
`receipt/arms.txt` are the window's own scripts, byte-identical to the box's copies. The members were checked against
the box's files (for example `out/compare.out` `b16b328e961c43eb...` and `out/bf16/probe.json` `37a0258c9f5c5f0c...`
on both), and `sha256sum -c receipt/SHA256SUMS` verifies the directory.
The tracked `receipt/compare.py` run over the extracted `receipt/device.tgz` reproduces `compare.out` line for line
(the re-run differs only in the CRLF line endings the Windows Python writes), so the verdict above is checkable from
the package alone.

The box's own `~/work/DraftHeadBf16/receipt.tgz` was written at 15:36, before the last two arms finished, and holds a
partial `out/`; the tracked file is the complete re-tar, and that is the difference between the two hashes.

## What is not proved here

- `compare.py`'s `pre` line is absent from `compare.out`: it judges a refusal only from a probe record, and the
  unfixed arm stopped at the start script's boot smoke test and wrote none. The refusal line quoted above is the
  receipt for that check, and it names the defect's own error.
- `M2` survives the host test by construction, as measured above. The device arms are its test, and they are what
  distinguish the window: with the window closed the `bf16` arm serves, with the series' window the image fails every
  request `FormatMismatch`.
- The `test-cuda-host` line carries `30 skipped`. This record does not attribute them; the gate host has no GPU and
  the line is quoted as it came.

## Retirements

None. No patch of r5 is superseded, no hunk of this package replaces an r5 line except the recode window's own
braces and the pin row it moves.

## Scratch

- Laptop: `work/DraftHeadPkg/RESULT.md` is this lane's report; the pristine worktree and the transfer tarballs beside
  it were removed when the lane closed. `work/DraftHeadBf16/` is the earlier lane's, left as it was found.
- spark5: `~/work/DraftHeadPkg/` held the staged head tree, the two mutant trees and their logs; the logs are tracked
  in `receipt/` and the folder was removed on 2026-11-23 (`~/INVENTORY.md` has the entry and its time).
- Paperclip: `~/work/DraftHeadBf16/gate/` and `~/work/DraftHeadPkg/` held the gate runner, the three staged tarballs,
  five extracted trees, one Zig cache and the logs (7.4 GB); the logs and the receipt are tracked in `receipt/` and
  both were removed on 2026-11-23 (`~/INVENTORY.md` has the removal line).
- spark6: `~/work/DraftHeadBf16/` (box, in, out) and the two images the window built are kept, so the window can be
  re-run. `~/INVENTORY.md` records them. Remove with `rm -rf ~/work/DraftHeadBf16` and
  `docker rmi tensorfold-qwen38:dhbf16-pre tensorfold-qwen38:dhbf16-fix`.
