---
name: rebase-levers-onto-new-upstream-release
description: "Rebase archived TensorFold lever branches onto a newer upstream release, stack them into one branch, re-sign, and hand the stack to spark6 for image builds."
---

# Rebase levers onto a new upstream release

Use when upstream has shipped a new TensorFold release and our lever/port branches sit on an older base. Output: one branch per lever for PRs, one stack branch for measurement, all signed, and a bare repo on spark6 the build daemon can serve.

## 1. Find the base and each branch's own commits

- `git fetch <upstream> --tags` and read the release tag; note the release commit (the tag may be annotated, so fetch the COMMIT sha: fetching `vX.Y.Z:refs/heads/base` fails with "non-commit object").
- A port branch is often cut from a main commit AFTER the old release, not from the tag. Find the first port commit (`git log --oneline <oldrelease>..archive/<branch>`) and use ITS PARENT as the rebase upstream. Rebasing from the old release instead replays dozens of upstream commits.
- Prefer replaying only the port commits: `git cherry-pick <newbase>..archive/<branch>` or `git rebase --onto <newbase> <first-port-parent> <branch>`.

## 2. Worktrees and paths

- One worktree per lever: `git worktree add -b <name> C:/Users/Adam/Gitea/tf-<name> archive/<branch>`.
- Windows git cannot use msys `/c/...` paths: passing one silently creates a tree at `C:/c/...`. Always use `C:/Users/...` for worktree add, cd and push targets.

## 3. Resolve conflicts

- Read `conflict://` blocks with the read tool, then write the replacement to the SAME `conflict://<id>` path with body `@ours`, `@theirs`, `@both` or combined text.
- `@both` is only for additive blocks (two row lists, two imports, two changelog bullets).
- NEVER put the bulk form (`1: @both`) into a single block: it writes that literal text into the file. The per-id form applies only to `conflict://*`.
- A whole-file write to the wrong path destroys the file; recover with `git checkout -- <path>` (restores the index copy, conflict markers and all), then edit precisely.
- Recurring shapes: `## Unreleased` bullets (keep both, then move all lever bullets into one Unreleased section and leave the release section as upstream wrote it), add/add `cuda_knobs.zig` (concatenate both sets of functions under one header and one import), `environment.zig` rows (concatenate, then check for duplicate `.name =` values), and refactors upstream did (for example `gdn_fused.on()` becoming `self.k.forms.gdn_fused`): keep upstream's API and carry our condition.
- When a commit's change is already present (upstream landed the same tile pieces), the cherry-pick is empty: `git cherry-pick --skip`.
- If a marker slips into a commit, fix the file, `git commit -S --fixup=<sha>`, then `GIT_SEQUENCE_EDITOR=true git rebase -i --autosquash <base>`.

## 4. Re-sign

Rebased commits lose signatures. Per branch, in its worktree: `git rebase <base> --exec 'git commit --amend --no-edit -S'`. Verify with `git log --format='%G?' <base>..HEAD | grep -c '^N'` = 0.

## 5. Stack and hand off

- `git worktree add -b stacked <path> <base>`, then `git cherry-pick <base>..<lever>` per branch in measured-value order; resolve as above; squash fixups and sign the same way.
- Build repo: `git init --bare ~/work/lanes/ots126/tf.git` on spark6 (under the daemon's base path). Laptop ssh push may fail from Git for Windows; use `git bundle create x.bundle <base>..<stack>`, scp it, then on the box `git fetch <upstream-clone> <base-sha>:refs/heads/base` followed by `git fetch ~/x.bundle refs/heads/<stack>:refs/heads/<stack>`.
- Build: `bash ~/work/merge/build-br.sh TAG git://192.168.99.16/ots126/tf <stack-sha>` (no recipe patches; that is what a stock/upstream arm is).
- Boot cells through `~/work/lanes/rpr/recipe/start.sh` with `IMAGE=... CHECKPOINT=nvfp4 VISION=0 KV_DTYPE=bf16 PARALLEL=C CONTEXT=131072 HOST=127.0.0.1`. Do not use `~/qwen6-start.sh` for a production image: its recipe copy is now v1.1.4 and gates `tf.kernels=embedded` while the production image carries `present`.

## 6. Gates before any PR

- Base-versus-head lean (each side's own copy of the tool; the two file counts must differ), whole-tree `zig fmt --check`, host suite with identical failing lists, golden and reply-sha equality, ABBA fresh-boot cells at 1/2/4/6/8, and the repo's CHANGELOG bullet.
