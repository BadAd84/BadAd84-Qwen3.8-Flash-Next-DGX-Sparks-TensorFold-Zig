---
name: run-atc-overlap-for-tensorfold-prs
description: "Run TensorFold's mandatory pre-PR ATC overlap check (atc needs node+gh; runs on the laptop via .cmd files against a full, freshly fetched clone)"
---

# Run the ATC overlap check for a TensorFold PR

TensorFold's CONTRIBUTING requires `atc overlap --json` before opening any PR. The `atc` CLI needs
Node 22.16+, git 2.38+ and an authenticated `gh`. spark6 has none of these; the LAPTOP has all three
(`gh auth status` = BadAd84), so run it there.

## Setup (once)
- Full clone `C:/Users/Adam/Gitea/tf-atc-full` (https://github.com/ashhart/TensorFold.git).
  A blobless clone (`--filter=blob:none`) BREAKS it: `workingTreeUnavailable`, `changedFiles: null`,
  every conflict reads `unknown` with 34+ bogus overlaps. Use a full clone.

## Per check
0. **Fetch main first, inside the clone.** A clone whose `main` was last fetched weeks ago compares an
   up-to-date branch against an ancient base: `changedFiles` came back 3593 for a 2-file branch and every
   conflict read `unknown`. `git fetch origin main`, then assert two things before believing anything:
   `git merge-base origin/main <branch>` equals the branch's stated base, and `changedFiles` equals the
   branch's real file count (`git diff --name-only <base> <branch> | wc -l`).
1. Write a `.cmd` file (WSL bash CANNOT invoke `npx.cmd` directly - "The system cannot find the path
   specified"); point it at the full clone, fetch the port branch, check it out, run atc:

   ```bat
   @echo off
   cd /d C:\Users\Adam\Gitea\tf-atc-full
   git fetch C:/path/to/branch/repo <sha>
   git checkout -q -B atc-<name> FETCH_HEAD
   npx --yes github:ashhart/ATC overlap --json
   ```

2. `cmd.exe /c "C:\\Users\\Adam\\atcoverlap.cmd" > atc.json 2>atc.err`
   (~50-60 s; the JSON lands after a git-fetch progress line).

## Parse
- The output has log text before the JSON: slice from the first `{`.
- `changedFiles` (int) confirms the tree was read. `overlaps[]` carries `pullRequest`,
  `sharedFiles`, `conflict`: `conflicts` = hard merge conflict (git merge-tree found a real clash),
  `unknown` = not computed, `clean` = no clash.
- **Intersect each conflicting PR's files with YOUR changed files**
  (`gh pr view N --repo ashhart/TensorFold --json files -q '.files[].path'` versus
  `git diff --name-only <base> <branch>`). A conflict whose shared files do not include one of yours is
  that PR's own business with main, not a conflict to coordinate. A conflict whose only shared file is
  `CHANGELOG.md` is the ordinary every-PR case - report it as such, not as a blocker.
- `limitations` (e.g. `pullFilesLimit`, `otherPullRequestsLimit`, `timeLimit`) means the snapshot is
  partial: say so in the PR text and give the count of `unknown` entries.
- The board (`npx --yes github:ashhart/ATC board --repo ashhart/TensorFold`, 2 MB JSON) runs the
  same way; `complete: false` there means claim advice is unreliable - the draft-PR route covers
  the claim per `docs/atc/SKILL.md`.

## PR-text wording (proven 2026-11-09, updated 2026-11-23)
"- Overlap: `atc overlap --json` on this head against main at <sha>: N changed files, M open PRs share at
least one of them, and K hard merge conflicts - every one is `<file>`, the ordinary case; no code file
conflicts. One same-function change to sequence: #<n> (...). The snapshot is partial (`pullFilesLimit`),
with U entries `unknown`." When no conflict shares a file with ours, say that instead of naming the
CHANGELOG case.
