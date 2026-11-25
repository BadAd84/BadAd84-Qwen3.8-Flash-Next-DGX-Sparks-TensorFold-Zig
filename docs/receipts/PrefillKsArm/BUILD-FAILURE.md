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
