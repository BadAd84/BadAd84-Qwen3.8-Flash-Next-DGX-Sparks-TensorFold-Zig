# Rebase of the part-sizing branch onto main 1c9688ca2

Worktree `work/PartFix/tree` (branch `flashnext-head-part-rows-up`), the issue text `work/PartFix/issue.md`,
the PR text built by `work/PartFix/body/` from the fresh gate logs in `work/PartFix/logs/`. Nothing was pushed
and no issue or pull request text was posted.

## The rebase

The branch was one commit on `1587c8cae`, 634 commits behind main's tip `1c9688ca2`. It was re-seated with:

```
git rebase --onto 1c9688ca265d7ad8768a72d4a877bbcc2abf5a5e 1587c8caee631dcc97c8fbb68f4bba353353c4c5
Successfully rebased and updated refs/heads/flashnext-head-part-rows-up.
```

No conflict: the two files the commit touches are unchanged between the old base and the new tip
(`git diff 1587c8cae 1c9688ca2 -- zig/src/families/flashnext/cuda_scratch_sizes.zig
zig/src/families/flashnext/cuda_scratch_sizes_test.zig` is empty). Twenty-two other files under
`zig/src/families/flashnext/` did move on main; none of them touches `part`, `partRows`, the plan's piece,
`streams`, `out_sk`, `fc_sk`, `piece_rows` or `dims`.

- Old head `9a5518ef930f3a63a20bb301437310d956feb64f` (tree `a868b7c295c9088f5598c177398059b27f5866b2`).
- New head `bbbf0d414b5ef05fd291812da2f8d49f0932998e` (tree
  `57dd6467c126e46e1c1d4e19e68094221585679a`), parent `1c9688ca2`, one commit.
- Signed: `git verify-commit HEAD` reports a good signature from `Adam Hillson <adam.hillson@gmail.com>`
  (RSA `84F1F5D7328B1B6FB19B890D6C119F9284D7790F`); author and committer are both
  `BadAd84 <BadAd84@users.noreply.github.com>`, the author date is preserved, and there is no AI
  attribution line.
- Same change: `git patch-id --stable` over the diff is `5838968da6d007d7ac6da939498f759772150daa` before and
  after the rebase, and both touched files are byte-identical between the old and new commits. The diff is
  still 2 files, +133/-2.
- `git merge-tree --write-tree --name-only HEAD 1c9688ca2` writes HEAD's own tree, so main is an ancestor and
  the merge is clean; `git diff --check 1c9688ca2..HEAD` is clean.
- No CHANGELOG bullet: `CONTRIBUTING.md` at `1c9688ca2` carries no changelog requirement (`grep -i changelog`
  finds nothing), the pull request template does not ask for one, and `tools/pr_check.py` keeps it advisory.
  CHANGELOG.md stays main's file entire.
- The branch exists nowhere on the fork (`git ls-remote --heads fork-ssh flashnext-head-part-rows-up` prints
  nothing), which is why rewriting the single commit during the rebase was allowed.

Main moved again after the rebase: at the time of writing upstream main is `6e44558d7` (`212693570`,
`a89d7abc7`, `3aac6181d`, `6e44558d7` on top of `1c9688ca2`), and none of those four commits touches
`zig/src/families/flashnext/` (`git -C tf-atc-full diff --name-only 1c9688ca2 6e44558d7 --
zig/src/families/flashnext/` is empty). The branch is not re-seated now: posting re-seats this one commit on
main's tip, a re-parent of unrelated commits, and re-runs these checks on the re-seated head, as the body's
`Stacked on` line says.

## The constants, read at the new tip

Every constant the fix and its arithmetic depend on, read from the new tip rather than remembered:

| what | at 1c9688ca2 | where |
|---|---|---|
| `partRows` body | `max(2 * cap, out_sk * min(cap, 63))` | `cuda_scratch_sizes.zig` |
| zero slice | `cuMemsetD8Async(part + bytes, ...)` with `bytes = m * w.n * 4` | `cuda_tiles.zig:45` |
| the head's `fc_h` lane | `lane(..., ps.part, streams * m, fc_sk)` | `cuda_mtp_pieces.zig:45` |
| `streams` | 4 | `cuda_prompt_wt.zig:14` |
| `out_sk` | 8 | `cuda_prompt_wt.zig:50` |
| `dims` | 2560 | `cuda_prompt_wt.zig:13` |
| `fc_sk` | 4 | `cuda_mtp.zig:88` |
| `piece_rows` | 256 | `cuda_mtp.zig:90` |
| `max_rows` | 32 | `cuda_mtp.zig:84` |
| `forwardHead` piece | `max(1, min(piece_rows, s.cap / 2))` | `cuda_mtp_ops.zig:135` |
| the plan's piece | the same, on `max(admitted, 32)` | `cuda_mtp_plan.zig:30` |
| `reserveRows` floor | 32 | `cuda_mtp_plan.zig:17` |

