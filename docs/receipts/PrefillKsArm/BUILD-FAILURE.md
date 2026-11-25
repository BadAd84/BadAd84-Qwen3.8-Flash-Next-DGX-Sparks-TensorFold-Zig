# The 0041 image build: failed on the wrong base, 2026-11-25

Command: ~/work/zbuild/build.sh ks41 with the 41 patches of patches/main-1ece6e6db-r5-dev/ as arguments (staged at ~/work/pks/patches/). It failed in the patch loop of the Dockerfile, exit 1:

    error: patch failed: zig/src/families/flashnext/cuda_mtp_draft.zig:22
    error: zig/src/families/flashnext/cuda_mtp_ops.zig: patch does not apply

Cause: the script sources ~/qwen-zig/scripts/config.sh and builds TensorFold at that file's TF_REF, which is not the series base. Our 41 patches are cut against 1ece6e6dbbc073582d50738ce8e73e3c3261a73b and apply 41 of 41 to a fresh extract of it, so the mismatch is the base, not the patches: the files named belong to patches 0027 to 0028, not to 0041.

Next run: TF_REF=1ece6e6dbbc073582d50738ce8e73e3c3261a73b with build.sh ks41 and the patch arguments. Then arms F0 (off), F1 (PROMPT_KS_N=64 PROMPT_KS_GROUP=8), F2 (GROUP=0) per docs/receipts/PrefillKernelPort/AB-PLAN.md, reply hashes equal across all three, and the booted binary proven to carry the lever row.
