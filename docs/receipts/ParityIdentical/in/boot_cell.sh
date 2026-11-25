#!/usr/bin/env bash
# boot_cell.sh ARM MODE C [DRY] - one boot's environment, stated in one place, used for the preflight dry run and
# every measured boot alike.
#
#   P  production: its own launcher (~/qwen6-start-prod.sh, recipe ~/qwen-zig-prod) and image
#      tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7. The launcher pins its 54 TF_/TENSORFOLD_ names, so only the
#      names it does NOT pin, plus the recipe's own switches (DRAFTS, VISION, KV_DTYPE), reach the engine:
#        control    nothing
#        nodrafts   DRAFTS=0        (recipe `--no-drafts`, box-start-prod.sh:45)
#        pmm0       TF_FLASHNEXT_PROMPT_MM=0   (unpinned; prod recipe forwards ^(TENSORFOLD|TF_FLASHNEXT)_[A-Z0-9_]+=)
#        bf16kv     KV_DTYPE=bf16   (recipe `--kv-dtype bf16`, box-start-prod.sh:46-47)
#        novision   VISION=0        (recipe drops --vision, box-start-prod.sh:49-52)
#        int4tile64 TF_FLASHNEXT_INT4_TILE=64  (unpinned; takes the 64-pair prompt tile: "the same bits either way",
#                   cuda_int4.zig:146-152. TF_FLASHNEXT_HEAD_ROW_TILES is NOT usable as a bit lever: both launchers
#                   pin it to 2 in their own exec env, so an export cannot reach the engine)
#
#   D  the dev composition: ~/qwen6-start.sh with dev.env sourced (the environment of record), image
#      tensorfold-qwen38:r5dev40. dev.env states the whole arm; a mode exports its override after it:
#        control    nothing
#        nodrafts   DRAFTS=0
#        chunk2048  TF_FLASHNEXT_CHUNK=2048 TF_FLASHNEXT_CHUNK_SOLO=2048   (the prompt pass size; P's is 2048)
#        bf16kv     KV_DTYPE=bf16
#        notier     LEARN=0         (no --prompt-cache-* and no --learn-*; the 6 GiB ask goes with it)
#        int4tile64 TF_FLASHNEXT_INT4_TILE=64  (the 64-pair prompt tile; "the same bits either way". HEAD_ROW_TILES is
#                   pinned to 2 by the dev launcher, so it cannot be used as a bit lever)
#        mtpbf16    MTP_WEIGHTS=bf16 (the drafter on the checkpoint's rows instead of the mxfp8 recode)
#
# LOCK_HOLDER=0 on both: the window driver holds ~/work/gpu.lock for the whole run.
set -u
arm=${1:?P or D}
mode=${2:?mode}
C=${3:?streams}
DRY=${4:-0}
export LOCK_HOLDER=0 PARALLEL="$C" CONTEXT=262144 HOST=127.0.0.1 WARM_TURNS=0 DRY_RUN="$DRY"
case $arm in
  P)
    unset IMAGE
    case $mode in
      control) ;;
      nodrafts) export DRAFTS=0 ;;
      pmm0) export TF_FLASHNEXT_PROMPT_MM=0 ;;
      bf16kv) export KV_DTYPE=bf16 ;;
      novision) export VISION=0 ;;
      int4tile64) export TF_FLASHNEXT_INT4_TILE=64 ;;
      *) echo "arm P has no mode $mode" >&2; exit 2 ;;
    esac
    exec "$HOME/qwen6-start-prod.sh"
    ;;
  D)
    set +u
    . "$HOME/work/parityid/in/dev.env"
    set -u
    export IMAGE=tensorfold-qwen38:r5dev40
    case $mode in
      control) ;;
      nodrafts) export DRAFTS=0 ;;
      chunk2048) export TF_FLASHNEXT_CHUNK=2048 TF_FLASHNEXT_CHUNK_SOLO=2048 ;;
      bf16kv) export KV_DTYPE=bf16 ;;
      notier) export LEARN=0 ;;
      int4tile64) export TF_FLASHNEXT_INT4_TILE=64 ;;
      mtpbf16) export MTP_WEIGHTS=bf16 ;;
      *) echo "arm D has no mode $mode" >&2; exit 2 ;;
    esac
    exec "$HOME/qwen6-start.sh"
    ;;
  *)
    echo "arm must be P or D, not $arm" >&2
    exit 2
    ;;
esac