None of them moved between the old base and the new tip, so the defect, the fix and the memory table are the
same change they were. Every figure was nevertheless re-derived from these values and from the new gate logs:
`body/figs.py` for the pull request, `body/issue_check.py` for the report.

`partRows` has exactly two readers at the new tip, and both are the same function: the scratch's byte count
(`cuda_batch_state.zig:390`) and the allocation (`cuda_batch_state.zig:437`). No other code sizes `part` or
asserts that it is two cap-stride slices, so the head's term cannot desynchronise a second sizing. A head pass
is still bounded by `piece_rows`: `forwardHead` takes `m = min(piece, next.len)` with `piece <= piece_rows`,
and `forwardHeadMany` refuses a lane over `piece_rows` rows and groups lanes so a group's rows fit the piece.

## The sweep, re-derived on the new trees

The head test was compiled and run on both trees on Paperclip:

- Control, the branch: no `part rows:` line anywhere in the log, and the module's binary ran 316 of 316.
- Mutant, the base commit's `partRows` body with the branch's test: rc 1, and the log carries
  `part rows: the head's fc_h lane over a pass is short at 896 caps, 128 to 1023`,
  `part rows: first cap 128 needs 512 rows, partRows gives 504`, `expected 0, found 896`.

So the sweep still fails on main and passes with the fix at the new tip, with the numbers the report states.
The report's own figures are checked by `body/issue_check.py` (14 phrases, 0 missing) and its numbers mutated
one at a time by `body/issue_mutate.py` (25 caught, 0 survived).

## Gates

Every gate ran on Paperclip from two fresh `git archive` extractions that were checked blob by blob against
their commits (`body/archive.py`: 13476 of 13476 and 13477 of 13477 tree blobs, 0 mismatches) and then checked
by sha256 against the manifests made from those tars on the box (rc 0 for both, 13476 and 13477 files). Every
step ran under `flock -w 14400 ~/work/host.lock` with `umask 022`; the Zig local cache was shared between the
control and the mutant, so only the module's own test binary is rebuilt for the mutant. The box was also
running another lane's builds while these ran, so the walls below are under shared load.

The lean pair is CI's own step: the head's `tools/zig/lean_check.py` is copied into the base tree first (both
copies are `a08d2a424e01b16a488c2684afbac4e9f7284df4b500c546641c19a2158659ce`), so both sides run one checker.
Both runs exit 1 on the trees' standing findings, and the gate is the pair.

| gate | rc | wall | what it said |
|---|---|---|---|
| base tree, `lean_check.py` | 1 | 3 s | `7684 files, 165 problems` (standing) |
| head tree, `lean_check.py` | 1 | 2 s | `7685 files, 165 problems` (standing) |
| `lean_new.py <base log> <head log>` | 0 | 0 s | `lean: 165 problems, 165 on the base, 0 new` |
| `zig fmt --check build.zig zig` | 0 | 2 s | no output |
| `python3 pincheck.py <tree>/` | 0 | 0 s | `files 169 failing 0` |
| `python3 tools/zig/cuda_common_check.py` | 0 | 0 s | `cuda common: 55 local copies, 0 violations` |
| `python3 tools/zig/cuda_fragment_check.py` | 0 | 1 s | `cuda fragments: 2 fragments, 15 includes, 0 misses` |
| `python3 -m unittest discover -s tools/zig -p cuda_common_check_test.py` | 0 | 0 s | `Ran 9 tests` |
| `python3 tools/test_pdl_early_loads.py -v` | 0 | 0 s | `Ran 17 tests` |
| `zig build test-flashnext-mtp-plan-host` | 0 | 3 s | `Build Summary: 3/3 steps succeeded; 3/3 tests passed` |
| `zig build test-cuda-host` | 0 | 222 s | `Build Summary: 474/474 steps succeeded; 8655/8697 tests passed (42 skipped)`; the module's binary 316 of 316 |
| the same on the mutant tree | 1 | 201 s | `Build Summary: 472/474 steps succeeded (1 failed); 4918/4950 tests passed (31 skipped, 1 failed)`; the failure is the sweep, `expected 0, found 896` |
| `zig build test-environment-host` | 0 | 0 s | success |
| `zig build -Dfixed-cpu test-gradient-serving test-qwen-serving-host` | 0 | 3 s | success |
| `zig build -Dfixed-cpu test-kernel-contract` | 0 | 289 s | success (the planted controls report red, rc 0) |
| `zig build -Dtarget=aarch64-linux-gnu compile-config-server` | 0 | 243 s | `Build Summary: 8/8 steps succeeded` |
| `zig build -Dtarget=aarch64-linux-gnu compile-cuda-tests` | 0 | 176 s | `Build Summary: 10/10 steps succeeded` |
| `zig build -Dnvcc=<toolkit>/bin/nvcc compile-cuda-tests` | 0 | 629 s | `Build Summary: 183/183 steps succeeded` |
| `zig build -Dnvcc=<toolkit>/bin/nvcc -Dtarget=aarch64-linux-gnu compile-cuda-tests` | 0 | 597 s | `Build Summary: 183/183 steps succeeded` |
| `zig build -Dnvcc=<toolkit>/bin/nvcc -Doptimize=fast fatbins install native` | 0 | 963 s | `Build Summary: 367/367 steps succeeded` |

