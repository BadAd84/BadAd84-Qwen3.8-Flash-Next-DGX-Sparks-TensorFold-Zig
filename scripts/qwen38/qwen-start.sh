#!/usr/bin/env bash
# qwen-start.sh (spark4, copied to ~): start or restart the RETIRED Qwen3.8 Flash Next Python serve on :8888 with the
# OTS image (tensorfold-qwen38:v061-ots = the recipe's image + TensorFold PR #319 + ple-cache + chain-stop,
# build_qwen_ots.sh). A plain `./start.sh` in ~/qwen38-flashnext would start the recipe's own image and drop those.
# Arguments go to the recipe's start.sh (e.g. `qwen-start.sh restart`). The container restarts by itself after a
# reboot (restart policy unless-stopped).
#
# This launcher CANNOT carry the composition's dev defaults and does not pretend to; they belong to the Zig dev
# launcher, scripts/qwen38/zig/qwen6-start.sh (scripts/qwen38/README.md says which launcher carries what). Its recipe
# (MiaAI-Lab Qwen3.8-Flash-Next-Single-DGX-Spark-TensorFold @ 4c0dea8) has no CHECKPOINT setting - it pins MODEL_ID -
# and its engine (TensorFold v0.6.1) takes --kv-dtype bf16|int8|int4 only (src/tensorfold/cli_args.py:124, no fp8) and
# has no --learn-conversations, --learn-dir, --prompt-cache-disk, --learn-gib, --learn-daily-gib or --learn-min-free-gib
# flag. Nothing in it reads TF_FLASHNEXT_MTP_WEIGHTS. What it does read is stated below at the dev serve's shape:
# VISION=0 (text only) and the engine's own KV dtype, written out rather than left to the recipe's default.
set -euo pipefail
export IMAGE=tensorfold-qwen38:v061-ots
# Dev serve shape from scripts/qwen38/zig/target/env/dev.env: text only (VISION=0; the recipe's own default is 1,
# recipe scripts/config.sh VISION) and int8 KV, this engine's default (config.sh KV_DTYPE) written out because fp8 is
# not one of its --kv-dtype choices. Override from the environment (VISION=1, KV_DTYPE=bf16); .env cannot override
# these, since the launcher exports them before the recipe reads it.
export VISION="${VISION:-0}"
export KV_DTYPE="${KV_DTYPE:-int8}"
# MTP chains: up to 8 drafts a round, a chain stopping once the calibrated chance that all its drafts land falls under
# 0.30 (README.md, chain-stop). Today's recipe rule instead: MTP_DRAFTS=6 and TENSORFOLD_CHAIN_RULE=conf.
export MTP_DRAFTS="${MTP_DRAFTS:-8}"
export TENSORFOLD_CHAIN_RULE="${TENSORFOLD_CHAIN_RULE:-cum}"
export TENSORFOLD_CHAIN_T="${TENSORFOLD_CHAIN_T:-0.30}"
cd "$HOME/qwen38-flashnext"
./start.sh "$@" </dev/null
docker update --restart unless-stopped qwen38-flash-next-tf >/dev/null
