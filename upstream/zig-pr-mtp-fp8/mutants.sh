#!/usr/bin/env bash
# mutants.sh (spark6): patches/0011's checks. The patch changes which weights the MTP head drafts from; replies are
# guarded by the target's verification, so the checks are (1) golden replies byte-identical (zarm.sh / zgold_cmp.py)
# and (2) the overlay read order: with TF_FLASHNEXT_INT4AR_FAST=1 as well, the checkpoint's fast-fp8/ repeats the MTP
# layer's bf16 tensors. The mutant is the read order reversed (fast-fp8/ first): the load must then stop with
# "bf16 { 320, 10240 } with scales f32" - observed on 2026-10-08 with the first version of the patch (image zots4),
# and the fixed order (zots5) booted and served with both overlays. Re-run: build both images with build_zig_ots.sh
# (the mutant = the patch with the two openOverlay lines swapped) and boot each with
#   PREPARE=0 IMAGE=<tag> TF_FLASHNEXT_MTP_FP8=<overlay> TF_FLASHNEXT_INT4AR_FAST=1 ~/qwen-zig/start.sh restart
# expecting exit 0 for the patch and "the server exited (code 1)" for the mutant.
echo "manual: see the header" >&2
exit 2
