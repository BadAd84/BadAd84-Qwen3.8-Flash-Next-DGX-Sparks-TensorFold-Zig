#!/usr/bin/env bash
# boot_env.sh ARM C [DRY] - the one place the two arms' boot environments are stated, used for the preflight dry
# run and for every measured boot alike, so what the parser was tested with is what the serve runs.
#
#   P  production: its own launcher and recipe, the pinned image (the launcher's default), PARALLEL=C, loopback,
#      warm turns off, CONTEXT=262144 (the recipe's own default, stated).
#   D  the dev composition: ~/qwen6-start.sh with dev.env sourced (the environment of record), IMAGE=r5dev40,
#      PARALLEL=C, loopback, warm turns off, CONTEXT=262144, its own defaults (CHECKPOINT=int4, VISION=0,
#      KV_DTYPE=fp8, TF_FLASHNEXT_MTP_WEIGHTS=mxfp8) and the persistent KV tier the launcher states.
#
# LOCK_HOLDER=0 on both: the window driver holds ~/work/gpu.lock for the whole run.
set -u
arm=${1:?P or D}
C=${2:?streams}
DRY=${3:-0}
export LOCK_HOLDER=0 PARALLEL="$C" CONTEXT=262144 HOST=127.0.0.1 WARM_TURNS=0 DRY_RUN="$DRY"
case $arm in
  P)
    unset IMAGE
    exec "$HOME/qwen6-start-prod.sh"
    ;;
  D)
    set +u
    . "$HOME/work/parity/in/dev.env"
    set -u
    export IMAGE=tensorfold-qwen38:r5dev40
    exec "$HOME/qwen6-start.sh"
    ;;
  *)
    echo "arm must be P or D, not $arm" >&2
    exit 2
    ;;
esac
