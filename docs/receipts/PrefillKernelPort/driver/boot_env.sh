#!/usr/bin/env bash
# boot_env.sh ARM C [DRY] - the three arms of the 0041 prompt-tile window, in one place.
#
#   F0  the dev composition as served (control): ~/qwen6-start.sh with dev.env sourced, IMAGE=tensorfold-qwen38:r5dev40,
#       CHECKPOINT=int4, VISION=0, KV_DTYPE=fp8, MTP_WEIGHTS=mxfp8, the persistent KV tier (LEARN=1). No prompt-tile
#       name is set, so TF_FLASHNEXT_PROMPT_KS_N=0 and the engine's 128-column prompt tile runs.
#   F1  F0 plus TF_FLASHNEXT_PROMPT_KS_N=64 TF_FLASHNEXT_PROMPT_KS_GROUP=8: the captured prompt matmul's geometry
#       (prompt_mm.py's _b16mm_ks BLOCK_N=64 and GROUP=8) on the fused K-slice prompt tile.
#   F2  F0 plus TF_FLASHNEXT_PROMPT_KS_N=64 TF_FLASHNEXT_PROMPT_KS_GROUP=0: the 64-column block with the engine's own
#       band sweep, which separates the column block from the band.
#
# Every arm boots the same launcher, image and recipe unchanged; only the names above differ, and the driver captures
# the container's own env and argv at every boot, so the override is proved, not asserted. The F1/F2 arms also prove
# themselves from the boot line `prompt matmuls: the fused K-slice tile on 64-column blocks, N row tiles a band`.
set -u
arm=${1:?F0, F1 or F2}
C=${2:?streams}
DRY=${3:-0}
export LOCK_HOLDER=0 PARALLEL="$C" CONTEXT=262144 HOST=127.0.0.1 WARM_TURNS=0 DRY_RUN="$DRY"
case $arm in
  F0|F1|F2)
    set +u
    . "$HOME/work/parity/in/dev.env"
    set -u
    export IMAGE=tensorfold-qwen38:r5dev40
    if [ "$arm" = F1 ]; then
      export TF_FLASHNEXT_PROMPT_KS_N=64 TF_FLASHNEXT_PROMPT_KS_GROUP=8
    fi
    if [ "$arm" = F2 ]; then
      export TF_FLASHNEXT_PROMPT_KS_N=64 TF_FLASHNEXT_PROMPT_KS_GROUP=0
    fi
    exec "$HOME/qwen6-start.sh"
    ;;
  *)
    echo "arm must be F0, F1 or F2, not $arm" >&2
    exit 2
    ;;
esac
