#!/usr/bin/env bash
# qwen6-start.sh - the DEV launcher for the Qwen3.8 Flash Next Zig serve on spark6 (box copy: ~/qwen6-start.sh).
#
# Production is NOT this file: the box starts production with ~/qwen6-start-prod.sh (recipe ~/qwen-zig-prod,
# production's 54-name environment, the TF_FLASHNEXT_MTP_FP8 overlay), which stays untouched. This copy carries the
# dev engine's defaults from scripts/qwen38/zig/target/env/dev.env and PROMOTION-RULES.md, each overridable:
# CHECKPOINT=int4, VISION=0, KV_DTYPE=fp8, TF_FLASHNEXT_MTP_WEIGHTS=mxfp8 and the persistent KV tier (LEARN=0 turns
# the tier off; MTP_WEIGHTS=bf16 puts the drafter back on the checkpoint's rows).
#
# Image: tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 = the recipe's Zig 1.0.0 release + our 0001-0028 + the
# zmerge8 keep set + the two byte-neutral 64K-page boot fixes
# (label ai-engine.kindling: 0001-vision-clone + 0002-upload-staging), the only build of that stack that boots on
# kindling spark-os. Golden 6/6 and every decode reply equal to stock at 1/2/4/6/8 streams (2026-10-12).
# Env: the measured zmerge8 arm env (spark6 ~/work/lanes/merge8, copy ~/work/ots-255-knob/m8env.sh) with three
# changes:
#   - no HOST=127.0.0.1 (that was the benchmark lockdown; the serve answers on every interface, :8888);
#   - TENSORFOLD_WARM_TURNS=0: warm turns are the one keep with a measured 1-stream regression (back-to-back prompts
#     +0.08-0.25 s TTFT, section 4 item 1), a trade only the owner accepts. Set WARM_TURNS=1 to enable them
#     (next-turn TTFT 8k 0.52 -> 0.31 s, 100k 0.66 -> 0.50 s at every concurrency);
#   - the dev engine's checkpoint, text-only shape, KV dtype, drafter recode and KV tier (the block below).
# Runs the recipe's own start.sh (~/qwen-zig, recipe 1.0.0 @ 364f21a) and holds the box's GPU lock
# (~/work/gpu.lock, the spark4-6 rule) for as long as the container runs. Stop: ~/qwen-zig/stop.sh.
set -euo pipefail
IMAGE=${IMAGE:-tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7}
PARALLEL=${PARALLEL:-8}
WARM_TURNS=${WARM_TURNS:-0}
# The dev serve's checkpoint and shape, from the recipe's own settings (~/qwen-zig/scripts/config.sh:24 CHECKPOINT
# default nvfp4, :125 KV_DTYPE default fp8, :136 VISION default 1). The composition serves the INT4-AutoRound
# checkpoint only (patches/main-1ece6e6db-r5-dev/README.md: the config check refuses the FP4 checkpoint by name) and
# the dev arm runs text only (dev.env), so the checkpoint and vision are stated here.
CHECKPOINT=${CHECKPOINT:-int4}
VISION=${VISION:-0}
KV_DTYPE=${KV_DTYPE:-fp8}
# The drafter's BF16 linears recoded to MXFP8 at load (patch 0014; the reader is a raw getenv,
# zig/src/families/flashnext/cuda_mtp_mxfp8.zig:23, default bf16). TF_FLASHNEXT_MTP_FP8, which this file used to set,
# is production's overlay path and has no reader in this tree.
MTP_WEIGHTS=${MTP_WEIGHTS:-mxfp8}
# The persistent KV tier, dev.env's ask: --prompt-cache-gib 6 (granted 3.1 GiB of store), 60 GiB of states, 200 GiB
# a day, a 20 GiB free-disk floor. --prompt-cache-disk is the engine's own spelling of --learn-conversations
# --learn-dir (zig/src/server/cli.zig:465-469, and the two spellings are refused together, cli.zig:319-325 and
# cli_test.zig:529-556), so this is the tier in the only form the argument check takes.
LEARN=${LEARN:-1}
LEARN_GIB=${LEARN_GIB:-60}
LEARN_DAILY_GIB=${LEARN_DAILY_GIB:-200}
LEARN_MIN_FREE_GIB=${LEARN_MIN_FREE_GIB:-20}
PROMPT_CACHE_GIB=${PROMPT_CACHE_GIB:-6}
PROMPT_CACHE_DISK=${PROMPT_CACHE_DISK:-/cache/kv}
TIER_ARGS=()
if [ "$LEARN" = 1 ]; then
  TIER_ARGS=(--prompt-cache-gib "$PROMPT_CACHE_GIB" --prompt-cache-disk "$PROMPT_CACHE_DISK"
             --learn-gib "$LEARN_GIB" --learn-daily-gib "$LEARN_DAILY_GIB" --learn-min-free-gib "$LEARN_MIN_FREE_GIB")
fi
STATE=$HOME/.local/state/qwen38-flash-next-tf
RECIPE=$HOME/qwen-zig