`tools/pr_check.py --base <base>` needs git objects, so it ran from the branch's own worktree on the laptop
(one of the light Python tools the workstation rule allows locally): rc 0 in 11 s, `merge base
1c9688ca265d7ad8768a72d4a877bbcc2abf5a5e; 2 changed files; lean 165 vs 165, 0 new`, 0 error(s), 1 warning(s),
the warning being its `--pr NUMBER` CHANGELOG advisory. Its lean pair agrees with the box's lean pair.

The figure checks on the finished texts: `mkbody.py` placed 107 figures with 0 unresolved and 0 derived but
unused; `checkbody.py` verified 94 phrases with 0 missing and 0 hygiene hits; `mutate.py` corrupted each of
the 107 figures in turn and the checker caught 107 with 0 surviving; `issue_check.py` verified 14 phrases with 0
missing and `issue_mutate.py` caught 25 number mutations with 0 surviving. The mutation runners share one
temp file per target, so they must not run concurrently: two overlapped runs once reported 96 caught and 2
survived, and both survivors were that temp file being unlinked under one checker; the single-threaded
re-runs above are 107/0 and 25/0. The final single pass, with the body's and the report's shas, is logged in
`logs/text_checks.txt` (every rc 0).

## The ATC snapshot

`atc overlap --json` was run by Main on this head (`npx --yes github:ashhart/ATC overlap --json`, rc 0 in 46 s)
from the full clone `C:/Users/Adam/Gitea/tf-atc-full` after fetching main; the output is `atc_overlap.out`. The
clone's `origin/main` was fetched to `6e44558d7` at 09:05:31 and the artifact was written at 09:06, so the
comparison base was `6e44558d7`, whose merge base with this head is `1c9688ca2`, which is why the snapshot
reports `changedFiles: 2`. The snapshot is partial: `complete: false`, limitations `otherPullRequestsLimit`,
`pullFilesUnavailable`, `pullRequestsLimit`, `timeLimit`.

Its 41 entries are all open pull requests: 8 carry `conflicts`, 2 are `clean` and 31 are `unknown` because the
tool's `pullFilesUnavailable` limitation left their file lists unread. Every entry's `sharedFiles` count is
against `myPullRequests: [3218]`, an existing open pull request of the owner's that the tool attached this work
to (this branch has no pull request yet), so those counts are not this change's files.

`check_overlap_all.py` measured the entries again through the GitHub API's paginated file lists: for all 41 open
pull requests, every list is non-empty and none contains either of our two files (`sharing_ours: 0`, output
`atc_check.json`). So the 8 conflicts are in files this change does not touch and there is nothing to coordinate.
`figs.py` reads `atc_check.json` for the body's ATC figures and cross-checks it against the branch: the merge
base is the gated base, the changed-file count is the diff's 2, the verdicts sum to the entries, every entry is
open, and the shared count is 0.

## What changed in the prose, and why

Pull request body (`body/pr-body.in.md`, regenerated into `body/pr-body.md` by `mkbody.py`):

- Base, head and head tree follow the rebase: `1587c8ca...` -> `1c9688ca...`, `9a5518ef...` ->
  `bbbf0d41...`, `a868b7c2...` -> `57dd6467...`; the old merge-tree sentence left the body (see below).
- Lean pair `7357 files, 167 problems` and `7358 files, 167 problems` -> `7684 files, 165 problems` and
  `7685 files, 165 problems`; the new-findings line `167 problems, 167 on the base, 0 new` ->
  `165 problems, 165 on the base, 0 new`. Main fixed two standing findings since the old base.
- Test totals re-derived from the new logs: the module's binary 2 of 2 -> 316 of 316 (the old figure came from
  the first all-pass `run test` line in the log, which is a different binary; the new derivation pins the
  control's count to the total of the binary that fails on the mutant), mutant 310 pass 1 fail of 311 ->
  315 pass 1 fail of 316, control summary `442/442` and `7962/8005` -> `474/474` and `8655/8697 (42 skipped)`,
  mutant summary `440/442` -> `472/474 (1 failed)` and `4918/4950 (31 skipped, 1 failed)`. The skip and fail
  counts are now quoted rather than dropped.
