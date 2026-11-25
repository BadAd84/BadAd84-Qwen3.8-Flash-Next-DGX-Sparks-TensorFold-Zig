# The 0041 image build: failed on the wrong base, 2026-11-25

Command: ~/work/zbuild/build.sh ks41 with the 41 patches of patches/main-1ece6e6db-r5-dev/ as arguments (staged at ~/work/pks/patches/). It failed in the patch loop of the Dockerfile, exit 1:

    error: patch failed: zig/src/families/flashnext/cuda_mtp_draft.zig:22
    error: zig/src/families/flashnext/cuda_mtp_ops.zig: patch does not apply

Cause: the script sources ~/qwen-zig/scripts/config.sh and builds TensorFold at that file's TF_REF, which is not the series base. Our 41 patches are cut against 1ece6e6dbbc073582d50738ce8e73e3c3261a73b and apply 41 of 41 to a fresh extract of it, so the mismatch is the base, not the patches: the files named belong to patches 0027 to 0028, not to 0041.

Next run: TF_REF=1ece6e6dbbc073582d50738ce8e73e3c3261a73b with build.sh ks41 and the patch arguments. Then arms F0 (off), F1 (PROMPT_KS_N=64 PROMPT_KS_GROUP=8), F2 (GROUP=0) per docs/receipts/PrefillKernelPort/AB-PLAN.md, reply hashes equal across all three, and the booted binary proven to carry the lever row.

## Second run, same launch with TF_REF forced: it failed one layer earlier

`TF_REF=1ece6e6dbbc073582d50738ce8e73e3c3261a73b ~/work/zbuild/build.sh ks41b ...` failed in the RECIPE's
patch loop instead, exit 1:

    for p in /opt/tf-patches/*.patch; do git apply "$p" || exit 1; done

So the build is a TWO-BASE problem, not the one-variable fix written above: our forty-one patches are cut
against `1ece6e6d`, the recipe's `~/qwen-zig/patches/*.patch` are cut against the base `config.sh` pins,
and `build.sh` applies both to one tree. Forcing our base breaks the recipe's set; leaving the recipe's base
breaks three of ours (first run: `cuda_mtp_draft.zig`, `cuda_mtp_ops.zig`, patches 0027 to 0028).

The two real options, neither attempted (budget): read `config.sh` for both the base image and `TF_REF`
and check whether the recipe base already contains the upstream commits our series expects, or re-seat our
series onto the recipe's pinned `TF_REF`. Until one is done, no image built by `build.sh` can carry patch
0041, and the A/B in `docs/receipts/PrefillKernelPort/AB-PLAN.md` cannot run.

## Decision: re-seat our series onto the recipe's base

Read, not assumed: ~/qwen-zig/scripts/config.sh:46 pins TF_REF=eab8582819688325e371907e4706e1c602b8a273 (its own comment: v1.1.4); our series is cut against 1ece6e6dbbc073582d50738ce8e73e3c3261a73b; and git merge-base --is-ancestor 1ece6e6d eab85828 reports NOT an ancestor, so the recipe tree does not already carry what our patches expect. Option 1 is out, and the next attempt re-seats the forty-one patches onto eab85828 (the operation this repo has machinery and a skill for) rather than forcing a base inside build.sh, which applies two differently based sets to one tree.

## Tested: our series does not re-seat onto the recipe base either

git apply, then git apply --3way, of all forty-one patches onto a fresh extract of TF_REF=eab85828 (the recipe's v1.1.4): clean 1, three-way 0, fail 40, tree 7347 files against the base's; e.g. 0001-rows.patch, 0021-int4-autoround.patch and 0041-prompt-ks-tile.patch all fail both ways.

So the two sets are not merely differently based on one lineage: the recipe tree is not a descendant of ours (merge-base --is-ancestor says no) and our patches do not land on it. The build cannot be fixed by forcing a base or by a mechanical re-seat; it needs either the recipe's own patch set dropped from the image (build from our base and skip the recipe patches) or our series cut against the recipe's tree as a fresh port.

## Fifth attempt and the finding that supersedes the placeholder

Five launches failed in the recipe patch loop, each on context that should have matched: README.md at 280 (block context), README.md at 282 (one line), then .gitignore at 33. The Dockerfile fetches its tree from TF_REPO=https://github.com/ashhart/TensorFold.git at TF_REF, so the content it applies to is not the content our patches were cut against, even at the same sha. A placeholder cannot fix that: any patch generated from our clone can mismatch there.

Next step, one command: fetch that remote into work/upmain, check out 1ece6e6d, and diff its README.md and .gitignore against our clone's. If they differ, the whole forty-one-patch series must be regenerated against the remote's content; if they do not, the build's sparse fetch is the variable.

## Seven launches, every component excluded; the next experiment is inside the failing layer

Measured, each inside the build image (nvcr.io/nvidia/pytorch:26.07-py3):
- the remote serves our base sha with .gitignore at blob b9b813a2626b, 33 lines, identical to our clone's;
- the container checkout writes LF (sed -n 33p | od -c shows no CR) with core.autocrlf unset;
- the patch applies by hand there: git apply reports APPLIES;
- it applies from a bind mount through dash with the stage's own loop: for p in /opt/tf-patches/*.patch ... prints LOOP-OK;
- COPY does not alter the bytes (od -c after COPY shows the same header, with the index line).
Yet the stage fails at .gitignore:33 and always has, with a patch that has also been tried without an index line and with block context.

So the next experiment must run INSIDE the failing layer rather than reproduce its inputs: add a debug RUN to a copy of the Dockerfile that prints git status, git rev-parse HEAD, sha1sum .gitignore and cat -A of the file at line 33 immediately before the apply loop. Do not launch another build before that.