if [ -f "$STATE/start.lock" ] && ! pgrep -f "[q]wen-zig/start.sh" >/dev/null && ! pgrep -f "[.]/start.sh restart" >/dev/null; then
  echo "removing stale $STATE/start.lock (no start.sh running)"; rm -f "$STATE/start.lock"
fi
docker image inspect "$IMAGE" >/dev/null || { echo "image $IMAGE is not on this box"; exit 1; }

# The GPU lock holder: takes the lock, waits up to 10 minutes for the serve container to appear, then holds the lock
# while it runs and exits (releasing the lock) as soon as it is gone or stopped. Started before the boot so no other
# job slips in between. LOCK_HOLDER=0 skips it (a benchmark driver that already holds the lock boots the serve as
# one of its arms).
if [ "${LOCK_HOLDER:-1}" = 1 ] && ! pgrep -f "[q]wen6-gpu-lock-holder" >/dev/null; then
  setsid nohup bash -c 'exec -a qwen6-gpu-lock-holder flock -o "$HOME/work/gpu.lock" bash -c "
    up() { [ \"\$(docker inspect -f {{.State.Running}} qwen38-flash-next-tf 2>/dev/null)\" = true ]; }
    for i in \$(seq 1 60); do up && break; sleep 10; done
    while up; do sleep 10; done"' \
    >/dev/null 2>&1 < /dev/null &
  echo "gpu lock holder started (pid $!)"
fi

cd "$RECIPE"
exec env \
  IMAGE="$IMAGE" PREPARE=0 PARALLEL="$PARALLEL" WAIT_TIMEOUT=3600 \
  CHECKPOINT="$CHECKPOINT" VISION="$VISION" KV_DTYPE="$KV_DTYPE" \
  TF_FLASHNEXT_MTP_WEIGHTS="$MTP_WEIGHTS" \
  TENSORFOLD_IMAGE_TOKENS=16384 TENSORFOLD_MAX_IMAGES=50 TENSORFOLD_MEMORY_RESERVE_GIB=10 \
  TENSORFOLD_NO_UPDATE_CHECK=1 TENSORFOLD_PROMPT_CACHE_WHOLE=1 TENSORFOLD_PROMPT_CACHE_WHOLE_MIN=1024 \
  TENSORFOLD_VIDEO_TOKENS=16384 TENSORFOLD_VISION_WORKSPACE_MIB=2048 TENSORFOLD_WARM_TURNS="$WARM_TURNS" \
  TF_FLASHNEXT_BATCH_DRAWS=1 TF_FLASHNEXT_BATCH_WINDOWS=1 TF_FLASHNEXT_CONFIDENCE=-0.15 \
  TF_FLASHNEXT_COPY_MISS=keep TF_FLASHNEXT_COPY_RAMP=jump TF_FLASHNEXT_COPY_RESYNC=1 TF_FLASHNEXT_COPY_SHARED=1 \
  TF_FLASHNEXT_COST_RETIME=4 TF_FLASHNEXT_DEPTH=15 TF_FLASHNEXT_DRAFT_CONTINUE=0.20 \
  TF_FLASHNEXT_DRAFT_DEPTH_SHARED=7 TF_FLASHNEXT_DRAFT_INT4=1 TF_FLASHNEXT_DRAFT_PROPOSE=0.05 \
  TF_FLASHNEXT_EARLY_DRAW=1 TF_FLASHNEXT_FP8_FUSED_SPLIT=4 TF_FLASHNEXT_FP8_PROMPT_TILES=1 TF_FLASHNEXT_HC_Q12=1 \
  TF_FLASHNEXT_HEAD_ROW_TILES=2 TF_FLASHNEXT_INT4_PROMPT_GATE_UP=1 TF_FLASHNEXT_MULTI_LRU=1 \
  TF_FLASHNEXT_MULTI_MAX=192 TF_FLASHNEXT_MULTI_VERIFY=1 TF_FLASHNEXT_NGRAM_LATE=1 TF_FLASHNEXT_NGRAM_PREFETCH=1 \
  TF_FLASHNEXT_NGRAM_RANDOM=1 TF_FLASHNEXT_NGRAM_THREADS=32 TF_FLASHNEXT_PREFILL_ROWS=4096 \
  TF_FLASHNEXT_PREFILL_TAIL=512 TF_FLASHNEXT_PRODUCT_STREAMS=8 TF_FLASHNEXT_PROMPT_HEAD_SKIP=1 \
  TF_FLASHNEXT_QSA_SELECT=1 TF_FLASHNEXT_QSA_TILE=4 TF_FLASHNEXT_REDUCE_ACT=1 TF_FLASHNEXT_SEQ_POOL=8 \
  TF_FLASHNEXT_SHARED_EARLY_ROWS=6 TF_FLASHNEXT_SHARED_SLOT_LD=1 TF_FLASHNEXT_SOLO_MAX=1024 \
  TF_FLASHNEXT_UPMIX_DECODE=1 TF_FLASHNEXT_WARM_POOL=8 TF_FLASHNEXT_WINDOW=64 TF_FLASHNEXT_YARN=0 \
  TF_FLASHNEXT_SHARED_COST_LEVELS=0 \
  ./start.sh restart "${TIER_ARGS[@]+"${TIER_ARGS[@]}"}"
