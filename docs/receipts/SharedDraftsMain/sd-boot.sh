#!/usr/bin/env bash
# sd-boot.sh ARM - boot a fresh server of the clean-main image with the one lever set, wait for /health 200.
#   ARM=0: TF_FLASHNEXT_SHARED_DRAFTS=0     ARM=1: TF_FLASHNEXT_SHARED_DRAFTS=1 (the shipped default)
# Everything else is identical: same image, same checkpoint, same flags, no other TF_/TENSORFOLD_ name.
# The caller holds ~/work/gpu.lock (production stopped); this script does not touch production.
set -euo pipefail
ARM=${1:?arm 0 or 1}
case "$ARM" in 0|1) ;; *) echo "arm must be 0 or 1" >&2; exit 2 ;; esac
IMG=${IMG:-tensorfold-qwen38:main-9a38b1f7b}
NAME=${NAME:-sd-main-tf}
CTX=${CTX:-32768}
PAR=${PAR:-8}
CACHE_GIB=${CACHE_GIB:-3}
MODEL_DIR=/models/qwen38/snapshots/b9ce18a6887e18c089fdea8509a33e63429a3300
HF=$HOME/.cache/huggingface/hub/models--nvidia--Qwen3.8-Flash-Next-FP4-Local
URL=http://127.0.0.1:8888
[ -d "$HF/snapshots/b9ce18a6887e18c089fdea8509a33e63429a3300" ] || { echo "BOOT-FAIL checkpoint snapshot missing"; exit 1; }
docker image inspect "$IMG" >/dev/null 2>&1 || { echo "BOOT-FAIL image $IMG not on this box"; exit 1; }
docker rm -f "$NAME" >/dev/null 2>&1 || true
docker run -d --name "$NAME" --gpus all --ipc=host --network host \
  --ulimit memlock=-1 --ulimit stack=67108864 \
  -e TF_FLASHNEXT_SHARED_DRAFTS="$ARM" \
  -v "$HF":/models/qwen38:ro \
  "$IMG" serve "$MODEL_DIR" --name Qwen3.8-Flash-Next --host 0.0.0.0 --port 8888 \
    --context "$CTX" --parallel "$PAR" --prompt-cache-gib "$CACHE_GIB" --temperature 0 >/dev/null
for i in $(seq 1 120); do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "$URL/health" 2>/dev/null || true)
  if [ "$code" = 200 ]; then
    echo "BOOT OK arm $ARM image $IMG ${CTX}ctx ${PAR}par ${CACHE_GIB}GiB-cache after $((i*5))s"
    exit 0
  fi
  if [ "$(docker inspect -f '{{.State.Running}}' "$NAME" 2>/dev/null)" != true ]; then
    echo "BOOT-FAIL arm $ARM: container exited (health $code)"
    docker logs --tail 60 "$NAME" 2>&1 || true
    exit 1
  fi
  sleep 5
done
echo "BOOT-FAIL arm $ARM: /health not 200 after 600s"
docker logs --tail 60 "$NAME" 2>&1 || true
exit 1
