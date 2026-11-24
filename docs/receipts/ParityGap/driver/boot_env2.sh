#!/usr/bin/env bash
# boot_env2.sh ARM C [DRY] - the arm environments for the parity-gap window, in one place.
#
#   P   production as served (control): ~/qwen6-start-prod.sh, its recipe ~/qwen-zig-prod, the pinned image,
#       TENSORFOLD_CUDA_KERNELS=/opt/tensorfold/share/tensorfold/cuda/sm121 (the recipe injects it), fp8 KV,
#       vision on, warm turns off.
#   D   the dev composition as served (control): ~/qwen6-start.sh with dev.env sourced, ~/qwen-zig,
#       IMAGE=tensorfold-qwen38:r5dev40, CHECKPOINT=int4, VISION=0, KV_DTYPE=fp8, MTP_WEIGHTS=mxfp8, the
#       persistent KV tier (LEARN=1).
#   A1  D plus production's copy policy under the dev engine's own names (the four TF_FLASHNEXT_COPY_* names
#       D's env carries have no reader in D's tree; the readers are TENSORFOLD_COPY_*).
#   A2  P plus TF_FLASHNEXT_PROMPT_MM=0: the captured prompt-matmul path off, Python's two launches kept
#       (the prompt path's own header: same bits, the A/B and fallback).
#   A3  P plus TF_FLASHNEXT_GRAPH_FAIL=1: every graph instantiate fails and the round runs eagerly (the
#       engine's own fallback path; same result).
#   A4  D plus LEARN=0: the persistent KV tier and its 6 GiB prompt-cache ask dropped.
#
# Every arm boots its family's launcher, image and recipe unchanged; only the names above differ, and the
# driver captures the container's own env and argv at every boot, so the override is proved, not asserted.
set -u
arm=${1:?P, D, A1, A2, A3 or A4}
C=${2:?streams}
DRY=${3:-0}
export LOCK_HOLDER=0 PARALLEL="$C" CONTEXT=262144 HOST=127.0.0.1 WARM_TURNS=0 DRY_RUN="$DRY"
case $arm in
  P|A2|A3)
    unset IMAGE
    [ "$arm" = A2 ] && export TF_FLASHNEXT_PROMPT_MM=0
    [ "$arm" = A3 ] && export TF_FLASHNEXT_GRAPH_FAIL=1
    exec "$HOME/qwen6-start-prod.sh"
    ;;
  D|A1|A4)
    set +u
    . "$HOME/work/parity/in/dev.env"
    set -u
    export IMAGE=tensorfold-qwen38:r5dev40
    if [ "$arm" = A1 ]; then
      export TENSORFOLD_COPY_MISS=keep TENSORFOLD_COPY_RAMP=jump TENSORFOLD_COPY_SHARED=1 \
             TENSORFOLD_COPY_RESYNC=1 TENSORFOLD_COPY_RESYNC_PROMPT_ONLY=1
    fi
    [ "$arm" = A4 ] && export LEARN=0
    exec "$HOME/qwen6-start.sh"
    ;;
  *)
    echo "arm must be P, D, A1, A2, A3 or A4, not $arm" >&2
    exit 2
    ;;
esac