- Gate walls are the new runs: 205 -> 222, 191 -> 201, 2 -> 3, 288 -> 289, 235 -> 243, 170 -> 176,
  1,044 -> 629, 817 -> 597, 1,085 -> the new fatbins wall. Every rc is unchanged (0, except the mutant's
  intended 1 and the lean pair's standing 1).
- The nvcc rows now quote their `Build Summary` step counts, as the other compile rows do.
- A `pr_check` row was added, with its merge base, changed files, lean pair, error and warning counts.
- The sweep line said `1 caps short after the change`; it now says `0 caps short after the change` and names
  the write ranges it counts. Why: the old figure came from a probe that started at cap 1 and used the piece
  formula without the plan's `max(cap, 32)` floor, so it counted cap 1, where no head pass ever runs
  (`reserveRows` floors the scratch at 32). The test sweeps from 32 and asserts zero, and the new figure is
  derived over the test's own caps.
- The environment bullet said a GB10 machine ran the host gates; the gates ran on a CPU-only x86_64 host with
  16 threads, so it now says that, and keeps nvcc 13.3 for the x86_64 and aarch64 CUDA compiles. No GPU work
  took place on any machine.
- The issue bullet now carries the literal placeholder `Fixes #<ISSUE>` and says that the report's number
  replaces it, because no issue exists yet; a read-only `gh search issues` re-run today finds nothing for the
  six search terms except #2715, the DeepSeek-V4.1 bit-repeatability report.
- The `atc overlap --json` bullet was replaced with the measured snapshot: the base it compared against
  (`6e44558d7`, whose merge base with this head is the gated base), the four limitations and `complete: false`,
  the 41 entries split 8 `conflicts` / 2 `clean` / 31 `unknown`, the plain statement that none of those
  conflicts touches this change (all 41 file lists measured through the GitHub API) rather than the
  "no open change here touches" claim, and the tool's attachment of the work to pull request #3218, which is
  why its per-entry `sharedFiles` are not this change's.
- The `Stacked on` bullet now names `1c9688ca2` as the gated base, and says that main's commits since are
  outside `zig/src/families/flashnext/` and that posting re-seats this commit on main's tip and re-runs the
  checks on the re-seated head.
- The old "a merge of head and main writes tree ..." sentence was removed from the body because main is no
  longer the gated base; the fact it carried is now a derived check (`merge_clean`, which fails unless a merge
  with the gated base writes HEAD's own tree).
- The "Not run" bullet no longer lists `atc overlap --json`: it was run, and only the device run remains
  unrun, with the snapshot to be re-run at posting.

The issue text (`issue.md`):

- The version line named `1eed88bb0` and `1587c8ca`; it now names `1c9688ca2`, the base of the branch and the
  tip every constant was read at. The constant list repeated in that line was removed because the same
  constants are enumerated once, in the arithmetic paragraph.
- The sweep bullet gains the far-cap domain the host test also checks (4,096 to 262,144, where the term is
  inert).

## What did not change

The constants, the arithmetic (512 against 504 at 128, 2,048 against 2,046 at 1,023, fitting from 1,024,
896 caps from 128 to 1,023), the memory table (a row is 10,240 bytes; 65,536 rows and 671,088,640 bytes at
32,768; the largest cost 15,728,640 bytes at a 256-row scratch), the diff, the device statements and the
checklist. The commit message needed no change: every figure in it is one of the above and all of them were
re-derived.

## Not done

Nothing was pushed, no remote branch was created, and no issue or pull request text was posted; `gh` was used
read-only for the issue search and for the ATC entries' file lists. `atc overlap --json` was run by Main and its
snapshot is recorded above; no device run was made.

## Cleanup

The box's scratch (`~/work/PartFix`, 9.8 GB: the two tars, both extracted trees, the Zig cache, the mutant and
the installed prefix) was removed after the logs were pulled back; nothing was installed on the box. In this
work dir the pre-rebase scratch was removed (the old head's `tree.tar`/`tree.manifest`, the scripts that read
them, the stale `run2.out` and the previous toolkit-path failure logs); the current record is `base.tar` and
`tree2.tar` with their manifests, `rebase_extract.sh` and `rebase_all.sh` with `logs/`, and `body/` with its
figures and checkers. The ATC record is `atc_overlap.out` (the tool's output), `atc_check.json` with the
per-pull-request file check from `check_overlap_all.py`, and `parse_overlap.py` (Main's parser). The old local
branch ref `pre-rebase-backup` was deleted; the pre-rebase head is
`9a5518ef930f3a63a20bb301437310d956feb64f` as recorded above.
