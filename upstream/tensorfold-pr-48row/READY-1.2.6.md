# Rows PR, rebased to 1.2.6

> RETIRED REFERENCE: the Gitea repository `ots/tensorfold-levers124` named in this file no longer exists. Every ref it held is in
> `archive/tensorfold-levers124/levers124.bundle` (`REFS.txt` lists them; `README.md` there says how to restore one). The
> production engine source is the branch `production` of this repository.

The branch this PR will be posted from is `rows126` in `ots/tensorfold-levers124`, cut from upstream v1.2.6
(`6e9af9302`), 5 commits, tip `d1ad3fc2d`. The same change as a patch series is in `patches/` here and applies
with `git apply` in filename order to a pristine checkout of `6e9af9302`.

Gates on this head, run the way the repo's CI runs them:

- `tools/pr_check.py --base 1.2.6`: 0 errors, 9 changed files, lean 386 vs 386, 0 new.
- The one gate finding the 1.2.4 head had is fixed: the self-check's switch is read through
  `platform/environment.zig` (`TF_FLASHNEXT_WINDOW_CHECK` has its row) instead of a direct `getenv`, and the
  four-line comment above it is one line.

Outstanding before this posts: the numbers in `PR_final.md` are the 1.2.4 arms (`up124` against `w64`). They
are replaced from the 1.2.6 A/B (`up126` against the patch-series image) once that build boots and its golden
is clean, and the head sha in the text becomes `d1ad3fc2d`'s successor at posting time.
