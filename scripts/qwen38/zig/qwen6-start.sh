#!/usr/bin/env bash
# qwen6-start.sh - start (or restart) the Qwen3.8 Flash Next Zig serve on spark6 (box copy: ~/qwen6-start.sh).
#
# Image: tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7 = the recipe's Zig 1.0.0 release + our 0001-0028 + the
# zmerge8 keep set (docs/ZIG-SPEED-CAMPAIGN-2026-10.md section 4) + the two byte-neutral 64K-page boot fixes
# (label ai-engine.kindling: 0001-vision-clone + 0002-upload-staging), the only build of that stack that boots on
# kindling spark-os. Golden 6/6 and every decode reply equal to stock at 1/2/4/6/8 streams (2026-10-12).
# Env: the measured zmerge8 arm env (spark6 ~/work/lanes/merge8, copy ~/work/ots-255-knob/m8env.sh) with two changes:
#   - no HOST=127.0.0.1 (that was the benchmark lockdown; the serve answers on every interface, :8888);
#   - TENSORFOLD_WARM_TURNS=0: warm turns are the one keep with a measured 1-stream regression (back-to-back prompts
#     +0.08-0.25 s TTFT, section 4 item 1), a trade only the owner accepts. Set WARM_TURNS=1 to enable them
#     (next-turn TTFT 8k 0.52 -> 0.31 s, 100k 0.66 -> 0.50 s at every concurrency).
# Runs the recipe's own start.sh (~/qwen-zig, recipe 1.0.0 @ 364f21a) and holds the box's GPU lock
# (~/work/gpu.lock, the spark4-6 rule) for as long as the container runs. Stop: ~/qwen-zig/stop.sh.
set -euo pipefail
IMAGE=${IMAGE:-tensorfold-qwen38:zmerge8-kfix-e5139fcd8c6101c7}
PARALLEL=${PARALLEL:-8}
WARM_TURNS=${WARM_TURNS:-0}
STATE=$HOME/.local/state/qwen38-flash-next-tf
RECIPE=$HOME/qwen-zig
MTP_FP8=/root/.cache/huggingface/tensorfold-mtp-fp8/azampatti--Qwen3.8-Flash-Next-125B-A5B-INT4-AutoRound/1464274120d36a4d8fcaa934552334a7d83ce0fd

if [ -f "$STATE/start.lock" ] && ! pgrep -f "[q]wen-zig/start.sh" >/dev/null && ! pgrep -f "[.]/start.sh restart" >/dev/null; then
  echo "removing stale $STATE/start.lock (no start.sh running)"; rm -f "$STATE/start.lock"
fi
docker image inspect "$IMAGE" >/dev/null || { echo "image $IMAGE is not on this box"; exit 1; }
[ -d "$HOME/.cache/huggingface/tensorfold-mtp-fp8" ] || { echo "the MTP FP8 overlay dir is missing (mtp_fp8.py)"; exit 1; }

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
  TF_FLASHNEXT_MTP_FP8="$MTP_FP8" \
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
  ./start.sh restart
